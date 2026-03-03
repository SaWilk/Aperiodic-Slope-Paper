%% aperiodic_fooof_qc__all_subjects.m
% QC for aperiodic slope (FOOOF exponent) + PSD sanity checks
%
% What this script does (per subject):
%   1) Loads Welch PSD mats (open + closed) from:
%        derivatives/07_psd_welch/sub-XXX/
%        sub-XXX_desc-psd_method-welch_freqres-0p50_cond-open.mat   (PSDopen, freqs, meta)
%        sub-XXX_desc-psd_method-welch_freqres-0p50_cond-closed.mat (PSDclosed, freqs, meta)
%   2) Loads FOOOF exponent mats (open + closed) from:
%        derivatives/08_fooof/sub-XXX/
%        sub-XXX_desc-fooof_cond-open.mat   (expects exponent vector)
%        sub-XXX_desc-fooof_cond-closed.mat (expects exponent vector)
%   3) Plots:
%        - mean PSD spectra open vs closed (log-log), with explicit colors
%        - topographies of exponent (open, closed, closed-open)
%   4) Writes summary tables (CSV):
%        - epoch counts (open/closed)
%        - mean exponent (open/closed) + mean difference
%
% Notes:
% - This is QC only (no stats). Group analysis + cluster tests should be a separate script.
% - Requires EEGLAB for pop_loadset + topoplot.
% - Uses a single reference EEG .set to get chanlocs. You can point it at any subject/condition .set.
%
% Saskia pipeline paths (edit if needed):
%   derivatives root: Z:\pb\KPP_KPN_joined\Aperiodic\Saskia\derivatives
%   step06 eeg sets:  derivatives\06_epoched_runica\sub-XXX\*.set
%
% Date: 02-Mar-2026

clear; clc;

%% ---------------- USER CONFIG ----------------
derivRoot = fullfile('Z:\pb\KPP_KPN_joined\Aperiodic\Saskia', 'derivatives');

psdRoot   = fullfile(derivRoot, '07_psd_welch');
fooofRoot = fullfile(derivRoot, '08_fooof');
eegRoot   = fullfile(derivRoot, '06_epoched_runica');

% PSD filename convention
freq_res_tag = '0p50';   % matches "..._freqres-0p50_..." in your filenames
fmax = 45;               % plot up to this frequency (Hz)
use_loglog = true;       % log-log PSD plot is typical for aperiodic sanity checks

% Output QC folder (BIDS-ish derivative subfolder)
qcOutDir = fullfile(derivRoot, 'checks', 'qc_aperiodic');
if ~exist(qcOutDir,'dir'); mkdir(qcOutDir); end

% Explicit group colors (consistent across plots)
COL_OPEN   = [0.20 0.50 0.90];  % blue-ish
COL_CLOSED = [0.90 0.35 0.20];  % red-ish

% Which channels to report posterior alpha sanity (optional)
do_posterior_alpha_check = true;
postChans = {'O1','O2','Oz','POz','Pz','PO3','PO4'};
alphaBand = [8 12];

% If you want to also save individual subject PNGs
save_png = true;

% EEGLAB path
eeglabDir = 'K:\Wilken_Arbeitsordner\MATLAB\eeglab_current\eeglab2025.1.0';

%% ---------------- START EEGLAB (for topoplot + pop_loadset) -------------
addpath(eeglabDir);
try
    eeglab('nogui');
catch
    addpath(genpath(eeglabDir));
    eeglab('nogui');
end

%% ---------------- FIND SUBJECTS ----------------
subDirs = dir(fullfile(psdRoot, 'sub-*'));
subDirs = subDirs([subDirs.isdir]);

if isempty(subDirs)
    error('No sub-* folders found in %s', psdRoot);
end

%% ---------------- LOAD REFERENCE CHANLOCS ----------------
% Pick first subject that has an EEG set to get chanlocs
EEGref = [];
for i = 1:numel(subDirs)
    sub = subDirs(i).name;
    setCand = dir(fullfile(eegRoot, sub, '*_epoched_final_EEG.set'));
    if ~isempty(setCand)
        setPath = fullfile(setCand(1).folder, setCand(1).name);
        EEGref = pop_loadset(setPath);
        break;
    end
end
if isempty(EEGref) || ~isfield(EEGref,'chanlocs') || isempty(EEGref.chanlocs)
    error('Could not load a reference EEG set with chanlocs from %s', eegRoot);
end
refLabels = {EEGref.chanlocs.labels};
nChanRef  = numel(refLabels);

%% ---------------- QC ACCUMULATORS ----------------
rows = {}; % for summary CSV
% Columns: sub, n_epochs_open, n_epochs_closed, mean_exp_open, mean_exp_closed, mean_exp_diff, fooof_nchan_open, fooof_nchan_closed
allExpOpen  = [];  % nSub x nChan
allExpClose = [];  % nSub x nChan
subListKept = {};

posteriorAlphaRows = {}; % optional extra report

%% ---------------- MAIN LOOP ----------------
for i = 1:numel(subDirs)

    sub = subDirs(i).name;

    % ---------- PSD paths ----------
    psdOpenPath = fullfile(psdRoot, sub, sprintf('%s_desc-psd_method-welch_freqres-%s_cond-open.mat',   sub, freq_res_tag));
    psdCloPath  = fullfile(psdRoot, sub, sprintf('%s_desc-psd_method-welch_freqres-%s_cond-closed.mat', sub, freq_res_tag));

    if ~exist(psdOpenPath,'file') || ~exist(psdCloPath,'file')
        fprintf('SKIP %s: missing PSD mats (open=%d closed=%d)\n', sub, exist(psdOpenPath,'file')==2, exist(psdCloPath,'file')==2);
        continue;
    end

    % ---------- FOOOF paths ----------
    fooofOpenPath = fullfile(fooofRoot, sub, sprintf('%s_desc-fooof_cond-open.mat',   sub));
    fooofCloPath  = fullfile(fooofRoot, sub, sprintf('%s_desc-fooof_cond-closed.mat', sub));

    if ~exist(fooofOpenPath,'file') || ~exist(fooofCloPath,'file')
        fprintf('SKIP %s: missing FOOOF mats (open=%d closed=%d)\n', sub, exist(fooofOpenPath,'file')==2, exist(fooofCloPath,'file')==2);
        continue;
    end

    % ---------- Load PSD ----------
    Sopen = load(psdOpenPath);   % expects PSDopen, freqs, meta
    Sclo  = load(psdCloPath);    % expects PSDclosed, freqs, meta

    if ~isfield(Sopen,'PSDopen') || ~isfield(Sopen,'freqs')
        fprintf('SKIP %s: PSD OPEN mat missing PSDopen/freqs\n', sub); continue;
    end
    if ~isfield(Sclo,'PSDclosed') || ~isfield(Sclo,'freqs')
        fprintf('SKIP %s: PSD CLOSED mat missing PSDclosed/freqs\n', sub); continue;
    end
    if ~isfield(Sopen,'meta') || ~isfield(Sclo,'meta')
        fprintf('SKIP %s: PSD mats missing meta struct (need epoch counts)\n', sub); continue;
    end

    freqs_open = Sopen.freqs(:);
    freqs_clo  = Sclo.freqs(:);
    if numel(freqs_open) ~= numel(freqs_clo) || any(abs(freqs_open - freqs_clo) > 1e-12)
        fprintf('SKIP %s: freq grid differs open vs closed\n', sub); continue;
    end

    freqs = freqs_open;
    keepF = freqs <= fmax;
    f = freqs(keepF);

    PSDopen   = Sopen.PSDopen(keepF, :);    % [nFreq x nChan]
    PSDclosed = Sclo.PSDclosed(keepF, :);   % [nFreq x nChan]

    % Epoch counts
    nEpOpen   = safe_getfield(Sopen.meta, 'n_epochs_open',   NaN);
    nEpClosed = safe_getfield(Sclo.meta,  'n_epochs_closed', NaN);

    % ---------- Load FOOOF ----------
    Fopen = load(fooofOpenPath);
    Fclo  = load(fooofCloPath);

    % Exponent variable name can differ by implementation; try common options
    expOpen  = pick_first_existing(Fopen, {'exps','exp','exponent','exponents'});
    expClose = pick_first_existing(Fclo,  {'exps','exp','exponent','exponents'});

    if isempty(expOpen) || isempty(expClose)
        fprintf('SKIP %s: could not find exponent vector in fooof mats\n', sub);
        continue;
    end

    expOpen  = expOpen(:)';
    expClose = expClose(:)';

    % Match exponent length to reference chanlocs if needed
    if numel(expOpen) ~= nChanRef || numel(expClose) ~= nChanRef
        fprintf('SKIP %s: exponent length mismatch (open=%d closed=%d ref=%d)\n', sub, numel(expOpen), numel(expClose), nChanRef);
        continue;
    end

    expDiff = expClose - expOpen;

    % Store for grand averages
    subListKept{end+1,1} = sub;
    allExpOpen(end+1,:)  = expOpen;
    allExpClose(end+1,:) = expClose;

    % Summary numbers
    meanExpOpen  = mean(expOpen,  'omitnan');
    meanExpClose = mean(expClose, 'omitnan');
    meanExpDiff  = mean(expDiff,  'omitnan');

    rows(end+1,:) = {sub, nEpOpen, nEpClosed, meanExpOpen, meanExpClose, meanExpDiff, numel(expOpen), numel(expClose)};

   %% ---------------- PLOT 1: PSD + FOOOF aperiodic overlay ----------------

[mOpen, seOpen]     = mean_sem_across_ch(PSDopen);
[mClosed, seClosed] = mean_sem_across_ch(PSDclosed);

% --- reconstruct aperiodic fits (channel-wise) ---
% avoid f=0
validF = f > 0;
f_no0  = f(validF);

% open
aper_open = zeros(numel(f_no0), numel(expOpen));
for ch = 1:numel(expOpen)
    aper_open(:,ch) = 10.^( Fopen.offsets(ch) ...
        - expOpen(ch).*log10(f_no0) );
end
mAperOpen = mean(aper_open, 2, 'omitnan');

% closed
aper_closed = zeros(numel(f_no0), numel(expClose));
for ch = 1:numel(expClose)
    aper_closed(:,ch) = 10.^( Fclo.offsets(ch) ...
        - expClose(ch).*log10(f_no0) );
end
mAperClosed = mean(aper_closed, 2, 'omitnan');

% restrict PSD to >0 frequencies
mOpen_plot   = mOpen(validF);
mClosed_plot = mClosed(validF);
seOpen_plot  = seOpen(validF);
seClosed_plot= seClosed(validF);

fig1 = figure('Color','w','Position',[100 100 1100 450]);
ax1 = axes(fig1); hold(ax1,'on');

% PSD mean +/- SEM
h1 = plot_mean_sem(ax1, f_no0, mOpen_plot,   seOpen_plot,   COL_OPEN);
h2 = plot_mean_sem(ax1, f_no0, mClosed_plot, seClosed_plot, COL_CLOSED);

% Aperiodic fits (dashed)
h3 = plot(ax1, f_no0, mAperOpen,  '--', 'LineWidth',2,'Color',COL_OPEN*0.6);
h4 = plot(ax1, f_no0, mAperClosed,'--', 'LineWidth',2,'Color',COL_CLOSED*0.6);

% ---- AXIS FIX ----
set(ax1,'XScale','linear','YScale','log');   % linear Hz axis
xlim([0 fmax]);
xticks(0:5:fmax);
xlabel('Frequency (Hz)');
ylabel('PSD');

title(sprintf('%s | Welch PSD + FOOOF aperiodic', sub),'Interpreter','none');
legend([h1 h2 h3 h4],{'PSD open','PSD closed','FOOOF open','FOOOF closed'},...
    'Location','northeast');
grid(ax1,'on');

if save_png
    outPng = fullfile(qcOutDir, sprintf('%s_desc-qc_psd_fooof_overlay.png', sub));
    exportgraphics(fig1, outPng, 'Resolution', 200);
end
close(fig1);
    %% ---------------- OPTIONAL: posterior alpha sanity report -------------
    if do_posterior_alpha_check
        idxPost = find(ismember(refLabels, postChans));
        if ~isempty(idxPost)
            idxA = f >= alphaBand(1) & f <= alphaBand(2);
            aOpen  = mean(mean(PSDopen(idxA, idxPost), 2, 'omitnan'), 1, 'omitnan');
            aClose = mean(mean(PSDclosed(idxA, idxPost), 2, 'omitnan'), 1, 'omitnan');
            posteriorAlphaRows(end+1,:) = {sub, aOpen, aClose};
            fprintf('Posterior alpha: %s OPEN=%.4g | CLOSED=%.4g\n', sub, aOpen, aClose);
        end
    end

    %% ---------------- PLOT 2: exponent topographies ----------------------
    fig2 = figure('Color','w','Position',[100 100 1200 420]);

    % consistent map limits across panels (per subject)
    clim = [min([expOpen expClose expDiff],[],'omitnan'), max([expOpen expClose expDiff],[],'omitnan')];
    if any(~isfinite(clim)) || clim(1)==clim(2)
        clim = 'maxmin';
    end

    subplot(1,3,1);
    topoplot(expOpen, EEGref.chanlocs, 'electrodes','on');
    title('Exponent (open)');
    if isnumeric(clim); caxis(clim); end
    colorbar;

    subplot(1,3,2);
    topoplot(expClose, EEGref.chanlocs, 'electrodes','on');
    title('Exponent (closed)');
    if isnumeric(clim); caxis(clim); end
    colorbar;

    subplot(1,3,3);
    topoplot(expDiff, EEGref.chanlocs, 'electrodes','on');
    title('Exponent (closed - open)');
    if isnumeric(clim); caxis(clim); end
    colorbar;

    sgtitle(sprintf('%s | FOOOF exponent topo | nEp open=%s closed=%s', sub, num2str(nEpOpen), num2str(nEpClosed)), 'Interpreter','none');

    if save_png
        outPng2 = fullfile(qcOutDir, sprintf('%s_desc-qc_exponent_topos.png', sub));
        exportgraphics(fig2, outPng2, 'Resolution', 200);
    end
    close(fig2);

    fprintf('DONE %s\n', sub);

end

%% ---------------- GRAND AVERAGES ----------------
if ~isempty(allExpOpen)

    mExpOpen  = mean(allExpOpen,  1, 'omitnan');
    mExpClose = mean(allExpClose, 1, 'omitnan');
    mExpDiff  = mExpClose - mExpOpen;

    figG = figure('Color','w','Position',[100 100 1200 420]);

    climG = [min([mExpOpen mExpClose mExpDiff],[],'omitnan'), max([mExpOpen mExpClose mExpDiff],[],'omitnan')];
    if any(~isfinite(climG)) || climG(1)==climG(2)
        climG = 'maxmin';
    end

    subplot(1,3,1);
    topoplot(mExpOpen, EEGref.chanlocs, 'electrodes','on');
    title('Mean exponent (open)');
    if isnumeric(climG); caxis(climG); end
    colorbar;

    subplot(1,3,2);
    topoplot(mExpClose, EEGref.chanlocs, 'electrodes','on');
    title('Mean exponent (closed)');
    if isnumeric(climG); caxis(climG); end
    colorbar;

    subplot(1,3,3);
    topoplot(mExpDiff, EEGref.chanlocs, 'electrodes','on');
    title('Mean exponent (closed - open)');
    if isnumeric(climG); caxis(climG); end
    colorbar;

    sgtitle(sprintf('GRAND AVERAGE | N=%d subjects', size(allExpOpen,1)), 'Interpreter','none');

    if save_png
        outPngG = fullfile(qcOutDir, sprintf('grandAverage_desc-qc_exponent_topos_N-%d.png', size(allExpOpen,1)));
        exportgraphics(figG, outPngG, 'Resolution', 200);
    end
    close(figG);
end

%% ---------------- WRITE SUMMARY TABLES ----------------
summaryCsv = fullfile(qcOutDir, 'qc_summary_exponent_epochs.csv');
T = cell2table(rows, 'VariableNames', {'subject','n_epochs_open','n_epochs_closed','mean_exp_open','mean_exp_closed','mean_exp_closed_minus_open','nchan_exp_open','nchan_exp_closed'});
writetable(T, summaryCsv);

if do_posterior_alpha_check && ~isempty(posteriorAlphaRows)
    alphaCsv = fullfile(qcOutDir, 'qc_posterior_alpha_report.csv');
    Ta = cell2table(posteriorAlphaRows, 'VariableNames', {'subject','posterior_alpha_open','posterior_alpha_closed'});
    writetable(Ta, alphaCsv);
end

fprintf('\nQC DONE. Outputs in:\n  %s\n', qcOutDir);

%% ===================== LOCAL FUNCTIONS =====================

function v = safe_getfield(S, fld, defaultVal)
    if isstruct(S) && isfield(S, fld)
        v = S.(fld);
    else
        v = defaultVal;
    end
end

function vec = pick_first_existing(S, candidates)
    vec = [];
    for k = 1:numel(candidates)
        nm = candidates{k};
        if isfield(S, nm)
            vec = S.(nm);
            return;
        end
    end
end

function [m, se] = mean_sem_across_ch(PSD)
    % PSD: [nFreq x nChan]
    m  = mean(PSD, 2, 'omitnan');
    sd = std(PSD, 0, 2, 'omitnan');
    n  = sum(~isnan(PSD), 2);
    se = sd ./ sqrt(max(n,1));
end

function h = plot_mean_sem(ax, f, m, se, rgb)
    % plots mean + sem band with explicit color
    m  = m(:);
    se = se(:);
    f  = f(:);

    lo = m - se;
    hi = m + se;

    % keep positive for log plots
    lo = max(lo, eps);
    hi = max(hi, eps);
    m  = max(m, eps);

    patch(ax, [f; flipud(f)], [lo; flipud(hi)], rgb, ...
        'FaceAlpha', 0.18, 'EdgeColor', 'none');

    h = plot(ax, f, m, 'LineWidth', 1.8, 'Color', rgb);
end
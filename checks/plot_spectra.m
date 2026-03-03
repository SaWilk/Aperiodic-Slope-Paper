%% aperiodic_fooof_02_qc_plot_spectra.m
% QC plot of Welch PSD spectra (OPEN vs CLOSED) per subject
%
% Expects files created by prep_PSD_welch_for_fooof.m:
%   sub-XXX_desc-psd_method-welch_freqres-0p50_cond-open.mat   (contains PSDopen, freqs, meta)
%   sub-XXX_desc-psd_method-welch_freqres-0p50_cond-closed.mat (contains PSDclosed, freqs, meta)
%
% Output:
%   <psdRoot>\qc_plots\sub-XXX_psd_meanSpectra_open_vs_closed.png
%
% Notes:
% - This script avoids the common plotting pitfall where both curves get the same color.
% - Optional posterior alpha check prints a number per subject.
%
% Saskia Wilken / adapted from your pipeline conventions
% 27-Feb-2026

clear; clc;

%% ---------------- CONFIG ----------------
freq_res_tag = '0p50';   % must match your filename convention (0p50 for 0.5 Hz)
fmax         = 45;       % Hz shown
use_loglog   = true;     % typical for aperiodic checks
save_png     = true;

% Optional quick alpha sanity check (helps detect swapped open/closed)
do_posterior_alpha_check = true;
alpha_band = [8 12];
post = {'O1','O2','Oz','POz','Pz','PO3','PO4'};

psdRoot = fullfile('Z:\pb\KPP_KPN_joined\Aperiodic\Saskia\derivatives', '07_psd_welch');
outDir  = fullfile(psdRoot, 'qc_plots');
if ~exist(outDir,'dir'); mkdir(outDir); end

%% ---------------- FIND SUBJECT FOLDERS ----------------
subDirs = dir(fullfile(psdRoot, 'sub-*'));
subDirs = subDirs([subDirs.isdir]);

if isempty(subDirs)
    error('No sub-* folders found in %s', psdRoot);
end

%% ---------------- LOOP SUBJECTS ----------------
for i = 1:numel(subDirs)

    sub = subDirs(i).name;

    openPath = fullfile(psdRoot, sub, sprintf('%s_desc-psd_method-welch_freqres-%s_cond-open.mat',   sub, freq_res_tag));
    cloPath  = fullfile(psdRoot, sub, sprintf('%s_desc-psd_method-welch_freqres-%s_cond-closed.mat', sub, freq_res_tag));

    if ~exist(openPath,'file') || ~exist(cloPath,'file')
        fprintf('SKIP %s (missing PSD mat): open=%d closed=%d\n', sub, exist(openPath,'file')==2, exist(cloPath,'file')==2);
        continue;
    end

    % Load separately (because variables differ)
    Sopen = load(openPath);   % expects PSDopen, freqs, meta(optional)
    Sclo  = load(cloPath);    % expects PSDclosed, freqs, meta(optional)

    % Guard rails with helpful error messages
    if ~isfield(Sopen,'PSDopen')
        error('%s OPEN file missing PSDopen. Variables: %s', sub, strjoin(fieldnames(Sopen), ', '));
    end
    if ~isfield(Sclo,'PSDclosed')
        error('%s CLOSED file missing PSDclosed. Variables: %s', sub, strjoin(fieldnames(Sclo), ', '));
    end
    if ~isfield(Sopen,'freqs') || ~isfield(Sclo,'freqs')
        error('%s missing freqs in one of the files.', sub);
    end

    freqs_open = Sopen.freqs(:);
    freqs_clo  = Sclo.freqs(:);

    if numel(freqs_open) ~= numel(freqs_clo) || any(abs(freqs_open - freqs_clo) > 1e-12)
        fprintf('SKIP %s (freq grids differ between open/closed)\n', sub);
        continue;
    end

    freqs = freqs_open;
    keep  = freqs <= fmax;
    f     = freqs(keep);

    % PSD matrices are [nFreq x nChan]
    PSDopen   = Sopen.PSDopen(keep, :);
    PSDclosed = Sclo.PSDclosed(keep, :);

    % Mean + SEM across channels (per frequency)
    [mOpen,   seOpen]   = mean_sem_across_ch(PSDopen);
    [mClosed, seClosed] = mean_sem_across_ch(PSDclosed);

    %% ---------- optional posterior alpha sanity check ----------
    if do_posterior_alpha_check
        labels = {};
        if isfield(Sopen,'meta') && isstruct(Sopen.meta)
            if isfield(Sopen.meta,'chanlabels') && ~isempty(Sopen.meta.chanlabels)
                labels = Sopen.meta.chanlabels;
            elseif isfield(Sopen.meta,'chanlocs') && ~isempty(Sopen.meta.chanlocs) && isstruct(Sopen.meta.chanlocs)
                % sometimes stored as chanlocs structs
                try
                    labels = {Sopen.meta.chanlocs.labels};
                catch
                    labels = {};
                end
            end
        end

        if ~isempty(labels)
            idxPost = find(ismember(labels, post));
            idxA    = freqs >= alpha_band(1) & freqs <= alpha_band(2);

            aOpen  = mean(Sopen.PSDopen(idxA, idxPost), 'all', 'omitnan');
            aClose = mean(Sclo.PSDclosed(idxA, idxPost), 'all', 'omitnan');

            fprintf('Posterior alpha %s: OPEN.mat=%.4g | CLOSED.mat=%.4g\n', sub, aOpen, aClose);
        else
            fprintf('Posterior alpha %s: (skipped; no chan labels found in meta)\n', sub);
        end
    end

    %% ------------- FIGURE: mean spectra -------------
    fig = figure('Color','w','Position',[100 100 1100 500]);
    ax  = axes(fig); hold(ax,'on');

    hOpen  = plot_mean_sem(ax, f, mOpen,   seOpen);
    hClose = plot_mean_sem(ax, f, mClosed, seClosed);

    if use_loglog
        set(ax,'XScale','log','YScale','log');
        ylabel(ax,'PSD');
    else
        ylabel(ax,'PSD');
    end

    xlabel(ax,'Frequency (Hz)');
    title(ax, sprintf('%s | Welch PSD | freqres=%s | open vs closed', sub, freq_res_tag), 'Interpreter','none');
    legend(ax, [hOpen hClose], {'open','closed'}, 'Location','northeast');
    grid(ax,'on');

    if save_png
        outPng = fullfile(outDir, sprintf('%s_psd_meanSpectra_open_vs_closed.png', sub));
        exportgraphics(fig, outPng, 'Resolution', 200);
    end
    close(fig);

    fprintf('DONE %s\n', sub);
end

fprintf('All QC plots saved to: %s\n', outDir);

%% ---------------- LOCAL FUNCTIONS ----------------
function [m, se] = mean_sem_across_ch(PSD)
    % PSD: [nFreq x nChan]
    m  = mean(PSD, 2, 'omitnan');
    sd = std(PSD, 0, 2, 'omitnan');
    n  = sum(~isnan(PSD), 2);
    se = sd ./ sqrt(max(n,1));
end

function h = plot_mean_sem(ax, f, m, se)
    % Plots mean curve + SEM shading, using the axis color order correctly.

    % pick next color from axes color order
    co  = ax.ColorOrder;
    idx = mod(numel(ax.Children), size(co,1)) + 1;
    c   = co(idx,:);

    % protect log-scale plots from zeros/negatives
    m  = max(m, eps);
    lo = max(m-se, eps);
    hi = max(m+se, eps);

    % SEM band (hidden from legend)
    fill(ax, [f; flipud(f)], [lo; flipud(hi)], c, ...
        'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility','off');

    % mean line (used in legend)
    h = plot(ax, f, m, 'LineWidth', 1.8, 'Color', c);
end
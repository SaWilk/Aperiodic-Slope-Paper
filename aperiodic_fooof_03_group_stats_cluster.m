%% aperiodic_fooof_04_group_stats_cluster.m
%
% Group-level stats + cluster permutation on FOOOF exponent (aperiodic slope)
% + plots (mean topos, raw diffs + X marks, Cohen's d + parula + X marks)
% + spectra plots for significant clusters (2 groups only, PSD + fitted FOOOF lines)
%
% Styling additions:
%   - Transparent backgrounds (PNGs)
%   - ~2× larger fonts
%   - Thicker axes / colorbars
%   - X markers (RAW: white; d: black)
%   - p-value (first 3 decimals) shown in RAW + d topographies (cluster-corrected)
%   - Tables only written if significant
%   - Spectra only plotted for significant clusters
%   - ALSO export SVGs for all figures
%   - Output tables additionally include mean R² of FOOOF fit (overall + per group)
%
% Saskia Wilken

clear; clc;

%% ================= CONFIG =================
root     = 'Z:\pb\KPP_KPN_joined\Aperiodic\Saskia';
rawDir   = fullfile(root, 'rawdata');
derivDir = fullfile(root, 'derivatives');

fooofRoot = fullfile(derivDir, '08_fooof');
psdRoot   = fullfile(derivDir, '07_psd_welch');

outBase = fullfile(fooofRoot, 'stats_extended');
outTopo = fullfile(outBase, 'topos');
outSpec = fullfile(outBase, 'spectra_sigclusters');
outTbl  = fullfile(outBase, 'tables');

if ~exist(outBase,'dir'); mkdir(outBase); end
if ~exist(outTopo,'dir'); mkdir(outTopo); end
if ~exist(outSpec,'dir'); mkdir(outSpec); end
if ~exist(outTbl,'dir');  mkdir(outTbl);  end

alpha_cluster = 0.05;
alpha_test    = 0.05;
nperm         = 2000;

groups  = ["HC","CHR","PP"];
pairs   = {"HC","CHR"; "HC","PP"; "CHR","PP"};

% FOOOF/PSD frequency range for (re)constructing the aperiodic fit line
fitRange = [1 45]; % Hz

% ===== Spectra colors (match your provided figure: HC=purple, PP=orange, CHR=green) =====
% (Pastel tones sampled/approximated from the figure)
COL.HC  = [0.742 0.681 0.826];  % purple
COL.PP  = [0.833 0.683 0.528];  % orange
COL.CHR = [0.498 0.781 0.496];  % green

% ===== X marker styling =====
% RAW exponent difference plots: WHITE X
XCOL_RAW = [1 1 1];
% Effect size plots: BLACK X
XCOL_D   = [0 0 0];

XSIZE = 12;
XW    = 2.5;

% ---- Styling (≈2× larger fonts + thicker axes/cbars) ----
STYLE.fontBase   = 18;    % was ~9–10 typically -> doubled
STYLE.fontTitle  = 20;
STYLE.fontCbar   = 16;
STYLE.axLineW    = 1.8;
STYLE.cbarLineW  = 1.6;

%% ================= EEGLAB + FIELDTRIP =================
eeglabDir = 'K:\Wilken_Arbeitsordner\MATLAB\eeglab_current\eeglab2025.1.0';
addpath(eeglabDir);
try, eeglab('nogui'); catch, addpath(genpath(eeglabDir)); eeglab('nogui'); end

ftDir = 'K:\Wilken_Arbeitsordner\MATLAB\fieldtrip-20260227';
addpath(ftDir);
ft_defaults;

chanloc_set = fullfile(derivDir,'06_epoched_runica','sub-002', ...
    'sub-002_ses-01_task-baseline_eeg_cond-closed_epoched_final_EEG.set');
EEGref        = pop_loadset(chanloc_set);
chanlocs_all  = EEGref.chanlocs;
labels_all    = {chanlocs_all.labels};

% Build neighbour structure from chanloc coords (drop NaN coords)
xyz  = [[chanlocs_all.X]' [chanlocs_all.Y]' [chanlocs_all.Z]'];
good = all(isfinite(xyz),2);

chanlocs = chanlocs_all(good);
labels   = labels_all(good);
xyz      = xyz(good,:);

elec = [];
elec.label   = labels(:);
elec.elecpos = xyz;
elec.chanpos = xyz;
elec.unit    = 'mm';

cfgN = [];
cfgN.method   = 'triangulation';
cfgN.channel  = labels;
cfgN.elec     = elec;
cfgN.feedback = 'no';
neigh = ft_prepare_neighbours(cfgN);

%% ================= LOAD PARTICIPANTS =================
xlsxPath = fullfile(rawDir,'participants.xlsx');
if ~exist(xlsxPath,'file')
    error('Missing participants.xlsx: %s', xlsxPath);
end

Traw = readtable(xlsxPath,'VariableNamingRule','preserve');

% hard requirement: VPNummer + Group columns
if ~all(ismember({'VPNummer','Group'}, string(Traw.Properties.VariableNames)))
    disp(Traw.Properties.VariableNames);
    error('participants.xlsx must contain VPNummer and Group columns.');
end

Traw.Group = upper(string(Traw.Group));
Traw.sub   = string(arrayfun(@(x)sprintf('sub-%03d',x), Traw.VPNummer,'uni',0));
Traw = Traw(ismember(Traw.Group,groups),:);

%% =====================================================================
%% ====================== LOOP CONDITIONS ==============================
%% =====================================================================
for cond_to_use = ["open","closed"]

    fprintf('\n=========== CONDITION: %s ===========\n', cond_to_use);

    %% ---------- Load exponents (+ R²) ----------
    expMat   = [];
    r2Mat    = [];
    keepRows = false(height(Traw),1);

    for i = 1:height(Traw)
        sub = char(Traw.sub(i));
        f = fullfile(fooofRoot, sub, sprintf('%s_desc-fooof_cond-%s.mat', sub, cond_to_use));
        if ~exist(f,'file'), continue; end

        S = load(f);
        if ~isfield(S,'exps') || isempty(S.exps), continue; end

        exps = S.exps(:)';   % full channel vector
        exps = exps(good);   % enforce same channel subset as chanlocs/neigh

        r2s  = extract_r2_vector(S); % robustly try to get R² vector
        if ~isempty(r2s)
            r2s = r2s(:)';          % ensure row
            if numel(r2s) == numel(good)
                r2s = r2s(good);
            elseif numel(r2s) == numel(exps)
                % already matches "good" subset length
            else
                % mismatch -> set to NaN so we don't break anything
                r2s = nan(1, numel(exps));
            end
        else
            r2s = nan(1, numel(exps));
        end

        if isempty(expMat)
            expMat = nan(height(Traw), numel(exps));
            r2Mat  = nan(height(Traw), numel(exps));
        end

        if numel(exps) ~= size(expMat,2)
            fprintf('SKIP %s: exponent length mismatch (%d vs %d)\n', sub, numel(exps), size(expMat,2));
            continue;
        end

        expMat(i,:) = exps;
        r2Mat(i,:)  = r2s;

        keepRows(i) = true;
    end

    T      = Traw(keepRows,:);
    expMat = expMat(keepRows,:);
    r2Mat  = r2Mat(keepRows,:);

    if isempty(T)
        warning('No usable FOOOF data for %s', cond_to_use);
        continue;
    end

    % report group sizes
    for g = groups
        fprintf('  %s: N=%d\n', g, sum(T.Group==g));
    end

    %% ---------- Group means / SD ----------
    grpMean = struct(); grpSD = struct();
    for g = groups
        idx = T.Group==g;
        grpMean.(g) = mean(expMat(idx,:),1,'omitnan')';
        grpSD.(g)   = std(expMat(idx,:),0,1,'omitnan')';
    end

    %% ---------- Shared color scales ----------
    % Absolute: min .. 95th percentile (winsorize top 5%)
    absVals = cell2mat(struct2cell(grpMean));
    absMin  = min(absVals(:));
    abs95   = prctile(absVals(:),95);
    absLim  = [absMin abs95];

    % Raw differences: symmetric 95% of abs across all pair diffs
    diffVals = [];
    for p = 1:size(pairs,1)
        diffVals = [diffVals; grpMean.(pairs{p,1}) - grpMean.(pairs{p,2})]; %#ok<AGROW>
    end
    diffLimAbs = prctile(abs(diffVals(:)),95);
    diffLim    = [-diffLimAbs diffLimAbs];

    %% ---------- Plot mean topos (same scale) ----------
    for g = groups
        fig = figure('Visible','off','Color','none');
        ax  = axes(fig); %#ok<NASGU>
        topoplot(grpMean.(g), chanlocs, 'maplimits', absLim, 'electrodes','on');
        cb=colorbar; ylabel(cb,'Aperiodic exponent');
        title(sprintf('%s mean exponent (%s) | N=%d', g, cond_to_use, sum(T.Group==g)), 'Interpreter','none');

        apply_style_current_axes(STYLE, cb);

        baseName = fullfile(outTopo, sprintf('meanTopo_%s_%s', g, cond_to_use));
        safe_export_png(fig, [baseName '.png']);
        safe_export_svg(fig, [baseName '.svg']);
        close(fig);
    end

    %% ================== BUILD FIELDTRIP INPUT STRUCTS ==================
    subsFT = cell(height(T),1);
    for i = 1:height(T)
        D=[];
        D.label  = labels(:);
        D.time   = 0;
        D.dimord = 'chan_time';
        D.avg    = expMat(i,:)' ;
        subsFT{i}= D;
    end

    %% ================== OMNIBUS ANOVA CLUSTER ==================
    design=zeros(1,height(T));
    design(T.Group=="HC")  = 1;
    design(T.Group=="CHR") = 2;
    design(T.Group=="PP")  = 3;

    cfg=[];
    cfg.method            = 'montecarlo';
    cfg.statistic         = 'indepsamplesF';
    cfg.correctm          = 'cluster';
    cfg.clusteralpha      = alpha_cluster;
    cfg.clusterstatistic  = 'maxsum';
    cfg.minnbchan         = 2;
    cfg.neighbours        = neigh;
    cfg.tail              = 1;
    cfg.clustertail       = 1;
    cfg.alpha             = alpha_test;
    cfg.numrandomization  = nperm;
    cfg.design            = design;
    cfg.ivar              = 1;

    fprintf('Running cluster ANOVA (%s)...\n', cond_to_use);
    statF = ft_timelockstatistics(cfg, subsFT{:});
    save(fullfile(outBase, sprintf('stat_clusterANOVA_%s.mat', cond_to_use)), 'statF');

    % Only write ANOVA table if something significant (now includes mean R²)
    outCsvANOVA = fullfile(outTbl, sprintf('clusters_ANOVA_%s.csv', cond_to_use));
    write_cluster_table_if_sig(statF, alpha_test, outCsvANOVA, r2Mat, T, [], [], "ANOVA");

    %% ================== PAIRWISE CLUSTER TESTS + PLOTS ==================
    for p = 1:size(pairs,1)

        g1=pairs{p,1}; g2=pairs{p,2};
        idx1=find(T.Group==g1);
        idx2=find(T.Group==g2);

        dat1=subsFT(idx1);
        dat2=subsFT(idx2);

        design2=[ones(1,numel(idx1)), 2*ones(1,numel(idx2))];

        cfg2=[];
        cfg2.method            = 'montecarlo';
        cfg2.statistic         = 'indepsamplesT';
        cfg2.correctm          = 'cluster';
        cfg2.clusteralpha      = alpha_cluster;
        cfg2.clusterstatistic  = 'maxsum';
        cfg2.minnbchan         = 2;
        cfg2.neighbours        = neigh;
        cfg2.tail              = 0;
        cfg2.clustertail       = 0;
        cfg2.alpha             = alpha_test;
        cfg2.numrandomization  = nperm;
        cfg2.design            = design2;
        cfg2.ivar              = 1;

        fprintf('Running pairwise cluster %s vs %s (%s)...\n', g1, g2, cond_to_use);
        statT = ft_timelockstatistics(cfg2, dat1{:}, dat2{:});
        save(fullfile(outBase, sprintf('stat_cluster_%s_vs_%s_%s.mat', g1, g2, cond_to_use)), 'statT');

        % Determine significant channels from corrected mask
        if isfield(statT,'mask') && ~isempty(statT.mask)
            sigIdx = find(statT.mask(:,1) == 1);
        else
            sigIdx = [];
        end
        hasSig = ~isempty(sigIdx);

        % cluster-corrected p-value to display (best/lowest across pos+neg)
        pBest = get_best_cluster_p(statT);
        if isnan(pBest)
            pStr = 'p=n/a';
        else
            pStr = sprintf('p=%.3f', pBest);
        end

        % Only write table if significant (now includes mean R² overall + per group)
        outCsv = fullfile(outTbl, sprintf('clusters_%s_vs_%s_%s.csv', g1, g2, cond_to_use));
        write_cluster_table_if_sig(statT, alpha_test, outCsv, r2Mat, T, idx1, idx2, sprintf('%s_vs_%s', g1, g2));

        % ---- RAW exponent difference topo (with WHITE X marks) ----
        topoDiffRaw = grpMean.(g1) - grpMean.(g2);

        fig = figure('Visible','off','Color','none');
        ax = axes(fig); %#ok<NASGU>
        topoplot(topoDiffRaw, chanlocs, 'maplimits', diffLim, 'electrodes','on', ...
            'emarker2', {sigIdx, '*', XCOL_RAW, XSIZE, XW});
        cb=colorbar; ylabel(cb,'\Delta exponent (raw)');
        title(sprintf('RAW diff exponent: %s - %s | %s | %s | sigCh=%d', ...
            g1, g2, cond_to_use, pStr, numel(sigIdx)), 'Interpreter','none');

        apply_style_current_axes(STYLE, cb);

        baseName = fullfile(outTopo, sprintf('diffRAW_%s_minus_%s_%s_sigX', g1, g2, cond_to_use));
        safe_export_png(fig, [baseName '.png']);
        safe_export_svg(fig, [baseName '.svg']);
        close(fig);

        % ---- Cohen''s d topo (parula, with BLACK X marks) ----
        n1=numel(idx1); n2=numel(idx2);
        s1=grpSD.(g1); s2=grpSD.(g2);
        pooled = sqrt(((n1-1).*s1.^2 + (n2-1).*s2.^2)./(n1+n2-2));
        d = topoDiffRaw ./ pooled;

        dLimAbs = prctile(abs(d),95);
        dLim = [-dLimAbs dLimAbs];

        fig = figure('Visible','off','Color','none');
        ax = axes(fig); %#ok<NASGU>
        topoplot(d, chanlocs, 'maplimits', dLim, 'electrodes','on', ...
            'emarker2', {sigIdx, 'x', XCOL_D, XSIZE, XW});
        colormap(fig, parula);
        cb=colorbar; ylabel(cb,'Cohen''s d');
        title(sprintf('Effect size (d): %s - %s | %s | %s | sigCh=%d', ...
            g1, g2, cond_to_use, pStr, numel(sigIdx)), 'Interpreter','none');

        apply_style_current_axes(STYLE, cb);

        baseName = fullfile(outTopo, sprintf('effectsizeD_%s_minus_%s_%s_sigX', g1, g2, cond_to_use));
        safe_export_png(fig, [baseName '.png']);
        safe_export_svg(fig, [baseName '.svg']);
        close(fig);

        % ---- Significant-cluster spectra plots (ONLY IF there are sig electrodes) ----
        if hasSig
            sigLabels = labels(sigIdx);
            plot_sig_cluster_spectra_two_groups( ...
                T, g1, g2, sigLabels, labels, good, psdRoot, fooofRoot, ...
                cond_to_use, fitRange, COL, outSpec, STYLE);
        end
    end

end % condition loop

fprintf('\nDONE.\n');

%% ======================================================================
%% ============================= FUNCTIONS ===============================
%% ======================================================================

function r2s = extract_r2_vector(S)
% Try to robustly extract an R²-per-channel vector from the loaded FOOOF .mat.
% Returns [] if nothing plausible is found.

r2s = [];

cands = ["r2s","r2","r_squared","rsquared","rSquared","R2","fooof_r2","r2_all","r2_per_chan"];
for nm = cands
    if isfield(S, nm)
        v = S.(nm);
        if isnumeric(v) && ~isempty(v)
            r2s = v;
            return;
        end
    end
end

% Sometimes nested structs (rare, but safe to check)
fn = fieldnames(S);
for i = 1:numel(fn)
    f = S.(fn{i});
    if isstruct(f)
        for nm = cands
            if isfield(f, nm)
                v = f.(nm);
                if isnumeric(v) && ~isempty(v)
                    r2s = v;
                    return;
                end
            end
        end
    end
end
end

function wrote = write_cluster_table_if_sig(stat, alpha_test, outCsv, r2Mat, T, idx1, idx2, labelTag)
% Writes semicolon CSV ONLY if any cluster has prob <= alpha_test.
% Includes channel list per cluster.
% Additionally includes mean R² of the FOOOF fit:
%   - mean_r2_all: across all subjects relevant for this test (all for ANOVA; g1+g2 for pairwise)
%   - mean_r2_g1 / mean_r2_g2 for pairwise (NaN for ANOVA)
%
% idx1/idx2 are row indices into T for g1/g2 in the pairwise case; for ANOVA pass []/[].

wrote = false;
rows = {};

isPairwise = ~isempty(idx1) && ~isempty(idx2);

if isPairwise
    rowsAll = [idx1(:); idx2(:)];
    g1Name  = string(T.Group(idx1(1)));
    g2Name  = string(T.Group(idx2(1)));
else
    rowsAll = (1:height(T))';
    g1Name  = "";
    g2Name  = "";
end

% Positive clusters
if isfield(stat,'posclusters') && ~isempty(stat.posclusters) && isfield(stat,'posclusterslabelmat')
    for k=1:numel(stat.posclusters)
        p = stat.posclusters(k).prob;
        if p <= alpha_test
            chanMask = (stat.posclusterslabelmat(:,1)==k);
            chans = stat.label(chanMask);

            [mAll, m1, m2] = compute_mean_r2(r2Mat, rowsAll, idx1, idx2, chanMask);

            rows(end+1,:) = { ...
                "pos", k, p, stat.posclusters(k).clusterstat, ...
                strjoin(string(chans), " "), ...
                mAll, m1, m2, char(g1Name), char(g2Name), char(labelTag) ...
                }; %#ok<AGROW>
        end
    end
end

% Negative clusters
if isfield(stat,'negclusters') && ~isempty(stat.negclusters) && isfield(stat,'negclusterslabelmat')
    for k=1:numel(stat.negclusters)
        p = stat.negclusters(k).prob;
        if p <= alpha_test
            chanMask = (stat.negclusterslabelmat(:,1)==k);
            chans = stat.label(chanMask);

            [mAll, m1, m2] = compute_mean_r2(r2Mat, rowsAll, idx1, idx2, chanMask);

            rows(end+1,:) = { ...
                "neg", k, p, stat.negclusters(k).clusterstat, ...
                strjoin(string(chans), " "), ...
                mAll, m1, m2, char(g1Name), char(g2Name), char(labelTag) ...
                }; %#ok<AGROW>
        end
    end
end

if isempty(rows)
    % no output if nothing significant (as requested)
    return;
end

Tout = cell2table(rows, 'VariableNames', { ...
    'sign','cluster_id','p','clusterstat','channels', ...
    'mean_r2_all','mean_r2_g1','mean_r2_g2','g1','g2','test'});

writetable(Tout, outCsv, 'Delimiter',';');
wrote = true;
end

function [mAll, m1, m2] = compute_mean_r2(r2Mat, rowsAll, idx1, idx2, chanMask)
% chanMask is logical over channels (same ordering as r2Mat columns).
mAll = NaN; m1 = NaN; m2 = NaN;

if isempty(r2Mat) || all(isnan(r2Mat(:)))
    return;
end

chIdx = find(chanMask);
if isempty(chIdx)
    return;
end

tmpAll = r2Mat(rowsAll, chIdx);
mAll   = mean(tmpAll(:), 'omitnan');

if ~isempty(idx1) && ~isempty(idx2)
    tmp1 = r2Mat(idx1, chIdx);
    tmp2 = r2Mat(idx2, chIdx);
    m1   = mean(tmp1(:), 'omitnan');
    m2   = mean(tmp2(:), 'omitnan');
end
end

function pBest = get_best_cluster_p(stat)
% Returns best (lowest) cluster-corrected p across pos+neg clusters.
% If no clusters exist, returns NaN.

pBest = NaN;
pCand = [];

if isfield(stat,'posclusters') && ~isempty(stat.posclusters)
    pCand = [pCand, [stat.posclusters.prob]];
end
if isfield(stat,'negclusters') && ~isempty(stat.negclusters)
    pCand = [pCand, [stat.negclusters.prob]];
end

if ~isempty(pCand)
    pBest = min(pCand);
end
end

function apply_style_current_axes(STYLE, cb)
% Applies consistent font sizing + thicker axes/cbar.
ax = gca;

set(ax, 'FontSize', STYLE.fontBase, 'LineWidth', STYLE.axLineW);
ax.XAxis.TickLength = [0.015 0.015];
ax.YAxis.TickLength = [0.015 0.015];

% Title sizing (topoplot sets it via title(); we override here)
tt = get(ax,'Title');
if ~isempty(tt) && isgraphics(tt)
    set(tt, 'FontSize', STYLE.fontTitle, 'FontWeight', 'normal');
end

if nargin >= 2 && ~isempty(cb) && isgraphics(cb)
    set(cb, 'FontSize', STYLE.fontCbar, 'LineWidth', STYLE.cbarLineW);
end
end

function safe_export_png(fig, outPng)
% Exports with transparent background if supported; otherwise falls back safely.

try
    exportgraphics(fig, outPng, 'Resolution', 220, 'BackgroundColor', 'none');
catch
    set(fig, 'Color', 'none');
    print(fig, outPng, '-dpng', '-r220');
end
end

function safe_export_svg(fig, outSvg)
% Vector export for Inkscape processing.

try
    exportgraphics(fig, outSvg, 'ContentType','vector', 'BackgroundColor','none');
catch
    % Fallback; some MATLAB versions ignore transparency here, but SVG remains editable
    print(fig, outSvg, '-dsvg');
end
end

function plot_sig_cluster_spectra_two_groups(T, g1, g2, sigLabels, labels, good, psdRoot, fooofRoot, cond_to_use, fitRange, COL, outDir, STYLE)
% Plots mean PSD (across sig electrodes, then across subjects) for TWO groups only,
% plus mean reconstructed aperiodic fit line (dashed).
% Title includes electrode list.

groups2 = [string(g1) string(g2)];

% Accumulators
PSDm = struct(); FITm = struct();
freqsRef = [];

for gg = groups2

    idx = find(T.Group==gg);
    subjP = []; subjF = [];

    for ii = idx'
        sub = char(T.sub(ii));

        psdFile = fullfile(psdRoot, sub, sprintf('%s_desc-psd_method-welch_freqres-0p50_cond-%s.mat', sub, cond_to_use));
        fooFile = fullfile(fooofRoot, sub, sprintf('%s_desc-fooof_cond-%s.mat', sub, cond_to_use));
        if ~exist(psdFile,'file') || ~exist(fooFile,'file'), continue; end

        P = load(psdFile);
        F = load(fooFile);

        if ~isfield(P,'freqs'), continue; end
        if ~isfield(F,'exps') || ~isfield(F,'offsets'), continue; end

        freqs = P.freqs(:);
        keepF = freqs>=fitRange(1) & freqs<=fitRange(2);
        freqs = freqs(keepF);

        if isempty(freqsRef), freqsRef = freqs; end
        if numel(freqs) ~= numel(freqsRef) || any(abs(freqs-freqsRef)>1e-10)
            continue;
        end

        key="PSDclosed"; if cond_to_use=="open", key="PSDopen"; end
        if ~isfield(P,key), continue; end

        % PSD: nF(full) x nChan(full). Reduce to "good" channels and frequency range.
        PSD = P.(key);
        if size(PSD,2) < numel(good)
            continue;
        end
        PSD = PSD(:, good);
        PSD = PSD(keepF, :);

        % FOOOF params: reduce to good as well
        exps_all = F.exps(:)';      exps_all = exps_all(good);
        offs_all = F.offsets(:)';   offs_all = offs_all(good);

        % map significant labels to indices (labels already correspond to good channels)
        idxCh = find(ismember(string(labels), string(sigLabels)));
        if isempty(idxCh), continue; end

        PSDsig = mean(PSD(:, idxCh), 2, 'omitnan');

        expMean = mean(exps_all(idxCh), 'omitnan');
        offMean = mean(offs_all(idxCh), 'omitnan');

        fitLine = 10.^(offMean - expMean.*log10(freqs));

        subjP = [subjP, PSDsig]; %#ok<AGROW>
        subjF = [subjF, fitLine]; %#ok<AGROW>
    end

    if isempty(subjP)
        PSDm.(gg) = [];
        FITm.(gg) = [];
    else
        PSDm.(gg) = mean(subjP, 2, 'omitnan');
        FITm.(gg) = mean(subjF, 2, 'omitnan');
    end
end

if isempty(freqsRef), return; end
if isempty(PSDm.(groups2(1))) || isempty(PSDm.(groups2(2))), return; end

% Electrode list for title (truncate if huge)
elecStr = strjoin(string(sigLabels), " ");
if strlength(elecStr) > 180
    elecStr = extractBefore(elecStr, 180) + "...";
end

fig = figure('Visible','off','Color','none','Position',[100 100 1050 480]);
ax = axes(fig); hold(ax,'on');

for gg = groups2
    plot(ax, freqsRef, PSDm.(gg), 'LineWidth', 3, 'Color', COL.(char(gg)));
    plot(ax, freqsRef, FITm.(gg), '--', 'LineWidth', 2.7, 'Color', COL.(char(gg)));
end

set(ax,'XScale','log','YScale','log');
xlabel(ax,'Frequency (Hz)');
ylabel(ax,'PSD');
grid(ax,'on');

xt = [1 2 3 5 8 10 15 20 30 40];
xt = xt(xt>=min(freqsRef) & xt<=max(freqsRef));
ax.XTick = xt;
ax.XTickLabel = string(xt);

legend(ax, { ...
    sprintf('%s PSD', groups2(1)), sprintf('%s fit', groups2(1)), ...
    sprintf('%s PSD', groups2(2)), sprintf('%s fit', groups2(2))}, ...
    'Location','southwest');

title(ax, sprintf('Sig-cluster spectra | %s vs %s | %s | electrodes: %s', ...
    groups2(1), groups2(2), cond_to_use, elecStr), 'Interpreter','none');

set(ax, 'FontSize', STYLE.fontBase, 'LineWidth', STYLE.axLineW);
tt = get(ax,'Title'); if isgraphics(tt), set(tt,'FontSize',STYLE.fontTitle,'FontWeight','normal'); end

baseName = fullfile(outDir, sprintf('spectra_sigCluster_%s_vs_%s_%s', groups2(1), groups2(2), cond_to_use));
safe_export_png(fig, [baseName '.png']);
safe_export_svg(fig, [baseName '.svg']);
close(fig);
end
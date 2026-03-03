%% aperiodic_fooof_04_group_stats_cluster.m
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

% Colors for group spectra (explicit!)
COL.HC  = [0.15 0.55 0.25];
COL.CHR = [0.85 0.35 0.15];
COL.PP  = [0.20 0.45 0.85];

% X marker styling (dark brown)
XCOL = [0.35 0.18 0.05];
XSIZE = 10;
XW    = 2;

%% ================= EEGLAB + FIELDTRIP =================
eeglabDir = 'K:\Wilken_Arbeitsordner\MATLAB\eeglab_current\eeglab2025.1.0';
addpath(eeglabDir);
try, eeglab('nogui'); catch, addpath(genpath(eeglabDir)); eeglab('nogui'); end

ft_defaults;

chanloc_set = fullfile(derivDir,'06_epoched_runica','sub-002',...
    'sub-002_ses-01_task-baseline_eeg_cond-closed_epoched_final_EEG.set');
EEGref   = pop_loadset(chanloc_set);
chanlocs_all = EEGref.chanlocs;
labels_all   = {chanlocs_all.labels};

% Build neighbour structure from chanloc coords (drop NaN coords)
xyz = [[chanlocs_all.X]' [chanlocs_all.Y]' [chanlocs_all.Z]'];
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
Traw = readtable(fullfile(rawDir,'participants.xlsx'),'VariableNamingRule','preserve');
Traw.Group = upper(string(Traw.Group));
Traw.sub   = string(arrayfun(@(x)sprintf('sub-%03d',x), Traw.VPNummer,'uni',0));
Traw = Traw(ismember(Traw.Group,groups),:);

%% =====================================================================
%% ====================== LOOP CONDITIONS ==============================
%% =====================================================================
for cond_to_use = ["open","closed"]

    fprintf('\n=========== CONDITION: %s ===========\n', cond_to_use);

    %% ---------- Load exponents ----------
    expMat   = [];
    keepRows = false(height(Traw),1);

    for i = 1:height(Traw)
        sub = char(Traw.sub(i));
        f = fullfile(fooofRoot, sub, sprintf('%s_desc-fooof_cond-%s.mat', sub, cond_to_use));
        if ~exist(f,'file'), continue; end

        S = load(f);
        if ~isfield(S,'exps') || isempty(S.exps), continue; end

        exps = S.exps(:)';         % full channel vector
        exps = exps(good);         % enforce same channel subset as chanlocs/neigh

        if isempty(expMat)
            expMat = nan(height(Traw), numel(exps));
        end

        if numel(exps) ~= size(expMat,2)
            fprintf('SKIP %s: exponent length mismatch (%d vs %d)\n', sub, numel(exps), size(expMat,2));
            continue;
        end

        expMat(i,:) = exps;
        keepRows(i) = true;
    end

    T = Traw(keepRows,:);
    expMat = expMat(keepRows,:);

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
    % Absolute (all groups): min .. 95th percentile (winsorize top 5%)
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
        fig = figure('Visible','off');
        topoplot(grpMean.(g), chanlocs, 'maplimits', absLim, 'electrodes','on');
        cb=colorbar; ylabel(cb,'Aperiodic exponent');
        title(sprintf('%s mean exponent (%s) | N=%d', g, cond_to_use, sum(T.Group==g)), 'Interpreter','none');
        saveas(fig, fullfile(outTopo, sprintf('meanTopo_%s_%s.png', g, cond_to_use)));
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

    % Only write ANOVA table if something significant
    write_cluster_table_if_sig(statF, alpha_test, ...
        fullfile(outTbl, sprintf('clusters_ANOVA_%s.csv', cond_to_use)));

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

        % Determine significant channels (mask) + significant clusters
        if isfield(statT,'mask')
            sigIdx = find(statT.mask(:,1) == 1);
        else
            sigIdx = [];
        end
        hasSig = ~isempty(sigIdx);

        % Only write table if significant
        outCsv = fullfile(outTbl, sprintf('clusters_%s_vs_%s_%s.csv', g1, g2, cond_to_use));
        wroteTable = write_cluster_table_if_sig(statT, alpha_test, outCsv);

        % ---- RAW exponent difference topo (with X marks) ----
        topoDiffRaw = grpMean.(g1) - grpMean.(g2);

        fig = figure('Visible','off');
        topoplot(topoDiffRaw, chanlocs, 'maplimits', diffLim, 'electrodes','on', ...
            'emarker2', {sigIdx, 'x', XCOL, XSIZE, XW});
        cb=colorbar; ylabel(cb,'Δ exponent (raw)');
        title(sprintf('RAW diff exponent: %s - %s | %s | sigCh=%d', g1, g2, cond_to_use, numel(sigIdx)), 'Interpreter','none');
        saveas(fig, fullfile(outTopo, sprintf('diffRAW_%s_minus_%s_%s_sigX.png', g1, g2, cond_to_use)));
        close(fig);

        % ---- Cohen''s d topo (parula, with X marks) ----
        n1=numel(idx1); n2=numel(idx2);
        s1=grpSD.(g1); s2=grpSD.(g2);
        pooled = sqrt(((n1-1).*s1.^2 + (n2-1).*s2.^2)./(n1+n2-2));
        d = topoDiffRaw ./ pooled;

        dLimAbs = prctile(abs(d),95);
        dLim = [-dLimAbs dLimAbs];

        fig = figure('Visible','off');
        topoplot(d, chanlocs, 'maplimits', dLim, 'electrodes','on', ...
            'emarker2', {sigIdx, 'x', XCOL, XSIZE, XW});
        colormap(fig, parula);
        cb=colorbar; ylabel(cb,'Cohen''s d');
        title(sprintf('Effect size (d): %s - %s | %s | sigCh=%d', g1, g2, cond_to_use, numel(sigIdx)), 'Interpreter','none');
        saveas(fig, fullfile(outTopo, sprintf('effectsizeD_%s_minus_%s_%s_sigX.png', g1, g2, cond_to_use)));
        close(fig);

        % ---- Significant-cluster spectra plots (ONLY IF significant) ----
        if hasSig
            sigLabels = labels(sigIdx);
            plot_sig_cluster_spectra_two_groups( ...
                T, g1, g2, sigLabels, psdRoot, fooofRoot, cond_to_use, fitRange, COL, outSpec);
        end

        % (Optional) If you want: only generate spectra when the table was written
        % (i.e. when clusters are truly significant by prob, not just mask)
        % uncomment:
        % if wroteTable && hasSig
        %    ...
        % end
    end

end % condition loop

fprintf('\nDONE.\n');

%% ======================================================================
%% ============================= FUNCTIONS ===============================
%% ======================================================================

function wrote = write_cluster_table_if_sig(stat, alpha_test, outCsv)
% Writes semicolon CSV ONLY if any cluster has prob <= alpha_test.
% Includes channel list per cluster.
%
% Returns wrote=true/false.

wrote = false;
rows = {};

% Positive clusters
if isfield(stat,'posclusters') && ~isempty(stat.posclusters) && isfield(stat,'posclusterslabelmat')
    for k=1:numel(stat.posclusters)
        p = stat.posclusters(k).prob;
        if p <= alpha_test
            chans = stat.label(stat.posclusterslabelmat(:,1)==k);
            rows(end+1,:) = { "pos", k, p, stat.posclusters(k).clusterstat, strjoin(string(chans), " ") }; %#ok<AGROW>
        end
    end
end

% Negative clusters
if isfield(stat,'negclusters') && ~isempty(stat.negclusters) && isfield(stat,'negclusterslabelmat')
    for k=1:numel(stat.negclusters)
        p = stat.negclusters(k).prob;
        if p <= alpha_test
            chans = stat.label(stat.negclusterslabelmat(:,1)==k);
            rows(end+1,:) = { "neg", k, p, stat.negclusters(k).clusterstat, strjoin(string(chans), " ") }; %#ok<AGROW>
        end
    end
end

if isempty(rows)
    % no output if nothing significant (as requested)
    return;
end

Tout = cell2table(rows, 'VariableNames',{'sign','cluster_id','p','clusterstat','channels'});
writetable(Tout, outCsv, 'Delimiter',';');
wrote = true;
end

function plot_sig_cluster_spectra_two_groups(T, g1, g2, sigLabels, psdRoot, fooofRoot, cond_to_use, fitRange, COL, outDir)
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

        freqs = P.freqs(:);
        keepF = freqs>=fitRange(1) & freqs<=fitRange(2);
        freqs = freqs(keepF);

        if isempty(freqsRef), freqsRef = freqs; end
        if numel(freqs) ~= numel(freqsRef) || any(abs(freqs-freqsRef)>1e-10)
            continue;
        end

        key="PSDclosed"; if cond_to_use=="open", key="PSDopen"; end
        if ~isfield(P,key), continue; end

        % PSD is nF x nChan (from MATLAB)
        PSD = P.(key);
        % need channel labels to map electrodes; fallback: use reference label order if missing
        if isfield(P,'meta') && isfield(P.meta,'chanlabels')
            lab = P.meta.chanlabels;
            if ischar(lab), lab = cellstr(lab); end
        else
            % if missing, cannot safely map => skip
            continue;
        end

        % Select significant channels by label
        idxCh = find(ismember(string(lab), string(sigLabels)));
        if isempty(idxCh), continue; end

        PSDsig = mean(PSD(keepF, idxCh), 2, 'omitnan'); % mean across sig chans

        % Reconstruct mean aperiodic fit across same sig channels
        if ~isfield(F,'exps') || ~isfield(F,'offsets'), continue; end

        % Attempt to align FOOOF channel order to PSD labels (assumes same order)
        expMean = mean(F.exps(idxCh), 'omitnan');
        offMean = mean(F.offsets(idxCh), 'omitnan');

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

fig = figure('Visible','off','Color','w','Position',[100 100 1050 480]);
ax = axes(fig); hold(ax,'on');

for gg = groups2
    plot(ax, freqsRef, PSDm.(gg), 'LineWidth', 2.2, 'Color', COL.(char(gg)));
    plot(ax, freqsRef, FITm.(gg), '--', 'LineWidth', 2.0, 'Color', COL.(char(gg)));
end

set(ax,'XScale','log','YScale','log');
xlabel(ax,'Frequency (Hz)');
ylabel(ax,'PSD');
grid(ax,'on');

% readable x ticks
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

outPng = fullfile(outDir, sprintf('spectra_sigCluster_%s_vs_%s_%s.png', groups2(1), groups2(2), cond_to_use));
exportgraphics(fig, outPng, 'Resolution', 200);
close(fig);
end
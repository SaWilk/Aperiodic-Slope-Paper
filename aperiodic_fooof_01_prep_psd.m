%% prep_PSD_welch_for_fooof.m
% Standalone PSD-prep script
%
% Reads FINAL Step06 EEG-only datasets:
%   *_cond-open*_epoched_final_EEG.set
%   *_cond-closed*_epoched_final_EEG.set
%
% Computes Welch PSD per epoch, then averages across epochs.
% Saves OPEN and CLOSED separately (no mixing), plus optional PSDall (open+closed pooled).
%
% Output location (derivatives-style intermediate):
%   <derivatives_root>\07_psd_welch\sub-XXX\
%
% Notes:
% - Uses 50% overlap in Welch by default (smoother PSD).
% - Fixes analydate filtering using datetime (your old string compare was unreliable).
% - Avoids nonstandard concatdata(); uses cat() instead.
%
% Author: Saskia Wilken and Alena Rußmann
% Tools used: ChatGPT
% Date: 27-Feb-2026

clear; clc;

%% -------------------- config parameters ---------------------------------
project   = 'AD1';

% only process subjects whose sub-folder timestamp is NEWER than this
% (set to [] to disable filtering)
analydate = [];

freq_res  = 0.5;     % target frequency resolution (Hz); determines Welch window length fs/freq_res
use_overlap_50pct = true;

% optional: also write PSDall (open+closed pooled before epoch-averaging)
write_psdall = false;

% NEW: skip subjects that already have PSD output files
skip_if_psd_exists = true;

%% -------------------- resolve paths -------------------------------------
file   = mfilename('fullpath');
fparts = strsplit(file, filesep);

% defaults
HomeDir = '';
dataDir = '';
saveDir = '';

eeglab

if contains(file, 'HomeOffice')
    % kept for compatibility; adapt as needed
    HomeDir = strjoin(fparts(1:end-2), filesep);
    dataDir = fullfile(HomeDir, 'temp-data');
    saveDir = fullfile(HomeDir, 'derivatives', project, '07_psd_welch');

elseif contains(file, 'KPP_KPN_joined')
    % PC/network style (your current context)
    addpath('K:\Wilken_Arbeitsordner\MATLAB\eeglab_current\eeglab2025.1.0');

    % IMPORTANT: adapt these two if your project folder differs
    %   Z:\pb\KPP_KPN_joined\Aperiodic\Saskia\derivatives\06_epoched_runica\sub-XXX\...
    dataDir = fullfile('Z:\pb\KPP_KPN_joined\Aperiodic\Saskia\derivatives', '06_epoched_runica');
    saveDir = fullfile('Z:\pb\KPP_KPN_joined\Aperiodic\Saskia\derivatives', '07_psd_welch');

elseif contains(file, 'beegfs')
    % HPC style
    addpath('/beegfs/u/bbf7366/toolboxes/eeglab2025.1.0/');
    HomeDir = strjoin(fparts(1:find(strcmp(fparts, 'bbf7366'))), filesep);
    dataDir = fullfile(HomeDir, 'derivatives', project,'preprocessed_eeg', '06_epoched_runica');
    saveDir = fullfile(HomeDir, 'derivatives', project, '07_psd_welch');

else
    % fallback: edit manually
    error('Could not auto-detect environment from script path. Please set dataDir/saveDir manually.');
end

if ~exist(dataDir,'dir')
    error('dataDir not found: %s', dataDir);
end
if ~exist(saveDir,'dir')
    mkdir(saveDir);
end

% eeglab('nogui'); % optional - pop_loadset typically works without starting GUI

%% -------------------- logging -------------------------------------------
logfile = fullfile(saveDir, 'prep_psd_01_log.txt');

start_msg = sprintf([ ...
    '%s\n' ...
    'prep_PSD config:\n' ...
    '  project: %s\n' ...
    '  dataDir: %s\n' ...
    '  saveDir: %s\n' ...
    '  freq_res: %.3f Hz\n' ...
    '  overlap: %s\n' ...
    '  analydate filter: %s\n' ...
    '  write_psdall: %d\n' ...
    '  skip_if_psd_exists: %d\n' ...
    '--------------------------------\n'], ...
    string(datetime()), project, dataDir, saveDir, freq_res, ...
    ternary(use_overlap_50pct, '50%', '0%'), ...
    ternary(isempty(analydate), 'OFF', char(analydate)), ...
    write_psdall, skip_if_psd_exists);

writelines(start_msg, logfile, 'WriteMode','overwrite');

%% -------------------- subject discovery + date filter -------------------
subs = dir(fullfile(dataDir, 'sub-*'));
subs = subs([subs.isdir]);

if isempty(subs)
    error('No sub-* folders found in: %s', dataDir);
end

if ~isempty(analydate)
    % subs(k).date is char like '26-Feb-2026 15:16:00'
    try
        sub_dates = datetime({subs.date}, 'InputFormat','dd-MMM-yyyy HH:mm:ss');
        mask = sub_dates > analydate;
    catch
        % fallback: if parsing fails, do not filter
        mask = true(size(subs));
        writelines("WARNING: Could not parse subs.date as datetime -> analydate filtering DISABLED.", logfile, 'WriteMode','append');
    end
else
    mask = true(size(subs));
end

subnames = {subs(mask).name};

writelines(sprintf('Subjects selected: %d / %d\n', numel(subnames), numel(subs)), logfile, 'WriteMode','append');

%% -------------------- main loop -----------------------------------------
for s = 1:numel(subnames)

    subj = subnames{s};
    subjDir = fullfile(dataDir, subj);

    % create save folder
    savePath = fullfile(saveDir, subj);
    if ~isfolder(savePath)
        mkdir(savePath);
    end

    % ---------- output file names (known before we compute anything) -------
    tag = sprintf('freqres-%.2f', freq_res);
    tag = strrep(tag, '.', 'p');

    out_open   = fullfile(savePath, sprintf('%s_desc-psd_method-welch_%s_cond-open.mat',   subj, tag));
    out_closed = fullfile(savePath, sprintf('%s_desc-psd_method-welch_%s_cond-closed.mat', subj, tag));
    out_all    = fullfile(savePath, sprintf('%s_desc-psd_method-welch_%s_cond-all.mat',    subj, tag));

    if skip_if_psd_exists
        has_open   = exist(out_open,   'file') == 2;
        has_closed = exist(out_closed, 'file') == 2;
        has_all    = exist(out_all,    'file') == 2;

        if write_psdall
            if has_open && has_closed && has_all
                writelines(sprintf('SKIP %s: PSD outputs already exist (open/closed/all)\n', subj), logfile, 'WriteMode','append');
                continue;
            end
        else
            if has_open && has_closed
                writelines(sprintf('SKIP %s: PSD outputs already exist (open/closed)\n', subj), logfile, 'WriteMode','append');
                continue;
            end
        end
    end

    % ---------- find the FINAL Step06 EEG-only sets (open/closed) ----------
    open_set   = dir(fullfile(subjDir, '*cond-open*_epoched_final_EEG.set'));
    closed_set = dir(fullfile(subjDir, '*cond-closed*_epoched_final_EEG.set'));

    if isempty(open_set) || isempty(closed_set)
        writelines(sprintf('SKIP %s: missing open or closed EEG-only set.\n  open=%d | closed=%d\n', ...
            subj, numel(open_set), numel(closed_set)), logfile, 'WriteMode','append');
        continue;
    end

    % if multiple found, pick most recent by datenum
    open_set   = pick_most_recent(open_set);
    closed_set = pick_most_recent(closed_set);

    % load datasets
    EEGopen   = pop_loadset('filename', open_set.name,   'filepath', open_set.folder);
    EEGclosed = pop_loadset('filename', closed_set.name, 'filepath', closed_set.folder);

    % sanity: channels should match for later topo comparisons
    if EEGopen.nbchan ~= EEGclosed.nbchan
        writelines(sprintf('WARNING %s: open/closed channel count differs (open=%d, closed=%d). Skipping subject.\n', ...
            subj, EEGopen.nbchan, EEGclosed.nbchan), logfile, 'WriteMode','append');
        clear EEGopen EEGclosed;
        continue;
    end

    % sampling rate + window length
    sr = EEGopen.srate;

    win = round(sr / freq_res);    % freq_res ≈ fs / win
    win = max(win, 4);             % avoid tiny windows

    % cap window to epoch length
    ep_len_open = size(EEGopen.data, 2);
    ep_len_closed = size(EEGclosed.data, 2);
    win = min([win, ep_len_open, ep_len_closed]);

    % overlap
    if use_overlap_50pct
        noverlap = floor(win/2);
    else
        noverlap = 0;
    end

    % log channel count anomalies
    if EEGopen.nbchan < 61
        writelines(sprintf('%s has %d channels\n', subj, EEGopen.nbchan), logfile, 'WriteMode','append');
    end

    % ---------- PSD OPEN ----------
    nEpO = size(EEGopen.data, 3);
    PSDopen_ep = [];
    freqs = [];

    for ep = 1:nEpO
        X = double(EEGopen.data(:, :, ep))'; % time x chan
        [psd, f] = pwelch(X, win, noverlap, [], sr); % psd: freq x chan
        if ep == 1
            freqs = f;
            PSDopen_ep = nan([numel(freqs) EEGopen.nbchan nEpO]);
        end
        PSDopen_ep(:,:,ep) = psd;
    end
    PSDopen = mean(PSDopen_ep, 3, 'omitnan'); % freq x chan

    % ---------- PSD CLOSED ----------
    nEpC = size(EEGclosed.data, 3);
    PSDclosed_ep = [];

    for ep = 1:nEpC
        X = double(EEGclosed.data(:, :, ep))'; % time x chan
        [psd, f] = pwelch(X, win, noverlap, [], sr);
        if ep == 1
            % ensure same freq grid as open
            if isempty(freqs)
                freqs = f;
            else
                if numel(f) ~= numel(freqs) || any(abs(f - freqs) > 1e-12)
                    writelines(sprintf('WARNING %s: freq grids differ between open and closed. Skipping.\n', subj), logfile, 'WriteMode','append');
                    PSDclosed_ep = [];
                    break;
                end
            end
            PSDclosed_ep = nan([numel(freqs) EEGclosed.nbchan nEpC]);
        end
        PSDclosed_ep(:,:,ep) = psd;
    end

    if isempty(PSDclosed_ep)
        clear EEGopen EEGclosed PSDopen PSDopen_ep PSDclosed_ep;
        continue;
    end

    PSDclosed = mean(PSDclosed_ep, 3, 'omitnan'); % freq x chan

    % ---------- optional pooled PSDall ----------
    PSDall = [];
    if write_psdall
        % pool epochs across both conditions, then average
        PSDall_ep = cat(3, PSDopen_ep, PSDclosed_ep);  % freq x chan x (nEpO+nEpC)
        PSDall = mean(PSDall_ep, 3, 'omitnan');
    end

    % ---------- metadata (useful for later FOOOF + QA) ----------
    meta = struct();
    meta.subject = subj;
    meta.open_set = open_set.name;
    meta.closed_set = closed_set.name;
    meta.srate_hz = sr;
    meta.freq_res_hz_requested = freq_res;
    meta.win_samples = win;
    meta.noverlap_samples = noverlap;
    meta.n_epochs_open = nEpO;
    meta.n_epochs_closed = nEpC;
    meta.datetime = char(datetime());

    % ---------- save (open/closed separate) ----------
    save(out_open,   'PSDopen',   'freqs', 'meta', '-v7.3');
    save(out_closed, 'PSDclosed', 'freqs', 'meta', '-v7.3');

    if write_psdall
        save(out_all, 'PSDall', 'freqs', 'meta', '-v7.3');
    end

    writelines(sprintf('OK %s: saved PSD (open/closed)%s\n', subj, ternary(write_psdall,' + all','')), logfile, 'WriteMode','append');

    % clear per-subject variables to avoid accidental carry-over
    clear EEGopen EEGclosed PSDopen PSDclosed PSDall PSDopen_ep PSDclosed_ep;

end

writelines(sprintf('\nDONE %s\n', string(datetime())), logfile, 'WriteMode','append');

%% -------------------- helpers -------------------------------------------
function d = pick_most_recent(listing)
    if numel(listing) == 1
        d = listing;
        return;
    end
    [~, ix] = max([listing.datenum]);
    d = listing(ix);
end

function out = ternary(cond, a, b)
    if cond
        out = a;
    else
        out = b;
    end
end
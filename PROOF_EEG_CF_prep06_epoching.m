%% ANALYSIS SCRIPT - EEG - PROOF - Classical Paradigm (Real Data)
% SCRIPT 06: EPOCHING + FINAL ARTIFACT REJECTION + CONDITION DATASETS
%
% Original epoching logic: Metin Ozyagcilar (Nov 2023)
% Pipeline-consistent refactor (no ICA here; no GUI; robust saving/logging):
% Saskia Wilken (Jan 2026)
%
% INPUT  (MATRICS pipeline):
%   K:\Wilken Arbeitsordner\Preprocessed_data\MATRICS\05_until_epoching\<sub>\*_until_epoching.set
%
% OUTPUT:
%   K:\Wilken Arbeitsordner\Preprocessed_data\MATRICS\06_epoched_final\<sub>\
%       *_rerefav_epoched.set
%       *_rerefmast_epoched.set
%       *_rerefav_baselineremoved.set
%       *_rerefmast_baselineremoved.set
%       *_rerefav_<COND>.set
%       *_rerefmast_<COND>.set
%       *_rerefav_<ACQ/EXT-COMB>.set
%       *_rerefmast_<ACQ/EXT-COMB>.set
%
% Notes:
%   - Epochs are created around events_phase (exact list below).
%   - Baseline correction uses [-200 0] ms as in original.
%   - Artifact rejection is applied BEFORE baseline (matches your original order).
%   - Artifact rejection here uses EEGLAB-native criteria (threshold + jointprob)
%     instead of epoch_properties/min_z/prep_rej_opt (often missing on other machines).
%
% EEGLAB:
%   - Tested style: eeglab('nogui') and pop_newset(...,'gui','off') to avoid prompts.

clear; close all; clc;

%% =========================
% CONFIG (minimal)
% =========================
cfg = struct();

% IO
cfg.overwrite_outputs = true;        % DEFAULT: overwrite existing outputs
cfg.save_intermediate_steps = true;  % keep the intermediate reref/epoched/baselineremoved sets
cfg.make_condition_sets = true;      % condition-specific outputs
cfg.make_whole_acq_sets = true;      % ACSMComb/ACSPComb
cfg.make_whole_ext_sets = true;      % ECSMComb/ECSPComb

% Artifact rejection (EEG-only; excludes EOG + AUX)
cfg.do_artifact_rejection = true;
cfg.eegthresh_uv = 100;              % adjust if needed; classic ERP often 75-150
cfg.jointprob_local = 3;             % typical 3-5
cfg.jointprob_global = 3;

% Epoching / baseline (from your original)
epoch_start = -0.4;
epoch_end   =  2.6;
base_start_ms = -200;

%% =========================
% EVENTS (FROM YOUR ORIGINAL SCRIPT)
% =========================
events_phase_wholeacq = {'S 2021' 'S 2022' 'S 2421' 'S 2422'};
conds_phase_wholeacq  = {'ACSMComb', 'ACSPComb'};

events_phase_wholeext = {'S 2041' 'S 2042' 'S 2043' 'S 2441' 'S 2442' 'S 2443'};
conds_phase_wholeext  = {'ECSMComb', 'ECSPComb'};

events_phase = {'S 201'  'S 241'  'S 2021' 'S 2421' 'S 2022' 'S 2422' 'S 203'  'S 213'  'S 223' 'S 233'  'S 243' 'S 2041' 'S 2441' 'S 2042' 'S 2442' ...
    'S 2043' 'S 2443' 'S 205'  'S 245'};

conds_phase = {'HCSM','HCSP','ACSMFirst', 'ACSPFirst', 'ACSMSecond', 'ACSPSecond', 'GCSM', 'GGSM', 'GGSU', 'GGSP', 'GCSP', ...
    'ECSMFirst', 'ECSPFirst', 'ECSMSecond', 'ECSPSecond', 'ECSMThird', 'ECSPThird', 'ROFCSM', 'ROFCS+'};

if numel(events_phase) ~= numel(conds_phase)
    error('events_phase and conds_phase must have the same length.');
end

%% =========================
% PATHS (MATRICS PIPELINE STYLE)
% =========================
% If you want this to auto-follow your "go up 3 levels" convention, you can,
% but here we keep it simple and explicit like your other MATRICS scripts.

OUTPUT_ROOT_MATRICS = 'K:\Wilken Arbeitsordner\Preprocessed_data\MATRICS';

INPUT_DIR  = fullfile(OUTPUT_ROOT_MATRICS, '05_until_epoching_infomax_eye.9');
OUTPUT_DIR = fullfile(OUTPUT_ROOT_MATRICS, '06_epoched');

if ~exist(OUTPUT_DIR,'dir'); mkdir(OUTPUT_DIR); end

% local script logs (next to this script)
this_file = matlab.desktop.editor.getActiveFilename();
this_dir  = fileparts(this_file);
logs_dir  = fullfile(this_dir, 'logs');
if ~exist(logs_dir,'dir'); mkdir(logs_dir); end

timestamp_str = datestr(now, 'yyyymmdd_HHMMSS');
runlog_path = fullfile(logs_dir, ['06_epoching_runlog_' timestamp_str '.txt']);
append_line(runlog_path, '=== START 06_epoching ===');
append_line(runlog_path, ['Script: ' this_file]);

% EEGLAB
% (match your other scripts; adjust to your actual location if needed)
base_path  = fileparts(fileparts(fileparts(this_dir)));
path_eeglab = [base_path, '\MATLAB\eeglab_current\eeglab2025.1.0'];

cd(path_eeglab);
[ALLEEG, EEG, CURRENTSET] = eeglab('nogui');
append_line(runlog_path, 'EEGLAB started (nogui).');

%% =========================
% DISCOVER SUBJECTS + INPUT SETS
% =========================
ds = dir(INPUT_DIR);
ds = ds([ds.isdir]);
ds = ds(~ismember({ds.name},{'.','..'}));
subject_ids = {ds.name};

if isempty(subject_ids)
    error('No subject folders found in %s', INPUT_DIR);
end

%% =========================
% MAIN LOOP
% =========================
for si = 1:numel(subject_ids)

    subject_id = subject_ids{si};
    subj_in_dir  = fullfile(INPUT_DIR, subject_id);
    subj_out_dir = fullfile(OUTPUT_DIR, subject_id);
    if ~exist(subj_out_dir,'dir'); mkdir(subj_out_dir); end

    in_sets = dir(fullfile(subj_in_dir, '*_until_epoching.set'));
    if isempty(in_sets)
        log_and_print(runlog_path, 'WARN', sprintf('No *_until_epoching.set found for %s', subject_id));
        continue;
    end

    for fi = 1:numel(in_sets)

        t_run = tic;

        in_name  = in_sets(fi).name;
        run_base = erase(in_name, '_until_epoching.set');

        log_and_print(runlog_path, 'RUN', sprintf('%s | %s', subject_id, run_base));

        try
            EEG = pop_loadset('filename', in_name, 'filepath', subj_in_dir);
            EEG = eeg_checkset(EEG);

            % Ensure event.type is char (protect pop_epoch / pop_selectevent)
            if isfield(EEG,'event') && ~isempty(EEG.event)
                try
                    tmp = cellfun(@char, {EEG.event.type}, 'UniformOutput', false);
                    [EEG.event.type] = tmp{:};
                catch
                    % ignore
                end
            end

            % Determine indices by type; keep AUX channels, but EXCLUDE from rejection and re-ref
            [idxEEG, idxEOG, idxAUX] = get_indices_by_type(EEG);
            EEG = append_comment(EEG, sprintf('channel counts: EEG=%d | EOG=%d | AUX=%d', numel(idxEEG), numel(idxEOG), numel(idxAUX)));

            % =========================
            % STEP 1: RE-REFERENCE (AVERAGE)  [original excluded IO1]
            % Pipeline-consistent: compute average reference over EEG channels only,
            % excluding EOG + AUX from the reference computation.
            % =========================
            EEG_rerefav = EEG;

            if isempty(idxEEG)
                EEG_rerefav = append_comment(EEG_rerefav, 'WARNING: no EEG channels found -> reref skipped.');
            else
                exclude_idx = setdiff(1:EEG_rerefav.nbchan, idxEEG); % exclude EOG + AUX
                EEG_rerefav = pop_reref(EEG_rerefav, [], 'exclude', exclude_idx);
                EEG_rerefav = eeg_checkset(EEG_rerefav);
                EEG_rerefav = append_comment(EEG_rerefav, sprintf('average reference applied (EEG-only). excluded=%d', numel(exclude_idx)));
            end

            fn_rerefav = fullfile(subj_out_dir, [run_base '_rerefav.set']);
            safe_saveset(EEG_rerefav, fn_rerefav, cfg.overwrite_outputs);

            % =========================
            % STEP 2: RE-REFERENCE (MASTOIDS) [T9/T10 if present]
            % =========================
            EEG_rerefmast = EEG;

            chan_m1 = find(strcmpi({EEG_rerefmast.chanlocs.labels}, 'T9'), 1, 'first');
            chan_m2 = find(strcmpi({EEG_rerefmast.chanlocs.labels}, 'T10'),1, 'first');

            if isempty(chan_m1) || isempty(chan_m2)
                EEG_rerefmast = append_comment(EEG_rerefmast, 'WARNING: T9/T10 not found -> mastoid reref skipped; keeping original ref.');
            else
                % exclude EOG + AUX from ref computation by passing them in exclude
                exclude_idx = setdiff(1:EEG_rerefmast.nbchan, idxEEG); % still compute only using EEG
                EEG_rerefmast = pop_reref(EEG_rerefmast, [chan_m1 chan_m2], 'exclude', exclude_idx);
                EEG_rerefmast = eeg_checkset(EEG_rerefmast);
                EEG_rerefmast = append_comment(EEG_rerefmast, sprintf('mastoid reference applied (T9/T10). excluded=%d', numel(exclude_idx)));
            end

            fn_rerefmast = fullfile(subj_out_dir, [run_base '_rerefmast.set']);
            safe_saveset(EEG_rerefmast, fn_rerefmast, cfg.overwrite_outputs);

            % =========================
            % STEP 3: EPOCH + REJECT + BASELINE  (for BOTH references)
            % =========================
            ref_variants = {'rerefav','rerefmast'};
            for z = 1:2

                if z == 1
                    EEGz = EEG_rerefav;
                    ref_tag = 'rerefav';
                else
                    EEGz = EEG_rerefmast;
                    ref_tag = 'rerefmast';
                end

                % --- Epoch around *all* events_phase (original) ---
                EEGz = pop_epoch(EEGz, events_phase, [epoch_start epoch_end], 'newname', [run_base '_' ref_tag '_epoched'], 'epochinfo', 'yes');
                EEGz = eeg_checkset(EEGz);

                % Ensure times consistent (avoid "bad time range" surprises)
                EEGz.times = round(linspace(epoch_start*1000, epoch_end*1000, size(EEGz.data,2)));

                fn_epoched = fullfile(subj_out_dir, [run_base '_' ref_tag '_epoched.set']);
                safe_saveset(EEGz, fn_epoched, cfg.overwrite_outputs);

                % --- Artifact rejection (EEG-only) ---
                if cfg.do_artifact_rejection
                    [idxEEGz, ~, ~] = get_indices_by_type(EEGz);

                    if isempty(idxEEGz) || EEGz.trials < 1
                        EEGz = append_comment(EEGz, 'artifact rejection skipped (no EEG channels or no epochs).');
                    else
                        % 1) amplitude threshold
                        EEGz = pop_eegthresh(EEGz, 1, idxEEGz, -cfg.eegthresh_uv, cfg.eegthresh_uv, ...
                            epoch_start+0.05, epoch_end-0.05, 0, 1);
                        EEGz = eeg_checkset(EEGz);

                        % 2) joint probability
                        if EEGz.trials > 0
                            EEGz = pop_jointprob(EEGz, 1, idxEEGz, cfg.jointprob_local, cfg.jointprob_global, 0, 1, 0);
                            EEGz = eeg_checkset(EEGz);
                        end

                        EEGz = append_comment(EEGz, sprintf('artifact rejection EEG-only: thresh=±%d uV, jointprob local=%d global=%d', ...
                            cfg.eegthresh_uv, cfg.jointprob_local, cfg.jointprob_global));
                    end
                else
                    EEGz = append_comment(EEGz, 'artifact rejection disabled by cfg.');
                end

                fn_badrej = fullfile(subj_out_dir, [run_base '_' ref_tag '_badtrialsrejected.set']);
                safe_saveset(EEGz, fn_badrej, cfg.overwrite_outputs);

                % --- Baseline correction (original: [base_start 0]) ---
                EEGz = pop_rmbase(EEGz, [base_start_ms 0], []);
                EEGz = eeg_checkset(EEGz);
                EEGz = append_comment(EEGz, sprintf('baseline correction applied: [%d 0] ms', base_start_ms));

                fn_base = fullfile(subj_out_dir, [run_base '_' ref_tag '_baselineremoved.set']);
                safe_saveset(EEGz, fn_base, cfg.overwrite_outputs);

                % =========================
                % STEP 4: CONDITION-SPECIFIC DATASETS (1-to-1 mapping)
                % =========================
                if cfg.make_condition_sets
                    for e = 1:numel(events_phase)
                        ev = events_phase{e};
                        cond = conds_phase{e};

                        EEGc = pop_selectevent(EEGz, 'latency', '-2<=2', 'type', {ev}, ...
                            'deleteevents','off','deleteepochs','on','invertepochs','off');
                        EEGc = eeg_checkset(EEGc);

                        fn_cond = fullfile(subj_out_dir, [run_base '_' ref_tag '_' cond '.set']);
                        safe_saveset(EEGc, fn_cond, cfg.overwrite_outputs);
                    end
                end

                % =========================
                % STEP 5: ACQ AS A WHOLE (pairs)
                % =========================
                if cfg.make_whole_acq_sets
                    % pair 1 -> ACSMComb uses S2021 + S2022
                    EEGacq1 = pop_selectevent(EEGz, 'latency','-2<=2', ...
                        'type', {events_phase_wholeacq{1}, events_phase_wholeacq{2}}, ...
                        'deleteevents','off','deleteepochs','on','invertepochs','off');
                    EEGacq1 = eeg_checkset(EEGacq1);
                    fn_acq1 = fullfile(subj_out_dir, [run_base '_' ref_tag '_' conds_phase_wholeacq{1} '.set']);
                    safe_saveset(EEGacq1, fn_acq1, cfg.overwrite_outputs);

                    % pair 2 -> ACSPComb uses S2421 + S2422
                    EEGacq2 = pop_selectevent(EEGz, 'latency','-2<=2', ...
                        'type', {events_phase_wholeacq{3}, events_phase_wholeacq{4}}, ...
                        'deleteevents','off','deleteepochs','on','invertepochs','off');
                    EEGacq2 = eeg_checkset(EEGacq2);
                    fn_acq2 = fullfile(subj_out_dir, [run_base '_' ref_tag '_' conds_phase_wholeacq{2} '.set']);
                    safe_saveset(EEGacq2, fn_acq2, cfg.overwrite_outputs);
                end

                % =========================
                % STEP 6: EXT AS A WHOLE (triples)
                % =========================
                if cfg.make_whole_ext_sets
                    % triple 1 -> ECSMComb uses S2041+S2042+S2043
                    EEGext1 = pop_selectevent(EEGz, 'latency','-2<=2', ...
                        'type', {events_phase_wholeext{1}, events_phase_wholeext{2}, events_phase_wholeext{3}}, ...
                        'deleteevents','off','deleteepochs','on','invertepochs','off');
                    EEGext1 = eeg_checkset(EEGext1);
                    fn_ext1 = fullfile(subj_out_dir, [run_base '_' ref_tag '_' conds_phase_wholeext{1} '.set']);
                    safe_saveset(EEGext1, fn_ext1, cfg.overwrite_outputs);

                    % triple 2 -> ECSPComb uses S2441+S2442+S2443
                    EEGext2 = pop_selectevent(EEGz, 'latency','-2<=2', ...
                        'type', {events_phase_wholeext{4}, events_phase_wholeext{5}, events_phase_wholeext{6}}, ...
                        'deleteevents','off','deleteepochs','on','invertepochs','off');
                    EEGext2 = eeg_checkset(EEGext2);
                    fn_ext2 = fullfile(subj_out_dir, [run_base '_' ref_tag '_' conds_phase_wholeext{2} '.set']);
                    safe_saveset(EEGext2, fn_ext2, cfg.overwrite_outputs);
                end

                % end z (reference variants)
            end

            elapsed = toc(t_run);
            log_and_print(runlog_path, 'DONE', sprintf('%s | %s | %.1fs', subject_id, run_base, elapsed));

        catch ME
            elapsed = toc(t_run);
            log_and_print(runlog_path, 'ERR', sprintf('%s | %s | %.1fs | %s', subject_id, run_base, elapsed, ME.message));
        end
    end
end

append_line(runlog_path, '=== FINISHED 06_epoching ===');

%% =========================
% LOCAL FUNCTIONS
% =========================
function EEG = append_comment(EEG, msg)
    ts = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    line = sprintf('[%s] %s', ts, msg);
    if ~isfield(EEG,'comments') || isempty(EEG.comments)
        EEG.comments = line;
    else
        EEG.comments = sprintf('%s\n%s', EEG.comments, line);
    end
end

function append_line(log_path, msg)
    try
        fid = fopen(log_path, 'a');
        if fid ~= -1
            fprintf(fid, '[%s] %s\n', datestr(now,'yyyy-mm-dd HH:MM:SS'), msg);
            fclose(fid);
        end
    catch
    end
end

function log_and_print(log_path, tag, msg)
    C.reset = char(27) + "[0m";
    C.red   = char(27) + "[31m";
    C.green = char(27) + "[32m";
    C.yellow= char(27) + "[33m";
    C.cyan  = char(27) + "[36m";

    switch upper(tag)
        case 'RUN',  col = C.cyan;
        case 'DONE', col = C.green;
        case 'WARN', col = C.yellow;
        case 'ERR',  col = C.red;
        otherwise,   col = C.reset;
    end

    fprintf('%s[%s]%s %s\n', col, tag, C.reset, msg);
    append_line(log_path, sprintf('[%s] %s', tag, msg));
end

function [idxEEG, idxEOG, idxAUX] = get_indices_by_type(EEG)
    idxEEG = [];
    idxEOG = [];
    idxAUX = [];
    if ~isfield(EEG,'chanlocs') || isempty(EEG.chanlocs) || ~isfield(EEG.chanlocs,'type')
        idxEEG = 1:EEG.nbchan; % fallback
        return;
    end
    types = lower(string({EEG.chanlocs.type}));
    idxEEG = find(types == "eeg");
    idxEOG = find(types == "eog");
    idxAUX = find(~(types == "eeg" | types == "eog"));
end

function safe_saveset(EEG, fullpath_set, overwrite)
    [out_dir, out_file, out_ext] = fileparts(fullpath_set);
    if ~exist(out_dir,'dir'); mkdir(out_dir); end
    if isempty(out_ext)
        out_ext = '.set';
    end
    fullpath_set = fullfile(out_dir, [out_file out_ext]);

    if exist(fullpath_set,'file') && ~overwrite
        return;
    end

    EEG = pop_saveset(EEG, 'filename', [out_file out_ext], 'filepath', out_dir);
end

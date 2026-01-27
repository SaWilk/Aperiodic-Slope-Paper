%% ANALYSIS SCRIPT - EEG - PROOF - Classical Paradigm (Real Data)
% SCRIPT 06: EPOCHING + FINAL ARTIFACT REJECTION (SINGLE OUTPUT)
%
% Original epoching logic: Metin Ozyagcilar (Nov 2023)
% Pipeline-consistent refactor + "single final output" default:
% Saskia Wilken (Jan 2026)
%
% INPUT  (MATRICS pipeline):
%   ...\05_until_epoching_infomax_eye.9\<sub>\*_until_epoching.set
%
% OUTPUT (DEFAULT):
%   Exactly ONE dataset is created per input file:
%       ...\06_epoched\<sub>\<run_base>_epoched_final.set
%
% Notes:
%   - Reference choice is a config option; ONLY the chosen one is executed.
%   - Filename does NOT encode reference (handle via separate derivatives folders if desired).
%   - Artifact rejection BEFORE baseline (as in original).
%   - Rejection uses: amplitude threshold + joint probability + kurtosis (more aggressive defaults).
%   - No legacy condition split outputs.

clear; close all; clc;

%% =========================
% CONFIG
% =========================
cfg = struct();

% IO
cfg.overwrite_outputs       = true;

% Saving behavior
cfg.save_final_only         = true;    % default: only save final dataset
cfg.save_intermediate_steps = false;   % if true AND save_final_only=false -> saves intermediate sets too

% Reference choice (ONLY ONE executed)
%   "avg"     -> average reference (EEG-only)
%   "mastoid" -> mastoid reference using T9/T10 (EEG-only), falls back to original ref if missing
cfg.reference_mode = "avg"; % <- CHANGE HERE: "avg" or "mastoid"

% Artifact rejection (EEG-only; excludes EOG + AUX)
cfg.do_artifact_rejection = true;

% More aggressive defaults
cfg.eegthresh_uv     = 75;     % amplitude threshold (uV)
cfg.jointprob_local  = 2.5;    % local joint prob
cfg.jointprob_global = 2.5;    % global joint prob

% Add kurtosis rejection (default ON)
cfg.do_kurtosis_reject = true;
cfg.kurtosis_local     = 3;
cfg.kurtosis_global    = 3;

% Trim edges slightly for rejection checks
cfg.rej_margin_s = 0.02;

% Epoching / baseline
epoch_start   = -0.4;
epoch_end     =  2.6;
base_start_ms = -200;

% Sanity check window for "CS followed by shock"
cfg.acq_shock_follow_window_s = 2.0; % seconds

%% =========================
% EVENTS (STATIC LIST TO EPOCH AROUND)
% =========================
events_phase = { ...
    'S 201','S 241', ...
    'S 2021','S 2421','S 2022','S 2422', ...
    'S 203','S 213','S 223','S 233','S 243', ...
    'S 2041','S 2441','S 2042','S 2442','S 2043','S 2443', ...
    'S 205','S 245' ...
};

%% =========================
% PATHS
% =========================
OUTPUT_ROOT_MATRICS = 'K:\Wilken_Arbeitsordner\Preprocessed_data\MATRICS\eeg';

INPUT_DIR  = fullfile(OUTPUT_ROOT_MATRICS, '05_until_epoching');
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
append_line(runlog_path, ['cfg.reference_mode: ' char(cfg.reference_mode)]);
append_line(runlog_path, 'Final output filename template: <run_base>_epoched_final.set');

% EEGLAB
base_path   = fileparts(fileparts(fileparts(this_dir)));
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

            % Ensure event.type is char
            if isfield(EEG,'event') && ~isempty(EEG.event)
                try
                    tmp = cellfun(@char, {EEG.event.type}, 'UniformOutput', false);
                    [EEG.event.type] = tmp{:};
                catch
                end
            end

            % Participant-specific CS mapping (used for comments + (optional) downstream semantics)
            cs_map = get_cs_mapping_from_comments(EEG);
            if isempty(cs_map.CSplus_identity)
                log_and_print(runlog_path, 'WARN', sprintf('%s | %s | Could not parse CS mapping from EEG.comments. ROF CS+/CS- labels may be wrong.', subject_id, run_base));
                EEG = append_comment(EEG, 'WARNING: could not parse CS1/CS2 -> CS+/CS- mapping from EEG.comments (expected "CS1 = CS+" or "CS2 = CS+").');
            else
                log_and_print(runlog_path, 'DONE', sprintf('%s | %s | Parsed from comments: %s = CS+', subject_id, run_base, cs_map.CSplus_identity));
                EEG = append_comment(EEG, sprintf('Epoching: parsed CS mapping from comments: %s = CS+', cs_map.CSplus_identity));
            end

            acq_map = decide_csplus_family_from_acq_shocks(EEG, cfg.acq_shock_follow_window_s);
            if isempty(acq_map.CSplus_family)
                log_and_print(runlog_path, 'WARN', sprintf('%s | %s | Could not decide ACQ CS+ family from EEG (shock-follow). Default: 242x=CS+, 202x=CS-.', subject_id, run_base));
                EEG = append_comment(EEG, 'WARNING: ACQ CS+ family undecidable via shock-follow; defaulting to 242x=CS+, 202x=CS-.');
                acq_map.CSplus_family  = "242";
                acq_map.CSminus_family = "202";
            else
                log_and_print(runlog_path, 'DONE', sprintf('%s | %s | ACQ CS+ family=%s (202x=%d, 242x=%d)', ...
                    subject_id, run_base, acq_map.CSplus_family, acq_map.n_follow_202, acq_map.n_follow_242));
                EEG = append_comment(EEG, sprintf('Epoching: ACQ shock-follow decided CS+ family=%s (202x=%d, 242x=%d; window=%.1fs)', ...
                    acq_map.CSplus_family, acq_map.n_follow_202, acq_map.n_follow_242, cfg.acq_shock_follow_window_s));
            end

            % (Kept for completeness; not used for filenames)
            conds_phase = build_condition_labels(acq_map, cs_map);
            if numel(events_phase) ~= numel(conds_phase)
                error('events_phase and conds_phase must have the same length.');
            end

            % Channel type indices
            [idxEEG, idxEOG, idxAUX] = get_indices_by_type(EEG);
            EEG = append_comment(EEG, sprintf('channel counts: EEG=%d | EOG=%d | AUX=%d', numel(idxEEG), numel(idxEOG), numel(idxAUX)));

            % =========================
            % STEP 1: APPLY CHOSEN REFERENCE (ONLY ONE)
            % =========================
            EEGref = EEG;

            if cfg.reference_mode == "avg"

                if isempty(idxEEG)
                    EEGref = append_comment(EEGref, 'WARNING: no EEG channels found -> average reref skipped.');
                else
                    exclude_idx = setdiff(1:EEGref.nbchan, idxEEG); % exclude EOG + AUX
                    EEGref = pop_reref(EEGref, [], 'exclude', exclude_idx);
                    EEGref = eeg_checkset(EEGref);
                    EEGref = append_comment(EEGref, sprintf('reference_mode=avg: average reference applied (EEG-only). excluded=%d', numel(exclude_idx)));
                end

            elseif cfg.reference_mode == "mastoid"

                chan_m1 = find(strcmpi({EEGref.chanlocs.labels}, 'T9'), 1, 'first');
                chan_m2 = find(strcmpi({EEGref.chanlocs.labels}, 'T10'),1, 'first');

                if isempty(chan_m1) || isempty(chan_m2)
                    EEGref = append_comment(EEGref, 'reference_mode=mastoid: WARNING T9/T10 not found -> mastoid reref skipped; keeping original ref.');
                else
                    exclude_idx = setdiff(1:EEGref.nbchan, idxEEG); % exclude EOG + AUX
                    EEGref = pop_reref(EEGref, [chan_m1 chan_m2], 'exclude', exclude_idx);
                    EEGref = eeg_checkset(EEGref);
                    EEGref = append_comment(EEGref, sprintf('reference_mode=mastoid: mastoid reference applied (T9/T10). excluded=%d', numel(exclude_idx)));
                end

            else
                error('cfg.reference_mode must be "avg" or "mastoid". Current: %s', char(cfg.reference_mode));
            end

            if cfg.save_intermediate_steps && ~cfg.save_final_only
                fn_ref = fullfile(subj_out_dir, [run_base '_refapplied.set']);
                safe_saveset(EEGref, fn_ref, cfg.overwrite_outputs);
            end

            % =========================
            % STEP 2: EPOCH
            % =========================
            EEGep = pop_epoch(EEGref, events_phase, [epoch_start epoch_end], ...
                'newname', [run_base '_epoched'], 'epochinfo', 'yes');
            EEGep = eeg_checkset(EEGep);

            EEGep.times = round(linspace(epoch_start*1000, epoch_end*1000, size(EEGep.data,2)));

            if cfg.save_intermediate_steps && ~cfg.save_final_only
                fn_ep = fullfile(subj_out_dir, [run_base '_epoched.set']);
                safe_saveset(EEGep, fn_ep, cfg.overwrite_outputs);
            end

            % =========================
            % STEP 3: ARTIFACT REJECTION (EEG-only)
            % =========================
            EEGrej = EEGep;

            if cfg.do_artifact_rejection
                [idxEEGep, ~, ~] = get_indices_by_type(EEGrej);

                if isempty(idxEEGep) || EEGrej.trials < 1
                    EEGrej = append_comment(EEGrej, 'artifact rejection skipped (no EEG channels or no epochs).');
                else
                    t1 = epoch_start + cfg.rej_margin_s;
                    t2 = epoch_end   - cfg.rej_margin_s;

                    % (1) amplitude threshold
                    EEGrej = pop_eegthresh(EEGrej, 1, idxEEGep, ...
                        -cfg.eegthresh_uv, cfg.eegthresh_uv, t1, t2, 0, 1);
                    EEGrej = eeg_checkset(EEGrej);

                    % (2) joint probability
                    if EEGrej.trials > 0
                        EEGrej = pop_jointprob(EEGrej, 1, idxEEGep, ...
                            cfg.jointprob_local, cfg.jointprob_global, 0, 1, 0);
                        EEGrej = eeg_checkset(EEGrej);
                    end

                    % (3) kurtosis
                    if cfg.do_kurtosis_reject && EEGrej.trials > 0
                        EEGrej = pop_rejkurt(EEGrej, 1, idxEEGep, ...
                            cfg.kurtosis_local, cfg.kurtosis_global, 0, 1, 0);
                        EEGrej = eeg_checkset(EEGrej);
                    end

                    EEGrej = append_comment(EEGrej, sprintf( ...
                        'artifact rejection EEG-only: thresh=±%d uV (%.2f..%.2fs), jointprob L=%.2f G=%.2f, kurtosis L=%.2f G=%.2f', ...
                        cfg.eegthresh_uv, t1, t2, cfg.jointprob_local, cfg.jointprob_global, ...
                        cfg.kurtosis_local, cfg.kurtosis_global));
                end
            else
                EEGrej = append_comment(EEGrej, 'artifact rejection disabled by cfg.');
            end

            if cfg.save_intermediate_steps && ~cfg.save_final_only
                fn_rej = fullfile(subj_out_dir, [run_base '_badtrialsrejected.set']);
                safe_saveset(EEGrej, fn_rej, cfg.overwrite_outputs);
            end

            % =========================
            % STEP 4: BASELINE CORRECTION
            % =========================
            EEGfinal = pop_rmbase(EEGrej, [base_start_ms 0], []);
            EEGfinal = eeg_checkset(EEGfinal);
            EEGfinal = append_comment(EEGfinal, sprintf('baseline correction applied: [%d 0] ms', base_start_ms));

            if cfg.save_intermediate_steps && ~cfg.save_final_only
                fn_base = fullfile(subj_out_dir, [run_base '_baselineremoved.set']);
                safe_saveset(EEGfinal, fn_base, cfg.overwrite_outputs);
            end

            % =========================
            % FINAL OUTPUT (the only required output)
            % =========================
            fn_final = fullfile(subj_out_dir, [run_base '_epoched_final.set']);
            log_and_print(runlog_path, 'DONE', sprintf('%s | %s | saving FINAL: %s', subject_id, run_base, fn_final));
            safe_saveset(EEGfinal, fn_final, cfg.overwrite_outputs);

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

    EEG = pop_saveset(EEG, 'filename', [out_file out_ext], 'filepath', out_dir, 'gui', 'off');
end

%% ==========================================================
% HELPERS: mapping + labels
% ==========================================================
function cs_map = get_cs_mapping_from_comments(EEG)
    cs_map = struct('CSplus_identity','', 'CSminus_identity','');

    if ~isfield(EEG,'comments') || isempty(EEG.comments)
        return;
    end

    txt = string(EEG.comments);

    pat1 = '(CS1)\s*[:=\- >]+\s*CS\+';
    pat2 = '(CS2)\s*[:=\- >]+\s*CS\+';

    if ~isempty(regexp(txt, pat1, 'once'))
        cs_map.CSplus_identity  = 'CS1';
        cs_map.CSminus_identity = 'CS2';
        return;
    end
    if ~isempty(regexp(txt, pat2, 'once'))
        cs_map.CSplus_identity  = 'CS2';
        cs_map.CSminus_identity = 'CS1';
        return;
    end

    pat3 = 'CS\+\s*[:=\- >]+\s*(CS1)';
    pat4 = 'CS\+\s*[:=\- >]+\s*(CS2)';
    if ~isempty(regexp(txt, pat3, 'once'))
        cs_map.CSplus_identity  = 'CS1';
        cs_map.CSminus_identity = 'CS2';
        return;
    end
    if ~isempty(regexp(txt, pat4, 'once'))
        cs_map.CSplus_identity  = 'CS2';
        cs_map.CSminus_identity = 'CS1';
        return;
    end
end

function acq_map = decide_csplus_family_from_acq_shocks(EEG, win_s)
    acq_map = struct('CSplus_family',"", 'CSminus_family',"", 'n_follow_202',0, 'n_follow_242',0);

    if ~isfield(EEG,'event') || isempty(EEG.event) || ~isfield(EEG,'srate') || isempty(EEG.srate)
        return;
    end

    types = cell(numel(EEG.event),1);
    lat_s = zeros(numel(EEG.event),1);
    for k = 1:numel(EEG.event)
        types{k} = normalize_type(EEG.event(k).type);
        lat_s(k) = double(EEG.event(k).latency) / double(EEG.srate);
    end

    is_cs202 = ismember(types, {'S 2021','S 2022'});
    is_cs242 = ismember(types, {'S 2421','S 2422'});
    is_shock = strcmp(types, 'S 5') | strcmp(types, 'S  5');

    shock_idx = find(is_shock);
    if isempty(shock_idx)
        return;
    end

    for k = 1:numel(types)-1
        if ~(is_cs202(k) || is_cs242(k))
            continue;
        end

        nxt = shock_idx(find(shock_idx > k, 1, 'first'));
        if isempty(nxt)
            continue;
        end

        dt = lat_s(nxt) - lat_s(k);
        if dt >= 0 && dt <= win_s
            if is_cs202(k)
                acq_map.n_follow_202 = acq_map.n_follow_202 + 1;
            else
                acq_map.n_follow_242 = acq_map.n_follow_242 + 1;
            end
        end
    end

    if acq_map.n_follow_202 > acq_map.n_follow_242
        acq_map.CSplus_family  = "202";
        acq_map.CSminus_family = "242";
    elseif acq_map.n_follow_242 > acq_map.n_follow_202
        acq_map.CSplus_family  = "242";
        acq_map.CSminus_family = "202";
    else
        acq_map.CSplus_family  = "";
        acq_map.CSminus_family = "";
    end

    function t = normalize_type(x)
        if isnumeric(x)
            t = strtrim(num2str(x));
        else
            t = char(string(x));
            t = strtrim(t);
            t = regexprep(t, '\s+', ' ');
            m = regexp(t, '^S(\d+)$', 'tokens', 'once');
            if ~isempty(m)
                t = ['S ' m{1}];
            end
        end
    end
end

function conds = build_condition_labels(acq_map, cs_map)
    conds = cell(1, 2+4+5+6+2);

    % HAB
    conds{1} = 'HAB_CS1';
    conds{2} = 'HAB_CS2';

    % ACQ
    if acq_map.CSplus_family == "242"
        conds{3} = 'ACQ_CSminus_first';
        conds{4} = 'ACQ_CSplus_first';
        conds{5} = 'ACQ_CSminus';
        conds{6} = 'ACQ_CSplus';
    else
        conds{3} = 'ACQ_CSplus_first';
        conds{4} = 'ACQ_CSminus_first';
        conds{5} = 'ACQ_CSplus';
        conds{6} = 'ACQ_CSminus';
    end

    % GEN
    conds{7}  = 'GEN_CS1';
    conds{8}  = 'GEN_GS1';
    conds{9}  = 'GEN_GSU';
    conds{10} = 'GEN_GS2';
    conds{11} = 'GEN_CS2';

    % EXT
    if acq_map.CSplus_family == "242"
        conds{12} = 'EXT_CSminus_first';
        conds{13} = 'EXT_CSplus_first';
        conds{14} = 'EXT_CSminus_second';
        conds{15} = 'EXT_CSplus_second';
        conds{16} = 'EXT_CSminus_third';
        conds{17} = 'EXT_CSplus_third';
    else
        conds{12} = 'EXT_CSplus_first';
        conds{13} = 'EXT_CSminus_first';
        conds{14} = 'EXT_CSplus_second';
        conds{15} = 'EXT_CSminus_second';
        conds{16} = 'EXT_CSplus_third';
        conds{17} = 'EXT_CSminus_third';
    end

    % ROF
    if strcmpi(cs_map.CSplus_identity, 'CS1')
        conds{18} = 'ROF_CSplus';
        conds{19} = 'ROF_CSminus';
    elseif strcmpi(cs_map.CSplus_identity, 'CS2')
        conds{18} = 'ROF_CSminus';
        conds{19} = 'ROF_CSplus';
    else
        conds{18} = 'ROF_CS1';
        conds{19} = 'ROF_CS2';
    end
end

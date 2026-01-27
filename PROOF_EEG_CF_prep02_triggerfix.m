%% ANALYSIS SCRIPT - EEG - PROOF - Classical Paradigm (Real Data)
% Metin Ozyagcilar & Saskia Wilken / RE-ORGANIZING TRIGGERS / NOV 2023 & DEZ 2025
% MATLAB 2025b
%
% IMPORTANT FIX (Jan 2026, per your note):
%   RAW TRIGGER MEANING IS FIXED (NO SUBJECT-LEVEL COUNTERBALANCING):
%     - S 20 = CS-
%     - S 24 = CS+
%   Therefore:
%     - Remove behavior/parity CS1/CS2 mapping logic
%     - Remove EEG-acquisition “sanity check override” logic
%     - Update all identity-coded phase remaps (habituation/generalization) accordingly
%
% ADDITIONS (order QC):
%  A) Read behavioral logfile from BIDS tree: sub-*/ses-01/beh/
%  B) RAW QC BEFORE RENAMING: Compare behavior key-events order vs RAW EEG triggers
%     and write detailed mismatch CSV (1s bins) if mismatch is detected
%  C) Write a running log to ROOT\logs\triggers\triggerfix_<timestamp>.log
%
% CHANGE (per request, minimal):
%  - Do NOT save the unaltered "00_eeglab_set" raw .set file(s)
%  - Only save *_triggersfixed.set into 01_trigger_fix
%
% SIMPLIFICATION (per request):
%  - Extinction remapping is single-pass with 3 blocks:
%       first 11 -> 2041/2441
%       next 10  -> 2042/2442
%       rest     -> 2043/2443
%  - Removed the SECOND/POST-RENAMING order check (to avoid confusion and bugs)

clear all; close all; clc;

%% DEFINE FOLDERS

this_file  = matlab.desktop.editor.getActiveFilename();
this_dir   = fileparts(this_file);

base_path = fileparts(fileparts(fileparts(this_dir)));

mainpath    = [base_path, '\Paper\2025-11-03 MATRICS Study\MATRICS-Study']; %#ok<NASGU>
path_eeglab = [base_path, '\MATLAB\eeglab_current\eeglab2025.1.0'];

path_bids_root = [base_path, '\Raw_data\BIDS_RTGMN_Classic'];

% NOTE: raw-set output disabled (no 00_eeglab_set output)
path_preprocessed = [base_path, '\Preprocessed_data\MATRICS\eeg\01_trigger_fix'];

%% LOGGING
logs_dir = fullfile(this_dir, 'logs', 'triggers');
if ~exist(logs_dir,'dir'); mkdir(logs_dir); end
log_file = fullfile(logs_dir, sprintf('triggerfix_%s.log', datestr(now,'yyyymmdd_HHMMSS')));
log_fid  = fopen(log_file, 'a');
if log_fid < 0
    error('Could not open log file for writing: %s', log_file);
end
cleanupObj = onCleanup(@() fclose(log_fid)); %#ok<NASGU>

logmsg(log_fid, '=== Triggerfix started: %s ===', datestr(now));
logmsg(log_fid, 'Script dir (ROOT): %s', this_dir);
logmsg(log_fid, 'BIDS root: %s', path_bids_root);
logmsg(log_fid, 'NOTE: RAW QC (behavior vs RAW EEG) is executed BEFORE any renaming.');
logmsg(log_fid, 'NOTE: Extinction remap is SINGLE-PASS (3 blocks: 11 / 10 / rest).');
logmsg(log_fid, 'FIXED RAW MAPPING: S 20 = CS- | S 24 = CS+ (no subject-level remapping).');

%% SUBJECT IDs
ds = dir(fullfile(path_bids_root,'sub-*'));
ds = ds([ds.isdir]);
sub = arrayfun(@(d) [erase(d.name,'sub-')], ds, 'uni', false);

%% CREATE SUBJECT FOLDERS (ensure roots exist)
if ~exist(path_preprocessed,'dir'); mkdir(path_preprocessed); end
for i = 1:length(sub)
    if ~exist(fullfile(path_preprocessed, sub{i}), 'dir')
        mkdir(fullfile(path_preprocessed, sub{i}));
    end
end

cd(path_eeglab);
[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab; %#ok<ASGLU>

%% START FIXING THE TRIGGERS

for i = 1:3 % length(sub)   % loop subjects

    subj_id = sub{i};
    logmsg(log_fid, '--- Subject %s ---', subj_id);

    % Locate behavioral logfile (optional; only used for RAW order QC)
    beh = [];
    beh_file = '';
    try
        beh_file = find_behavior_log(path_bids_root, subj_id);
        logmsg(log_fid, 'Behavior log: %s', beh_file);
        beh = read_behavior_log(beh_file);
    catch ME
        logmsg(log_fid, 'WARNING: Could not read/interpret behavioral log for %s. Reason: %s', subj_id, ME.message);
        logmsg(log_fid, 'RAW ORDER CHECK will be skipped for this subject.');
        beh = [];
        beh_file = '';
    end

    % PURGE subject output folder before writing fresh results
    sub_out_dir_fixed = fullfile(path_preprocessed, subj_id);
    if exist(sub_out_dir_fixed, 'dir'); rmdir(sub_out_dir_fixed, 's'); end
    mkdir(sub_out_dir_fixed);

    eeg_dir  = fullfile(path_bids_root, ['sub-' subj_id], 'ses-01', 'eeg');

    pattern   = sprintf('sub-%s_ses-01_task-classical*_eeg.vhdr', subj_id);
    vhdr_list = dir(fullfile(eeg_dir, pattern));
    if isempty(vhdr_list)
        logmsg(log_fid, 'No BIDS EEG files found for %s in %s', subj_id, eeg_dir);
        fprintf('No BIDS EEG files found for %s in %s\n', subj_id, eeg_dir);
        continue;
    end

    for f = 1:numel(vhdr_list)

        eeglab redraw
        a = 0;

        bids_vhdr = vhdr_list(f).name;

        EEG = pop_loadbv(eeg_dir, bids_vhdr, [], ...
            [1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 ...
             25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 ...
             47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66]);

        [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, a, 'gui', 'off');
        a = a + 1;

        % NOTE: raw .set output disabled; still need bids_base for naming output
        [~, bids_base] = fileparts(bids_vhdr);
        EEG = eeg_checkset(EEG);

        % ==========================================================
        % RAW ORDER QC (BEHAVIOR vs RAW EEG)  <-- MUST BE BEFORE RENAMING
        % Writes a detailed mismatch CSV if mismatch is detected.
        % ==========================================================
        if ~isempty(beh)
            try
                qc_cfg = struct();
                qc_cfg.bin_size_s = 1;                 % 1-second bins
                qc_cfg.max_rows   = 20000;             % safety cap for very long runs
                qc_cfg.keep_tokens = ["S 20","S 21","S 22","S 23","S 24","S 15","S 5"];
                qc_cfg.write_csv_on_ok = false;        % only write when mismatch by default

                raw_qc_behavior_vs_eeg_and_write_csv( ...
                    beh, EEG, subj_id, bids_base, logs_dir, log_fid, qc_cfg);

            catch ME
                logmsg(log_fid, 'WARNING: RAW ORDER CHECK failed for %s (%s)', bids_base, ME.message);
            end
        else
            logmsg(log_fid, 'RAW ORDER CHECK skipped (no behavioral log parsed) for %s', bids_base);
        end

        % ------------------------------------------------------------
        % FIXED RAW MAPPING (NO COUNTERBALANCING):
        %   S 20 == CS-
        %   S 24 == CS+
        % ------------------------------------------------------------
        raw_CSminus = 'S 20';
        raw_CSplus  = 'S 24';
        EEG = append_comment_line(EEG, 'CS mapping FIXED: S20=CS- | S24=CS+');

        %% ==========================
        %  PASS 1: PHASE-GATED REMAP (SINGLE PASS)
        % ==========================

        hab_start = 0;
        acq_start = 0;
        gen_start = 0;
        ext_start = 0;
        rof_start = 0;

        acq_block_csmin  = 0;
        acq_block_csplus = 0;

        % Extinction counters (single-pass; 3 blocks like acquisition but with 11/10/rest)
        ext_count_csmin  = 0;
        ext_count_csplus = 0;
        ext_n_first  = 11;
        ext_n_second = 10;

        for x = 1:length(EEG.event)

            % Normalize type once (helps if BrainVision spacing varies)
            EEG.event(x).type = normalize_trigger_type(EEG.event(x).type);

            % Phase markers
            switch EEG.event(x).type
                case 'S 91'
                    hab_start = 1; acq_start = 0; gen_start = 0; ext_start = 0; rof_start = 0;
                case 'S 92'
                    hab_start = 0; acq_start = 1; gen_start = 0; ext_start = 0; rof_start = 0;
                case 'S 93'
                    hab_start = 0; acq_start = 0; gen_start = 1; ext_start = 0; rof_start = 0;
                case 'S 94'
                    hab_start = 0; acq_start = 0; gen_start = 0; ext_start = 1; rof_start = 0;
                case 'S 95'
                    hab_start = 0; acq_start = 0; gen_start = 0; ext_start = 0; rof_start = 1;
            end

            % Habituation remap (identity-style codes but NOW interpreted as CS-/CS+ by raw mapping)
            if hab_start == 1
                switch EEG.event(x).type
                    case 'S 20', EEG.event(x).type = 'S 201'; % CS-
                    case 'S 21', EEG.event(x).type = 'S 211'; % GS1
                    case 'S 22', EEG.event(x).type = 'S 221'; % GSU
                    case 'S 23', EEG.event(x).type = 'S 231'; % GS2
                    case 'S 24', EEG.event(x).type = 'S 241'; % CS+
                end
            end

            % Acquisition remap (VALENCE-coded: 202x = CS-, 242x = CS+)
            if acq_start == 1
                if (acq_block_csmin < 10) || (acq_block_csplus < 10)
                    switch EEG.event(x).type
                        case raw_CSminus, EEG.event(x).type = 'S 2021'; acq_block_csmin  = acq_block_csmin  + 1;
                        case raw_CSplus,  EEG.event(x).type = 'S 2421'; acq_block_csplus = acq_block_csplus + 1;
                    end
                else
                    switch EEG.event(x).type
                        case raw_CSminus, EEG.event(x).type = 'S 2022'; acq_block_csmin  = acq_block_csmin  + 1;
                        case raw_CSplus,  EEG.event(x).type = 'S 2422'; acq_block_csplus = acq_block_csplus + 1;
                    end
                end
            end

            % Generalization remap (identity-style codes but NOW interpreted as CS-/CS+ by raw mapping)
            if gen_start == 1
                switch EEG.event(x).type
                    case 'S 20', EEG.event(x).type = 'S 203'; % CS-
                    case 'S 21', EEG.event(x).type = 'S 213'; % GS1
                    case 'S 22', EEG.event(x).type = 'S 223'; % GSU
                    case 'S 23', EEG.event(x).type = 'S 233'; % GS2
                    case 'S 24', EEG.event(x).type = 'S 243'; % CS+
                end
            end

            % Extinction remap (VALENCE-coded; SINGLE PASS with 3 blocks)
            if ext_start == 1
                switch EEG.event(x).type
                    case raw_CSminus
                        ext_count_csmin = ext_count_csmin + 1;
                        if ext_count_csmin <= ext_n_first
                            EEG.event(x).type = 'S 2041';
                        elseif ext_count_csmin <= (ext_n_first + ext_n_second)
                            EEG.event(x).type = 'S 2042';
                        else
                            EEG.event(x).type = 'S 2043';
                        end

                    case raw_CSplus
                        ext_count_csplus = ext_count_csplus + 1;
                        if ext_count_csplus <= ext_n_first
                            EEG.event(x).type = 'S 2441';
                        elseif ext_count_csplus <= (ext_n_first + ext_n_second)
                            EEG.event(x).type = 'S 2442';
                        else
                            EEG.event(x).type = 'S 2443';
                        end
                end
            end

            % ==========================================================
            % ROF remap (VALENCE-coded for CS triggers)
            %   - CS- -> S 205
            %   - CS+ -> S 245
            %   - GS1/GSU/GS2 keep identity-coded: 215/225/235
            % ==========================================================
            if rof_start == 1
                switch EEG.event(x).type
                    case raw_CSminus, EEG.event(x).type = 'S 205'; % CS-
                    case raw_CSplus,  EEG.event(x).type = 'S 245'; % CS+
                    case 'S 21', EEG.event(x).type = 'S 215'; % GS1
                    case 'S 22', EEG.event(x).type = 'S 225'; % GSU
                    case 'S 23', EEG.event(x).type = 'S 235'; % GS2
                end
            end
        end

        %% ==========================================================
        %  PASS 3: "disable" first extinction trial per stream for epoching
        % ==========================================================

        first_ext_minus_done = 0; % CS- stream (2041/2042/2043)
        first_ext_plus_done  = 0; % CS+ stream (2441/2442/2443)

        for x = 1:length(EEG.event)

            if first_ext_minus_done == 0 && strcmp(EEG.event(x).type, 'S 2041')
                EEG.event(x).type = raw_CSminus; % revert first CS- extinction marker -> S 20
                first_ext_minus_done = 1;
            end

            if first_ext_plus_done == 0 && strcmp(EEG.event(x).type, 'S 2441')
                EEG.event(x).type = raw_CSplus; % revert first CS+ extinction marker -> S 24
                first_ext_plus_done = 1;
            end

            if first_ext_minus_done && first_ext_plus_done
                break;
            end
        end

        %% ==========================================================
        %  PASS 4: disable first acquisition trials
        % ==========================================================

        acqdelete_one = 0; % CS- first trial
        acqdelete_two = 0; % CS+ first trial

        for x = 1:length(EEG.event)
            if acqdelete_one ~= 1 && strcmp(EEG.event(x).type, 'S 2021')
                EEG.event(x).type = 'S 20999';
                acqdelete_one = 1;
            end
            if acqdelete_two ~= 1 && strcmp(EEG.event(x).type, 'S 2421')
                EEG.event(x).type = 'S 24999';
                acqdelete_two = 1;
            end
            if acqdelete_one && acqdelete_two
                break;
            end
        end

        %% SAVE trigger-fixed dataset (ONLY output now)
        EEG = eeg_checkset(EEG);
        EEG = pop_saveset(EEG, 'filename', [bids_base '_triggersfixed.set'], 'filepath', sub_out_dir_fixed);
        [ALLEEG, EEG] = eeg_store(ALLEEG, EEG, CURRENTSET);

        %% CHECK TRIGGERS (optional)
        num245 = 0;
        for x = 1:length(EEG.event)
            if strcmp(EEG.event(x).type, 'S 245')
                num245 = num245 + 1;
            end
        end
        fprintf('%s: %d occurrences of S 245\n', bids_base, num245);
        logmsg(log_fid, '%s: %d occurrences of S 245', bids_base, num245);

    end % file loop
end % subject loop

logmsg(log_fid, '=== Triggerfix finished: %s ===', datestr(now));

%% ==========================
% Local helper functions
% ==========================

function logmsg(fid, varargin)
    msg = sprintf(varargin{:});
    fprintf(fid, '[%s] %s\n', datestr(now,'yyyy-mm-dd HH:MM:SS'), msg);
end

function EEG = append_comment_line(EEG, line)
    % Robust append to EEG.comments
    try
        if ~isfield(EEG,'comments') || isempty(EEG.comments)
            EEG.comments = line;
        else
            EEG.comments = sprintf('%s\n%s', EEG.comments, line);
        end
    catch
        % never fail
    end
end

function tok = normalize_trigger_type(t)
    if isnumeric(t)
        tok = strtrim(num2str(t));
        return;
    end
    tok = char(string(t));
    tok = strtrim(tok);
    tok = regexprep(tok, '\s+', ' ');

    % Normalize S<number> -> S <number>
    m = regexp(tok, '^S(\d+)$', 'tokens', 'once');
    if ~isempty(m)
        tok = ['S ' m{1}];
        return;
    end

    % Normalize "S <spaces>number" -> "S number"
    m = regexp(tok, '^S\s+(\d+)$', 'tokens', 'once');
    if ~isempty(m)
        tok = ['S ' m{1}];
        return;
    end
end

function beh_file = find_behavior_log(path_bids_root, subj_id)
    % Search in: sub-<id>/ses-01/beh/ for files containing 'CF_<id>'
    % Accept .log (real), .txt (fallback), and pick best candidate.

    beh_dir = fullfile(path_bids_root, ['sub-' subj_id], 'ses-01', 'beh');
    if ~exist(beh_dir,'dir')
        error('No beh directory: %s', beh_dir);
    end

    tag = sprintf('CF_%s', subj_id);

    % --- collect candidates (.log preferred, but allow .txt) ---
    cands = [ ...
        dir(fullfile(beh_dir, '*.log')); ...
        dir(fullfile(beh_dir, '*.txt'))  ...
    ];

    if isempty(cands)
        error('No .log/.txt files in %s', beh_dir);
    end

    % Filter by tag occurrence in filename (CF_<id>)
    keep = false(size(cands));
    for k = 1:numel(cands)
        keep(k) = contains(cands(k).name, tag, 'IgnoreCase', true);
    end
    cands_tagged = cands(keep);

    % If nothing matches the tag, fall back to *any* log/txt file
    if ~isempty(cands_tagged)
        cands = cands_tagged;
    end

    % Prefer *_2* if present
    idx2 = find(arrayfun(@(d) contains(d.name, '_2', 'IgnoreCase', true), cands));
    if ~isempty(idx2)
        cands = cands(idx2);
    end

    % Prefer .log over .txt if both exist among remaining candidates
    isLog = arrayfun(@(d) endsWith(lower(d.name), '.log'), cands);
    if any(isLog)
        cands = cands(isLog);
    end

    % Pick most recent
    [~, ix] = max([cands.datenum]);
    beh_file = fullfile(beh_dir, cands(ix).name);
end

function beh = read_behavior_log(beh_file)
    raw = fileread(beh_file);
    lines = regexp(raw, '\r\n|\n|\r', 'split');

    header_idx = 0;
    for i = 1:numel(lines)
        if startsWith(strtrim(lines{i}), 'Subject')
            header_idx = i;
            break;
        end
    end
    if header_idx == 0
        error('Could not find header line starting with "Subject" in %s', beh_file);
    end

    tmp = [tempname '.txt'];
    fid = fopen(tmp,'w');
    for i = header_idx:numel(lines)
        fprintf(fid, '%s\n', lines{i});
    end
    fclose(fid);

    opts = detectImportOptions(tmp, 'Delimiter', '\t', 'FileType', 'text');
    T = readtable(tmp, opts);
    delete(tmp);

    T.Properties.VariableNames = matlab.lang.makeValidName(T.Properties.VariableNames);
    beh = T;
end

%% ==========================================================
% RAW QC: detailed mismatch CSV (semicolon-separated)
%% ==========================================================
function raw_qc_behavior_vs_eeg_and_write_csv(beh, EEG, subj_id, bids_base, logs_dir, log_fid, cfg)
% RAW QC BEFORE ANY RENAMING:
% - builds "key token streams" from behavior + EEG.event (raw)
% - checks subsequence order (behavior tokens must appear in EEG in-order)
% - if mismatch: estimates delay, creates 1s-binned alignment table, writes CSV (semicolon)

    arguments
        beh table
        EEG struct
        subj_id char
        bids_base char
        logs_dir char
        log_fid
        cfg.bin_size_s (1,1) double = 1
        cfg.max_rows   (1,1) double = 20000
        cfg.keep_tokens (1,:) string = ["S 20","S 21","S 22","S 23","S 24","S 15","S 5"]
        cfg.write_csv_on_ok (1,1) logical = false
    end

    % --- build token+time streams ---
    [beh_tok, beh_t_s] = build_beh_key_token_stream_with_time(beh);
    [eeg_tok, eeg_t_s] = build_eeg_key_token_stream_with_time(EEG);

    % Filter to the same token universe
    keepB = ismember(beh_tok, cfg.keep_tokens);
    beh_tok = beh_tok(keepB); beh_t_s = beh_t_s(keepB);

    keepE = ismember(eeg_tok, cfg.keep_tokens);
    eeg_tok = eeg_tok(keepE); eeg_t_s = eeg_t_s(keepE);

    if isempty(beh_tok)
        logmsg(log_fid, 'RAW ORDER CHECK: behavior tokens empty after filtering for %s', bids_base);
        return;
    end
    if isempty(eeg_tok)
        logmsg(log_fid, 'RAW ORDER CHECK: EEG tokens empty after filtering for %s', bids_base);
        return;
    end

    % --- check subsequence order + get detailed mismatch indices ---
    [ok, rep] = check_subsequence_order_detailed(beh_tok, eeg_tok);

    if ok
        logmsg(log_fid, 'RAW ORDER CHECK OK for %s | %s', bids_base, rep.summary);
        if ~cfg.write_csv_on_ok
            return;
        end
    else
        logmsg(log_fid, 'RAW ORDER CHECK MISMATCH for %s | missing="%s" at beh_i=%d | lastMatchEegIdx=%d', ...
            bids_base, rep.missing_token, rep.beh_i, rep.last_match_eeg_idx);
        logmsg(log_fid, '  beh_ctx[%d..%d]=%s', rep.beh_ctx_i1, rep.beh_ctx_i2, strjoin(rep.beh_ctx, ','));
        logmsg(log_fid, '  eeg_ctx[%d..%d]=%s', rep.eeg_ctx_j1, rep.eeg_ctx_j2, strjoin(rep.eeg_ctx, ','));
    end

    % --- estimate delay using FIRST STIM token (first of S20..S24) ---
    isStimB = ismember(beh_tok, ["S 20","S 21","S 22","S 23","S 24"]);
    isStimE = ismember(eeg_tok, ["S 20","S 21","S 22","S 23","S 24"]);

    if any(isStimB) && any(isStimE)
        tB0 = beh_t_s(find(isStimB, 1, 'first'));
        tE0 = eeg_t_s(find(isStimE, 1, 'first'));
        delay_s = tE0 - tB0; % add to behavior times to align to EEG
    else
        delay_s = NaN;
    end

    % --- build 1s-binned alignment table ---
    % Use "time since first stim" for readability.
    if any(isStimB)
        beh_rel = beh_t_s - beh_t_s(find(isStimB, 1, 'first'));
    else
        beh_rel = beh_t_s - beh_t_s(1);
    end
    if any(isStimE)
        eeg_rel = eeg_t_s - eeg_t_s(find(isStimE, 1, 'first'));
    else
        eeg_rel = eeg_t_s - eeg_t_s(1);
    end

    % Apply delay correction to behavior so bins line up with EEG bins
    if ~isnan(delay_s)
        beh_rel_aligned = beh_rel + delay_s;
    else
        beh_rel_aligned = beh_rel;
    end

    bin = cfg.bin_size_s;

    minT = min([0; beh_rel_aligned; eeg_rel]);
    maxT = max([beh_rel_aligned; eeg_rel]);

    b0 = floor(minT/bin) * bin;
    b1 = ceil(maxT/bin)  * bin;

    edges = b0:bin:b1;
    if numel(edges) < 2
        edges = [b0, b0+bin];
    end

    nBins = numel(edges)-1;
    if nBins > cfg.max_rows
        nBins = cfg.max_rows;
        edges = edges(1:nBins+1);
    end

    beh_in_bin = cell(nBins,1);
    eeg_in_bin = cell(nBins,1);
    n_beh      = zeros(nBins,1);
    n_eeg      = zeros(nBins,1);

    for bi = 1:nBins
        t1 = edges(bi);
        t2 = edges(bi+1);

        idxB = beh_rel_aligned >= t1 & beh_rel_aligned < t2;
        idxE = eeg_rel         >= t1 & eeg_rel         < t2;

        if any(idxB)
            beh_in_bin{bi} = strjoin(beh_tok(idxB), '|');
            n_beh(bi) = sum(idxB);
        else
            beh_in_bin{bi} = "";
        end

        if any(idxE)
            eeg_in_bin{bi} = strjoin(eeg_tok(idxE), '|');
            n_eeg(bi) = sum(idxE);
        else
            eeg_in_bin{bi} = "";
        end
    end

    T = table();
    T.bin_start_s      = edges(1:nBins)';
    T.bin_end_s        = edges(2:nBins+1)';
    T.beh_events       = string(beh_in_bin);
    T.eeg_events       = string(eeg_in_bin);
    T.n_beh_events     = n_beh;
    T.n_eeg_events     = n_eeg;

    out_csv = fullfile(logs_dir, sprintf('order_mismatch_sub-%s_%s.csv', subj_id, bids_base));
    fid = fopen(out_csv, 'w');
    if fid < 0
        logmsg(log_fid, 'WARNING: could not write mismatch CSV: %s', out_csv);
        return;
    end

    fprintf(fid, 'subject;%s\n', subj_id);
    fprintf(fid, 'bids_base;%s\n', bids_base);
    fprintf(fid, 'delay_s;%s\n', num2str(delay_s));
    fprintf(fid, 'bin_size_s;%g\n', bin);
    fprintf(fid, 'mismatch;%d\n', ~ok);
    if ~ok
        fprintf(fid, 'first_missing_token;%s\n', rep.missing_token);
        fprintf(fid, 'beh_missing_index;%d\n', rep.beh_i);
        fprintf(fid, 'last_match_eeg_index;%d\n', rep.last_match_eeg_idx);
    end
    fprintf(fid, '\n');
    fprintf(fid, 'bin_start_s;bin_end_s;beh_events;eeg_events;n_beh_events;n_eeg_events\n');

    for r = 1:height(T)
        fprintf(fid, '%.3f;%.3f;%s;%s;%d;%d\n', ...
            T.bin_start_s(r), T.bin_end_s(r), ...
            escape_semicolons(T.beh_events(r)), ...
            escape_semicolons(T.eeg_events(r)), ...
            T.n_beh_events(r), T.n_eeg_events(r));
    end
    fclose(fid);

    logmsg(log_fid, 'RAW ORDER CHECK: wrote mismatch CSV: %s', out_csv);
end

function s = escape_semicolons(s)
    s = string(s);
    s = replace(s, ";", ",");
end

function [tokens, times_s] = build_beh_key_token_stream_with_time(beh)
% Returns:
%   tokens: string(N,1) of "S xx"
%   times_s: double(N,1) in seconds (from beh.Time in ms)
%
% Robust mapping:
%   - Accept CS-/CSminus/CS1 -> S 20
%   - Accept CS+/CSplus/CS2 -> S 24

    vars = beh.Properties.VariableNames;
    if ~ismember('EventType', vars) || ~ismember('Code', vars) || ~ismember('Time', vars)
        error('Behavior log missing required columns among EventType/Code/Time');
    end

    [~, ix] = sort(beh.Time);
    beh = beh(ix,:);

    tokens  = strings(0,1);
    times_s = zeros(0,1);

    for r = 1:height(beh)
        et = string(beh.EventType(r));
        cd = string(beh.Code(r));
        t  = double(beh.Time(r)) / 1000; % ms -> s

        if strcmpi(et, 'Picture')
            cdl = lower(strtrim(cd));

            % CS- stream -> S20
            if ismember(cdl, ["cs-","csminus","cs_min","csmin","cs1"])
                tokens(end+1,1) = "S 20"; times_s(end+1,1) = t; continue;
            end

            % GS mapping stays same
            if strcmpi(cd,'GS1'); tokens(end+1,1) = "S 21"; times_s(end+1,1) = t; continue; end
            if strcmpi(cd,'GSU'); tokens(end+1,1) = "S 22"; times_s(end+1,1) = t; continue; end
            if strcmpi(cd,'GS2'); tokens(end+1,1) = "S 23"; times_s(end+1,1) = t; continue; end

            % CS+ stream -> S24
            if ismember(cdl, ["cs+","csplus","cs_pls","cspls","cs2"])
                tokens(end+1,1) = "S 24"; times_s(end+1,1) = t; continue;
            end
        end

        if strcmpi(et, 'Sound') && strcmpi(cd, 'Startle')
            tokens(end+1,1) = "S 15"; times_s(end+1,1) = t; continue;
        end

        if strcmpi(et, 'Nothing') && strcmpi(cd, 'Shock')
            tokens(end+1,1) = "S 5"; times_s(end+1,1) = t; continue;
        end
    end
end

function [tokens, times_s] = build_eeg_key_token_stream_with_time(EEG)
% Use RAW EEG.event (right after pop_loadbv) and convert latency->seconds.

    if ~isfield(EEG,'event') || isempty(EEG.event)
        tokens  = strings(0,1);
        times_s = zeros(0,1);
        return;
    end
    if ~isfield(EEG,'srate') || isempty(EEG.srate)
        error('EEG.srate missing/empty');
    end

    n = numel(EEG.event);
    tokens  = strings(0,1);
    times_s = zeros(0,1);

    for k = 1:n
        t = normalize_trigger_type(EEG.event(k).type);
        if strcmpi(t, 'boundary'); continue; end

        tok = string(t);
        tokens(end+1,1)  = tok;
        times_s(end+1,1) = double(EEG.event(k).latency) / double(EEG.srate);
    end
end

function [ok, rep] = check_subsequence_order_detailed(beh_tokens, eeg_tokens)
% Like your old check, but returns indices + contexts in structured form.

    i = 1; j = 1;
    lastMatchEegIdx = 0;

    while i <= numel(beh_tokens) && j <= numel(eeg_tokens)
        if beh_tokens(i) == eeg_tokens(j)
            lastMatchEegIdx = j;
            i = i + 1;
            j = j + 1;
        else
            j = j + 1;
        end
    end

    ok = (i > numel(beh_tokens));

    rep = struct();
    rep.last_match_eeg_idx = lastMatchEegIdx;

    if ok
        rep.summary = sprintf('OK: %d behavior tokens found in EEG stream (in-order subsequence).', numel(beh_tokens));
        rep.missing_token = "";
        rep.beh_i = NaN;
        rep.beh_ctx = strings(0,1);
        rep.eeg_ctx = strings(0,1);
        rep.beh_ctx_i1 = NaN; rep.beh_ctx_i2 = NaN;
        rep.eeg_ctx_j1 = NaN; rep.eeg_ctx_j2 = NaN;
        return;
    end

    rep.missing_token = beh_tokens(i);
    rep.beh_i = i;

    rep.beh_ctx_i1 = max(1, i-10);
    rep.beh_ctx_i2 = min(numel(beh_tokens), i+10);
    rep.beh_ctx = beh_tokens(rep.beh_ctx_i1:rep.beh_ctx_i2);

    rep.eeg_ctx_j1 = max(1, lastMatchEegIdx-10);
    rep.eeg_ctx_j2 = min(numel(eeg_tokens), lastMatchEegIdx+30);
    rep.eeg_ctx = eeg_tokens(rep.eeg_ctx_j1:rep.eeg_ctx_j2);
end

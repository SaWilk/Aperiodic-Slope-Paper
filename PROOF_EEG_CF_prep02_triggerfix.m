function step_out = proof_eeg_cf_prep02_triggerfix(subj_id, cfg, paths, helpers)
% PROOF_EEG_CF_PREP02_TRIGGERFIX  Trigger re-mapping + (optional) RAW order QC.
%
% - Function; no cd/clear/close
% - Exactly one output per subject by default
% - Logging via helpers.logmsg_default
% - Delete behavior via cfg.io.overwrite_mode ("delete"|"skip")
% - Uses ONLY helpers.safe_delete_set (defined in mother script)

%% ========================================================================
%  DEFAULTS
% ========================================================================
step_out = struct('ok', false, 'skipped', false, 'out_set_file', '', 'message', '');

step_cfg = struct();
step_cfg.run_raw_order_qc = true;

step_cfg.allow_multiple_runs = false;
step_cfg.multiple_vhdr_policy = "most_recent"; % "most_recent" | "first" | "error"

step_cfg.qc_out_dir = "";

step_cfg.ext_n_first  = 11;
step_cfg.ext_n_second = 10;

step_cfg.disable_first_acq_trials = true;
step_cfg.disable_first_ext_trials = true;

step_cfg.overwrite_mode = "";

% merge cfg overrides if present
if isfield(cfg, 'steps') && isfield(cfg.steps, 'prep02_triggerfix')
    s = cfg.steps.prep02_triggerfix;
    if isfield(s, 'overwrite_mode') && strlength(string(s.overwrite_mode)) > 0
        step_cfg.overwrite_mode = string(s.overwrite_mode);
    end
    if isfield(s, 'allow_multiple_runs'); step_cfg.allow_multiple_runs = s.allow_multiple_runs; end
    if isfield(s, 'run_raw_order_qc');    step_cfg.run_raw_order_qc    = s.run_raw_order_qc; end
end

overwrite_mode = resolve_overwrite_mode(cfg, step_cfg);

%% ========================================================================
%  PATHS
% ========================================================================
if ~isfield(paths, 'bids_ses_dir')
    paths.bids_ses_dir = fullfile(paths.bids_root, sprintf('sub-%s', subj_id), 'ses-01');
end

if isfield(paths, 'prep02_out_dir')
    prep02_out_dir = paths.prep02_out_dir;
else
    % fallback (should normally never happen)
    prep02_out_dir = fullfile(paths.out_root, '01_trigger_fix', sprintf('sub-%s', subj_id));
end
helpers.ensure_dir(prep02_out_dir);

qc_out_dir = step_cfg.qc_out_dir;
if strlength(string(qc_out_dir)) == 0
    qc_out_dir = prep02_out_dir;
end
helpers.ensure_dir(qc_out_dir);

%% ========================================================================
%  INPUT DISCOVERY (BIDS EEG)
% ========================================================================
eeg_dir = fullfile(paths.bids_ses_dir, 'eeg');
pattern = sprintf('sub-%s_ses-01_task-classical*_eeg.vhdr', subj_id);
vhdr_list = dir(fullfile(eeg_dir, pattern));

if isempty(vhdr_list)
    msg = sprintf('No BIDS EEG .vhdr found for sub-%s in %s (pattern=%s)', subj_id, eeg_dir, pattern);
    helpers.logmsg_default('%s', msg);
    step_out.message = msg;
    return;
end

% choose file if multiple and allow_multiple_runs=false
if numel(vhdr_list) > 1 && ~step_cfg.allow_multiple_runs
    switch step_cfg.multiple_vhdr_policy
        case "error"
            msg = sprintf('Found %d .vhdr files for sub-%s but allow_multiple_runs=false. Refuse to proceed.', ...
                numel(vhdr_list), subj_id);
            helpers.logmsg_default('%s', msg);
            step_out.message = msg;
            return;

        case "first"
            vhdr_list = vhdr_list(1);

        otherwise % "most_recent"
            [~, ix] = max([vhdr_list.datenum]);
            vhdr_list = vhdr_list(ix);
    end

    helpers.logmsg_default('Multiple vhdr found; using "%s" policy -> %s', ...
        string(step_cfg.multiple_vhdr_policy), vhdr_list.name);
end

% safety: ensure struct array (some people accidentally turn this into non-struct)
if ~isstruct(vhdr_list)
    msg = 'vhdr_list is not a struct array (unexpected).';
    helpers.logmsg_default('ERROR: %s', msg);
    step_out.message = msg;
    return;
end

%% ========================================================================
%  OPTIONAL BEHAVIOR LOG (for RAW QC)
% ========================================================================
beh = [];
beh_file = "";
if step_cfg.run_raw_order_qc
    try
        beh_file = helpers.find_behavior_log(paths.bids_root, subj_id);
        beh = helpers.read_behavior_log(beh_file);
        helpers.logmsg_default('Behavior log: %s', beh_file);
    catch me
        helpers.logmsg_default('WARNING: Could not read/interpret behavioral log for sub-%s. RAW QC skipped. Reason: %s', ...
            subj_id, me.message);
        beh = [];
        beh_file = "";
    end
else
    helpers.logmsg_default('RAW QC disabled by cfg.');
end

%% ========================================================================
%  MAIN LOOP
% ========================================================================
out_files = strings(0,1);

for f = 1:numel(vhdr_list)

    bids_vhdr = vhdr_list(f).name;
    [~, bids_base] = fileparts(bids_vhdr);

    % --- IMPORTANT: out_set_file is built HERE (not inside helper funcs)
    out_set_file = fullfile(prep02_out_dir, sprintf('%s_triggersfixed.set', bids_base));
    out_set_file = char(string(out_set_file));  % normalize for exist/delete/logging

    % Overwrite policy (per output file)
    [do_run, skip_reason] = should_run_step(out_set_file, overwrite_mode, helpers, cfg);
    if ~do_run
        helpers.logmsg_default('Step 02 skip: %s', skip_reason);
        step_out.skipped = true;
        out_files(end+1,1) = string(out_set_file);
        continue;
    end

    if overwrite_mode == "delete"
        helpers.safe_delete_set(out_set_file);
    end

    helpers.logmsg_default('Step 02 triggerfix: loading %s', bids_vhdr);

    EEG = pop_loadbv(eeg_dir, bids_vhdr, [], ...
        [1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 ...
         25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 ...
         47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66]);

    EEG = eeg_checkset(EEG);

    % ==========================================================
    % RAW QC BEFORE RENAMING (optional)
    % ==========================================================
    if ~isempty(beh)
        try
            qc_cfg = struct();
            qc_cfg.bin_size_s        = 1;
            qc_cfg.max_rows          = 20000;
            qc_cfg.keep_tokens       = ["S 20","S 21","S 22","S 23","S 24","S 15","S 5"];
            qc_cfg.write_csv_on_ok   = false;
            qc_cfg.qc_out_dir        = qc_out_dir;

            helpers.raw_qc_behavior_vs_eeg_and_write_csv( ...
                beh, EEG, subj_id, bids_base, qc_out_dir, qc_cfg);

        catch me
            helpers.logmsg_default('WARNING: RAW QC failed for %s (sub-%s). Reason: %s', bids_base, subj_id, me.message);
        end
    else
        helpers.logmsg_default('RAW QC skipped (no behavior log) for %s', bids_base);
    end

    % ------------------------------------------------------------
    % FIXED RAW MAPPING:
    %   S 20 == CS-
    %   S 24 == CS+
    % ------------------------------------------------------------
    raw_csminus = 'S 20';
    raw_csplus  = 'S 24';

    EEG = helpers.append_eeg_comment(EEG, 'prep02_triggerfix: fixed CS mapping S20=CS- | S24=CS+');

    % ==========================================================
    % PASS 1: PHASE-GATED REMAP (SINGLE PASS)
    % ==========================================================
    hab_start = false; acq_start = false; gen_start = false; ext_start = false; rof_start = false;

    acq_block_csmin  = 0;
    acq_block_csplus = 0;

    ext_count_csmin  = 0;
    ext_count_csplus = 0;

    ext_n_first  = step_cfg.ext_n_first;
    ext_n_second = step_cfg.ext_n_second;

    for x = 1:numel(EEG.event)

        EEG.event(x).type = helpers.normalize_trigger_type(EEG.event(x).type);

        switch EEG.event(x).type
            case 'S 91'
                hab_start = true;  acq_start = false; gen_start = false; ext_start = false; rof_start = false;
            case 'S 92'
                hab_start = false; acq_start = true;  gen_start = false; ext_start = false; rof_start = false;
            case 'S 93'
                hab_start = false; acq_start = false; gen_start = true;  ext_start = false; rof_start = false;
            case 'S 94'
                hab_start = false; acq_start = false; gen_start = false; ext_start = true;  rof_start = false;
            case 'S 95'
                hab_start = false; acq_start = false; gen_start = false; ext_start = false; rof_start = true;
        end

        if hab_start
            switch EEG.event(x).type
                case 'S 20', EEG.event(x).type = 'S 201';
                case 'S 21', EEG.event(x).type = 'S 211';
                case 'S 22', EEG.event(x).type = 'S 221';
                case 'S 23', EEG.event(x).type = 'S 231';
                case 'S 24', EEG.event(x).type = 'S 241';
            end
        end

        if acq_start
            if (acq_block_csmin < 10) || (acq_block_csplus < 10)
                switch EEG.event(x).type
                    case raw_csminus
                        EEG.event(x).type = 'S 2021'; acq_block_csmin  = acq_block_csmin  + 1;
                    case raw_csplus
                        EEG.event(x).type = 'S 2421'; acq_block_csplus = acq_block_csplus + 1;
                end
            else
                switch EEG.event(x).type
                    case raw_csminus
                        EEG.event(x).type = 'S 2022'; acq_block_csmin  = acq_block_csmin  + 1;
                    case raw_csplus
                        EEG.event(x).type = 'S 2422'; acq_block_csplus = acq_block_csplus + 1;
                end
            end
        end

        if gen_start
            switch EEG.event(x).type
                case 'S 20', EEG.event(x).type = 'S 203';
                case 'S 21', EEG.event(x).type = 'S 213';
                case 'S 22', EEG.event(x).type = 'S 223';
                case 'S 23', EEG.event(x).type = 'S 233';
                case 'S 24', EEG.event(x).type = 'S 243';
            end
        end

        if ext_start
            switch EEG.event(x).type
                case raw_csminus
                    ext_count_csmin = ext_count_csmin + 1;
                    if ext_count_csmin <= ext_n_first
                        EEG.event(x).type = 'S 2041';
                    elseif ext_count_csmin <= (ext_n_first + ext_n_second)
                        EEG.event(x).type = 'S 2042';
                    else
                        EEG.event(x).type = 'S 2043';
                    end

                case raw_csplus
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

        if rof_start
            switch EEG.event(x).type
                case raw_csminus, EEG.event(x).type = 'S 205';
                case raw_csplus,  EEG.event(x).type = 'S 245';
                case 'S 21', EEG.event(x).type = 'S 215';
                case 'S 22', EEG.event(x).type = 'S 225';
                case 'S 23', EEG.event(x).type = 'S 235';
            end
        end
    end

    % ==========================================================
    % PASS 3: disable first extinction trial per stream
    % ==========================================================
    if step_cfg.disable_first_ext_trials
        first_ext_minus_done = false;
        first_ext_plus_done  = false;

        for x = 1:numel(EEG.event)
            if ~first_ext_minus_done && strcmp(EEG.event(x).type, 'S 2041')
                EEG.event(x).type = raw_csminus;
                first_ext_minus_done = true;
            end
            if ~first_ext_plus_done && strcmp(EEG.event(x).type, 'S 2441')
                EEG.event(x).type = raw_csplus;
                first_ext_plus_done = true;
            end
            if first_ext_minus_done && first_ext_plus_done
                break;
            end
        end

        EEG = helpers.append_eeg_comment(EEG, 'prep02_triggerfix: disabled first extinction CS-/CS+ trial (reverted first 2041->S20 and 2441->S24)');
    end

    % ==========================================================
    % PASS 4: disable first acquisition trials
    % ==========================================================
    if step_cfg.disable_first_acq_trials
        acqdelete_one = false;
        acqdelete_two = false;

        for x = 1:numel(EEG.event)
            if ~acqdelete_one && strcmp(EEG.event(x).type, 'S 2021')
                EEG.event(x).type = 'S 20999';
                acqdelete_one = true;
            end
            if ~acqdelete_two && strcmp(EEG.event(x).type, 'S 2421')
                EEG.event(x).type = 'S 24999';
                acqdelete_two = true;
            end
            if acqdelete_one && acqdelete_two
                break;
            end
        end

        EEG = helpers.append_eeg_comment(EEG, 'prep02_triggerfix: disabled first acquisition CS-/CS+ trial (2021->20999, 2421->24999)');
    end

    EEG = eeg_checkset(EEG);

% ---- SAVE output (robust) -------------------------------------------------
fname = sprintf('%s_triggersfixed.set', bids_base);

if cfg.io.dry_run
    helpers.logmsg_default('DRY RUN: would save trigger-fixed set: %s', fullfile(prep02_out_dir, fname));
else
    EEG = helpers.safe_saveset(EEG, prep02_out_dir, fname, helpers, cfg);
    helpers.logmsg_default('Saved trigger-fixed set: %s', fullfile(prep02_out_dir, fname));
end

    % quick sanity count
    num245 = 0;
    for x = 1:numel(EEG.event)
        if strcmp(EEG.event(x).type, 'S 245')
            num245 = num245 + 1;
        end
    end
    helpers.logmsg_default('%s: %d occurrences of S 245', bids_base, num245);

    out_files(end+1,1) = string(out_set_file);
end

%% ========================================================================
%  FINALIZE
% ========================================================================
step_out.ok = true;

if numel(out_files) >= 1
    step_out.out_set_file = char(out_files(1));
end

if numel(out_files) > 1
    step_out.message = sprintf('Wrote %d trigger-fixed sets (allow_multiple_runs=true).', numel(out_files));
end

end % function


%% ========================================================================
%  LOCAL UTILITIES (SAFE: NO OUTER-SCOPE VARIABLES)
% ========================================================================
function overwrite_mode = resolve_overwrite_mode(cfg, step_cfg)
overwrite_mode = string(cfg.io.overwrite_mode);
if isfield(step_cfg, 'overwrite_mode') && strlength(string(step_cfg.overwrite_mode)) > 0
    overwrite_mode = string(step_cfg.overwrite_mode);
end
if overwrite_mode ~= "delete" && overwrite_mode ~= "skip"
    overwrite_mode = "delete";
end
end

function [do_run, reason] = should_run_step(out_set_file, overwrite_mode, helpers, cfg)
% Decide whether to run based on file existence and overwrite policy.
out_set_file = char(string(out_set_file)); % must be char row vector for exist()

exists_out = exist(out_set_file, 'file') == 2;

if ~exists_out
    do_run = true;
    reason = "output not present";
    return;
end

if overwrite_mode == "skip"
    do_run = false;
    reason = sprintf('output exists -> skip (%s)', out_set_file);
    return;
end

do_run = true;
reason = sprintf('output exists -> delete + regenerate (%s)', out_set_file);

if cfg.io.dry_run
    helpers.logmsg_default('DRY RUN: would delete existing output: %s', out_set_file);
end
end

function out = force_char_scalar(x)
% Force any string/cell/char into a 1xN char row vector (scalar).
    if isstring(x)
        x = x(:);
        if isempty(x); out = ''; else; out = char(x(1)); end
        return;
    end
    if iscell(x)
        if isempty(x); out = ''; else; out = force_char_scalar(x{1}); end
        return;
    end
    if ischar(x)
        if isempty(x); out = ''; else; out = x(1,:); end  % first row only
        return;
    end
    if isempty(x)
        out = '';
        return;
    end
    out = char(string(x(1)));
end

function v = getfield_safe(S, field, default)
    if isstruct(S) && isfield(S, field)
        v = S.(field);
    else
        v = default;
    end
end


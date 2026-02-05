function step_out = proof_eeg_cf_prep02_triggerfix(subj_id, cfg, paths, helpers)
% PROOF_EEG_CF_PREP02_TRIGGERFIX - PROOF - Classical Paradigm / Saskia Wilken / JAN 2026
% Step 02 of the PROOF Classical-Conditioning EEG preprocessing pipeline.
%
% Does (short):
%   - Load BIDS BrainVision EEG (.vhdr) for the subject (handles multiple candidates by policy).
%   - OPTIONAL Quality Control (QC): compare event order between behavior log vs raw EEG triggers
%     and write a mismatch CSV (best-effort; never fails the step).
%   - Remap raw triggers into phase-specific codes using phase start markers (S 91..S 95).
%   - Optionally "disable" the first acquisition/extinction trials by replacing their event codes.
%   - Save *_triggersfixed.set into derivatives/01_trigger_fix/sub-XXX/
%
% MATLAB R2023a | EEGLAB required (pop_loadbv, eeg_checkset, pop_saveset)

%% ========================================================================
%  DEFAULTS
% ========================================================================
step_out = struct('ok', false, 'skipped', false, 'out_set_file', '', 'message', '');

step_cfg = struct();

% --- Optional Quality Control (QC) ---
step_cfg.run_raw_order_qc = true;

% --- Multiple BIDS EEG recordings per subject handling ---
step_cfg.allow_multiple_runs  = false;
step_cfg.multiple_vhdr_policy = "most_recent"; % "most_recent" | "first" | "error"

% --- QC output directory (if empty -> prefer paths.qc_dir, else prep02_out_dir) ---
step_cfg.qc_out_dir = "";

% --- Extinction segmentation (Ext1 / Ext2 / Ext3) ---
step_cfg.ext_n_first  = 11;
step_cfg.ext_n_second = 10;

% --- "Disable" first trials (helps exclude known-unreliable early trials) ---
step_cfg.disable_first_acq_trials = true;
step_cfg.disable_first_ext_trials = true;

% --- Explicit channel list for pop_loadbv (PROOF default: 66 channels) ---
step_cfg.use_explicit_chanlist = true;

% --- Overwrite policy override for this step ("" = use cfg.io.overwrite_mode) ---
step_cfg.overwrite_mode = "";

% ---- merge cfg overrides if present -------------------------------------
if isfield(cfg, 'steps') && isfield(cfg.steps, 'prep02_triggerfix')
    s = cfg.steps.prep02_triggerfix;
    if isfield(s, 'overwrite_mode') && strlength(string(s.overwrite_mode)) > 0
        step_cfg.overwrite_mode = string(s.overwrite_mode);
    end
    if isfield(s, 'allow_multiple_runs'); step_cfg.allow_multiple_runs = s.allow_multiple_runs; end
    if isfield(s, 'run_raw_order_qc');    step_cfg.run_raw_order_qc    = s.run_raw_order_qc; end
    if isfield(s, 'multiple_vhdr_policy'); step_cfg.multiple_vhdr_policy = string(s.multiple_vhdr_policy); end
    if isfield(s, 'qc_out_dir');           step_cfg.qc_out_dir = string(s.qc_out_dir); end
    if isfield(s, 'ext_n_first');          step_cfg.ext_n_first = s.ext_n_first; end
    if isfield(s, 'ext_n_second');         step_cfg.ext_n_second = s.ext_n_second; end
    if isfield(s, 'disable_first_acq_trials'); step_cfg.disable_first_acq_trials = s.disable_first_acq_trials; end
    if isfield(s, 'disable_first_ext_trials'); step_cfg.disable_first_ext_trials = s.disable_first_ext_trials; end
    if isfield(s, 'use_explicit_chanlist');    step_cfg.use_explicit_chanlist = s.use_explicit_chanlist; end
end

% ---- merge overrides from mother cfg.prep02 (highest priority) ------------
% This allows adjusting Step02 behavior via cfg.prep02.<field>.
% Example: cfg.prep02.run_raw_order_qc = false;
if isfield(cfg, 'prep02') && isstruct(cfg.prep02)
    f = fieldnames(cfg.prep02);
    for k = 1:numel(f)
        step_cfg.(f{k}) = cfg.prep02.(f{k});
    end
end

overwrite_mode = helpers.resolve_overwrite_mode(cfg, step_cfg.overwrite_mode);

%% ========================================================================
%  PATHS
% ========================================================================
if ~isfield(paths, 'bids_ses_dir')
    paths.bids_ses_dir = fullfile(paths.bids_root, sprintf('sub-%s', subj_id), 'ses-01');
end

if isfield(paths, 'prep02_out_dir')
    prep02_out_dir = paths.prep02_out_dir;
else
    % fallback (should normally never happen if build_paths() is used)
    prep02_out_dir = fullfile(paths.out_root, '01_trigger_fix', sprintf('sub-%s', subj_id));
end
helpers.ensure_dir(prep02_out_dir);

% Prefer centralized QC directory (from mother script) when available
qc_out_dir = string(step_cfg.qc_out_dir);
if strlength(qc_out_dir) == 0
    if isfield(paths, 'qc_dir') && strlength(string(paths.qc_dir)) > 0
        qc_out_dir = string(paths.qc_dir);
    else
        qc_out_dir = string(prep02_out_dir);
    end
end
helpers.ensure_dir(char(qc_out_dir));

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
    switch string(step_cfg.multiple_vhdr_policy)
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

    helpers.logmsg_default('Multiple vhdr found; using policy="%s" -> %s', ...
        string(step_cfg.multiple_vhdr_policy), vhdr_list.name);
end

%% ========================================================================
%  OPTIONAL BEHAVIOR LOG (for RAW Quality Control)
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

    % Output file name
    out_set_file = fullfile(prep02_out_dir, sprintf('%s_triggersfixed.set', bids_base));
    out_set_file = char(string(out_set_file)); % normalize for exist/logging

    % Overwrite policy (centralized helper from mother script)
    [do_run, skip_reason] = helpers.step_should_run_outputs(out_set_file, overwrite_mode, cfg);

    if ~do_run
        helpers.logmsg_default('Step 02 skip: %s', string(skip_reason));
        step_out.skipped = true;
        out_files(end+1,1) = string(out_set_file);
        continue;
    end

    if overwrite_mode == "delete"
        helpers.safe_delete_set(out_set_file);
    end

    helpers.logmsg_default('Step 02 triggerfix: loading %s', bids_vhdr);

    % NOTE: PROOF default expects 66 channels. If your recordings differ, set
    % step_cfg.use_explicit_chanlist=false (then pop_loadbv loads all channels).
    if step_cfg.use_explicit_chanlist
        chanlist = 1:66;
        EEG = pop_loadbv(eeg_dir, bids_vhdr, [], chanlist);
    else
        EEG = pop_loadbv(eeg_dir, bids_vhdr);
    end

    EEG = eeg_checkset(EEG);

    % =====================================================================
    % RAW QC BEFORE RENAMING (optional; best-effort)
    % =====================================================================
    if ~isempty(beh)
        try
            qc_cfg = struct();
            qc_cfg.bin_size_s        = 1;
            qc_cfg.max_rows          = 20000;
            qc_cfg.keep_tokens       = ["S 20","S 21","S 22","S 23","S 24","S 15","S 5"];
            qc_cfg.write_csv_on_ok   = false;

            helpers.raw_qc_behavior_vs_eeg_and_write_csv( ...
                beh, EEG, subj_id, bids_base, char(qc_out_dir), qc_cfg);

        catch me
            helpers.logmsg_default('WARNING: RAW QC failed for %s (sub-%s). Reason: %s', bids_base, subj_id, me.message);
        end
    else
        helpers.logmsg_default('RAW QC skipped (no behavior log) for %s', bids_base);
    end

    % Fixed meaning in this pipeline (no subject-level counterbalancing):
    raw_csminus = 'S 20';
    raw_csplus  = 'S 24';
    EEG = helpers.append_eeg_comment(EEG, 'prep02_triggerfix: fixed CS mapping S20=CS- | S24=CS+');

    % =====================================================================
    % PASS 1: PHASE-GATED REMAP
    % =====================================================================
    hab_start = false; acq_start = false; gen_start = false; ext_start = false; rof_start = false;

    acq_block_csmin  = 0;
    acq_block_csplus = 0;

    ext_count_csmin  = 0;
    ext_count_csplus = 0;

    ext_n_first  = step_cfg.ext_n_first;
    ext_n_second = step_cfg.ext_n_second;

    for x = 1:numel(EEG.event)

        EEG.event(x).type = helpers.normalize_trigger_type(EEG.event(x).type);

        % Phase switches (markers)
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

        % Habituation
        if hab_start
            switch EEG.event(x).type
                case 'S 20', EEG.event(x).type = 'S 201';
                case 'S 21', EEG.event(x).type = 'S 211';
                case 'S 22', EEG.event(x).type = 'S 221';
                case 'S 23', EEG.event(x).type = 'S 231';
                case 'S 24', EEG.event(x).type = 'S 241';
            end
        end

        % Acquisition (split early vs late blocks)
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

        % Generalization
        if gen_start
            switch EEG.event(x).type
                case 'S 20', EEG.event(x).type = 'S 203';
                case 'S 21', EEG.event(x).type = 'S 213';
                case 'S 22', EEG.event(x).type = 'S 223';
                case 'S 23', EEG.event(x).type = 'S 233';
                case 'S 24', EEG.event(x).type = 'S 243';
            end
        end

        % Extinction (Ext1 / Ext2 / Ext3)
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

        % Return of fear
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

    % =====================================================================
    % PASS 2: disable first extinction trial per stream (optional)
    % =====================================================================
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

    % =====================================================================
    % PASS 3: disable first acquisition trials (optional)
    % =====================================================================
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

    % =====================================================================
    % SAVE OUTPUT (robust wrapper from mother script)
    % =====================================================================
    fname = sprintf('%s_triggersfixed.set', bids_base);

    if cfg.io.dry_run
        helpers.logmsg_default('DRY RUN: would save trigger-fixed set: %s', fullfile(prep02_out_dir, fname));
    else
        EEG = helpers.safe_saveset(EEG, prep02_out_dir, fname, helpers, cfg);
        helpers.logmsg_default('Saved trigger-fixed set: %s', fullfile(prep02_out_dir, fname));
    end

    % Quick sanity count for S 245 (Return-of-fear CS+ marker)
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

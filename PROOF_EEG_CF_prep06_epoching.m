function step_out = proof_eeg_cf_prep06_epoching(subj_id, cfg, paths, helpers)
% PROOF_EEG_CF_PREP06_EPOCHING - PROOF - Classical Paradigm / Saskia Wilken / JAN 2026
%
% Step 06 of the PROOF Classical-Conditioning EEG preprocessing pipeline.
%
% Does (short):
%   - Apply the chosen reference (average OR mastoid; exactly one).
%   - Epoch continuous EEG around task events.
%   - Perform final automatic epoch-level artifact rejection (FASTER-style).
%   - Apply baseline correction.
%   - Enforce subject-level exclusion if too many epochs are rejected.
%   - Save ONE final epoched dataset by default.
%
% Inputs:
%   paths.prep05_out_dir
%     *_until_epoching.set
%
% Outputs (default):
%   paths.prep06_out_dir
%     *_epoched_final.set
%
% Policy:
%   - Reference choice is cfg.prep06.reference_mode (ONLY that one is executed).
%   - Artifact rejection is applied BEFORE baseline correction.
%   - Subject is automatically rejected if rejected-epoch proportion exceeds
%     cfg.prep06.max_reject_prop (default = 0.25).
%
% Notes:
%   - Designed to be fully non-interactive and HPC-safe.
%   - Subject rejection happens AFTER epoch rejection and BEFORE saving final output.
%
% MATLAB R2023a | EEGLAB + FASTER required


step_out = struct('ok', false, 'message', '', 'outputs', {{}});

subj_label = sprintf('sub-%s', subj_id);

try
    c = cfg.prep06;

    overwrite_mode = helpers.resolve_overwrite_mode(cfg, cfg.steps.prep06_epoching.overwrite_mode);

    in_dir  = paths.prep05_out_dir;
    out_dir = paths.prep06_out_dir;
    helpers.ensure_dir(out_dir);

    in_sets = dir(fullfile(in_dir, '*_until_epoching.set'));
    if isempty(in_sets)
        step_out.ok = true;
        step_out.message = sprintf('prep06_epoching: no *_until_epoching.set for %s (skip).', subj_label);
        helpers.logmsg_default('%s', step_out.message);
        return;
    end

    outputs_written = {};

    for fi = 1:numel(in_sets)

        in_name  = in_sets(fi).name;
        run_base = erase(in_name, '_until_epoching.set');

        out_name = run_base + "_epoched_final.set";
        out_path = fullfile(out_dir, char(out_name));

        % Overwrite policy check
        [do_run, reason] = helpers.step_should_run_outputs(out_path, overwrite_mode, cfg);
        helpers.logmsg_default('prep06_epoching: %s | %s | %s', subj_label, run_base, string(reason));

        if ~do_run
            outputs_written{end+1} = out_path; %#ok<AGROW>
            continue;
        end

        if overwrite_mode == "delete" && exist(out_path,'file') == 2 && ~cfg.io.dry_run
            helpers.safe_delete_set(out_path);
        end

        % Load input
        EEG = helpers.safe_loadset(in_dir, in_name, helpers);


        EEG = helpers.append_eeg_comment(EEG, '--- STEP06: epoching + final artifact rejection ---');
        EEG = helpers.append_eeg_comment(EEG, sprintf('input=%s', in_name));

        % Ensure event.type is char (robustness)
        if isfield(EEG,'event') && ~isempty(EEG.event)
            try
                tmp = cellfun(@char, {EEG.event.type}, 'UniformOutput', false);
                [EEG.event.type] = tmp{:};
            catch
            end
        end

        EEG = helpers.append_eeg_comment(EEG, ...
            'Trigger convention (fixed): S 20=CS-, S 24=CS+. ACQ: 202x=CS-, 242x=CS+. No participant-specific mapping used.');

        % Channel type indices
        [idxEEG, idxEOG, idxAUX] = get_indices_by_type(EEG);
        EEG = helpers.append_eeg_comment(EEG, sprintf('channel counts: EEG=%d | EOG=%d | AUX=%d', ...
            numel(idxEEG), numel(idxEOG), numel(idxAUX)));

        % =========================
        % STEP 1: APPLY CHOSEN REFERENCE (ONLY ONE)
        % =========================
        EEGref = EEG;

        if c.reference_mode == "avg"

            if isempty(idxEEG)
                EEGref = helpers.append_eeg_comment(EEGref, 'WARNING: no EEG channels found -> average reref skipped.');
            else
                exclude_idx = setdiff(1:EEGref.nbchan, idxEEG); % exclude EOG + AUX
                EEGref = pop_reref(EEGref, [], 'exclude', exclude_idx);
                EEGref = eeg_checkset(EEGref);
                EEGref = helpers.append_eeg_comment(EEGref, sprintf('reference_mode=avg: average reference applied (EEG-only). excluded=%d', numel(exclude_idx)));
            end

        elseif c.reference_mode == "mastoid"

            chan_m1 = find(strcmpi({EEGref.chanlocs.labels}, 'T9'), 1, 'first');
            chan_m2 = find(strcmpi({EEGref.chanlocs.labels}, 'T10'),1, 'first');

            if isempty(chan_m1) || isempty(chan_m2)
                EEGref = helpers.append_eeg_comment(EEGref, 'reference_mode=mastoid: WARNING T9/T10 not found -> mastoid reref skipped; keeping original ref.');
            else
                exclude_idx = setdiff(1:EEGref.nbchan, idxEEG);
                EEGref = pop_reref(EEGref, [chan_m1 chan_m2], 'exclude', exclude_idx);
                EEGref = eeg_checkset(EEGref);
                EEGref = helpers.append_eeg_comment(EEGref, sprintf('reference_mode=mastoid: mastoid reference applied (T9/T10). excluded=%d', numel(exclude_idx)));
            end

        else
            error('cfg.prep06.reference_mode must be "avg" or "mastoid". Current: %s', char(c.reference_mode));
        end

        if c.save_intermediate_steps && ~c.save_final_only
            fn_ref = fullfile(out_dir, [run_base '_refapplied.set']);
            safe_saveset(EEGref, fn_ref, overwrite_mode, cfg, c.savemode, helpers);
        end

        % =========================
        % STEP 2: EPOCH
        % =========================
        EEGep = pop_epoch(EEGref, c.events_phase, [c.epoch_start_s c.epoch_end_s], ...
            'newname', [run_base '_epoched'], 'epochinfo', 'yes');
        EEGep = eeg_checkset(EEGep);

        try
            EEGep.times = round(linspace(c.epoch_start_s*1000, c.epoch_end_s*1000, size(EEGep.data,2)));
        catch
        end

        if c.save_intermediate_steps && ~c.save_final_only
            fn_ep = fullfile(out_dir, [run_base '_epoched.set']);
            safe_saveset(EEGep, fn_ep, overwrite_mode, cfg, c.savemode, helpers);
        end

        % =========================
        % STEP 3: ARTIFACT REJECTION (FASTER epoch_properties + z>thr)
        % =========================
        EEGrej = EEGep;

        if c.do_artifact_rejection

            if isempty(idxEEG) || EEGrej.trials < 1
                EEGrej = helpers.append_eeg_comment(EEGrej, 'FASTER artifact rejection skipped (no EEG channels or no epochs).');
                helpers.logmsg_default('prep06_epoching: %s | %s | WARN: FASTER skipped (no EEG or no epochs).', subj_label, run_base);
            else
                [EEGrej, rej_info] = faster_reject_epochs(EEGrej, idxEEG, c);

                EEGrej = helpers.append_eeg_comment(EEGrej, sprintf( ...
                    'FASTER epoch rejection: z>%g using epoch_properties()+max|z|; rejected=%d/%d; kept=%d; robust=%d', ...
                    c.faster_z_thresh, rej_info.n_rejected, rej_info.n_total, rej_info.n_kept, rej_info.robust_z));

                helpers.logmsg_default('prep06_epoching: %s | %s | FASTER rejected=%d/%d kept=%d', ...
                    subj_label, run_base, rej_info.n_rejected, rej_info.n_total, rej_info.n_kept);
            end

        else
            EEGrej = helpers.append_eeg_comment(EEGrej, 'artifact rejection disabled by cfg.prep06.do_artifact_rejection=false');
        end

        if c.save_intermediate_steps && ~c.save_final_only
            fn_rej = fullfile(out_dir, [run_base '_badtrialsrejected.set']);
            safe_saveset(EEGrej, fn_rej, overwrite_mode, cfg, c.savemode, helpers);
        end

        % =========================
        % SUBJECT-LEVEL EXCLUSION BASED ON EPOCH LOSS
        % =========================
        if c.do_artifact_rejection && isfield(c, 'max_reject_prop') && ~isempty(c.max_reject_prop)

            prop_rejected = 0;
            if isfield(rej_info,'n_total') && rej_info.n_total > 0
                prop_rejected = rej_info.n_rejected / rej_info.n_total;
            end

            if prop_rejected > c.max_reject_prop
                msg = sprintf(['prep06_epoching: SUBJECT EXCLUDED | rejected %.1f%% of epochs ' ...
                               '(threshold %.1f%%). No final dataset written.'], ...
                               100*prop_rejected, 100*c.max_reject_prop);

                EEGrej = helpers.append_eeg_comment(EEGrej, msg);
                helpers.logmsg_default('prep06_epoching: %s | %s | %s', subj_label, run_base, msg);

                step_out.ok = false;
                step_out.message = msg;
                return;
            end
        end

        % =========================
        % STEP 4: BASELINE CORRECTION
        % =========================
        EEGfinal = pop_rmbase(EEGrej, [c.base_start_ms 0]);
        EEGfinal = eeg_checkset(EEGfinal);
        EEGfinal = helpers.append_eeg_comment(EEGfinal, sprintf('baseline correction applied: [%d 0] ms', c.base_start_ms));

        if c.save_intermediate_steps && ~c.save_final_only
            fn_base = fullfile(out_dir, [run_base '_baselineremoved.set']);
            safe_saveset(EEGfinal, fn_base, overwrite_mode, cfg, c.savemode, helpers);
        end

        % =========================
        % FINAL OUTPUT
        % =========================
        if cfg.io.dry_run
            helpers.logmsg_default('prep06_epoching: DRY RUN would save FINAL: %s', out_path);
        else
            EEGfinal.setname = [run_base '_epoched_final'];
            EEGfinal = helpers.safe_saveset(EEGfinal, out_dir, char(out_name), helpers, cfg);
            helpers.logmsg_default('prep06_epoching: saved FINAL: %s', out_path);
        end

        outputs_written{end+1} = out_path; %#ok<AGROW>
    end

    step_out.ok = true;
    step_out.outputs = outputs_written;
    step_out.message = sprintf('prep06_epoching: OK (%d output file(s)).', numel(outputs_written));

catch me
    step_out.ok = false;
    step_out.message = sprintf('prep06_epoching: %s', me.message);
end
end

%% ========================================================================
%  LOCAL HELPERS (keep inside this file)
% ========================================================================
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

function safe_saveset(EEG, fullpath_set, overwrite_mode, cfg, savemode, helpers)
% obey overwrite policy + cfg.io.dry_run, supports .set+.fdt cleanup via helpers.safe_delete_set

if nargin < 5 || isempty(savemode)
    savemode = 'twofiles';
end

[out_dir, out_file, out_ext] = fileparts(fullpath_set);
if ~exist(out_dir,'dir'); mkdir(out_dir); end
if isempty(out_ext); out_ext = '.set'; end

fullpath_set = fullfile(out_dir, [out_file out_ext]);

if exist(fullpath_set,'file') && overwrite_mode == "skip"
    return;
end

if overwrite_mode == "delete" && exist(fullpath_set,'file') && ~cfg.io.dry_run
    helpers.safe_delete_set(fullpath_set);
end

if cfg.io.dry_run
    return;
end

EEG = pop_saveset(EEG, ...
    'filename', [out_file out_ext], ...
    'filepath', out_dir, ...
    'savemode', savemode);
end

function [EEG_out, info] = faster_reject_epochs(EEG_in, idxEEG, c)
EEG_out = EEG_in;

info = struct();
info.n_total    = EEG_in.trials;
info.n_rejected = 0;
info.n_kept     = EEG_in.trials;
info.robust_z   = isfield(c,'faster_use_robust_z') && c.faster_use_robust_z;

if exist('epoch_properties','file') ~= 2
    % FASTER missing -> do nothing
    return;
end

props = epoch_properties(EEG_in, idxEEG);  % expected: [nEpoch x 3] typically

if isempty(props) || ~isnumeric(props)
    return;
end

% Ensure rows correspond to epochs
if size(props,1) ~= EEG_in.trials && size(props,2) == EEG_in.trials
    props = props.';
end
if size(props,1) ~= EEG_in.trials
    return;
end

% z across epochs per property
if info.robust_z
    med = median(props, 1, 'omitnan');
    madv = median(abs(props - med), 1, 'omitnan');
    denom = 1.4826 .* madv;
    denom(denom == 0 | isnan(denom)) = Inf;
    zmat = (props - med) ./ denom;
else
    mu = mean(props, 1, 'omitnan');
    sd = std(props, 0, 1, 'omitnan');
    sd(sd == 0 | isnan(sd)) = Inf;
    zmat = (props - mu) ./ sd;
end

bad = any(abs(zmat) > c.faster_z_thresh, 2);
bad_epochs = find(bad);

if isempty(bad_epochs)
    return;
end

EEG_out = pop_rejepoch(EEG_in, bad_epochs, 0);
EEG_out = eeg_checkset(EEG_out);

info.n_rejected = numel(bad_epochs);
info.n_kept     = EEG_out.trials;

% Optional warning if extreme
if isfield(c,'faster_warn_if_reject_prop_gt') && ~isempty(c.faster_warn_if_reject_prop_gt)
    prop = info.n_rejected / max(1, info.n_total);
    if prop > c.faster_warn_if_reject_prop_gt
        fprintf('WARNING: FASTER rejected %.1f%% of epochs (>%g%% threshold)\n', 100*prop, 100*c.faster_warn_if_reject_prop_gt);
    end
end
end

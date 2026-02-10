function step_out = aperiodic_eeg_b_prep06_epoching(subj_id, cfg, paths, helpers)
% APERIODIC_EEG_B_PREP06_EPOCHING - Aperiodic Baseline pipeline / Saskia Wilken / FEB 2026
%
% Step 06:
%   - Apply chosen reference (avg OR mastoid; exactly one).
%   - Epoch (regular fixed-length by default; trigger-based optional).
%   - Final automatic epoch-level artifact rejection (FASTER-style: epoch_properties + |z|>thr).
%   - Optional baseline correction.
%   - Subject-level exclusion if rejected-epoch proportion exceeds cfg.prep06.max_reject_prop.
%   - Save ONE final epoched dataset by default: *_epoched_final.set
%
% IMPORTANT: No local helper functions are defined in this file.
%            Everything uses inline logic + helpers passed in.
%
% Inputs:
%   paths.prep05_out_dir : contains *_until_epoching.set
% Outputs:
%   paths.prep06_out_dir : writes *_epoched_final.set (unless subject excluded)

step_out = struct('ok', false, 'message', '', 'outputs', {{}});

subj_label = sprintf('sub-%s', subj_id);

try
    c = cfg.prep06;

    % ---- defaults ---------------------------------------------------------
    if ~isfield(c,'epoching_mode') || isempty(c.epoching_mode)
        c.epoching_mode = "regular";   % "regular" | "trigger"
    end
    if ~isfield(c,'regepoch_length_sec') || isempty(c.regepoch_length_sec)
        c.regepoch_length_sec = 10;
    end
    if ~isfield(c,'regepoch_step_sec') || isempty(c.regepoch_step_sec)
        c.regepoch_step_sec = c.regepoch_length_sec;
    end
    if ~isfield(c,'savemode') || isempty(c.savemode)
        c.savemode = 'twofiles'; %#ok<NASGU>  % retained for compatibility; driver helper uses pop_saveset defaults
    end
    if ~isfield(c,'max_reject_prop') || isempty(c.max_reject_prop)
        c.max_reject_prop = 0.25;  % IMPORTANT: default is NOT 0.0
    end
    if ~isfield(c,'do_artifact_rejection') || isempty(c.do_artifact_rejection)
        c.do_artifact_rejection = true;
    end
    if ~isfield(c,'faster_z_thresh') || isempty(c.faster_z_thresh)
        c.faster_z_thresh = 3;
    end
    if ~isfield(c,'faster_use_robust_z') || isempty(c.faster_use_robust_z)
        c.faster_use_robust_z = false;
    end

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

        out_fname = char(string(run_base) + "_epoched_final.set");
        out_path  = fullfile(out_dir, out_fname);

        % ---- overwrite policy check ---------------------------------------
        [do_run, reason] = helpers.step_should_run_outputs(out_path, overwrite_mode, cfg);
        helpers.logmsg_default('prep06_epoching: %s | %s | %s', subj_label, run_base, string(reason));

        if ~do_run
            outputs_written{end+1} = out_path; %#ok<AGROW>
            continue;
        end

        if overwrite_mode == "delete" && exist(out_path,'file') == 2 && ~cfg.io.dry_run
            helpers.safe_delete_set(out_path);
        end

        % ---- load ----------------------------------------------------------
        EEG = helpers.safe_loadset(in_dir, in_name, helpers);

        EEG = helpers.append_eeg_comment(EEG, '--- STEP06: epoching + final artifact rejection ---');
        EEG = helpers.append_eeg_comment(EEG, sprintf('input=%s', in_name));
        EEG = helpers.append_eeg_comment(EEG, ...
            'Trigger convention (fixed): S 20=CS-, S 24=CS+. ACQ: 202x=CS-, 242x=CS+. No participant-specific mapping used.');

        % ---- ensure event.type is char (robustness) ------------------------
        if isfield(EEG,'event') && ~isempty(EEG.event)
            try
                tmp = cellfun(@char, {EEG.event.type}, 'UniformOutput', false);
                [EEG.event.type] = tmp{:};
            catch
            end
        end

        % ---- channel type indices (inline; no helper functions) ------------
        idxEEG = [];
        idxEOG = [];
        idxAUX = [];

        if isfield(EEG,'chanlocs') && ~isempty(EEG.chanlocs) && isfield(EEG.chanlocs,'type')
            try
                types = lower(string({EEG.chanlocs.type}));
                idxEEG = find(types == "eeg");
                idxEOG = find(types == "eog");
                idxAUX = find(~(types == "eeg" | types == "eog"));
            catch
                idxEEG = 1:EEG.nbchan;
            end
        else
            idxEEG = 1:EEG.nbchan; % fallback
        end

        EEG = helpers.append_eeg_comment(EEG, sprintf('channel counts: EEG=%d | EOG=%d | AUX=%d', ...
            numel(idxEEG), numel(idxEOG), numel(idxAUX)));

        % ===================================================================
        % STEP 1: APPLY CHOSEN REFERENCE (ONLY ONE)
        % ===================================================================
        EEGref = EEG;

        if string(c.reference_mode) == "avg"

            if isempty(idxEEG)
                EEGref = helpers.append_eeg_comment(EEGref, 'WARNING: no EEG channels found -> average reref skipped.');
            else
                exclude_idx = setdiff(1:EEGref.nbchan, idxEEG); % exclude EOG + AUX
                EEGref = pop_reref(EEGref, [], 'exclude', exclude_idx);
                EEGref = eeg_checkset(EEGref);
                EEGref = helpers.append_eeg_comment(EEGref, sprintf( ...
                    'reference_mode=avg: average reference applied (EEG-only). excluded=%d', numel(exclude_idx)));
            end

        elseif string(c.reference_mode) == "mastoid"

            chan_m1 = [];
            chan_m2 = [];
            if isfield(EEGref,'chanlocs') && ~isempty(EEGref.chanlocs)
                chan_m1 = find(strcmpi({EEGref.chanlocs.labels}, 'T9'),  1, 'first');
                chan_m2 = find(strcmpi({EEGref.chanlocs.labels}, 'T10'), 1, 'first');
            end

            if isempty(chan_m1) || isempty(chan_m2)
                EEGref = helpers.append_eeg_comment(EEGref, ...
                    'reference_mode=mastoid: WARNING T9/T10 not found -> mastoid reref skipped; keeping original ref.');
            else
                exclude_idx = setdiff(1:EEGref.nbchan, idxEEG);
                EEGref = pop_reref(EEGref, [chan_m1 chan_m2], 'exclude', exclude_idx);
                EEGref = eeg_checkset(EEGref);
                EEGref = helpers.append_eeg_comment(EEGref, sprintf( ...
                    'reference_mode=mastoid: mastoid reference applied (T9/T10). excluded=%d', numel(exclude_idx)));
            end

        else
            error('cfg.prep06.reference_mode must be "avg" or "mastoid". Current: %s', char(string(c.reference_mode)));
        end

        % ===================================================================
        % STEP 2: EPOCH
        % ===================================================================
        if string(c.epoching_mode) == "regular"

            L = double(c.regepoch_length_sec);
            S = double(c.regepoch_step_sec);
            if S <= 0; S = L; end

            EEGep = eeg_regepochs(EEGref, ...
                'recurrence', S, ...
                'limits', [0 L], ...
                'eventtype', 'regepoch');
            EEGep = eeg_checkset(EEGep);

            % set times in ms (0..L*1000)
            try
                EEGep.times = round(linspace(0, L*1000, size(EEGep.data,2)));
            catch
            end

        else
            % trigger-based epoching
            if ~isfield(c,'events_phase') || isempty(c.events_phase)
                error('epoching_mode="trigger" requires cfg.prep06.events_phase.');
            end
            if ~isfield(c,'epoch_start_s') || ~isfield(c,'epoch_end_s')
                error('epoching_mode="trigger" requires cfg.prep06.epoch_start_s and cfg.prep06.epoch_end_s.');
            end

            EEGep = pop_epoch(EEGref, c.events_phase, [c.epoch_start_s c.epoch_end_s], ...
                'newname', [char(run_base) '_epoched'], 'epochinfo', 'yes');
            EEGep = eeg_checkset(EEGep);

            try
                EEGep.times = round(linspace(c.epoch_start_s*1000, c.epoch_end_s*1000, size(EEGep.data,2)));
            catch
            end
        end

        % ===================================================================
        % STEP 3: ARTIFACT REJECTION (FASTER-style: epoch_properties + z>thr)
        % ===================================================================
        EEGrej = EEGep;

        rej_info = struct();
        rej_info.n_total    = EEGep.trials;
        rej_info.n_rejected = 0;
        rej_info.n_kept     = EEGep.trials;
        rej_info.robust_z   = logical(c.faster_use_robust_z);

        if c.do_artifact_rejection

            if isempty(idxEEG) || EEGrej.trials < 1
                EEGrej = helpers.append_eeg_comment(EEGrej, 'FASTER artifact rejection skipped (no EEG channels or no epochs).');
                helpers.logmsg_default('prep06_epoching: %s | %s | WARN: FASTER skipped (no EEG or no epochs).', subj_label, run_base);

            elseif exist('epoch_properties','file') ~= 2
                EEGrej = helpers.append_eeg_comment(EEGrej, 'FASTER artifact rejection skipped (epoch_properties not found).');
                helpers.logmsg_default('prep06_epoching: %s | %s | WARN: FASTER skipped (epoch_properties missing).', subj_label, run_base);

            else
                props = epoch_properties(EEGrej, idxEEG);

                if ~isempty(props) && isnumeric(props)
                    % Ensure rows correspond to epochs
                    if size(props,1) ~= EEGrej.trials && size(props,2) == EEGrej.trials
                        props = props.';
                    end

                    if size(props,1) == EEGrej.trials

                        if rej_info.robust_z
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

                        bad_mask = any(abs(zmat) > double(c.faster_z_thresh), 2);
                        bad_epochs = find(bad_mask);

                        if ~isempty(bad_epochs)
                            EEGrej = pop_rejepoch(EEGrej, bad_epochs, 0);
                            EEGrej = eeg_checkset(EEGrej);

                            rej_info.n_rejected = numel(bad_epochs);
                            rej_info.n_kept     = EEGrej.trials;
                        end
                    end
                end

                EEGrej = helpers.append_eeg_comment(EEGrej, sprintf( ...
                    'FASTER epoch rejection: z>%g using epoch_properties()+max|z|; rejected=%d/%d; kept=%d; robust=%d', ...
                    c.faster_z_thresh, rej_info.n_rejected, rej_info.n_total, rej_info.n_kept, rej_info.robust_z));

                helpers.logmsg_default('prep06_epoching: %s | %s | FASTER rejected=%d/%d kept=%d', ...
                    subj_label, run_base, rej_info.n_rejected, rej_info.n_total, rej_info.n_kept);
            end

        else
            EEGrej = helpers.append_eeg_comment(EEGrej, 'artifact rejection disabled by cfg.prep06.do_artifact_rejection=false');
        end

        % ===================================================================
        % SUBJECT-LEVEL EXCLUSION BASED ON EPOCH LOSS
        % ===================================================================
        if c.do_artifact_rejection && ~isempty(c.max_reject_prop)

            prop_rejected = 0;
            if rej_info.n_total > 0
                prop_rejected = rej_info.n_rejected / rej_info.n_total;
            end

            if prop_rejected > double(c.max_reject_prop)
                msg = sprintf(['prep06_epoching: SUBJECT EXCLUDED | rejected %.1f%% of epochs ' ...
                               '(threshold %.1f%%). No final dataset written.'], ...
                               100*prop_rejected, 100*double(c.max_reject_prop));

                EEGrej = helpers.append_eeg_comment(EEGrej, msg);
                helpers.logmsg_default('prep06_epoching: %s | %s | %s', subj_label, run_base, msg);

                step_out.ok = false;
                step_out.message = msg;
                return;
            end
        end

        % ===================================================================
        % STEP 4: BASELINE CORRECTION (OPTIONAL)
        % ===================================================================
        EEGfinal = EEGrej;

        if ~isfield(c,'do_baseline_correction') || isempty(c.do_baseline_correction)
            % sensible default: do baseline only for trigger-based epochs
            c.do_baseline_correction = (string(c.epoching_mode) ~= "regular");
        end
        if ~isfield(c,'base_start_ms') || isempty(c.base_start_ms)
            c.base_start_ms = -200;
        end
        if ~isfield(c,'base_end_ms') || isempty(c.base_end_ms)
            c.base_end_ms = 0;
        end

        if c.do_baseline_correction
            EEGfinal = pop_rmbase(EEGfinal, [double(c.base_start_ms) double(c.base_end_ms)]);
            EEGfinal = eeg_checkset(EEGfinal);
            EEGfinal = helpers.append_eeg_comment(EEGfinal, sprintf('baseline correction applied: [%d %d] ms', c.base_start_ms, c.base_end_ms));
        else
            EEGfinal = helpers.append_eeg_comment(EEGfinal, 'baseline correction skipped (cfg.prep06.do_baseline_correction=false)');
        end

        % ===================================================================
        % STEP 5: SAVE FINAL OUTPUT (THIS IS THE CRITICAL PART)
        % ===================================================================
        % Use the driver-provided helper (no local helper function).
        helpers.safe_saveset(EEGfinal, out_dir, out_fname, helpers, cfg);

        if cfg.io.dry_run
            helpers.logmsg_default('prep06_epoching: %s | %s | DRY RUN: would save final: %s', subj_label, run_base, out_path);
        else
            helpers.logmsg_default('prep06_epoching: %s | %s | saved final: %s', subj_label, run_base, out_path);
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

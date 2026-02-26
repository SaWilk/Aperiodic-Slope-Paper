function step_out = proof_eeg_baseline_prep06_epoching(subj_id, cfg, paths, helpers)
% PROOF_EEG_BASELINE_PREP06_EPOCHING - Baseline (Eyes Open/Closed) epoching
%
% Does:
%   - Segment continuous recording into Eyes OPEN vs Eyes CLOSED chunks using triggers:
%       * OPEN starts at t=0 until first trigger starting with '2' (typically S 21)
%       * CLOSED runs from that first '2x' marker until S 99 (end baseline)
%       * After S 99: OPEN again until end
%       * Additionally honors later S 1x / S 2x switches if present
%   - Within each chunk, create as many 10s non-overlapping epochs as fit (eeg_regepochs)
%   - Final epoch rejection (FASTER epoch_properties z-threshold)
%   - Save TWO final datasets per run: open + closed
%
% Inputs:
%   paths.prep05_out_dir: *_until_epoching.set
% Outputs:
%   paths.prep06_out_dir: *_cond-open_epoched_final.set, *_cond-closed_epoched_final.set

step_out = struct('ok', false, 'message', '', 'outputs', {{}});

subj_label = sprintf('sub-%s', subj_id);

try
    if ~isfield(cfg,'prep06') || isempty(cfg.prep06)
        error('cfg.prep06 missing.');
    end
    c = cfg.prep06;

    % ---- defaults ----
    if ~isfield(c,'do_artifact_rejection') || isempty(c.do_artifact_rejection)
        c.do_artifact_rejection = true;
    end
    if ~isfield(c,'faster_z_thresh') || isempty(c.faster_z_thresh)
        c.faster_z_thresh = 3;
    end
    if ~isfield(c,'faster_use_robust_z') || isempty(c.faster_use_robust_z)
        c.faster_use_robust_z = false;
    end
    if ~isfield(c,'max_reject_prop') || isempty(c.max_reject_prop)
        c.max_reject_prop = 0.25;
    end
    if ~isfield(c,'use_faster') || isempty(c.use_faster)
        c.use_faster = true;
    end
    if ~isfield(c,'use_ptp') || isempty(c.use_ptp)
        c.use_ptp = true;
    end
    if ~isfield(c,'ptp_uV_thresh') || isempty(c.ptp_uV_thresh)
        c.ptp_uV_thresh = 600;
    end

        % ---- channel splitting defaults (for nicer EEGLAB scroll) ----
    if ~isfield(c,'split_non_eeg_channels') || isempty(c.split_non_eeg_channels)
        c.split_non_eeg_channels = true;   % save EEG-only + AUX-only datasets
    end
    if ~isfield(c,'save_aux_only_if_present') || isempty(c.save_aux_only_if_present)
        c.save_aux_only_if_present = true; % skip AUX file if no AUX channels exist
    end

    % regepoch settings
    if ~isfield(c,'regepoch_length_sec') || isempty(c.regepoch_length_sec)
        c.regepoch_length_sec = 10;
    end
    if ~isfield(c,'regepoch_step_sec') || isempty(c.regepoch_step_sec)
        c.regepoch_step_sec = c.regepoch_length_sec;
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

                % output paths (two or four files, depending on split flag)
        base_open   = run_base + "_cond-open_epoched_final";
        base_closed = run_base + "_cond-closed_epoched_final";

        if c.split_non_eeg_channels
            out_name_open_eeg   = base_open   + "_EEG.set";
            out_name_open_aux   = base_open   + "_AUX.set";
            out_name_closed_eeg = base_closed + "_EEG.set";
            out_name_closed_aux = base_closed + "_AUX.set";

            out_path_open_eeg   = fullfile(out_dir, char(out_name_open_eeg));
            out_path_open_aux   = fullfile(out_dir, char(out_name_open_aux));
            out_path_closed_eeg = fullfile(out_dir, char(out_name_closed_eeg));
            out_path_closed_aux = fullfile(out_dir, char(out_name_closed_aux));

            out_files = {out_path_open_eeg, out_path_open_aux, out_path_closed_eeg, out_path_closed_aux};
        else
            out_name_open   = base_open   + ".set";
            out_name_closed = base_closed + ".set";

            out_path_open   = fullfile(out_dir, char(out_name_open));
            out_path_closed = fullfile(out_dir, char(out_name_closed));

            out_files = {out_path_open, out_path_closed};
        end

        % overwrite policy check: treat outputs as a group
        [do_run, reason] = helpers.step_should_run_outputs(out_files, overwrite_mode, cfg);
        helpers.logmsg_default('prep06_epoching: %s | %s | %s', subj_label, run_base, string(reason));

        if ~do_run
            for k = 1:numel(out_files)
                outputs_written{end+1} = out_files{k}; %#ok<AGROW>
            end
            continue;
        end

        if overwrite_mode == "delete" && ~cfg.io.dry_run
            for k = 1:numel(out_files)
                if exist(out_files{k}, 'file') == 2
                    helpers.safe_delete_set(out_files{k});
                end
            end
        end

        % ---- load input ----
        EEG = helpers.safe_loadset(in_dir, in_name, helpers);
        EEG = helpers.append_eeg_comment(EEG, '--- STEP06: baseline eyes-open/eyes-closed segmentation + regepochs ---');
        EEG = helpers.append_eeg_comment(EEG, sprintf('input=%s', in_name));

        % ---- normalize event.type to char ----
        if isfield(EEG,'event') && ~isempty(EEG.event)
            try
                tmp = cellfun(@char, {EEG.event.type}, 'UniformOutput', false);
                [EEG.event.type] = tmp{:};
            catch
            end
        end

        % ---- channel indices by type (inline, no helpers) ----
        idxEEG = [];
        idxEOG = [];
        idxAUX = [];
        if isfield(EEG,'chanlocs') && ~isempty(EEG.chanlocs) && isfield(EEG.chanlocs,'type')
            types = lower(string({EEG.chanlocs.type}));
            idxEEG = find(types == "eeg");
            idxEOG = find(types == "eog");
            idxAUX = find(~(types == "eeg" | types == "eog"));
        else
            idxEEG = 1:EEG.nbchan;
        end
        EEG = helpers.append_eeg_comment(EEG, sprintf('channel counts: EEG=%d | EOG=%d | AUX=%d', ...
            numel(idxEEG), numel(idxEOG), numel(idxAUX)));

        % =========================
        % 2) Build OPEN/CLOSED continuous segments
        % =========================
        if ~isfield(EEG,'event') || isempty(EEG.event)
            error('No EEG.event present -> cannot segment open/closed.');
        end
        if ~isfield(EEG,'srate') || isempty(EEG.srate)
            error('EEG.srate missing.');
        end

        % collect events of interest with latencies in seconds
        ev_t = [];
        ev_code = strings(0,1);

        for k = 1:numel(EEG.event)
            t0 = EEG.event(k).type;
            tok = helpers.normalize_trigger_type(t0);

            if strcmpi(tok,'boundary')
                continue;
            end

            if startsWith(tok, "S 1") || startsWith(tok, "S 2") || strcmp(tok, "S 99")
                ev_code(end+1,1) = string(tok); %#ok<AGROW>
                ev_t(end+1,1) = double(EEG.event(k).latency) / double(EEG.srate); %#ok<AGROW>
            end
        end

        % sort by time
        if ~isempty(ev_t)
            [ev_t, ix] = sort(ev_t);
            ev_code = ev_code(ix);
        end

        T_end = double(EEG.pnts) / double(EEG.srate);

        % segmentation state machine:
        % start OPEN at t=0, switch to CLOSED at first "S 2x", switch back OPEN at "S 1x",
        % force switch OPEN at S 99 (end baseline)
        seg_cond = strings(0,1);
        seg_t1   = [];
        seg_t2   = [];

        cur_cond = "open";
        cur_t1 = 0;

        eps_s = 1.0 / double(EEG.srate); % 1 sample

        for iEv = 1:numel(ev_code)
            code = ev_code(iEv);
            tEv  = ev_t(iEv);

            if tEv <= cur_t1 + eps_s
                continue;
            end

            is_open_marker   = startsWith(code, "S 1");   % S 11..S 14
            is_closed_marker = startsWith(code, "S 2");   % S 21..S 24
            is_end_baseline  = (code == "S 99");

            % determine if this event triggers a state change
            new_cond = cur_cond;

            if is_end_baseline
                new_cond = "open";  % after S99 open again
            elseif is_open_marker
                new_cond = "open";
            elseif is_closed_marker
                new_cond = "closed";
            end

            if new_cond ~= cur_cond
                % close current segment at this event time
                seg_cond(end+1,1) = cur_cond; %#ok<AGROW>
                seg_t1(end+1,1)   = cur_t1; %#ok<AGROW>
                seg_t2(end+1,1)   = tEv;    %#ok<AGROW>

                % start new segment at this event time
                cur_cond = new_cond;
                cur_t1 = tEv;
            end
        end

        % close final segment to end of recording
        if cur_t1 < T_end - eps_s
            seg_cond(end+1,1) = cur_cond; %#ok<AGROW>
            seg_t1(end+1,1)   = cur_t1; %#ok<AGROW>
            seg_t2(end+1,1)   = T_end;  %#ok<AGROW>
        end

        if isempty(seg_t1)
            error('Could not derive any open/closed segments.');
        end

        helpers.logmsg_default('prep06_epoching: %s | %s | derived %d segments (open/closed).', ...
            subj_label, run_base, numel(seg_t1));

        % =========================
        % 3) For each segment: select time window, regepoch into 10s chunks
        % =========================
        EEG_open_parts   = {};
        EEG_closed_parts = {};

        L = double(c.regepoch_length_sec);
        S = double(c.regepoch_step_sec);
        if S <= 0; S = L; end

        for sgi = 1:numel(seg_t1)

            t1 = seg_t1(sgi);
            t2 = seg_t2(sgi);

            % require at least one full epoch
            if (t2 - t1) < L
                continue;
            end

            % select continuous chunk
            EEGseg = pop_select(EEG, 'time', [t1, t2 - eps_s]);
            EEGseg = eeg_checkset(EEGseg);

            % regepoch within this chunk
            EEGep = eeg_regepochs(EEGseg, ...
                'recurrence', S, ...
                'limits', [0 L], ...
                'eventtype', 'regepoch');
            EEGep = eeg_checkset(EEGep);

            % tag condition
            EEGep.etc.baseline_condition = char(seg_cond(sgi));
            EEGep = helpers.append_eeg_comment(EEGep, sprintf('baseline_condition=%s | chunk=[%.3f %.3f]s | regepoch L=%.1fs S=%.1fs', ...
                seg_cond(sgi), t1, t2, L, S));

            if seg_cond(sgi) == "open"
                EEG_open_parts{end+1} = EEGep; %#ok<AGROW>
            else
                EEG_closed_parts{end+1} = EEGep; %#ok<AGROW>
            end
        end

        % merge parts per condition (if any)
        EEG_open = [];
        if ~isempty(EEG_open_parts)
            EEG_open = EEG_open_parts{1};
            for ii = 2:numel(EEG_open_parts)
                EEG_open = pop_mergeset(EEG_open, EEG_open_parts{ii}, 0);
                EEG_open = eeg_checkset(EEG_open);
            end
        end

        EEG_closed = [];
        if ~isempty(EEG_closed_parts)
            EEG_closed = EEG_closed_parts{1};
            for ii = 2:numel(EEG_closed_parts)
                EEG_closed = pop_mergeset(EEG_closed, EEG_closed_parts{ii}, 0);
                EEG_closed = eeg_checkset(EEG_closed);
            end
        end

        % =========================
        % 4) Final epoch rejection (OPEN/CLOSED)
        % =========================
        if isfield(c,'do_artifact_rejection') && c.do_artifact_rejection ...
                && isfield(cfg,'prep06') && isfield(cfg.prep06,'shared_epoch_rejection')

            reject_cfg = cfg.prep06.shared_epoch_rejection;

            if ~isempty(EEG_open) && EEG_open.trials > 0
                [EEG_open, info_open] = helpers.apply_shared_epoch_rejection(EEG_open, reject_cfg);
                helpers.logmsg_default('prep06_epoching: OPEN rejection: %d/%d epochs removed', ...
                    info_open.n_rejected, info_open.n_before);
            end

            if ~isempty(EEG_closed) && EEG_closed.trials > 0
                [EEG_closed, info_closed] = helpers.apply_shared_epoch_rejection(EEG_closed, reject_cfg);
                helpers.logmsg_default('prep06_epoching: CLOSED rejection: %d/%d epochs removed', ...
                    info_closed.n_rejected, info_closed.n_before);
            end
        end

        % =========================
        % 5) Save outputs
        % =========================
        wrote_any = false;

        if c.split_non_eeg_channels

            % ---------- OPEN ----------
            if ~isempty(EEG_open) && EEG_open.trials > 0
                [idx_eeg_keep, idx_aux_keep] = split_channel_indices(EEG_open);

                EEG_open_eeg = pop_select(EEG_open, 'channel', idx_eeg_keep);
                EEG_open_eeg = eeg_checkset(EEG_open_eeg);
                EEG_open_eeg.setname = char(base_open + "_EEG");
                EEG_open_eeg = helpers.append_eeg_comment(EEG_open_eeg, 'FINAL OUTPUT: eyes OPEN (EEG-only channels)');

                if ~cfg.io.dry_run
                    EEG_open_eeg = helpers.safe_saveset(EEG_open_eeg, out_dir, char(out_name_open_eeg), helpers, cfg);
                end
                helpers.logmsg_default('prep06_epoching: saved OPEN EEG-only: %s', out_path_open_eeg);
                outputs_written{end+1} = out_path_open_eeg; %#ok<AGROW>
                wrote_any = true;

if (~c.save_aux_only_if_present) || (numel(idx_aux_keep) > 0)                    
    EEG_open_aux = pop_select(EEG_open, 'channel', idx_aux_keep);
                    EEG_open_aux = eeg_checkset(EEG_open_aux);
                    EEG_open_aux.setname = char(base_open + "_AUX");
                    EEG_open_aux = helpers.append_eeg_comment(EEG_open_aux, 'FINAL OUTPUT: eyes OPEN (AUX-only channels)');

                    if ~cfg.io.dry_run
                        EEG_open_aux = helpers.safe_saveset(EEG_open_aux, out_dir, char(out_name_open_aux), helpers, cfg);
                    end
                    helpers.logmsg_default('prep06_epoching: saved OPEN AUX-only: %s', out_path_open_aux);
                    outputs_written{end+1} = out_path_open_aux; %#ok<AGROW>
                end
            end

            % ---------- CLOSED ----------
            if ~isempty(EEG_closed) && EEG_closed.trials > 0
                [idx_eeg_keep, idx_aux_keep] = split_channel_indices(EEG_closed);

                EEG_closed_eeg = pop_select(EEG_closed, 'channel', idx_eeg_keep);
                EEG_closed_eeg = eeg_checkset(EEG_closed_eeg);
                EEG_closed_eeg.setname = char(base_closed + "_EEG");
                EEG_closed_eeg = helpers.append_eeg_comment(EEG_closed_eeg, 'FINAL OUTPUT: eyes CLOSED (EEG-only channels)');

                if ~cfg.io.dry_run
                    EEG_closed_eeg = helpers.safe_saveset(EEG_closed_eeg, out_dir, char(out_name_closed_eeg), helpers, cfg);
                end
                helpers.logmsg_default('prep06_epoching: saved CLOSED EEG-only: %s', out_path_closed_eeg);
                outputs_written{end+1} = out_path_closed_eeg; %#ok<AGROW>
                wrote_any = true;

                if ~isempty(idx_aux_keep) && (~c.save_aux_only_if_present || numel(idx_aux_keep) > 0)
                    EEG_closed_aux = pop_select(EEG_closed, 'channel', idx_aux_keep);
                    EEG_closed_aux = eeg_checkset(EEG_closed_aux);
                    EEG_closed_aux.setname = char(base_closed + "_AUX");
                    EEG_closed_aux = helpers.append_eeg_comment(EEG_closed_aux, 'FINAL OUTPUT: eyes CLOSED (AUX-only channels)');

                    if ~cfg.io.dry_run
                        EEG_closed_aux = helpers.safe_saveset(EEG_closed_aux, out_dir, char(out_name_closed_aux), helpers, cfg);
                    end
                    helpers.logmsg_default('prep06_epoching: saved CLOSED AUX-only: %s', out_path_closed_aux);
                    outputs_written{end+1} = out_path_closed_aux; %#ok<AGROW>
                end
            end

        else
            % ------- old behavior: save full channel sets only -------
            if ~isempty(EEG_open) && EEG_open.trials > 0
                EEG_open.setname = char(base_open);
                EEG_open = helpers.append_eeg_comment(EEG_open, 'FINAL OUTPUT: eyes OPEN regepochs');
                if ~cfg.io.dry_run
                    EEG_open = helpers.safe_saveset(EEG_open, out_dir, char(out_name_open), helpers, cfg);
                end
                helpers.logmsg_default('prep06_epoching: saved OPEN: %s', out_path_open);
                outputs_written{end+1} = out_path_open; %#ok<AGROW>
                wrote_any = true;
            end

            if ~isempty(EEG_closed) && EEG_closed.trials > 0
                EEG_closed.setname = char(base_closed);
                EEG_closed = helpers.append_eeg_comment(EEG_closed, 'FINAL OUTPUT: eyes CLOSED regepochs');
                if ~cfg.io.dry_run
                    EEG_closed = helpers.safe_saveset(EEG_closed, out_dir, char(out_name_closed), helpers, cfg);
                end
                helpers.logmsg_default('prep06_epoching: saved CLOSED: %s', out_path_closed);
                outputs_written{end+1} = out_path_closed; %#ok<AGROW>
                wrote_any = true;
            end
        end

        if ~wrote_any
            helpers.logmsg_default('prep06_epoching: %s | %s | WARNING: no output written (no full 10s epochs or excluded).', ...
                subj_label, run_base);
        end

    end % in_sets loop

    step_out.ok = true;
    step_out.outputs = outputs_written;
    step_out.message = sprintf('prep06_epoching: OK (%d output path(s) recorded).', numel(outputs_written));

catch me
    step_out.ok = false;
    step_out.message = sprintf('prep06_epoching: %s', me.message);
end

        % helper inline to get indices (robust if type missing)
        function [idx_keep_eeg, idx_keep_aux] = split_channel_indices(EEGtmp)
            if isfield(EEGtmp,'chanlocs') && ~isempty(EEGtmp.chanlocs) && isfield(EEGtmp.chanlocs,'type')
                types = lower(string({EEGtmp.chanlocs.type}));
                idx_keep_eeg = find(types == "eeg");
                if isempty(idx_keep_eeg)
                    idx_keep_eeg = (1:EEGtmp.nbchan)'; % fallback if typing missing
                else
                    idx_keep_eeg = idx_keep_eeg(:);
                end
                idx_keep_aux = setdiff((1:EEGtmp.nbchan)', idx_keep_eeg); % includes EOG + all non-EEG
            else
                idx_keep_eeg = (1:EEGtmp.nbchan)';
                idx_keep_aux = [];
            end
        end
end

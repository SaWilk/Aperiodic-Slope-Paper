function step_out = proof_eeg_baseline_prep05_after_ica(subj_id, cfg, paths, helpers)
% PROOF_EEG_CF_PREP05_AFTER_ICA - PROOF - Classical Paradigm / Saskia Wilken / JAN 2026
%
% Step 05 of the PROOF Classical-Conditioning EEG preprocessing pipeline.
%
% Does (short):
%   - Load *_ica_applied.set files from Step 04.
%   - Run automatic ICA component classification using ICLabel.
%   - Mark components for rejection based on configurable ICLabel thresholds.
%   - Identify "edge" components close to rejection thresholds (kept, but flagged).
%   - Remove selected ICs WITHOUT user interaction (batch-safe).
%   - Save *_until_epoching.set for subsequent epoching.
%   - Write QA PNGs for rejected and edge ICs (optional).
%
% Inputs:
%   paths.prep04_out_dir
%     *_ica_applied.set
%
% Outputs:
%   paths.prep05_out_dir
%     *_until_epoching.set
%
% QA outputs (optional, PNG):
%   paths.checks_ica_comps_rej_dir   - rejected IC topographies
%   paths.checks_ica_comps_edge_dir - edge (non-rejected) IC topographies
%
% MATLAB R2023a | EEGLAB + ICLabel required


step_out = struct('ok', false, 'message', '', 'outputs', {{}});

subj_label = sprintf('sub-%s', subj_id);

try
    overwrite_mode = helpers.resolve_overwrite_mode(cfg, cfg.steps.prep05_after_ica.overwrite_mode);

    in_dir  = paths.prep04_out_dir;
    out_dir = paths.prep05_out_dir;

    helpers.ensure_dir(out_dir);

    % ----- QA dirs -----
    checks_subj_dir = paths.checks_ica_comps_subj_dir;
    checks_rej_dir  = paths.checks_ica_comps_rej_dir;
    checks_edge_dir = paths.checks_ica_comps_edge_dir;

    if isfield(cfg,'prep05') && isfield(cfg.prep05,'clear_subject_ica_comps_dir') && cfg.prep05.clear_subject_ica_comps_dir
        if exist(checks_subj_dir,'dir')
            try
                rmdir(checks_subj_dir,'s');
            catch me
                helpers.logmsg_default('prep05_after_ica: %s could not clear QA dir: %s', subj_label, me.message);
            end
        end
    end

    helpers.ensure_dir(checks_subj_dir);
    helpers.ensure_dir(checks_rej_dir);
    helpers.ensure_dir(checks_edge_dir);

    in_sets = dir(fullfile(in_dir, '*_ica_applied.set'));
    if isempty(in_sets)
        step_out.ok = true;
        step_out.message = sprintf('prep05_after_ica: no *_ica_applied.set found for %s (skip).', subj_label);
        helpers.logmsg_default('%s', step_out.message);
        return;
    end

    outputs_written = {};

    % thresholds
    c = cfg.prep05;

    for fi = 1:numel(in_sets)

        in_name  = in_sets(fi).name;
        run_base = erase(in_name, '_ica_applied.set');

        out_name = run_base + "_until_epoching.set";
        out_path = fullfile(out_dir, char(out_name));

        [do_run, reason] = helpers.step_should_run_outputs(out_path, overwrite_mode, cfg);
        helpers.logmsg_default('prep05_after_ica: %s | %s | %s', subj_label, run_base, string(reason));

        if ~do_run
            outputs_written{end+1} = out_path; %#ok<AGROW>
            continue;
        end

        if overwrite_mode == "delete" && exist(out_path,'file') == 2 && ~cfg.io.dry_run
            helpers.safe_delete_set(out_path);
        end

        EEG = helpers.safe_loadset(in_dir, in_name, helpers);
        EEG = helpers.append_eeg_comment(EEG, 'prep05_after_ica: ICLabel IC rejection until epoching');
        EEG = helpers.append_eeg_comment(EEG, sprintf('prep05_after_ica: input=%s', in_name));
        EEG = helpers.append_eeg_comment(EEG, sprintf(['prep05_after_ica: thr eye>%.2f muscle>%.2f heart>%.2f line>%.2f chnoise>%.2f other>%.2f brain_min>=%.2f'], ...
            c.iclabel_eye_remove_thr, c.iclabel_muscle_remove_thr, c.iclabel_heart_remove_thr, ...
            c.iclabel_linenoise_remove_thr, c.iclabel_channoise_remove_thr, ...
            c.iclabel_other_remove_thr, c.iclabel_brain_min_keep_thr));

        % Require ICA
        nIC = 0;
        if isfield(EEG,'icawinv') && ~isempty(EEG.icawinv)
            nIC = size(EEG.icawinv, 2);
        end
        if nIC < 2
            helpers.logmsg_default('prep05_after_ica: %s | %s SKIP: insufficient ICA components (nIC=%d).', subj_label, run_base, nIC);
            EEG = helpers.append_eeg_comment(EEG, sprintf('prep05_after_ica: SKIP insufficient ICA components (nIC=%d)', nIC));
            continue;
        end

        % ICLabel
        if exist('iclabel','file') ~= 2
            error('ICLabel not available on path (iclabel.m not found).');
        end
        EEG = iclabel(EEG);

        classif = EEG.etc.ic_classification.ICLabel.classifications;
        p_brain  = classif(:,1);
        p_muscle = classif(:,2);
        p_eye    = classif(:,3);
        p_heart  = classif(:,4);
        p_line   = classif(:,5);
        p_ch     = classif(:,6);
        p_other  = classif(:,7);

        eyes     = find(p_eye    > c.iclabel_eye_remove_thr);
        muscle   = find(p_muscle > c.iclabel_muscle_remove_thr);
        heart    = find(p_heart  > c.iclabel_heart_remove_thr);
        lineN    = find(p_line   > c.iclabel_linenoise_remove_thr);
        chanN    = find(p_ch     > c.iclabel_channoise_remove_thr);

        other95  = find(p_other  > c.iclabel_other_remove_thr);
        lowBrain = find(p_brain  < c.iclabel_brain_min_keep_thr);

        ic2rem = unique([eyes; muscle; heart; lineN; chanN; other95; lowBrain]);

        % edge
        m = c.iclabel_edge_margin;
        edge_eye    = find(p_eye    <= c.iclabel_eye_remove_thr       & p_eye    > (c.iclabel_eye_remove_thr       - m));
        edge_muscle = find(p_muscle <= c.iclabel_muscle_remove_thr    & p_muscle > (c.iclabel_muscle_remove_thr    - m));
        edge_heart  = find(p_heart  <= c.iclabel_heart_remove_thr     & p_heart  > (c.iclabel_heart_remove_thr     - m));
        edge_line   = find(p_line   <= c.iclabel_linenoise_remove_thr & p_line   > (c.iclabel_linenoise_remove_thr - m));
        edge_chan   = find(p_ch     <= c.iclabel_channoise_remove_thr & p_ch     > (c.iclabel_channoise_remove_thr - m));

        brain_edge_lo = c.iclabel_brain_min_keep_thr;
        brain_edge_hi = c.iclabel_brain_min_keep_thr + m;
        edge_brain = find(p_brain >= brain_edge_lo & p_brain < brain_edge_hi);

        ic_edge_raw = unique([edge_eye; edge_muscle; edge_heart; edge_line; edge_chan; edge_brain]);
        ic_edge = setdiff(ic_edge_raw, ic2rem);

        EEG.etc.ic_rejection = struct();
        EEG.etc.ic_rejection.mode = "iclabel_thresholds_extended";
        EEG.etc.ic_rejection.ic2rem = ic2rem(:)';
        EEG.etc.ic_rejection.edge_ic = ic_edge(:)';
        EEG.etc.ic_rejection.timestamp = datestr(now,'yyyy-mm-dd HH:MM:SS');

        EEG = helpers.append_eeg_comment(EEG, sprintf('prep05_after_ica: nIC=%d | remove=%d | edge(not removed)=%d', nIC, numel(ic2rem), numel(ic_edge)));

        % --- QA PNGs (only rejected + edge) ---
        if c.save_ic_topos_png && (~isempty(ic2rem) || ~isempty(ic_edge))
            if exist('topoplot','file') ~= 2
                helpers.logmsg_default('prep05_after_ica: %s | topoplot not available -> skipping PNG QA.', subj_label);
            else
                if isfield(EEG,'icachansind') && ~isempty(EEG.icachansind)
                    chanlocs_ica = EEG.chanlocs(EEG.icachansind);
                else
                    chanlocs_ica = EEG.chanlocs(1:size(EEG.icawinv,1));
                end

                write_ic_pngs(run_base, subj_id, ic2rem(:)', "rej",  checks_rej_dir,  chanlocs_ica);
                write_ic_pngs(run_base, subj_id, ic_edge(:)', "edge", checks_edge_dir, chanlocs_ica);
            end
        end

        % --- Remove ICs (no popups) ---
        if ~isempty(ic2rem)
            if exist('pop_subcomp','file') == 2
                % remove ic activations and recompute to avoid potential
                % cached ic activations to be used
                if isfield(EEG,'icaact'); EEG.icaact = []; end
                EEG = eeg_checkset(EEG, 'ica');
                % check if number of ica chans matches the number of ica
                % weights
                helpers.logmsg_default('ICA dims: nbchan=%d, icachansind=%d, icaweights=%s, icawinv=%s', ...
                EEG.nbchan, numel(EEG.icachansind), mat2str(size(EEG.icaweights)), mat2str(size(EEG.icawinv)));

                x = double(EEG.data);
                bad_nonfinite = find(any(~isfinite(x),2));
                bad_flat      = find(std(x,0,2) < 1e-6);   % adjust if your units are volts
                bad_range     = find((max(x,[],2)-min(x,[],2)) < 1e-5);

                disp('nonfinite channels:'); disp({EEG.chanlocs(bad_nonfinite).labels});
                disp('near-flat channels:'); disp({EEG.chanlocs(unique([bad_flat; bad_range])).labels});

                EEG = pop_subcomp(EEG, ic2rem, 0); % 0 = no confirm
            else
                EEG.reject.gcompreject = false(1, nIC);
                EEG.reject.gcompreject(ic2rem) = true;
                EEG = pop_rejcomp(EEG, ic2rem, 0);
            end
            EEG = eeg_checkset(EEG);
            EEG = helpers.append_eeg_comment(EEG, sprintf('prep05_after_ica: removed ICs: %s', mat2str(ic2rem(:)')));
        else
            EEG = helpers.append_eeg_comment(EEG, 'prep05_after_ica: no ICs removed.');
        end

        EEG.setname = char(run_base + "_until_epoching");

        if cfg.io.dry_run
            helpers.logmsg_default('prep05_after_ica: DRY RUN would save: %s', out_path);
        else
            EEG = helpers.safe_saveset(EEG, out_dir, char(out_name), helpers, cfg);
            helpers.logmsg_default('prep05_after_ica: saved: %s', out_path);
        end

        outputs_written{end+1} = out_path; %#ok<AGROW>
    end

    if isempty(outputs_written)
        step_out.ok = false;
        step_out.message = sprintf('prep05_after_ica: no outputs for %s.', subj_label);
        return;
    end

    step_out.ok = true;
    step_out.message = sprintf('prep05_after_ica: OK (%d output file(s)).', numel(outputs_written));
    step_out.outputs = outputs_written;

catch me
    step_out.ok = false;
    step_out.message = sprintf('prep05_after_ica: %s', me.message);
end


    function write_ic_pngs(run_base_local, subj_id_local, ic_list, tag, out_png_dir, chanlocs_ica_local)
        if isempty(ic_list); return; end

        for ii = 1:numel(ic_list)
            ic = ic_list(ii);

            fig = figure('Visible','off');
            set(fig,'Color','w');
            ax = axes(fig); %#ok<LAXES>
            axis(ax,'off');

            try
                topoplot(EEG.icawinv(:,ic), chanlocs_ica_local, 'electrodes', c.ic_topo_electrodes);

                ttl = sprintf('%s | IC %d (B %.2f M %.2f E %.2f H %.2f L %.2f C %.2f O %.2f) -> %s', ...
                    run_base_local, ic, p_brain(ic), p_muscle(ic), p_eye(ic), p_heart(ic), p_line(ic), p_ch(ic), p_other(ic), upper(tag));
                title(ttl, 'Interpreter','none', 'FontSize', 13);

            catch me_plot
                clf(fig); axis off;
                text(0, 0.5, sprintf('%s | IC %d\nCould not plot:\n%s', run_base_local, ic, me_plot.message), 'Interpreter','none');
            end

            png_name = sprintf('%s_%s_IC%03d_%s.png', subj_id_local, run_base_local, ic, tag);
            png_path = fullfile(out_png_dir, png_name);

            set(fig,'PaperUnits','centimeters','PaperPosition',c.ic_topo_fig_cm);
            print(fig, '-dpng', sprintf('-r%d', c.ic_topo_dpi), png_path);
            close(fig);
        end
    end

end

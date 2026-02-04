function step_out = proof_eeg_cf_prep04_ica(subj_id, cfg, paths, helpers)
% PROOF_EEG_CF_PREP04_ICA
% Run ICA on *_forica.set and transfer weights to *_preica.set.

step_out = struct('ok', false, 'message', '', 'outputs', {{}});

subj_label = sprintf('sub-%s', subj_id);

try
    overwrite_mode = helpers.resolve_overwrite_mode(cfg, cfg.steps.prep04_ica.overwrite_mode);

    in_dir_forica = paths.prep03_out_dir_forica;
    in_dir_preica = paths.prep03_out_dir_untilica;
    out_dir_after = paths.prep04_out_dir;

    helpers.ensure_dir(out_dir_after);

    forica_sets = dir(fullfile(in_dir_forica, '*_forica.set'));
    if isempty(forica_sets)
        step_out.ok = true;
        step_out.message = sprintf('prep04_ica: no *_forica.set found for %s (skip).', subj_label);
        helpers.logmsg_default('%s', step_out.message);
        return;
    end

    outputs_written = {};

    ica_method = string(cfg.prep04.ica_method);

    % ----- AMICA guards -----
    if ica_method == "amica"
        if ispc && isfield(cfg.prep04,'amica_require_no_spaces_on_windows') && cfg.prep04.amica_require_no_spaces_on_windows
            eeglab_root = string(helpers.getenv_or_empty("EEGLAB_ROOT"));
            amica_path = which('runamica15');
            if isempty(amica_path)
                error('AMICA requested, but runamica15 not found on path (AMICA plugin missing?).');
            end
            if contains(amica_path, ' ')
                error('AMICA requested, but runamica15 path contains spaces (Windows AMICA may fail): %s', amica_path);
            end
            if strlength(eeglab_root) > 0 && contains(eeglab_root, ' ')
                error('AMICA requested, but EEGLAB_ROOT contains spaces (Windows AMICA may fail): %s', eeglab_root);
            end
        end
    end

    for fi = 1:numel(forica_sets)

        forica_name = forica_sets(fi).name;
        run_base    = erase(forica_name, '_forica.set');

        preica_name = run_base + "_preica.set";
        preica_path = fullfile(in_dir_preica, char(preica_name));

        if exist(preica_path, 'file') ~= 2
            helpers.logmsg_default('prep04_ica: %s | %s missing preica: %s (skip run).', subj_label, run_base, preica_path);
            continue;
        end

        out_name = run_base + "_ica_applied.set";
        out_path = fullfile(out_dir_after, char(out_name));

        [do_run, reason] = helpers.step_should_run_outputs(out_path, overwrite_mode, cfg);
        helpers.logmsg_default('prep04_ica: %s | %s | %s', subj_label, run_base, string(reason));

        if ~do_run
            outputs_written{end+1} = out_path; %#ok<AGROW>
            continue;
        end

        if overwrite_mode == "delete" && exist(out_path,'file') == 2 && ~cfg.io.dry_run
            helpers.safe_delete_set(out_path);
        end

        % ----- Load -----
        ica_prep_eeg = helpers.safe_loadset(in_dir_forica, forica_name, helpers);
        preica_eeg   = helpers.safe_loadset(in_dir_preica,  char(preica_name), helpers);
        
        ica_prep_eeg = helpers.append_eeg_comment(ica_prep_eeg, 'prep04_ica: start ICA on _forica dataset');
        ica_prep_eeg = helpers.append_eeg_comment(ica_prep_eeg, sprintf('prep04_ica: loaded forica=%s', forica_name));

        preica_eeg   = helpers.append_eeg_comment(preica_eeg, 'prep04_ica: will apply ICA weights to _preica dataset');
        preica_eeg   = helpers.append_eeg_comment(preica_eeg, sprintf('prep04_ica: loaded preica=%s', char(preica_name)));

        % ----- prereg rank logic -----
        interpolated_count = 0;
        if isfield(preica_eeg,'etc') && isfield(preica_eeg.etc,'interpolated_channel_indices') && ~isempty(preica_eeg.etc.interpolated_channel_indices)
            interpolated_count = numel(preica_eeg.etc.interpolated_channel_indices);
        elseif isfield(preica_eeg,'chaninfo') && isfield(preica_eeg.chaninfo,'bad') && ~isempty(preica_eeg.chaninfo.bad)
            interpolated_count = numel(preica_eeg.chaninfo.bad);
        end

        use_pca  = false;
        pca_rank = [];

        if isfield(cfg.prep04,'use_pca_rank_if_interpolated') && cfg.prep04.use_pca_rank_if_interpolated && interpolated_count > 0
            use_pca  = true;
            pca_rank = max(ica_prep_eeg.nbchan - interpolated_count, 1);
            ica_prep_eeg = helpers.append_eeg_comment(ica_prep_eeg, ...
                sprintf('prep04_ica: prereg rank reduction: interpolated_count=%d => pca_rank=%d', interpolated_count, pca_rank));
        else
            ica_prep_eeg = helpers.append_eeg_comment(ica_prep_eeg, 'prep04_ica: no PCA rank reduction applied');
        end

        % ----- Run ICA -----
        ica_rank_used = ica_prep_eeg.nbchan;

        switch ica_method

            case "amica"
                x = double(reshape(ica_prep_eeg.data, ica_prep_eeg.nbchan, ica_prep_eeg.pnts * ica_prep_eeg.trials));

                if use_pca
                    pcakeep = pca_rank;
                else
                    pcakeep = min(rank(x'), size(x,1));
                end

                [ica_prep_eeg.icaweights, ica_prep_eeg.icasphere, ~] = runamica15(x, 'pcakeep', pcakeep);
                ica_prep_eeg.icawinv = pinv(ica_prep_eeg.icaweights * ica_prep_eeg.icasphere);

                % IMPORTANT: make explicit
                ica_prep_eeg.icachansind = 1:ica_prep_eeg.nbchan;

                ica_rank_used = pcakeep;
                ica_prep_eeg = eeg_checkset(ica_prep_eeg);
                ica_prep_eeg = helpers.append_eeg_comment(ica_prep_eeg, sprintf('prep04_ica: AMICA done. rank_used=%d', ica_rank_used));

            otherwise
                interrupt_ica = 'off';
                if isfield(cfg.prep04,'interrupt_ica'); interrupt_ica = cfg.prep04.interrupt_ica; end

                if use_pca
                    ica_prep_eeg = pop_runica(ica_prep_eeg, 'pca', pca_rank, 'interrupt', interrupt_ica);
                    ica_rank_used = pca_rank;
                else
                    use_extended = true;
                    if isfield(cfg.prep04,'use_extended_infomax'); use_extended = cfg.prep04.use_extended_infomax; end

                    if use_extended
                        ica_prep_eeg = pop_runica(ica_prep_eeg, 'extended', 1, 'interrupt', interrupt_ica);
                    else
                        ica_prep_eeg = pop_runica(ica_prep_eeg, 'interrupt', interrupt_ica);
                    end
                    ica_rank_used = ica_prep_eeg.nbchan;
                end

                ica_prep_eeg = eeg_checkset(ica_prep_eeg);
                ica_prep_eeg = helpers.append_eeg_comment(ica_prep_eeg, sprintf('prep04_ica: runica done. rank_used=%d', ica_rank_used));
        end

        % ----- Transfer to PREICA -----
        preica_eeg.icawinv     = ica_prep_eeg.icawinv;
        preica_eeg.icasphere   = ica_prep_eeg.icasphere;
        preica_eeg.icaweights  = ica_prep_eeg.icaweights;
        preica_eeg.icachansind = ica_prep_eeg.icachansind;

        preica_eeg = eeg_checkset(preica_eeg);
        preica_eeg = helpers.append_eeg_comment(preica_eeg, sprintf('prep04_ica: ICA weights transferred from %s', forica_name));
        preica_eeg = helpers.append_eeg_comment(preica_eeg, sprintf('prep04_ica: ica_method=%s | interpolated_count=%d | rank_used=%d', ...
            ica_method, interpolated_count, ica_rank_used));

        % ----- Save -----
        if cfg.io.dry_run
            helpers.logmsg_default('prep04_ica: DRY RUN would save: %s', out_path);
        else
            preica_eeg = helpers.safe_saveset(preica_eeg, out_dir_after, char(out_name), helpers, cfg);
            helpers.logmsg_default('prep04_ica: saved: %s', out_path);
        end

        outputs_written{end+1} = out_path; %#ok<AGROW>
    end

    if isempty(outputs_written)
        step_out.ok = false;
        step_out.message = sprintf('prep04_ica: no runs processed successfully for %s (no matching preica?).', subj_label);
        return;
    end

    step_out.ok = true;
    step_out.message = sprintf('prep04_ica: OK (%d output file(s)).', numel(outputs_written));
    step_out.outputs = outputs_written;

catch me
    step_out.ok = false;
    step_out.message = sprintf('prep04_ica: %s', me.message);
end
end

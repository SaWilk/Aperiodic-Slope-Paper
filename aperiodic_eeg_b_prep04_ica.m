function step_out = proof_eeg_baseline_prep04_ica(subj_id, cfg, paths, helpers)
% PROOF_EEG_CF_PREP04_ICA - PROOF - Classical Paradigm / Saskia Wilken / JAN 2026
% Run ICA on *_forica.set and transfer weights to *_preica.set.
%
% HOW TO USE
%   Called by run_eeg_pipeline() as Step 04.
%
% DESCRIPTION (short)
%   Loads the ICA-training dataset (*_forica.set) from Step 03, computes ICA
%   (RUNICA extended infomax or AMICA), and transfers ICA weights to the
%   continuous pipeline dataset (*_preica.set). Saves one output per run:
%       *_ica_applied.set
%
% INPUT
%   - paths.prep03_out_dir_forica:    *_forica.set (ICA training only)
%   - paths.prep03_out_dir_untilica:  *_preica.set (pipeline-continuous)
%
% OUTPUT
%   - paths.prep04_out_dir:           *_ica_applied.set
%
% OVERWRITE
%   Uses global cfg.io.overwrite_mode ("delete"|"skip"),
%   optionally overridden by cfg.steps.prep04_ica.overwrite_mode.

%% ========================================================================
%  OUTPUT INIT
% ========================================================================
step_out = struct('ok', false, 'message', '', 'outputs', {{}});

subj_label = sprintf('sub-%s', subj_id);

%% ========================================================================
%  DEFAULTS (Step 04 local config)
% ========================================================================
step_cfg = struct();

% ICA method: "runica" | "amica"
step_cfg.ica_method = "runica";

% runica options
step_cfg.use_extended_infomax = true;    % pop_runica('extended',1)
step_cfg.interrupt_ica        = 'off';   % 'off' recommended for batch/HPC

% rank logic: if interpolated channels exist, reduce PCA rank
step_cfg.use_pca_rank_if_interpolated = true;

% AMICA guard on Windows: fail fast if path contains spaces (AMICA can break)
step_cfg.amica_require_no_spaces_on_windows = true;

% AMICA temp handling
step_cfg.amica_tmp_root          = "";      % "" => use system tempdir
step_cfg.amica_delete_tmp        = true;    % delete tmp dir after successful AMICA
step_cfg.amica_keep_tmp_on_error = true;    % keep tmp dir if AMICA fails (debugging)

% per-step overwrite override ("" => use global)
step_cfg.overwrite_mode = "";

%% ========================================================================
%  MERGE OVERRIDES (mother cfg.prep04 + cfg.steps.prep04_ica)
% ========================================================================

% merge from mother cfg.prep04 (highest priority for ICA settings)
if isfield(cfg, 'prep04') && isstruct(cfg.prep04)
    f = fieldnames(cfg.prep04);
    for k = 1:numel(f)
        step_cfg.(f{k}) = cfg.prep04.(f{k});
    end
end

% merge overwrite override from cfg.steps.prep04_ica
if isfield(cfg,'steps') && isfield(cfg.steps,'prep04_ica') && isstruct(cfg.steps.prep04_ica)
    s = cfg.steps.prep04_ica;
    if isfield(s,'overwrite_mode') && strlength(string(s.overwrite_mode)) > 0
        step_cfg.overwrite_mode = string(s.overwrite_mode);
    end
end

overwrite_mode = helpers.resolve_overwrite_mode(cfg, step_cfg.overwrite_mode);

%% ========================================================================
%  PATHS
% ========================================================================
in_dir_forica = paths.prep03_out_dir_forica;
in_dir_preica = paths.prep03_out_dir_untilica;
out_dir_after = paths.prep04_out_dir;

helpers.ensure_dir(out_dir_after);

%% ========================================================================
%  FIND INPUTS
% ========================================================================
forica_sets = dir(fullfile(in_dir_forica, '*_forica.set'));
if isempty(forica_sets)
    step_out.ok = true;
    step_out.message = sprintf('prep04_ica: no *_forica.set found for %s (skip).', subj_label);
    helpers.logmsg_default('%s', step_out.message);
    return;
end

ica_method = string(step_cfg.ica_method);

%% ========================================================================
%  AMICA GUARDS
% ========================================================================
if ica_method == "amica"
    if ispc && isfield(step_cfg,'amica_require_no_spaces_on_windows') && step_cfg.amica_require_no_spaces_on_windows
        eeglab_root = string(helpers.getenv_or_empty("EEGLAB_ROOT"));
        amica_path = which('runamica15');
        if isempty(amica_path)
            error('AMICA requested, but runamica15 not found on path (AMICA plugin missing?).');
        end
        if contains(string(amica_path), ' ')
            error('AMICA requested, but runamica15 path contains spaces (Windows AMICA may fail): %s', amica_path);
        end
        if strlength(eeglab_root) > 0 && contains(eeglab_root, ' ')
            error('AMICA requested, but EEGLAB_ROOT contains spaces (Windows AMICA may fail): %s', eeglab_root);
        end
    end
end

%% ========================================================================
%  MAIN LOOP (one output per forica run)
% ========================================================================
outputs_written = {};

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

    % --- overwrite policy (single output) ---
    [do_run, reason, ~] = helpers.step_should_run_outputs({out_path}, overwrite_mode, cfg);
    helpers.logmsg_default('prep04_ica: %s | %s | %s', subj_label, run_base, string(reason));

    if ~do_run
        outputs_written{end+1} = out_path; %#ok<AGROW>
        continue;
    end

    if overwrite_mode == "delete" && exist(out_path,'file') == 2 && ~cfg.io.dry_run
        helpers.safe_delete_set(out_path);
    end

    %% --------------------------------------------------------------------
    %  LOAD
    % ---------------------------------------------------------------------
    ica_prep_eeg = helpers.safe_loadset(in_dir_forica, forica_name, helpers);
    preica_eeg   = helpers.safe_loadset(in_dir_preica,  char(preica_name), helpers);

    ica_prep_eeg = helpers.append_eeg_comment(ica_prep_eeg, 'prep04_ica: start ICA on _forica dataset');
    ica_prep_eeg = helpers.append_eeg_comment(ica_prep_eeg, sprintf('prep04_ica: loaded forica=%s', forica_name));

    preica_eeg   = helpers.append_eeg_comment(preica_eeg, 'prep04_ica: will apply ICA weights to _preica dataset');
    preica_eeg   = helpers.append_eeg_comment(preica_eeg, sprintf('prep04_ica: loaded preica=%s', char(preica_name)));

    %% --------------------------------------------------------------------
    %  RANK-SAFE PCA LOGIC (compute rank on ACTUAL ICA dataset: forica)
    % ---------------------------------------------------------------------
    interpolated_count = 0;
    if isfield(preica_eeg,'etc') && isfield(preica_eeg.etc,'interpolated_channel_indices') && ~isempty(preica_eeg.etc.interpolated_channel_indices)
        interpolated_count = numel(preica_eeg.etc.interpolated_channel_indices);
    elseif isfield(preica_eeg,'chaninfo') && isfield(preica_eeg.chaninfo,'bad') && ~isempty(preica_eeg.chaninfo.bad)
        interpolated_count = numel(preica_eeg.chaninfo.bad);
    end

    % Compute numerical rank from ICA-training data (forica), not preica
    X = double(reshape(ica_prep_eeg.data, ica_prep_eeg.nbchan, ica_prep_eeg.pnts * ica_prep_eeg.trials));
    rank_forica = local_rank_svd(X);

    % Decide whether to use PCA at all (only if rank deficiency exists)
    use_pca  = false;
    pca_rank = [];

    if isfield(step_cfg,'use_pca_rank_if_interpolated') && step_cfg.use_pca_rank_if_interpolated
        if rank_forica < ica_prep_eeg.nbchan
            use_pca  = true;
            pca_rank = max(rank_forica, 1);

            ica_prep_eeg = helpers.append_eeg_comment(ica_prep_eeg, sprintf( ...
                'prep04_ica: rank-safe PCA: nbchan=%d rank(forica)=%d interpolated_count(preica)=%d => pca_rank=%d', ...
                ica_prep_eeg.nbchan, rank_forica, interpolated_count, pca_rank));

            helpers.logmsg_default('prep04_ica: %s | %s | rank-safe PCA: nbchan=%d rank(forica)=%d interpolated_count(preica)=%d => pca_rank=%d', ...
                subj_label, run_base, ica_prep_eeg.nbchan, rank_forica, interpolated_count, pca_rank);
        else
            ica_prep_eeg = helpers.append_eeg_comment(ica_prep_eeg, sprintf( ...
                'prep04_ica: rank-safe PCA: nbchan=%d rank(forica)=%d => full-rank (no PCA)', ...
                ica_prep_eeg.nbchan, rank_forica));

            helpers.logmsg_default('prep04_ica: %s | %s | rank-safe PCA: nbchan=%d rank(forica)=%d => full-rank (no PCA)', ...
                subj_label, run_base, ica_prep_eeg.nbchan, rank_forica);
        end
    else
        ica_prep_eeg = helpers.append_eeg_comment(ica_prep_eeg, 'prep04_ica: rank-safe PCA disabled by config');
    end

    %% --------------------------------------------------------------------
    %  RUN ICA
    % ---------------------------------------------------------------------
    switch ica_method

        case "amica"
            % AMICA expects 2D [channels x samples]
            x = double(reshape(ica_prep_eeg.data, ica_prep_eeg.nbchan, ica_prep_eeg.pnts * ica_prep_eeg.trials));

            if use_pca
                pcakeep = pca_rank;
            else
                pcakeep = max(local_rank_svd(x), 1);
            end

            % ---- UNIQUE TEMP DIR PER SUBJECT/RUN ----
            amica_tmp_dir = local_make_unique_amica_tmpdir(step_cfg, subj_label, char(run_base));
            helpers.logmsg_default('prep04_ica: %s | %s | AMICA tmp dir: %s', subj_label, run_base, amica_tmp_dir);

            keep_tmp_on_error = isfield(step_cfg,'amica_keep_tmp_on_error') && step_cfg.amica_keep_tmp_on_error;
            delete_tmp_after  = isfield(step_cfg,'amica_delete_tmp') && step_cfg.amica_delete_tmp;

            try
                [ica_prep_eeg.icaweights, ica_prep_eeg.icasphere, ~] = runamica15( ...
                    x, ...
                    'pcakeep', pcakeep, ...
                    'outdir', amica_tmp_dir);

                ica_prep_eeg.icawinv = pinv(ica_prep_eeg.icaweights * ica_prep_eeg.icasphere);

                % Explicit: all channels used
                ica_prep_eeg.icachansind = 1:ica_prep_eeg.nbchan;

                ica_rank_used = pcakeep;
                ica_prep_eeg = eeg_checkset(ica_prep_eeg);
                ica_prep_eeg = helpers.append_eeg_comment(ica_prep_eeg, sprintf( ...
                    'prep04_ica: AMICA done. rank_used=%d | tmpdir=%s', ica_rank_used, amica_tmp_dir));

                if delete_tmp_after && ~cfg.io.dry_run
                    local_safe_rmdir(amica_tmp_dir);
                    helpers.logmsg_default('prep04_ica: %s | %s | deleted AMICA tmp dir: %s', ...
                        subj_label, run_base, amica_tmp_dir);
                end

            catch ME
                if keep_tmp_on_error
                    helpers.logmsg_default('prep04_ica: %s | %s | AMICA failed; keeping tmp dir for debugging: %s | %s', ...
                        subj_label, run_base, amica_tmp_dir, ME.message);
                else
                    local_safe_rmdir(amica_tmp_dir);
                    helpers.logmsg_default('prep04_ica: %s | %s | AMICA failed; tmp dir deleted: %s | %s', ...
                        subj_label, run_base, amica_tmp_dir, ME.message);
                end
                rethrow(ME);
            end

        otherwise
            interrupt_ica = 'off';
            if isfield(step_cfg,'interrupt_ica'); interrupt_ica = step_cfg.interrupt_ica; end

            if use_pca
                if isfield(step_cfg,'use_extended_infomax') && step_cfg.use_extended_infomax
                    ica_prep_eeg = pop_runica(ica_prep_eeg, 'extended', 1, 'pca', pca_rank, 'interrupt', interrupt_ica);
                else
                    ica_prep_eeg = pop_runica(ica_prep_eeg, 'pca', pca_rank, 'interrupt', interrupt_ica);
                end
                ica_rank_used = pca_rank;
            else
                use_extended = true;
                if isfield(step_cfg,'use_extended_infomax'); use_extended = step_cfg.use_extended_infomax; end

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

    %% --------------------------------------------------------------------
    %  TRANSFER TO PREICA
    % ---------------------------------------------------------------------
    preica_eeg.icawinv     = ica_prep_eeg.icawinv;
    preica_eeg.icasphere   = ica_prep_eeg.icasphere;
    preica_eeg.icaweights  = ica_prep_eeg.icaweights;
    preica_eeg.icachansind = ica_prep_eeg.icachansind;

    preica_eeg = eeg_checkset(preica_eeg);
    preica_eeg = helpers.append_eeg_comment(preica_eeg, sprintf('prep04_ica: ICA weights transferred from %s', forica_name));
    preica_eeg = helpers.append_eeg_comment(preica_eeg, sprintf('prep04_ica: ica_method=%s | interpolated_count=%d | rank_forica=%d | rank_used=%d', ...
        ica_method, interpolated_count, rank_forica, ica_rank_used));

    %% --------------------------------------------------------------------
    %  SAVE
    % ---------------------------------------------------------------------
    if cfg.io.dry_run
        helpers.logmsg_default('prep04_ica: DRY RUN would save: %s', out_path);
    else
        preica_eeg = helpers.safe_saveset(preica_eeg, out_dir_after, char(out_name), helpers, cfg);
        helpers.logmsg_default('prep04_ica: saved: %s', out_path);
    end

    outputs_written{end+1} = out_path; %#ok<AGROW>
end

%% ========================================================================
%  FINALIZE
% ========================================================================
if isempty(outputs_written)
    step_out.ok = false;
    step_out.message = sprintf('prep04_ica: no runs processed successfully for %s (no matching preica?).', subj_label);
    return;
end

step_out.ok = true;
step_out.message = sprintf('prep04_ica: OK (%d output file(s)).', numel(outputs_written));
step_out.outputs = outputs_written;

end


function r = local_rank_svd(X)
% Robust numerical rank via SVD with explicit tolerance.
% X is [channels x samples].

if isempty(X) || any(~isfinite(X(:)))
    % fallback: extremely conservative
    r = size(X,1);
    return;
end

% Center per-channel to reduce mean-offset issues
X = X - mean(X, 2);

s = svd(X, 'econ');
if isempty(s)
    r = 0;
    return;
end

% Explicit tolerance (similar spirit to MATLAB rank() but stable across scaling)
tol = max(size(X)) * eps(max(s)) * max(s);
r = sum(s > tol);

% Safety clamp
r = min(r, size(X,1));
end


function outdir = local_make_unique_amica_tmpdir(step_cfg, subj_label, run_base)
% Create a unique AMICA temp dir per subject/run/call.

if isfield(step_cfg,'amica_tmp_root') && strlength(string(step_cfg.amica_tmp_root)) > 0
    rootdir = char(step_cfg.amica_tmp_root);
else
    rootdir = tempdir;
end

stamp = char(string(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
rand_suffix = char(java.util.UUID.randomUUID.toString);
rand_suffix = strrep(rand_suffix, '-', '_');

folder_name = sprintf('amica_tmp_%s_%s_%s_%s', ...
    local_sanitize_fname(subj_label), ...
    local_sanitize_fname(run_base), ...
    stamp, ...
    rand_suffix(1:8));

outdir = fullfile(rootdir, folder_name);

if exist(outdir, 'dir')
    % extremely unlikely, but be safe
    pause(0.05);
    folder_name = sprintf('amica_tmp_%s_%s_%s_%s', ...
        local_sanitize_fname(subj_label), ...
        local_sanitize_fname(run_base), ...
        char(string(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))), ...
        char(java.util.UUID.randomUUID.toString));
    folder_name = strrep(folder_name, '-', '_');
    outdir = fullfile(rootdir, folder_name);
end

end


function s = local_sanitize_fname(s)
s = char(string(s));
s = regexprep(s, '[^\w\-]', '_');
end


function local_safe_rmdir(folder_path)
if exist(folder_path, 'dir')
    try
        rmdir(folder_path, 's');
    catch
        % do not crash pipeline on tmp cleanup failure
    end
end
end
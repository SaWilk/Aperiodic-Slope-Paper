function step_out = proof_eeg_cf_prep03_untilica(subj_id, cfg, paths, helpers)
% PROOF_EEG_CF_PREP03_UNTILICA - PROOF - Classical Paradigm / Saskia Wilken / JAN 2026
% Preprocess trigger-fixed set until ICA-prep.
% DESCRIPTION (short)
%   Loads the trigger-fixed continuous dataset from Step 02 and prepares two outputs:
%     (1) *_preica.set : continuous pipeline dataset for all later steps
%     (2) *_forica.set : ICA-training-only dataset (extra high-pass + epoch-based QC)
%   Key operations:
%     - optional crop to task window using markers (default S 91..S 97)
%     - channel type assignment (EEG/EOG/AUX)
%     - optional downsampling
%     - bad-channel detection (EEG only), optional interpolation before ICA
%     - filtering + optional line-noise removal on EEG+EOG only
%     - ICA-prep dataset creation (regepochs + optional MAD/jointprob rejection)

%% ========================================================================
%  OUTPUT INIT
% ========================================================================
step_out = struct( ...
    'ok', false, ...
    'skipped', false, ...
    'message', '', ...
    'run_base_name', '', ...
    'in_triggersfixed_set', '', ...
    'out_preica_set', '', ...
    'out_forica_set', '' );

%% ========================================================================
%  STEP CFG DEFAULTS 
% ========================================================================
step_cfg = struct();

% Crop
step_cfg.crop_to_task_markers = true;
step_cfg.crop_start_marker    = 'S 91';
step_cfg.crop_end_marker      = 'S 97';
step_cfg.crop_padding_sec     = [0 0];

% Channel typing labels
step_cfg.eog_channel_labels     = {'IO1','IO2','LO1','LO2'};
step_cfg.scr_channel_labels     = {'SCR'};
step_cfg.startle_channel_labels = {'Startle'};
step_cfg.ekg_channel_labels     = {'EKG'};

% Downsample: 0 (none) | 250 | 500
step_cfg.downsample_hz = 250;

% Bad channel detection mode: "auto" (clean_rawdata-based), "auto_rejchan", "manual", "off"
step_cfg.detect_bad_channels_mode = "auto";
step_cfg.auto_badchan_z_threshold  = 3.29;
step_cfg.auto_badchan_freqrange_hz = [1 125];

step_cfg.emu_flatline_sec           = 5;
step_cfg.emu_channel_corr_threshold = 0.80;

step_cfg.flag_flat_channels_as_bad      = true;
step_cfg.flat_channel_variance_epsilon  = 0;

% Interpolation timing
step_cfg.interpolate_bad_channels_before_ica = true;
step_cfg.interp_method = 'spherical';

% Filters
step_cfg.highpass_hz          = 0.01;
step_cfg.lowpass_hz           = 30;
step_cfg.ica_prep_highpass_hz = 1;

% Line noise
step_cfg.line_noise_method          = "pop_cleanline"; % "pop_cleanline" | "off"
step_cfg.line_noise_frequencies_hz  = [50 100];
step_cfg.pop_cleanline_bandwidth_hz = 2;
step_cfg.pop_cleanline_p_value      = 0.01;
step_cfg.pop_cleanline_verbose      = false;

% ICA-prep: regepochs + rejection (ICA training only)
step_cfg.ica_prep_use_regepochs               = true;
step_cfg.ica_prep_regepoch_length_sec         = 1;
step_cfg.ica_prep_use_jointprob_rejection     = true;
step_cfg.ica_prep_jointprob_local             = 2;
step_cfg.ica_prep_jointprob_global            = 2;

step_cfg.ica_prep_use_mad_epoch_rejection     = true;
step_cfg.ica_prep_mad_z_threshold             = 3;
step_cfg.ica_prep_mad_use_logvar              = true;

% Overwrite override ("" => use global)
step_cfg.overwrite_mode = "";

% Merge user overrides from mother cfg if present
if isfield(cfg, 'steps') && isfield(cfg.steps, 'prep03_untilica')
    s = cfg.steps.prep03_untilica;
    if isfield(s,'overwrite_mode') && strlength(string(s.overwrite_mode)) > 0
        step_cfg.overwrite_mode = string(s.overwrite_mode);
    end
end

%% ========================================================================
%  STEP CFG DEFAULTS 
% ========================================================================
step_cfg = struct();
... % deine Defaults

% >>> HIER HIN KOMMT 2b <<<
% merge overrides from mother cfg.prep03
if isfield(cfg, 'prep03') && isstruct(cfg.prep03)
    f = fieldnames(cfg.prep03);
    for k = 1:numel(f)
        step_cfg.(f{k}) = cfg.prep03.(f{k});
    end
end

% Merge user overrides from cfg.steps... (overwrite_mode)
...
overwrite_mode = helpers.resolve_overwrite_mode(cfg, step_cfg.overwrite_mode);


overwrite_mode = helpers.resolve_overwrite_mode(cfg, step_cfg.overwrite_mode);

%% ========================================================================
%  PATHS (mother should set these; fallback minimally)
% ========================================================================
if ~isfield(paths,'prep02_out_dir')
    paths.prep02_out_dir = fullfile(paths.subj_out_dir, '01_trigger_fix');
end
if ~isfield(paths,'prep03_out_dir_untilica')
    paths.prep03_out_dir_untilica = fullfile(paths.subj_out_dir, '02_until_ica');
end
if ~isfield(paths,'prep03_out_dir_forica')
    paths.prep03_out_dir_forica = fullfile(paths.subj_out_dir, '03_for_ica');
end

helpers.ensure_dir(paths.prep03_out_dir_untilica);
helpers.ensure_dir(paths.prep03_out_dir_forica);

sub_in_dir = paths.prep02_out_dir;

%% ========================================================================
%  FIND INPUT: *_triggersfixed.set (pick most recent if multiple)
% ========================================================================
trigger_fixed_sets = dir(fullfile(sub_in_dir, '*_triggersfixed.set'));

if isempty(trigger_fixed_sets)
    msg = sprintf('prep03_untilica: no *_triggersfixed.set found in %s (sub-%s)', sub_in_dir, subj_id);
    helpers.logmsg_default('%s', msg);
    step_out.message = msg;
    step_out.ok = false;
    return;
end

if numel(trigger_fixed_sets) > 1
    [~, ix] = max([trigger_fixed_sets.datenum]);
    helpers.logmsg_default('prep03_untilica: WARNING multiple trigger-fixed sets found (%d). Using most recent: %s', ...
        numel(trigger_fixed_sets), trigger_fixed_sets(ix).name);
    trigger_fixed_sets = trigger_fixed_sets(ix);
end

trigger_fixed_set_name = trigger_fixed_sets.name;
run_base_name = erase(trigger_fixed_set_name, '_triggersfixed.set');

step_out.run_base_name = run_base_name;
step_out.in_triggersfixed_set = fullfile(sub_in_dir, trigger_fixed_set_name);

% Output filenames (ALWAYS TWO)
out_preica = fullfile(paths.prep03_out_dir_untilica, sprintf('%s_preica.set', run_base_name));
out_forica = fullfile(paths.prep03_out_dir_forica,   sprintf('%s_forica.set', run_base_name));
step_out.out_preica_set = out_preica;
step_out.out_forica_set = out_forica;

%% ========================================================================
%  OVERWRITE POLICY (considers BOTH outputs)
%  IMPORTANT: DO NOT DELETE YET (we may skip later due to missing markers)
% ========================================================================
out_files = {out_preica, out_forica};
[do_run, reason, needs_regen] = helpers.step_should_run_outputs(out_files, overwrite_mode, cfg);

if ~do_run
    helpers.logmsg_default('prep03_untilica: skip (%s)', reason);
    step_out.skipped = true;
    step_out.ok = true;
    step_out.message = reason;
    return;
end

helpers.logmsg_default('prep03_untilica: START sub-%s | %s', subj_id, run_base_name);

%% ========================================================================
%  LOAD INPUT
% ========================================================================
EEG = helpers.safe_loadset(sub_in_dir, trigger_fixed_set_name, helpers);
EEG = eeg_checkset(EEG);

EEG = helpers.append_eeg_comment(EEG, 'prep03_untilica: start');
EEG = helpers.append_eeg_comment(EEG, sprintf('prep03_untilica: input=%s', trigger_fixed_set_name));

%% ========================================================================
%  CHANNEL TYPES
% ========================================================================
EEG = helpers.ensure_channel_types(EEG, step_cfg);

eeg_idx = find(strcmpi({EEG.chanlocs.type}, 'EEG'));
eog_idx = find(strcmpi({EEG.chanlocs.type}, 'EOG'));
aux_idx = find(~ismember(lower({EEG.chanlocs.type}), {'eeg','eog'}));

EEG = helpers.append_eeg_comment(EEG, sprintf('prep03_untilica: channel counts EEG=%d | EOG=%d | AUX=%d', ...
    numel(eeg_idx), numel(eog_idx), numel(aux_idx)));

%% ========================================================================
%  CROP TO TASK WINDOW (DEFAULT ON)
% ========================================================================
if step_cfg.crop_to_task_markers
    start_latency = helpers.find_first_event_latency(EEG, step_cfg.crop_start_marker);
    end_latency   = helpers.find_first_event_latency(EEG, step_cfg.crop_end_marker);

    if isempty(start_latency) || isempty(end_latency)
        msg = sprintf('prep03_untilica: missing task markers start(%s)=%d end(%s)=%d -> skip run (NO DELETION)', ...
            step_cfg.crop_start_marker, isempty(start_latency), step_cfg.crop_end_marker, isempty(end_latency));
        helpers.logmsg_default('%s', msg);
        step_out.ok = true;          % not a hard failure
        step_out.skipped = true;
        step_out.message = msg;
        return;
    end

    t_start = (double(start_latency) / EEG.srate) - step_cfg.crop_padding_sec(1);
    t_end   = (double(end_latency)   / EEG.srate) + step_cfg.crop_padding_sec(2);

    t_start = max(t_start, 0);
    t_end   = min(t_end, (EEG.pnts - 1) / EEG.srate);

    if t_end <= t_start
        msg = sprintf('prep03_untilica: invalid crop window t_start=%.3f t_end=%.3f -> skip run (NO DELETION)', t_start, t_end);
        helpers.logmsg_default('%s', msg);
        step_out.ok = true;
        step_out.skipped = true;
        step_out.message = msg;
        return;
    end

    EEG = pop_select(EEG, 'time', [t_start t_end]);
    EEG = eeg_checkset(EEG);

    EEG = helpers.append_eeg_comment(EEG, sprintf('prep03_untilica: cropped %s..%s padding=[%.2f %.2f] t=[%.3f %.3f]', ...
        step_cfg.crop_start_marker, step_cfg.crop_end_marker, step_cfg.crop_padding_sec(1), step_cfg.crop_padding_sec(2), t_start, t_end));
end

%% ========================================================================
%  DOWNSAMPLE
% ========================================================================
if step_cfg.downsample_hz == 250 || step_cfg.downsample_hz == 500
    EEG = pop_resample(EEG, step_cfg.downsample_hz);
    EEG = eeg_checkset(EEG);
    EEG = helpers.append_eeg_comment(EEG, sprintf('prep03_untilica: downsampled to %d Hz', step_cfg.downsample_hz));
elseif step_cfg.downsample_hz == 0
    EEG = helpers.append_eeg_comment(EEG, 'prep03_untilica: downsampling skipped');
else
    EEG = helpers.append_eeg_comment(EEG, sprintf('prep03_untilica: downsampling skipped (unsupported=%d)', step_cfg.downsample_hz));
end

% recompute indices
eeg_idx = find(strcmpi({EEG.chanlocs.type}, 'EEG'));
eog_idx = find(strcmpi({EEG.chanlocs.type}, 'EOG'));

%% ========================================================================
%  FLAT/INVALID EEG CHANNELS
% ========================================================================
flat_idx = [];
flat_labels = {};
if step_cfg.flag_flat_channels_as_bad && string(step_cfg.detect_bad_channels_mode) ~= "off" && ~isempty(eeg_idx)
    [flat_idx, flat_labels] = helpers.find_flat_or_invalid_channels(EEG, eeg_idx, step_cfg.flat_channel_variance_epsilon);
    if ~isempty(flat_idx)
        EEG = helpers.append_eeg_comment(EEG, sprintf('prep03_untilica: flat/invalid EEG flagged: %s', strjoin(flat_labels, ', ')));
    end
end

%% ========================================================================
%  BAD CHANNEL DETECTION (EEG ONLY; EOG EXCLUDED)
% ========================================================================
bad_idx = [];
bad_labels = {};

switch string(step_cfg.detect_bad_channels_mode)

    case "auto"
        if ~isempty(eeg_idx)
            try
                [emu_bad_idx, ~] = helpers.detect_bad_channels_emulation_style( ...
                    EEG, eeg_idx, step_cfg.emu_flatline_sec, step_cfg.emu_channel_corr_threshold);

                bad_idx = sort(unique([emu_bad_idx(:)' flat_idx(:)']));
                bad_idx = setdiff(bad_idx, eog_idx);

            catch me
                helpers.logmsg_default('prep03_untilica: badchan auto FAILED -> fallback flat only. %s', me.message);
                bad_idx = flat_idx;
            end
        end

    case "auto_rejchan"
        if isempty(eeg_idx)
            bad_idx = flat_idx;
        else
            try
                [~, idx_prob] = pop_rejchan(EEG, 'elec', eeg_idx, 'threshold', step_cfg.auto_badchan_z_threshold, 'norm', 'on', 'measure', 'prob');
                [~, idx_kurt] = pop_rejchan(EEG, 'elec', eeg_idx, 'threshold', step_cfg.auto_badchan_z_threshold, 'norm', 'on', 'measure', 'kurt');
                [~, idx_spec] = pop_rejchan(EEG, 'elec', eeg_idx, 'threshold', step_cfg.auto_badchan_z_threshold, 'norm', 'on', 'measure', 'spec', ...
                    'freqrange', step_cfg.auto_badchan_freqrange_hz);

                bad_idx = sort(unique([idx_prob idx_kurt idx_spec flat_idx]));
                bad_idx = setdiff(bad_idx, eog_idx);

            catch me
                helpers.logmsg_default('prep03_untilica: badchan auto_rejchan FAILED -> fallback flat only. %s', me.message);
                bad_idx = flat_idx;
            end
        end

    case "manual"
        error('prep03_untilica: detect_bad_channels_mode="manual" is not allowed in pipeline mode (non-interactive).');

    otherwise
        bad_idx = [];
end

if ~isempty(bad_idx)
    bad_labels = {EEG.chanlocs(bad_idx).labels};
    EEG = helpers.append_eeg_comment(EEG, sprintf('prep03_untilica: bad EEG labels: %s', strjoin(bad_labels, ', ')));
else
    EEG = helpers.append_eeg_comment(EEG, 'prep03_untilica: no bad EEG channels flagged');
end

% Store in EEG.chaninfo.bad
if ~isfield(EEG,'chaninfo') || isempty(EEG.chaninfo)
    EEG.chaninfo = struct();
end
EEG.chaninfo.bad = bad_labels;

%% ========================================================================
%  INTERPOLATE BAD CHANNELS BEFORE ICA (DEFAULT)
% ========================================================================
if step_cfg.interpolate_bad_channels_before_ica && ~isempty(bad_idx)
    EEG = helpers.append_eeg_comment(EEG, sprintf('prep03_untilica: interpolate BEFORE ICA (%s): %s', ...
        step_cfg.interp_method, strjoin(bad_labels, ', ')));

    EEG = pop_interp(EEG, bad_idx, step_cfg.interp_method);
    EEG = eeg_checkset(EEG);

    if ~isfield(EEG,'etc') || isempty(EEG.etc); EEG.etc = struct(); end
    EEG.etc.interpolated_channel_indices = bad_idx;
    EEG.etc.interpolated_channel_labels  = bad_labels;
else
    if ~isfield(EEG,'etc') || isempty(EEG.etc); EEG.etc = struct(); end
    EEG.etc.interpolated_channel_indices = [];
    EEG.etc.interpolated_channel_labels  = {};
end

%% ========================================================================
%  FILTERING + LINE NOISE (EEG+EOG ONLY)
% ========================================================================
eeg_idx = find(strcmpi({EEG.chanlocs.type}, 'EEG'));
eog_idx = find(strcmpi({EEG.chanlocs.type}, 'EOG'));
filter_idx = sort(unique([eeg_idx eog_idx]));

EEG = helpers.apply_filter_to_subset_only(EEG, filter_idx, step_cfg.highpass_hz, [], 'prep03_untilica high-pass');

line_noise_applied = false;
if string(step_cfg.line_noise_method) == "pop_cleanline"
    [EEG, line_noise_applied] = helpers.apply_pop_cleanline_to_subset(EEG, filter_idx, step_cfg);
end
EEG = helpers.append_eeg_comment(EEG, sprintf('prep03_untilica: line noise method=%s applied=%d', ...
    string(step_cfg.line_noise_method), line_noise_applied));

EEG = helpers.apply_filter_to_subset_only(EEG, filter_idx, [], step_cfg.lowpass_hz, 'prep03_untilica low-pass');

%% ========================================================================
%  NOW IT'S SAFE TO DELETE OUTPUTS (we know we won't early-return anymore)
% ========================================================================
if overwrite_mode == "delete" || needs_regen
    if cfg.io.dry_run
        helpers.logmsg_default('prep03_untilica: DRY RUN would delete outputs: %s | %s', out_preica, out_forica);
    else
        helpers.safe_delete_set(out_preica);
        helpers.safe_delete_set(out_forica);
    end
end

%% ========================================================================
%  SAVE PREICA (PIPELINE DATASET)  [ALWAYS]
% ========================================================================
if ~cfg.io.dry_run
    EEG = helpers.safe_saveset(EEG, paths.prep03_out_dir_untilica, sprintf('%s_preica.set', run_base_name), helpers, cfg);
end
EEG = helpers.append_eeg_comment(EEG, sprintf('prep03_untilica: saved preica: %s', out_preica));
helpers.logmsg_default('prep03_untilica: saved preica (dry_run=%d): %s', cfg.io.dry_run, out_preica);

%% ========================================================================
%  CREATE + SAVE FORICA (ICA TRAINING ONLY)  [ALWAYS]
% ========================================================================
ica_prep_eeg = EEG;

ica_prep_eeg = helpers.apply_filter_to_subset_only(ica_prep_eeg, filter_idx, step_cfg.ica_prep_highpass_hz, [], 'prep03_untilica ICA-prep high-pass');
ica_prep_eeg = helpers.append_eeg_comment(ica_prep_eeg, sprintf('prep03_untilica: ICA-prep high-pass %.2f Hz', step_cfg.ica_prep_highpass_hz));

if step_cfg.ica_prep_use_regepochs
    ica_prep_eeg = eeg_regepochs(ica_prep_eeg, ...
        'recurrence', step_cfg.ica_prep_regepoch_length_sec, ...
        'limits', [0 step_cfg.ica_prep_regepoch_length_sec]);
    ica_prep_eeg = eeg_checkset(ica_prep_eeg);
    ica_prep_eeg = helpers.append_eeg_comment(ica_prep_eeg, sprintf('prep03_untilica: ICA-prep regepochs %.2fs', step_cfg.ica_prep_regepoch_length_sec));
end

if step_cfg.ica_prep_use_mad_epoch_rejection
    ica_eeg_idx = find(strcmpi({ica_prep_eeg.chanlocs.type}, 'EEG'));
    if ~isempty(ica_eeg_idx) && ica_prep_eeg.trials >= 3
        [ica_prep_eeg, mad_info] = helpers.reject_ica_prep_epochs_by_mad_variance( ...
            ica_prep_eeg, ica_eeg_idx, step_cfg.ica_prep_mad_z_threshold, step_cfg.ica_prep_mad_use_logvar);
        if mad_info.did_apply
            ica_prep_eeg = helpers.append_eeg_comment(ica_prep_eeg, sprintf( ...
                'prep03_untilica: ICA-prep MAD reject z=%.2f rejected %d/%d', ...
                mad_info.z_thresh, mad_info.n_rejected, mad_info.n_before));
        end
    end
end

if step_cfg.ica_prep_use_jointprob_rejection
    [ica_prep_eeg, did_jointprob] = helpers.apply_jointprob_safely(ica_prep_eeg, ...
        step_cfg.ica_prep_jointprob_local, step_cfg.ica_prep_jointprob_global);
    ica_prep_eeg = helpers.append_eeg_comment(ica_prep_eeg, sprintf('prep03_untilica: ICA-prep jointprob applied=%d', did_jointprob));
end

if ~cfg.io.dry_run
    ica_prep_eeg = helpers.safe_saveset(ica_prep_eeg, paths.prep03_out_dir_forica, sprintf('%s_forica.set', run_base_name), helpers, cfg);
end
ica_prep_eeg = helpers.append_eeg_comment(ica_prep_eeg, sprintf('prep03_untilica: saved forica: %s', out_forica));
helpers.logmsg_default('prep03_untilica: saved forica (dry_run=%d): %s', cfg.io.dry_run, out_forica);

helpers.logmsg_default('prep03_untilica: DONE sub-%s | %s', subj_id, run_base_name);

step_out.ok = true;
step_out.skipped = false;
step_out.message = 'ok';

end

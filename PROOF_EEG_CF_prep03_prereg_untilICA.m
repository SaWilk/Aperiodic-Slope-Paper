%% ANALYSIS SCRIPT - EEG - PROOF - Classical Paradigm (Real Data)
% Metin Ozyagcilar & Saskia Wilken
% PREPROCESSING UNTIL ICA PREP (NO ICA RUN HERE)
%
% Original pipeline: Metin Ozyagcilar (Nov 2023)
% Extensions / refactor + best-practice fixes: Saskia Wilken (Jan 2026)
% MATLAB 2025b
%
% PURPOSE
%   - Load trigger-fixed .set files (no raw data access; no vhdr needed)
%   - Crop to task window (configurable markers; default S 91..S 97)
%       -> S 91: start habituation
%       -> S 97: end experiment
%       -> if marker(s) missing: skip run and log to ./logs
%   - Standardize channel types (EEG default, EOG, SCR, Startle, EKG)
%   - Downsample (default 250; options: 250/500/none)
%   - Detect bad EEG channels (auto by default; manual optional)
%       -> EOG channels are NEVER considered "bad channels"
%       -> flat/zero/invalid EEG channels are ALWAYS flagged as bad (auto+manual)
%       -> bad channels are stored in EEG.chaninfo.bad (and in comments)
%   - Interpolate bad EEG channels BEFORE ICA (DEFAULT, preregistered)
%       -> can be turned off; if off, warning indicates interpolation must happen after ICA
%   - High-pass + Low-pass filtering (FFT) for EEG+EOG channels only
%   - Line noise removal (DEFAULT: PREP cleanlinenoise / cleanLineNoise)
%       -> pop_cleanline optional (not default)
%   - Save:
%       (1) pre-ICA analysis dataset:   ...\02_until_ica\<sub>\*_preica.set
%       (2) ICA-prep dataset:           ...\03_for_ica\<sub>\*_forica.set
%   - Append processing log to EEG.comments
%   - Create composite summary report + store run records to scripts/logs
%
% NOTE
%   ICA is run in a separate script:
%     "04_run_ica_and_apply_weights_from_03_for_ica_to_04_after_ica.m"

%% TOOLBOXES / PLUG-INs
% (1) EEGLAB (v2023.1 & 2025.1)

%%

clear all; close all; clc;

%% =========================
%  CONFIG (DEFAULTS)
%  =========================
% Change config fields here. Config is saved into ./config (same folder level as this script).

config = struct();

% --- core toggles ---
config.save_intermediate_steps              = true;     % default: true
config.purge_subject_output_folders         = false;    % default: false

% --- crop to task window (DEFAULT ON) ---
% S 91: start habituation
% S 97: end experiment
config.crop_to_task_markers                = true;      % default: true
config.crop_start_marker                   = 'S 91';
config.crop_end_marker                     = 'S 97';
config.crop_padding_sec                    = [0 0];     % [pre post] seconds padding

% --- channel typing ---
config.eog_channel_labels                   = {'IO1','IO2','LO1','LO2'};
config.scr_channel_labels                   = {'SCR'};
config.startle_channel_labels               = {'Startle'};
config.ekg_channel_labels                   = {'EKG'};

% --- downsampling (Hz) ---
% options: 0 (none), 250 (default), 500
config.downsample_hz                        = 250;

% --- bad channel detection (EEG only; excludes EOG) ---
% MODES:
%   "auto"         = DEFAULT emulation-style (flatline 5s + corr 0.8) + flat/invalid check
%   "auto_rejchan" = your previous EEGLAB prob/kurt/spec z-threshold approach + flat/invalid check
%   "manual"       = manual indices + flat/invalid check
%   "off"          = disabled
config.detect_bad_channels_mode             = "auto";

% only used if detect_bad_channels_mode == "auto_rejchan"
config.auto_badchan_z_threshold             = 3.29;
config.auto_badchan_freqrange_hz            = [1 125];

% ONLY used if detect_bad_channels_mode == "auto" (emulation-style)
config.emu_flatline_sec                     = 5;     % default: 5 seconds
config.emu_channel_corr_threshold           = 0.80;  % default: 0.8

% flat channel detection (ALWAYS applied in auto/manual unless mode=="off")
config.flag_flat_channels_as_bad            = true;     % default: true
config.flat_channel_variance_epsilon        = 0;        % 0 = strictly var==0 (safe)

% --- interpolation timing ---
config.interpolate_bad_channels_before_ica  = true;     % DEFAULT: true (prereg)
config.interp_method                        = 'spherical';

% --- filters (Hz) ---
config.highpass_hz                          = 0.01;
config.lowpass_hz                           = 30;
config.ica_prep_highpass_hz                 = 1;

% --- line noise removal (default PREP-style) ---
config.line_noise_method                    = "prep_cleanlinenoise"; % default
% options: "prep_cleanlinenoise" | "pop_cleanline" | "off"
config.line_noise_frequencies_hz            = [50 100 150 200];

% pop_cleanline settings (only used if method == "pop_cleanline")
config.pop_cleanline_bandwidth_hz           = 2;
config.pop_cleanline_p_value                = 0.01;
config.pop_cleanline_verbose                = false;

% --- ICA-prep "quality" epochs (only for ICA training dataset creation) ---
config.ica_prep_use_regepochs               = true;
config.ica_prep_regepoch_length_sec         = 1;
config.ica_prep_use_jointprob_rejection     = true;
config.ica_prep_jointprob_local             = 2;
config.ica_prep_jointprob_global            = 2;

% --- ICA-prep robust epoch rejection (MAD-z of log-variance; ICA training only) ---
config.ica_prep_use_mad_epoch_rejection     = true;   % default: true
config.ica_prep_mad_z_threshold             = 3;      % CHANGED: was 4; more aggressive
config.ica_prep_mad_use_logvar              = true;   % stabilize heavy tails (recommended)

%% =========================
%  DEFINE FOLDERS
%  =========================

% script location
this_file = matlab.desktop.editor.getActiveFilename();
this_dir  = fileparts(this_file);

% create local support folders next to scripts
config_dir = fullfile(this_dir, 'config');
logs_dir   = fullfile(this_dir, 'logs');

if ~exist(config_dir,'dir'); mkdir(config_dir); end
if ~exist(logs_dir,'dir');   mkdir(logs_dir);   end

% --- RUN LOGGER (writes during execution) ---
timestamp_str = datestr(now, 'yyyymmdd_HHMMSS');
runlog_path = fullfile(logs_dir, ['runlog_02_until_ica_' timestamp_str '.txt']);
append_line_to_log(runlog_path, '=== START 02_until_ica ===');
append_line_to_log(runlog_path, ['Script: ' this_file]);

% go up 3 levels (match your project style)
base_path = fileparts(fileparts(fileparts(this_dir)));

% EEGLAB path
path_eeglab = [base_path, '\MATLAB\eeglab_current\eeglab2025.1.0'];

% input root: trigger-fixed sets
path_trigger_fixed_root = [base_path, '\Preprocessed_data\MATRICS\01_trigger_fix'];

% output roots (SIBLINGS, not nested)
OUTPUT_ROOT_MATRICS = 'K:\Wilken Arbeitsordner\Preprocessed_data\MATRICS';

OUTPUT_DIR_UNTIL_ICA = fullfile(OUTPUT_ROOT_MATRICS, '02_until_ica');
OUTPUT_DIR_FOR_ICA   = fullfile(OUTPUT_ROOT_MATRICS, '03_for_ica');
OUTPUT_DIR_REPORTS   = fullfile(OUTPUT_ROOT_MATRICS, 'reports');

if ~exist(OUTPUT_DIR_UNTIL_ICA,'dir'); mkdir(OUTPUT_DIR_UNTIL_ICA); end
if ~exist(OUTPUT_DIR_FOR_ICA,'dir');   mkdir(OUTPUT_DIR_FOR_ICA);   end
if ~exist(OUTPUT_DIR_REPORTS,'dir');   mkdir(OUTPUT_DIR_REPORTS);   end

% skip logs
skipped_runs_log_path = fullfile(logs_dir, 'skipped_runs_missing_task_markers.txt');

%% SAVE CONFIG (MAT + JSON) INTO ./config
config_mat_path  = fullfile(config_dir, 'config_02_until_ica.mat');
save(config_mat_path, 'config');

config_json_path = fullfile(config_dir, 'config_02_until_ica.json');
try
    fid = fopen(config_json_path, 'w');
    fwrite(fid, jsonencode(config, 'PrettyPrint', true), 'char');
    fclose(fid);
catch
    warning('Could not write JSON config. MAT file was saved.');
end

append_line_to_log(runlog_path, ['Config JSON: ' config_json_path]);

%% DISCOVER SUBJECT IDS FROM TRIGGER-FIX ROOT
ds = dir(path_trigger_fixed_root);
ds = ds([ds.isdir]);
ds = ds(~ismember({ds.name},{'.','..'}));
subject_ids = {ds.name};

%% START EEGLAB ONCE (nogui reduces prompts)
cd(path_eeglab);
[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab('nogui');
append_line_to_log(runlog_path, 'EEGLAB started (nogui).');

%% WARN IF INTERPOLATION IS DISABLED
if ~config.interpolate_bad_channels_before_ica
    warning(['config.interpolate_bad_channels_before_ica = false. ', ...
        'Then bad channels must be interpolated after ICA (post-ICA script) to restore a full montage.']);
end

%% RUN RECORDS (stored to ./logs)
run_records = [];

%% =========================
%  MAIN LOOP (subjects)
%  =========================
for subject_index = 1:3%length(subject_ids)

    subject_id = subject_ids{subject_index};

    subject_in_dir_fixed    = fullfile(path_trigger_fixed_root, subject_id);
    subject_out_dir_until   = fullfile(OUTPUT_DIR_UNTIL_ICA, subject_id);
    subject_out_dir_for_ica = fullfile(OUTPUT_DIR_FOR_ICA, subject_id);

    if ~exist(subject_out_dir_until,'dir');   mkdir(subject_out_dir_until);   end
    if ~exist(subject_out_dir_for_ica,'dir'); mkdir(subject_out_dir_for_ica); end

    if config.purge_subject_output_folders
        if exist(subject_out_dir_until,'dir');   rmdir(subject_out_dir_until,'s');   end
        if exist(subject_out_dir_for_ica,'dir'); rmdir(subject_out_dir_for_ica,'s'); end
        mkdir(subject_out_dir_until);
        mkdir(subject_out_dir_for_ica);
    end

    trigger_fixed_sets = dir(fullfile(subject_in_dir_fixed, '*_triggersfixed.set'));
    if isempty(trigger_fixed_sets)
        fprintf('Skipping %s: no *_triggersfixed.set files in %s\n', subject_id, subject_in_dir_fixed);
        append_line_to_log(runlog_path, sprintf('SKIP subject %s: no *_triggersfixed.set in %s', subject_id, subject_in_dir_fixed));
        continue;
    end

    %% =========================
    %  FILE LOOP (runs)
    %  =========================
    for file_index = 1:3numel(trigger_fixed_sets)

        trigger_fixed_set_name = trigger_fixed_sets(file_index).name;
        run_base_name = erase(trigger_fixed_set_name, '_triggersfixed.set');

        append_line_to_log(runlog_path, sprintf('--- RUN START: %s | %s ---', subject_id, run_base_name));

        trigger_fixed_set_path = fullfile(subject_in_dir_fixed, trigger_fixed_set_name);
        if ~exist(trigger_fixed_set_path,'file')
            fprintf('Skipping %s (%s): missing file: %s\n', subject_id, run_base_name, trigger_fixed_set_path);
            append_line_to_log(runlog_path, sprintf('SKIP run: missing file %s', trigger_fixed_set_path));
            continue;
        end

        EEG = pop_loadset('filename', trigger_fixed_set_name, 'filepath', subject_in_dir_fixed);
        EEG = eeg_checkset(EEG);

        % put into ALLEEG without GUI prompt
        [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, 0, 'setname', run_base_name, 'gui', 'off');

        % run-level bookkeeping
        eeg_channel_indices = [];
        eog_channel_indices = [];
        aux_channel_indices = []; % SCR/Startle/EKG (non-EEG physio)
        bad_eeg_channel_indices = [];
        bad_eeg_channel_labels  = {};
        flat_eeg_channel_indices = [];
        flat_eeg_channel_labels  = {};
        interpolated_channel_indices = [];
        line_noise_applied = false;

        % status flags for reporting
        run_status = "processed";

        EEG = append_to_eeg_comments(EEG, '--- preprocess until ICA prep (Saskia Wilken, Jan 2026) ---');
        EEG = append_to_eeg_comments(EEG, sprintf('input trigger-fixed set: %s', trigger_fixed_set_name));
        append_line_to_log(runlog_path, sprintf('Loaded: %s', trigger_fixed_set_name));

        %% STANDARDIZE CHANNEL TYPES (no deletions)
        EEG = ensure_channel_types(EEG, config);

        % derive indices by type after typing
        eeg_channel_indices = find(strcmpi({EEG.chanlocs.type}, 'EEG'));
        eog_channel_indices = find(strcmpi({EEG.chanlocs.type}, 'EOG'));
        aux_channel_indices = find(~ismember(lower({EEG.chanlocs.type}), {'eeg','eog'}));

        EEG = append_to_eeg_comments(EEG, sprintf('channel counts: EEG=%d | EOG=%d | AUX(non-EEG/non-EOG)=%d', ...
            numel(eeg_channel_indices), numel(eog_channel_indices), numel(aux_channel_indices)));

        %% CROP TO TASK MARKERS (S 91 .. S 97) - OPTIONAL BUT DEFAULT ON
        if config.crop_to_task_markers

            start_latency = find_first_event_latency(EEG, config.crop_start_marker);
            end_latency   = find_first_event_latency(EEG, config.crop_end_marker);

            if isempty(start_latency) || isempty(end_latency)

                run_status = "skipped_missing_task_markers";

                msg = sprintf('%s | %s | missing marker(s): start(%s)=%d end(%s)=%d', ...
                    subject_id, run_base_name, config.crop_start_marker, isempty(start_latency), ...
                    config.crop_end_marker, isempty(end_latency));

                fprintf('SKIP: %s\n', msg);
                append_line_to_log(skipped_runs_log_path, msg);
                append_line_to_log(runlog_path, ['SKIP markers: ' msg]);

                % record skip
                run_record = struct();
                run_record.subject_id = subject_id;
                run_record.run_base_name = run_base_name;
                run_record.status = run_status;

                run_record.missing_start_marker = isempty(start_latency);
                run_record.missing_end_marker   = isempty(end_latency);

                run_records = [run_records; run_record]; %#ok<AGROW>
                continue;
            end

            t_start = (double(start_latency) / EEG.srate) - config.crop_padding_sec(1);
            t_end   = (double(end_latency)   / EEG.srate) + config.crop_padding_sec(2);

            % clamp to valid range
            t_start = max(t_start, 0);
            t_end   = min(t_end, (EEG.pnts - 1) / EEG.srate);

            if t_end <= t_start

                run_status = "skipped_invalid_crop_window";

                msg = sprintf('%s | %s | invalid crop window: t_start=%.3f t_end=%.3f', ...
                    subject_id, run_base_name, t_start, t_end);

                fprintf('SKIP: %s\n', msg);
                append_line_to_log(skipped_runs_log_path, msg);
                append_line_to_log(runlog_path, ['SKIP crop window: ' msg]);

                run_record = struct();
                run_record.subject_id = subject_id;
                run_record.run_base_name = run_base_name;
                run_record.status = run_status;
                run_records = [run_records; run_record]; %#ok<AGROW>
                continue;
            end

            EEG = pop_select(EEG, 'time', [t_start t_end]);
            EEG = eeg_checkset(EEG);

            EEG = append_to_eeg_comments(EEG, sprintf(['cropped to task window using %s..%s ', ...
                '(S 91=start habituation, S 97=end experiment). padding_sec=[%.2f %.2f]'], ...
                config.crop_start_marker, config.crop_end_marker, ...
                config.crop_padding_sec(1), config.crop_padding_sec(2)));

            append_line_to_log(runlog_path, sprintf('Cropped: t=[%.3f %.3f] sec', t_start, t_end));

            if config.save_intermediate_steps
                EEG = pop_saveset(EEG, 'filename', [run_base_name '_cropped_taskwindow.set'], 'filepath', subject_out_dir_until);
            end
        end

        %% DOWNSAMPLE (applies to all channels to preserve alignment)
        if config.downsample_hz == 250 || config.downsample_hz == 500
            EEG = pop_resample(EEG, config.downsample_hz);
            EEG = eeg_checkset(EEG);
            EEG = append_to_eeg_comments(EEG, sprintf('downsampled to %d Hz (pop_resample)', config.downsample_hz));
            append_line_to_log(runlog_path, sprintf('Downsampled to %d Hz', config.downsample_hz));

            if config.save_intermediate_steps
                EEG = pop_saveset(EEG, 'filename', [run_base_name sprintf('_ds_%dhz.set', config.downsample_hz)], 'filepath', subject_out_dir_until);
            end
        elseif config.downsample_hz == 0
            EEG = append_to_eeg_comments(EEG, 'downsampling skipped (config.downsample_hz=0).');
            append_line_to_log(runlog_path, 'Downsampling skipped (0).');
        else
            warning('Unsupported config.downsample_hz=%d. Using no downsampling.', config.downsample_hz);
            EEG = append_to_eeg_comments(EEG, sprintf('downsampling skipped (unsupported value: %d).', config.downsample_hz));
            append_line_to_log(runlog_path, sprintf('Downsampling skipped (unsupported %d).', config.downsample_hz));
        end

        %% FLAT / INVALID EEG CHANNEL DETECTION (ALWAYS, except when mode=="off")
        if config.flag_flat_channels_as_bad && config.detect_bad_channels_mode ~= "off"

            if isempty(eeg_channel_indices)
                EEG = append_to_eeg_comments(EEG, 'flat channel check: no EEG channels found.');
            else
                [flat_eeg_channel_indices, flat_eeg_channel_labels] = find_flat_or_invalid_channels(EEG, eeg_channel_indices, config.flat_channel_variance_epsilon);

                if ~isempty(flat_eeg_channel_indices)
                    EEG = append_to_eeg_comments(EEG, sprintf('flat/invalid EEG channels flagged: %s', strjoin(flat_eeg_channel_labels, ', ')));
                    append_line_to_log(runlog_path, sprintf('Flat/invalid EEG: %s', strjoin(flat_eeg_channel_labels, ', ')));
                else
                    EEG = append_to_eeg_comments(EEG, 'flat/invalid EEG channel check: none flagged.');
                end
            end
        end

        %% BAD EEG CHANNEL DETECTION (EEG ONLY; EOG EXCLUDED)
        switch config.detect_bad_channels_mode

            case "auto"
                % DEFAULT: emulation-style (flatline 5s + correlation 0.8) + flat/invalid
                EEG = append_to_eeg_comments(EEG, sprintf('bad channel detection mode: auto (emulation-style; flatline=%ds; corr>=%.2f)', ...
                    config.emu_flatline_sec, config.emu_channel_corr_threshold));
                append_line_to_log(runlog_path, 'Bad channel detect: emulation-style.');

                try
                    if isempty(eeg_channel_indices)
                        error('No EEG channels found (chanlocs.type == "EEG"). Cannot detect bad EEG channels.');
                    end

                    [emu_bad_indices, emu_bad_labels] = detect_bad_channels_emulation_style(EEG, eeg_channel_indices, ...
                        config.emu_flatline_sec, config.emu_channel_corr_threshold);

                    % combine with flat channels (if any)
                    bad_eeg_channel_indices = sort(unique([emu_bad_indices(:)' flat_eeg_channel_indices(:)']));

                    % safety: never include EOG
                    bad_eeg_channel_indices = setdiff(bad_eeg_channel_indices, eog_channel_indices);

                    if isempty(bad_eeg_channel_indices)
                        EEG = append_to_eeg_comments(EEG, 'auto bad channel detection: none flagged (incl. flat check).');
                    else
                        bad_eeg_channel_labels = {EEG.chanlocs(bad_eeg_channel_indices).labels};
                        EEG = append_to_eeg_comments(EEG, sprintf('auto bad EEG channel labels: %s', strjoin(bad_eeg_channel_labels, ', ')));
                        append_line_to_log(runlog_path, sprintf('Bad EEG (auto): %s', strjoin(bad_eeg_channel_labels, ', ')));
                    end

                    if ~isempty(emu_bad_labels)
                        EEG = append_to_eeg_comments(EEG, sprintf('emulation-style flagged (pre-flat-merge): %s', strjoin(emu_bad_labels, ', ')));
                    end

                catch detection_error
                    EEG = append_to_eeg_comments(EEG, sprintf('auto(emulation) bad channel detection failed: %s', detection_error.message));
                    append_line_to_log(runlog_path, sprintf('Bad channel detect FAILED: %s', detection_error.message));

                    % fall back to flat-only, if available
                    bad_eeg_channel_indices = flat_eeg_channel_indices;
                    bad_eeg_channel_labels  = flat_eeg_channel_labels;
                end

            case "auto_rejchan"
                % YOUR OLD METHOD preserved
                EEG = append_to_eeg_comments(EEG, 'bad channel detection mode: auto_rejchan (prob/kurt/spec z-threshold; EEG only; EOG excluded)');
                append_line_to_log(runlog_path, 'Bad channel detect: auto_rejchan.');

                try
                    if isempty(eeg_channel_indices)
                        error('No EEG channels found (chanlocs.type == "EEG"). Cannot detect bad EEG channels.');
                    end

                    [~, idx_prob] = pop_rejchan(EEG, 'elec', eeg_channel_indices, ...
                        'threshold', config.auto_badchan_z_threshold, 'norm', 'on', 'measure', 'prob');

                    [~, idx_kurt] = pop_rejchan(EEG, 'elec', eeg_channel_indices, ...
                        'threshold', config.auto_badchan_z_threshold, 'norm', 'on', 'measure', 'kurt');

                    [~, idx_spec] = pop_rejchan(EEG, 'elec', eeg_channel_indices, ...
                        'threshold', config.auto_badchan_z_threshold, 'norm', 'on', 'measure', 'spec', ...
                        'freqrange', config.auto_badchan_freqrange_hz);

                    bad_eeg_channel_indices = sort(unique([idx_prob idx_kurt idx_spec flat_eeg_channel_indices]));
                    bad_eeg_channel_indices = setdiff(bad_eeg_channel_indices, eog_channel_indices);

                    if isempty(bad_eeg_channel_indices)
                        EEG = append_to_eeg_comments(EEG, 'auto_rejchan bad channel detection: none flagged (incl. flat check).');
                    else
                        bad_eeg_channel_labels = {EEG.chanlocs(bad_eeg_channel_indices).labels};
                        EEG = append_to_eeg_comments(EEG, sprintf('auto_rejchan bad EEG channel labels: %s', strjoin(bad_eeg_channel_labels, ', ')));
                        append_line_to_log(runlog_path, sprintf('Bad EEG (auto_rejchan): %s', strjoin(bad_eeg_channel_labels, ', ')));
                    end

                catch detection_error
                    EEG = append_to_eeg_comments(EEG, sprintf('auto_rejchan bad channel detection failed: %s', detection_error.message));
                    bad_eeg_channel_indices = flat_eeg_channel_indices;
                    bad_eeg_channel_labels  = flat_eeg_channel_labels;
                end

            case "manual"
                EEG = append_to_eeg_comments(EEG, 'bad channel detection mode: manual (EEG only; EOG excluded)');
                pop_eegplot(EEG, 1, 0, 1);

                manual_indices = input('Enter bad EEG channel indices [] (do NOT include EOG): ');
                if isempty(manual_indices)
                    EEG = append_to_eeg_comments(EEG, 'manual bad channel selection: none entered.');
                    bad_eeg_channel_indices = [];
                    bad_eeg_channel_labels  = {};
                else
                    manual_indices = sort(unique(manual_indices));
                    manual_indices = setdiff(manual_indices, eog_channel_indices); % safety

                    bad_eeg_channel_indices = sort(unique([manual_indices(:)' flat_eeg_channel_indices(:)']));
                    bad_eeg_channel_labels  = {EEG.chanlocs(bad_eeg_channel_indices).labels};

                    EEG = append_to_eeg_comments(EEG, sprintf('manual bad EEG channel labels: %s', strjoin(bad_eeg_channel_labels, ', ')));
                    append_line_to_log(runlog_path, sprintf('Bad EEG (manual): %s', strjoin(bad_eeg_channel_labels, ', ')));
                end

            otherwise
                EEG = append_to_eeg_comments(EEG, 'bad channel detection mode: off');
                bad_eeg_channel_indices = [];
                bad_eeg_channel_labels  = {};
        end

        %% STORE BAD CHANNELS IN EEG.CHANINFO.BAD (and keep in comments)
        if ~isfield(EEG, 'chaninfo') || isempty(EEG.chaninfo)
            EEG.chaninfo = struct();
        end
        EEG.chaninfo.bad = bad_eeg_channel_labels;

        %% INTERPOLATE BAD CHANNELS BEFORE ICA (DEFAULT, PREREGISTERED)
        if config.interpolate_bad_channels_before_ica && ~isempty(bad_eeg_channel_indices)

            EEG = append_to_eeg_comments(EEG, sprintf('interpolating bad EEG channels BEFORE ICA (%s): %s', ...
                config.interp_method, strjoin(bad_eeg_channel_labels, ', ')));
            append_line_to_log(runlog_path, sprintf('Interpolating: %s', strjoin(bad_eeg_channel_labels, ', ')));

            EEG = pop_interp(EEG, bad_eeg_channel_indices, config.interp_method);
            EEG = eeg_checkset(EEG);

            interpolated_channel_indices = bad_eeg_channel_indices;

            if ~isfield(EEG, 'etc') || isempty(EEG.etc)
                EEG.etc = struct();
            end
            EEG.etc.interpolated_channel_indices = interpolated_channel_indices;
            EEG.etc.interpolated_channel_labels  = bad_eeg_channel_labels;

            if config.save_intermediate_steps
                EEG = pop_saveset(EEG, 'filename', [run_base_name '_interp_before_ica.set'], 'filepath', subject_out_dir_until);
            end
        else
            if ~isfield(EEG, 'etc') || isempty(EEG.etc)
                EEG.etc = struct();
            end
            EEG.etc.interpolated_channel_indices = [];
            EEG.etc.interpolated_channel_labels  = {};

            if config.interpolate_bad_channels_before_ica
                EEG = append_to_eeg_comments(EEG, 'no interpolation performed (no bad EEG channels flagged).');
            else
                EEG = append_to_eeg_comments(EEG, 'interpolation BEFORE ICA disabled by config. (must be done after ICA if needed)');
            end
        end

        %% FILTERING (FFT) - EEG+EOG ONLY
        filter_channel_indices = sort(unique([eeg_channel_indices eog_channel_indices]));
        EEG = apply_filter_to_subset_only(EEG, filter_channel_indices, config.highpass_hz, [], 'high-pass');
        EEG = append_to_eeg_comments(EEG, sprintf('high-pass filter applied to EEG+EOG (FFT): %.4f Hz', config.highpass_hz));
        append_line_to_log(runlog_path, sprintf('High-pass: %.4f Hz', config.highpass_hz));

        %% LINE NOISE REMOVAL (EEG+EOG ONLY)
        switch config.line_noise_method
            case "prep_cleanlinenoise"
                [EEG, did_apply] = apply_prep_cleanlinenoise_to_subset(EEG, filter_channel_indices, config.line_noise_frequencies_hz);
                line_noise_applied = did_apply;

                if did_apply
                    EEG = append_to_eeg_comments(EEG, sprintf('line noise removed (PREP cleanlinenoise/cleanLineNoise) on EEG+EOG. freqs=%s', ...
                        mat2str(config.line_noise_frequencies_hz)));
                    append_line_to_log(runlog_path, 'Line noise removed: PREP cleanlinenoise.');
                else
                    EEG = append_to_eeg_comments(EEG, 'PREP cleanlinenoise requested but not available. (no line noise removal applied)');
                    append_line_to_log(runlog_path, 'Line noise removal FAILED/NA: PREP cleanlinenoise not available.');
                end

            case "pop_cleanline"
                [EEG, did_apply] = apply_pop_cleanline_to_subset(EEG, filter_channel_indices, config);
                line_noise_applied = did_apply;

                if did_apply
                    EEG = append_to_eeg_comments(EEG, sprintf('line noise removed (pop_cleanline) on EEG+EOG. freqs=%s', ...
                        mat2str(config.line_noise_frequencies_hz)));
                    append_line_to_log(runlog_path, 'Line noise removed: pop_cleanline.');
                else
                    EEG = append_to_eeg_comments(EEG, 'pop_cleanline requested but not available. (no line noise removal applied)');
                    append_line_to_log(runlog_path, 'Line noise removal FAILED/NA: pop_cleanline not available.');
                end

            otherwise
                EEG = append_to_eeg_comments(EEG, 'line noise removal skipped (config.line_noise_method="off").');
                line_noise_applied = false;
                append_line_to_log(runlog_path, 'Line noise removal skipped.');
        end

        %% LOW-PASS (FFT) - EEG+EOG ONLY
        EEG = apply_filter_to_subset_only(EEG, filter_channel_indices, [], config.lowpass_hz, 'low-pass');
        EEG = append_to_eeg_comments(EEG, sprintf('low-pass filter applied to EEG+EOG (FFT): %.2f Hz', config.lowpass_hz));
        append_line_to_log(runlog_path, sprintf('Low-pass: %.2f Hz', config.lowpass_hz));

        if config.save_intermediate_steps
            EEG = pop_saveset(EEG, 'filename', [run_base_name '_filtered_lineclean.set'], 'filepath', subject_out_dir_until);
        end

        %% SAVE PRE-ICA ANALYSIS DATASET
        preica_set_name = [run_base_name '_preica.set'];
        EEG = pop_saveset(EEG, 'filename', preica_set_name, 'filepath', subject_out_dir_until);
        EEG = append_to_eeg_comments(EEG, sprintf('saved pre-ica dataset: %s', fullfile(subject_out_dir_until, preica_set_name)));
        append_line_to_log(runlog_path, ['Saved pre-ICA: ' fullfile(subject_out_dir_until, preica_set_name)]);

        %% CREATE ICA-PREP DATASET (separate file)
        ica_prep_eeg = EEG;

        ica_prep_eeg = apply_filter_to_subset_only(ica_prep_eeg, filter_channel_indices, config.ica_prep_highpass_hz, [], 'ica-prep high-pass');
        ica_prep_eeg = append_to_eeg_comments(ica_prep_eeg, sprintf('ica-prep: high-pass applied to EEG+EOG (FFT): %.2f Hz', config.ica_prep_highpass_hz));

        if config.ica_prep_use_regepochs
            ica_prep_eeg = eeg_regepochs(ica_prep_eeg, ...
                'recurrence', config.ica_prep_regepoch_length_sec, ...
                'limits', [0 config.ica_prep_regepoch_length_sec]);
            ica_prep_eeg = eeg_checkset(ica_prep_eeg);
            ica_prep_eeg = append_to_eeg_comments(ica_prep_eeg, sprintf('ica-prep: eeg_regepochs applied (epoch length: %.2f sec)', config.ica_prep_regepoch_length_sec));
        end

        %% ICA-PREP: ROBUST MAD VARIANCE REJECTION (EEG only; excludes EOG)
        if config.ica_prep_use_mad_epoch_rejection

            % derive EEG-only indices (do NOT use EOG for this criterion)
            ica_eeg_idx = find(strcmpi({ica_prep_eeg.chanlocs.type}, 'EEG'));

            if isempty(ica_eeg_idx) || ica_prep_eeg.trials < 3
                ica_prep_eeg = append_to_eeg_comments(ica_prep_eeg, ...
                    'ica-prep: MAD epoch rejection skipped (no EEG channels or <3 epochs).');
                append_line_to_log(runlog_path, 'ica-prep: MAD epoch rejection skipped (no EEG or <3 epochs).');
            else
                [ica_prep_eeg, mad_info] = reject_ica_prep_epochs_by_mad_variance( ...
                    ica_prep_eeg, ica_eeg_idx, config.ica_prep_mad_z_threshold, config.ica_prep_mad_use_logvar);

                if mad_info.did_apply
                    ica_prep_eeg = append_to_eeg_comments(ica_prep_eeg, sprintf( ...
                        'ica-prep: MAD variance rejection applied (EEG-only). z_thr=%.2f | rejected %d/%d epochs (%.2f%%).', ...
                        mad_info.z_thresh, mad_info.n_rejected, mad_info.n_before, 100*mad_info.n_rejected/mad_info.n_before));

                    append_line_to_log(runlog_path, sprintf( ...
                        'ica-prep: MAD variance rejection z_thr=%.2f rejected %d/%d (%.2f%%).', ...
                        mad_info.z_thresh, mad_info.n_rejected, mad_info.n_before, 100*mad_info.n_rejected/mad_info.n_before));
                else
                    ica_prep_eeg = append_to_eeg_comments(ica_prep_eeg, ...
                        'ica-prep: MAD epoch rejection found no outlier epochs.');
                end
            end
        end

        if config.ica_prep_use_jointprob_rejection
            % IMPORTANT: pop_jointprob can crash on flat/invalid channels.
            % CHANGED: apply only on EEG+EOG (never AUX), and only on valid channels.
            [ica_prep_eeg, did_jointprob] = apply_jointprob_safely(ica_prep_eeg, ...
                config.ica_prep_jointprob_local, config.ica_prep_jointprob_global);

            if did_jointprob
                ica_prep_eeg = append_to_eeg_comments(ica_prep_eeg, sprintf('ica-prep: pop_jointprob applied (local=%d, global=%d)', ...
                    config.ica_prep_jointprob_local, config.ica_prep_jointprob_global));
            else
                ica_prep_eeg = append_to_eeg_comments(ica_prep_eeg, 'ica-prep: pop_jointprob skipped (insufficient valid channels or numerical issue).');
            end
        end

        forica_set_name = [run_base_name '_forica.set'];
        ica_prep_eeg = pop_saveset(ica_prep_eeg, 'filename', forica_set_name, 'filepath', subject_out_dir_for_ica);
        ica_prep_eeg = append_to_eeg_comments(ica_prep_eeg, sprintf('saved ica-prep dataset: %s', fullfile(subject_out_dir_for_ica, forica_set_name)));
        append_line_to_log(runlog_path, ['Saved for-ICA: ' fullfile(subject_out_dir_for_ica, forica_set_name)]);

        %% RUN RECORD
        run_record = struct();
        run_record.subject_id = subject_id;
        run_record.run_base_name = run_base_name;
        run_record.status = run_status;

        run_record.num_channels_total = EEG.nbchan;
        run_record.num_eeg_channels   = numel(eeg_channel_indices);
        run_record.num_eog_channels   = numel(eog_channel_indices);
        run_record.num_aux_channels   = numel(aux_channel_indices);

        run_record.crop_to_task_markers  = config.crop_to_task_markers;
        run_record.crop_start_marker     = string(config.crop_start_marker);
        run_record.crop_end_marker       = string(config.crop_end_marker);
        run_record.crop_padding_sec      = config.crop_padding_sec;

        run_record.downsample_hz = config.downsample_hz;

        run_record.flat_eeg_channel_indices = flat_eeg_channel_indices;
        run_record.flat_eeg_channel_labels  = flat_eeg_channel_labels;
        run_record.num_flat_eeg_channels    = numel(flat_eeg_channel_indices);

        run_record.bad_eeg_channel_indices = bad_eeg_channel_indices;
        run_record.bad_eeg_channel_labels  = bad_eeg_channel_labels;
        run_record.num_bad_eeg_channels    = numel(bad_eeg_channel_indices);

        run_record.interpolated_channel_indices = interpolated_channel_indices;
        run_record.num_interpolated_channels    = numel(interpolated_channel_indices);

        run_record.highpass_hz = config.highpass_hz;
        run_record.lowpass_hz  = config.lowpass_hz;
        run_record.ica_prep_highpass_hz = config.ica_prep_highpass_hz;

        run_record.line_noise_method  = string(config.line_noise_method);
        run_record.line_noise_applied = line_noise_applied;

        run_records = [run_records; run_record]; %#ok<AGROW>

        fprintf('DONE: %s | %s\n', subject_id, run_base_name);
        append_line_to_log(runlog_path, sprintf('--- RUN DONE: %s | %s ---', subject_id, run_base_name));

    end % file loop
end % subject loop

append_line_to_log(runlog_path, '=== END 02_until_ica main loop ===');

%% SAVE RUN RECORDS TO ./logs
timestamp_str = datestr(now, 'yyyymmdd_HHMMSS');
run_records_mat_path = fullfile(logs_dir, ['run_records_02_until_ica_' timestamp_str '.mat']);
save(run_records_mat_path, 'run_records', 'config');
append_line_to_log(runlog_path, ['Saved run_records MAT: ' run_records_mat_path]);

%% WRITE COMPOSITE SUMMARY REPORT
report_path = fullfile(OUTPUT_DIR_REPORTS, 'summary_02_until_ica.txt');
write_composite_summary_report(report_path, run_records, config);

fprintf('\nComposite report written to:\n%s\n', report_path);
fprintf('Run records saved to:\n%s\n', run_records_mat_path);

append_line_to_log(runlog_path, ['Composite report: ' report_path]);
append_line_to_log(runlog_path, '=== FINISHED 02_until_ica ===');

%% =================
%  LOCAL FUNCTIONS
%  =================
function EEG = append_to_eeg_comments(EEG, message_text)
    time_stamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    line_text = sprintf('[%s] %s', time_stamp, message_text);

    if ~isfield(EEG, 'comments') || isempty(EEG.comments)
        EEG.comments = line_text;
    else
        EEG.comments = sprintf('%s\n%s', EEG.comments, line_text);
    end
end

function append_line_to_log(log_path, message_text)
    try
        fid = fopen(log_path, 'a');
        if fid ~= -1
            fprintf(fid, '[%s] %s\n', datestr(now,'yyyy-mm-dd HH:MM:SS'), message_text);
            fclose(fid);
        else
            warning('Could not open log file for writing: %s', log_path);
        end
    catch
        warning('Failed writing to log file: %s', log_path);
    end
end

function latency = find_first_event_latency(EEG, event_type)
    latency = [];
    if ~isfield(EEG, 'event') || isempty(EEG.event)
        return;
    end

    types = {EEG.event.type};
    idx = find(strcmp(types, event_type), 1, 'first');
    if isempty(idx)
        return;
    end

    latency = EEG.event(idx).latency;
end

function EEG = ensure_channel_types(EEG, config)
    % Default all to EEG, then override by label lists.

    if ~isfield(EEG, 'chanlocs') || isempty(EEG.chanlocs)
        return;
    end

    labels = {EEG.chanlocs.labels};

    % default type
    for k = 1:numel(EEG.chanlocs)
        EEG.chanlocs(k).type = 'EEG';
    end

    % set EOG
    for i = 1:numel(config.eog_channel_labels)
        idx = find(strcmpi(labels, config.eog_channel_labels{i}));
        for j = 1:numel(idx)
            EEG.chanlocs(idx(j)).type = 'EOG';
        end
    end

    % SCR
    for i = 1:numel(config.scr_channel_labels)
        idx = find(strcmpi(labels, config.scr_channel_labels{i}));
        for j = 1:numel(idx)
            EEG.chanlocs(idx(j)).type = 'SCR';
        end
    end

    % Startle
    for i = 1:numel(config.startle_channel_labels)
        idx = find(strcmpi(labels, config.startle_channel_labels{i}));
        for j = 1:numel(idx)
            EEG.chanlocs(idx(j)).type = 'Startle';
        end
    end

    % EKG
    for i = 1:numel(config.ekg_channel_labels)
        idx = find(strcmpi(labels, config.ekg_channel_labels{i}));
        for j = 1:numel(idx)
            EEG.chanlocs(idx(j)).type = 'EKG';
        end
    end

    EEG = eeg_checkset(EEG);
end

function [flat_indices, flat_labels] = find_flat_or_invalid_channels(EEG, candidate_indices, variance_epsilon)
    % Flags channels as flat/invalid if:
    %   - any NaN/Inf values exist, OR
    %   - variance <= variance_epsilon (default epsilon=0 => strictly var==0)
    %
    % Returns absolute channel indices and labels.

    flat_indices = [];
    flat_labels  = {};

    if isempty(candidate_indices)
        return;
    end

    data_2d = double(EEG.data(candidate_indices, :));

    has_invalid = any(~isfinite(data_2d), 2);
    chan_var    = var(data_2d, 0, 2);

    is_flat = (chan_var <= variance_epsilon) | has_invalid;

    flat_indices = candidate_indices(is_flat);
    if ~isempty(flat_indices)
        flat_labels = {EEG.chanlocs(flat_indices).labels};
    end
end

function [bad_indices, bad_labels] = detect_bad_channels_emulation_style(EEG, eeg_indices, flatline_sec, corr_threshold)
    % Emulation-style: use clean_rawdata to FLAG channels (do not keep its output),
    % using flatline + channel correlation threshold. Only EEG channels are considered.

    bad_indices = [];
    bad_labels  = {};

    if isempty(eeg_indices)
        return;
    end

    if exist('clean_rawdata', 'file') ~= 2
        % Plugin missing -> return empty (flat/invalid is handled separately)
        return;
    end

    EEG_tmp = EEG;
    EEG_tmp = pop_select(EEG_tmp, 'channel', eeg_indices);
    EEG_tmp = eeg_checkset(EEG_tmp);

    labels_before = {EEG_tmp.chanlocs.labels};

    % clean_rawdata signature:
    % clean_rawdata(EEG, flatline, highpass, channelcorr, linenoise, burst, window)
    EEG_clean = clean_rawdata(EEG_tmp, flatline_sec, -1, corr_threshold, -1, -1, -1);
    EEG_clean = eeg_checkset(EEG_clean);

    labels_after = {EEG_clean.chanlocs.labels};
    removed_labels = setdiff(labels_before, labels_after, 'stable');

    if isempty(removed_labels)
        return;
    end

    all_labels = {EEG.chanlocs.labels};
    for i = 1:numel(removed_labels)
        idx = find(strcmpi(all_labels, removed_labels{i}), 1, 'first');
        if ~isempty(idx)
            bad_indices(end+1) = idx; %#ok<AGROW>
        end
    end

    bad_indices = unique(bad_indices);
    bad_labels  = {EEG.chanlocs(bad_indices).labels};
end

function EEG = apply_filter_to_subset_only(EEG, subset_indices, locutoff_hz, hicutoff_hz, label_for_log)

    if isempty(subset_indices)
        return;
    end

    original_data = EEG.data;

    EEG = pop_eegfiltnew(EEG, 'locutoff', locutoff_hz, 'hicutoff', hicutoff_hz, 'usefftfilt', 1);
    EEG = eeg_checkset(EEG);

    non_subset = setdiff(1:EEG.nbchan, subset_indices);
    EEG.data(non_subset, :) = original_data(non_subset, :);

    EEG = eeg_checkset(EEG);

    if nargin >= 5 && ~isempty(label_for_log)
        EEG = append_to_eeg_comments(EEG, sprintf('%s: applied only to channels %s', label_for_log, mat2str(subset_indices)));
    end
end

function [EEG, did_apply] = apply_prep_cleanlinenoise_to_subset(EEG, subset_indices, linefreqs_hz)
    % PREP pipeline typically provides cleanLineNoise or cleanlinenoise functions.
    % We try both, with safe behavior and no crashing if unavailable.
    did_apply = false;

    if isempty(subset_indices)
        return;
    end

    original_data = EEG.data;

    try
        if exist('cleanlinenoise','file') == 2
            EEG_tmp = EEG;
            EEG_tmp.data = EEG.data(subset_indices, :);

            try
                EEG_tmp = cleanlinenoise(EEG_tmp, linefreqs_hz);
            catch
                EEG_tmp = cleanlinenoise(EEG_tmp);
            end

            EEG.data(subset_indices, :) = EEG_tmp.data;
            did_apply = true;

        elseif exist('cleanLineNoise','file') == 2
            EEG_tmp = EEG;
            EEG_tmp.data = EEG.data(subset_indices, :);

            try
                EEG_tmp = cleanLineNoise(EEG_tmp);
            catch
                EEG_tmp = cleanLineNoise(EEG_tmp, linefreqs_hz);
            end

            EEG.data(subset_indices, :) = EEG_tmp.data;
            did_apply = true;
        end

    catch
        did_apply = false;
        EEG.data = original_data;
    end

    EEG = eeg_checkset(EEG);
end

function [EEG, did_apply] = apply_pop_cleanline_to_subset(EEG, subset_indices, config)
    did_apply = false;

    if isempty(subset_indices)
        return;
    end

    if exist('pop_cleanline','file') ~= 2
        return;
    end

    original_data = EEG.data;

    try
        EEG_tmp = EEG;
        EEG_tmp.data = EEG.data(subset_indices, :);

        EEG_tmp = pop_cleanline(EEG_tmp, ...
            'bandwidth',        config.pop_cleanline_bandwidth_hz, ...
            'chanlist',         1:size(EEG_tmp.data,1), ...
            'computepower',     0, ...
            'linefreqs',        config.line_noise_frequencies_hz, ...
            'normSpectrum',     0, ...
            'p',                config.pop_cleanline_p_value, ...
            'pad',              2, ...
            'plotfigures',      0, ...
            'scanforlines',     0, ...
            'sigtype',          'Channels', ...
            'taperbandwidth',   2, ...
            'tau',              100, ...
            'verb',             double(config.pop_cleanline_verbose), ...
            'winsize',          4, ...
            'winstep',          1);

        EEG.data(subset_indices, :) = EEG_tmp.data;
        did_apply = true;

    catch
        did_apply = false;
        EEG.data = original_data;
    end

    EEG = eeg_checkset(EEG);
end

function [EEG, did_apply] = apply_jointprob_safely(EEG, local_threshold, global_threshold)
    % pop_jointprob may fail if any channels are flat/zero/NaN.
    % CHANGED: apply ONLY on EEG+EOG channels (never AUX), and only those with
    % finite, non-zero variance.

    did_apply = false;

    if EEG.nbchan < 2
        return;
    end

    try
        % Restrict to EEG+EOG only when types exist
        if isfield(EEG, 'chanlocs') && isfield(EEG.chanlocs, 'type')
            types = lower(string({EEG.chanlocs.type}));
            cand_mask = (types == "eeg") | (types == "eog");
            cand_idx  = find(cand_mask);
        else
            cand_idx = 1:EEG.nbchan; % fallback
        end

        if numel(cand_idx) < 2
            return;
        end

        data_2d = double(reshape(EEG.data(cand_idx, :, :), numel(cand_idx), []));
        chan_var = var(data_2d, 0, 2);

        valid_mask = isfinite(chan_var) & (chan_var > 0);
        valid_idx_local = find(valid_mask);

        if numel(valid_idx_local) < 2
            return;
        end

        valid_idx = cand_idx(valid_idx_local);
        invalid_idx = setdiff(cand_idx, valid_idx);

        if ~isempty(invalid_idx)
            invalid_labels = {EEG.chanlocs(invalid_idx).labels};
            EEG = append_to_eeg_comments(EEG, sprintf('ica-prep: excluding flat/invalid EEG/EOG from jointprob: %s', strjoin(invalid_labels, ', ')));
        end

        EEG = pop_jointprob(EEG, 1, valid_idx, local_threshold, global_threshold, 0, 1, 0, [], 0);
        EEG = eeg_checkset(EEG);

        did_apply = true;

    catch jointprob_error
        EEG = append_to_eeg_comments(EEG, sprintf('ica-prep: pop_jointprob failed: %s', jointprob_error.message));
        did_apply = false;
    end
end

function write_composite_summary_report(report_path, run_records, config)

    fid = fopen(report_path, 'w');
    if fid == -1
        warning('Could not write report: %s', report_path);
        return;
    end

    fprintf(fid, 'SUMMARY REPORT - PREPROCESSING UNTIL ICA PREP\n');
    fprintf(fid, 'Generated: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(fid, 'Edits: Saskia Wilken (Jan 2026)\n\n');

    fprintf(fid, 'CONFIG SNAPSHOT\n');
    fprintf(fid, '  crop_to_task_markers: %d (%s..%s)\n', config.crop_to_task_markers, config.crop_start_marker, config.crop_end_marker);
    fprintf(fid, '  crop_padding_sec: [%g %g]\n', config.crop_padding_sec(1), config.crop_padding_sec(2));
    fprintf(fid, '  downsample_hz: %d\n', config.downsample_hz);
    fprintf(fid, '  detect_bad_channels_mode: %s\n', string(config.detect_bad_channels_mode));
    fprintf(fid, '  flag_flat_channels_as_bad: %d\n', config.flag_flat_channels_as_bad);
    fprintf(fid, '  interpolate_bad_channels_before_ica: %d\n', config.interpolate_bad_channels_before_ica);
    fprintf(fid, '  highpass_hz: %.4f\n', config.highpass_hz);
    fprintf(fid, '  lowpass_hz: %.2f\n', config.lowpass_hz);
    fprintf(fid, '  ica_prep_highpass_hz: %.2f\n', config.ica_prep_highpass_hz);
    fprintf(fid, '  line_noise_method: %s\n', string(config.line_noise_method));
    fprintf(fid, '  line_noise_frequencies_hz: %s\n', mat2str(config.line_noise_frequencies_hz));
    fprintf(fid, '\n');

    if isempty(run_records)
        fprintf(fid, 'No runs processed.\n');
        fclose(fid);
        return;
    end

    % only include processed runs for channel stats
    is_processed = arrayfun(@(r) isfield(r,'status') && string(r.status) == "processed", run_records);
    processed_records = run_records(is_processed);

    fprintf(fid, 'RUN COUNTS\n');
    fprintf(fid, '  total run records: %d\n', numel(run_records));
    fprintf(fid, '  processed: %d\n', sum(is_processed));
    fprintf(fid, '  skipped: %d\n\n', numel(run_records) - sum(is_processed));

    fprintf(fid, 'PER-RUN DETAILS\n');
    for k = 1:numel(run_records)
        r = run_records(k);

        fprintf(fid, '\n  subject: %s\n', r.subject_id);
        fprintf(fid, '  run: %s\n', r.run_base_name);

        if isfield(r,'status')
            fprintf(fid, '  status: %s\n', string(r.status));
        end

        if isfield(r,'num_channels_total')
            fprintf(fid, '  channels total: %d (EEG=%d, EOG=%d, AUX=%d)\n', ...
                r.num_channels_total, r.num_eeg_channels, r.num_eog_channels, r.num_aux_channels);
        end

        if isfield(r,'downsample_hz')
            fprintf(fid, '  downsample_hz: %d\n', r.downsample_hz);
        end

        if isfield(r,'num_flat_eeg_channels')
            fprintf(fid, '  flat EEG channels: %d\n', r.num_flat_eeg_channels);
            if isfield(r,'flat_eeg_channel_labels') && ~isempty(r.flat_eeg_channel_labels)
                fprintf(fid, '  flat EEG labels: %s\n', strjoin(r.flat_eeg_channel_labels, ', '));
            end
        end

        if isfield(r,'num_bad_eeg_channels')
            fprintf(fid, '  bad EEG channels: %d\n', r.num_bad_eeg_channels);
            if isfield(r,'bad_eeg_channel_labels') && ~isempty(r.bad_eeg_channel_labels)
                fprintf(fid, '  bad EEG labels: %s\n', strjoin(r.bad_eeg_channel_labels, ', '));
            end
        end

        if isfield(r,'num_interpolated_channels')
            fprintf(fid, '  interpolated channels before ICA: %d\n', r.num_interpolated_channels);
        end

        if isfield(r,'line_noise_method')
            fprintf(fid, '  line_noise_method: %s | applied: %d\n', r.line_noise_method, r.line_noise_applied);
        end
    end

    if isempty(processed_records)
        fprintf(fid, '\n\nNo processed runs available for aggregates.\n');
        fclose(fid);
        return;
    end

    num_bad  = arrayfun(@(r) r.num_bad_eeg_channels, processed_records);
    num_int  = arrayfun(@(r) r.num_interpolated_channels, processed_records);
    num_flat = arrayfun(@(r) r.num_flat_eeg_channels, processed_records);

    fprintf(fid, '\n\nAGGREGATES ACROSS PROCESSED RUNS\n');

    fprintf(fid, 'Flat EEG channels flagged per run:\n');
    fprintf(fid, '  mean: %.2f | sd: %.2f | range: %d - %d\n', mean(num_flat), std(num_flat), min(num_flat), max(num_flat));

    fprintf(fid, 'Bad EEG channels flagged per run (includes flat/invalid):\n');
    fprintf(fid, '  mean: %.2f | sd: %.2f | range: %d - %d\n', mean(num_bad), std(num_bad), min(num_bad), max(num_bad));

    fprintf(fid, 'Interpolated channels per run:\n');
    fprintf(fid, '  mean: %.2f | sd: %.2f | range: %d - %d\n', mean(num_int), std(num_int), min(num_int), max(num_int));

    fclose(fid);
end

function [EEG, info] = reject_ica_prep_epochs_by_mad_variance(EEG, chan_idx, z_thresh, use_logvar)
% Reject ICA-training epochs based on robust MAD-z of per-epoch variance.
% - Computes variance per epoch per channel
% - Optionally uses log-variance for robustness
% - For each channel, computes robust z across epochs:
%       z = (x - median(x)) / (1.4826 * MAD(x) + eps)
% - Marks an epoch bad if ANY EEG channel exceeds z_thresh
%
% Applies only to epoched EEGLAB data (EEG.trials > 1).

    info = struct();
    info.did_apply   = false;
    info.z_thresh    = z_thresh;
    info.n_before    = EEG.trials;
    info.n_rejected  = 0;
    info.rejected_epochs = [];

    if EEG.trials < 2 || isempty(chan_idx)
        return;
    end

    % data dims: channels x points x epochs
    X = double(EEG.data(chan_idx, :, :));
    nChan  = size(X, 1);
    nEpoch = size(X, 3);

    % per-epoch variance per channel
    % (variance across timepoints within epoch)
    v = zeros(nChan, nEpoch);
    for e = 1:nEpoch
        Xe = X(:,:,e);
        v(:,e) = var(Xe, 0, 2); % per channel
    end

    if use_logvar
        v = log10(v + eps);
    end

    % robust z per channel across epochs
    z = zeros(size(v));
    for c = 1:nChan
        xc = v(c,:);
        med = median(xc);
        madv = median(abs(xc - med));  % MAD
        denom = (1.4826 * madv) + eps; % consistent with SD for normal
        z(c,:) = (xc - med) ./ denom;
    end

    % CHANGED: use abs(z) so both unusually high AND unusually low variance epochs can be rejected
    bad_epoch_mask = any(abs(z) > z_thresh, 1);
    bad_epochs = find(bad_epoch_mask);

    if isempty(bad_epochs)
        return;
    end

    % remove epochs
    EEG = pop_rejepoch(EEG, bad_epoch_mask, 0);
    EEG = eeg_checkset(EEG);

    % store info for transparency
    if ~isfield(EEG, 'etc') || isempty(EEG.etc)
        EEG.etc = struct();
    end
    EEG.etc.ica_prep_mad_rejection = struct();
    EEG.etc.ica_prep_mad_rejection.z_thresh = z_thresh;
    EEG.etc.ica_prep_mad_rejection.use_logvar = use_logvar;
    EEG.etc.ica_prep_mad_rejection.rejected_epochs = bad_epochs;

    info.did_apply = true;
    info.n_rejected = numel(bad_epochs);
    info.rejected_epochs = bad_epochs;
end

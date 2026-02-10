function run_eeg_pipeline(varargin)
% RUN_EEG_PIPELINE Saskia Wilken / Saskia Wilken / DEZ 2025 driver for PROOF EEG preprocessing (PC / server / HPC).
%
% Goals / conventions:
%   - One config (cfg) here; step functions receive cfg + paths + helpers.
%   - One subject at a time (serial) or parallel (parfor) depending on cfg.env.mode / cfg.parallel.enable.
%   - One runlog per subject in: <ROOT>/logs/runlog_pipeline/
%       - Always echoed to command line + written to file
%       - If subject fails: log file renamed to include suffix "_ERR"
%   - Global overwrite behavior:
%       - cfg.io.overwrite_mode = "delete" (default): delete existing outputs for that step + regenerate
%       - cfg.io.overwrite_mode = "skip": if output exists, skip step
%       - Can be overridden per-step (cfg.steps.<step>.overwrite_mode)
%
% Step function signature:
%   step_out = proof_eeg_cf_prepXX_step(subj_id, cfg, paths, helpers)
%
% MATLAB R2023a 

%% HOW TO USE
%
% Expects outputs form the 01_BIDS_formatting function

%% ========================================================================
%  CONSTANTS 
% ========================================================================
DEFAULT_BIDS_FOLDER_NAME   = 'BIDS_RTGMN_Baseline';
LOG_SUBDIR_RUNLOG          = fullfile('logs', 'runlog_pipeline');

%% ========================================================================
%  CONFIG: ENVIRONMENT / EXECUTION
% ========================================================================
cfg = struct();

cfg.constants = struct();
cfg.constants.valid_sub_id_regex = '^\d{3}$';   % exactly 3 digits

cfg.constants.log_prefix_master  = 'run_eeg_pipeline';
cfg.constants.log_prefix_subject = 'sub';

cfg.constants.datestr_master  = 'yyyymmdd_HHMMSS';
cfg.constants.datestr_subject = 'yyyymmdd_HHMMSS_FFF';

% Root = folder where THIS file lives (portable across PC/server/HPC)
cfg.this_file = mfilename('fullpath');
cfg.root_dir  = fileparts(cfg.this_file);

% Environment mode toggles behavior (paths/parallel defaults, etc.)
%   "pc"     -> typically serial (or modest parallel), interactive-friendly
%   "server" -> parallel ok
%   "hpc"    -> parallel + SLURM-aware worker count
cfg.env = struct();

% --- Auto-detect environment (can be overridden by env var PROOF_ENV_MODE)
cfg.env.mode = detect_env_mode();  % "pc" | "server" | "hpc"

% Optional: keep info for logging
cfg.env.is_slurm = ~isempty(getenv('SLURM_JOB_ID'));
cfg.env.slurm_job_id = string(getenv_or_empty('SLURM_JOB_ID'));
cfg.env.slurm_cluster = string(getenv_or_empty('SLURM_CLUSTER_NAME'));

% PC only interactive clean start (safe: does nothing on HPC / batch)
if cfg.env.mode == "pc" && usejava('desktop')
    clc;
    evalin('base','clearvars');  % clears BASE workspace only (not function vars)
    % close all;
end

%% ========================================================================
%  CONFIG: IO / PATHS
% ========================================================================
cfg.paths = struct();
% Script root stays script-root (portable)

% --- Select data layout profile (THIS is the only thing you change per setup)
% "pc_now" | "pc_shared" | "hpc_hummel"
% --- Default profile depends on env.mode; can be overridden by env var PROOF_PROFILE
cfg.paths.profile = default_profile_for_mode(cfg.env.mode);

prof_env = string(getenv_or_empty('BASELINE_PROFILE'));
if strlength(prof_env) > 0
    cfg.paths.profile = prof_env;
end

% Resolve RAW + DERIVATIVES roots by profile (unless overridden below)
switch cfg.paths.profile

    case "pc_now"
        cfg.paths.bids_root = fullfile('K:\Wilken_Arbeitsordner\Raw_data', DEFAULT_BIDS_FOLDER_NAME);
        cfg.paths.out_root  = fullfile('K:\Wilken_Arbeitsordner\Preprocessed_data\Aperiodic_Signal\eeg');

    case "pc_shared"
        cfg.paths.bids_root = fullfile('Z:\pb\KLPSY1\KLPSY1-RTG\MATRICS\raw');
        cfg.paths.out_root  = fullfile('Z:\pb\KLPSY1\KLPSY1-RTG\MATRICS\derivatives/preprocessed_eeg_baseline');

    case "hpc_hummel"
        cfg.paths.bids_root = fullfile('/beegfs/u/bbf7366/raw', DEFAULT_BIDS_FOLDER_NAME);
        cfg.paths.out_root  = fullfile('/beegfs/u/bbf7366/derivatives/preprocessed_eeg/preprocessed_eeg_baseline');

    otherwise
        error('Unknown cfg.paths.profile="%s".', string(cfg.paths.profile));
end

% --- Absolute path overrides (highest priority)
bids_env = string(getenv_or_empty('BASELINE_BIDS_ROOT'));
out_env  = string(getenv_or_empty('BASELINE_OUT_ROOT'));
if strlength(bids_env) > 0
    cfg.paths.bids_root = bids_env;
end
if strlength(out_env) > 0
    cfg.paths.out_root = out_env;
end


% Toolbox locations (PC vs HPC)
cfg.toolboxes = struct();

cfg.toolboxes.path_eeglab_pc  = "K:\Wilken_Arbeitsordner\MATLAB\eeglab_current\eeglab2025.1.0";
cfg.toolboxes.path_eeglab_hpc = "/beegfs/u/bbf7366/toolboxes/eeglab_current/eeglab2025.1.0";

cfg.toolboxes.path_faster_pc  = "K:\Wilken_Arbeitsordner\MATLAB\FASTER";
cfg.toolboxes.path_faster_hpc = "/beegfs/u/bbf7366/toolboxes/FASTER";

cfg.toolboxes.use_genpath = true;

% EEGLAB startup behavior
cfg.toolboxes.eeglab = struct();
cfg.toolboxes.eeglab.no_update_check_on_hpc = true;
cfg.toolboxes.eeglab.nogui = true;

% Logging stays relative to *script root*
cfg.paths.logs_dir = fullfile(cfg.root_dir, LOG_SUBDIR_RUNLOG);

% Global overwrite behavior
cfg.io = struct();
cfg.io.overwrite_mode = "delete";  % "delete" | "skip"
cfg.io.dry_run = false;

%% ========================================================================
%  CONFIG: SUBJECT HANDLING
% ========================================================================
cfg.subjects = struct();
cfg.subjects.list              = []; % empty = discover all from bids_root/sub-*

%% ========================================================================
%  CONFIG: PARALLELIZATION
% ========================================================================
cfg.parallel = struct();
cfg.parallel.enable = true;      % will still be validated per env.mode
cfg.parallel.force_workers = []; % set to integer to override SLURM/auto detection

%% ========================================================================
%  CONFIG: PIPELINE STEPS (toggles + per-step overwrite overrides)
% ========================================================================
cfg.steps = struct();

cfg.steps.prep02_triggerfix = struct('run', false, 'overwrite_mode', "");
cfg.steps.prep03_untilica   = struct('run', true, 'overwrite_mode', "");
cfg.steps.prep04_ica        = struct('run', true, 'overwrite_mode', "");
cfg.steps.prep05_after_ica  = struct('run', true, 'overwrite_mode', "");
cfg.steps.prep06_epoching   = struct('run', true, 'overwrite_mode', "");

%% ========================================================================
%  CONFIG: WHICH STEP-FUNCTION FAMILY TO USE
% ========================================================================

% One switch to select function naming scheme.
% Examples:
%   "aperiodic_eeg_b"  -> aperiodic_eeg_b_prep03_untilica, etc.
%   "proof_eeg_cf"     -> proof_eeg_cf_prep03_untilica, etc.
cfg.pipeline = struct();
cfg.pipeline.step_prefix = "aperiodic_eeg_b";   % <----- THIS is your fix

% Build function handles from prefix (robust, avoids copy/paste errors)
cfg.step_fns = struct();
cfg.step_fns.prep02_triggerfix = str2func(char(cfg.pipeline.step_prefix + "_prep02_triggerfix"));
cfg.step_fns.prep03_untilica   = str2func(char(cfg.pipeline.step_prefix + "_prep03_untilica"));
cfg.step_fns.prep04_ica        = str2func(char(cfg.pipeline.step_prefix + "_prep04_ica"));
cfg.step_fns.prep05_after_ica  = str2func(char(cfg.pipeline.step_prefix + "_prep05_after_ica"));
cfg.step_fns.prep06_epoching   = str2func(char(cfg.pipeline.step_prefix + "_prep06_epoching"));

%% ========================================================================
%  CONFIG: STEP 02 (triggerfix)
% ========================================================================
cfg.prep02 = struct();

% RAW order Quality Control (QC) vs behavior log (writes CSV when mismatch)
cfg.prep02.run_raw_order_qc = true;

% If multiple BIDS .vhdr exist for same subject/task:
%   false -> enforce policy below
%   true  -> loop over all vhdr files found
cfg.prep02.allow_multiple_runs = false;

% Policy when multiple .vhdr found and allow_multiple_runs=false:
%   "most_recent" | "first" | "error"
cfg.prep02.multiple_vhdr_policy = "most_recent";

% Optional QC output directory ("" -> use step output directory)
cfg.prep02.qc_out_dir = "";

% Extinction block sizes (used for trigger remapping)
cfg.prep02.ext_n_first  = 11;
cfg.prep02.ext_n_second = 10;

% Disable (revert) first extinction trials per stream (CS-/CS+)
cfg.prep02.disable_first_ext_trials = true;

% Disable first acquisition trials (marks first CS-/CS+ as exclude tokens)
cfg.prep02.disable_first_acq_trials = true;


%% ========================================================================
%  CONFIG: STEP 03 (until ICA-prep)
% ========================================================================
cfg.prep03 = struct();

% Crop to task window (by markers)
cfg.prep03.crop_to_task_markers = false;
cfg.prep03.crop_start_marker    = 'S 91';
cfg.prep03.crop_end_marker      = 'S 97';
cfg.prep03.crop_padding_sec     = [0 0];   % [pre post] seconds

% Channel typing labels (used to set EEG/EOG/AUX types)
cfg.prep03.eog_channel_labels     = {'IO1','IO2','LO1','LO2'};
cfg.prep03.scr_channel_labels     = {'SCR'};
cfg.prep03.startle_channel_labels = {'Startle'};
cfg.prep03.ekg_channel_labels     = {'EKG'};

% Downsample: 0 (none) | 250 | 500
cfg.prep03.downsample_hz = 250;

% Bad channel detection: "auto" (clean_rawdata) | "auto_rejchan" (pop_rejchan) | "off"
cfg.prep03.detect_bad_channels_mode = "auto";
cfg.prep03.auto_badchan_z_threshold  = 3.29;
cfg.prep03.auto_badchan_freqrange_hz = [1 125];

% clean_rawdata-style parameters
cfg.prep03.emu_flatline_sec           = 5;
cfg.prep03.emu_channel_corr_threshold = 0.80;

% Flat/invalid channel flagging
cfg.prep03.flag_flat_channels_as_bad     = true;
cfg.prep03.flat_channel_variance_epsilon = 0;   % 0 = exactly flat or invalid

% Interpolation
cfg.prep03.interpolate_bad_channels_before_ica = true;
cfg.prep03.interp_method = 'spherical';

% Filters (applied to EEG+EOG only)
cfg.prep03.highpass_hz          = 0.1;
cfg.prep03.lowpass_hz           = 100;
cfg.prep03.ica_prep_highpass_hz = 1;

% Line noise
cfg.prep03.line_noise_method          = "pop_cleanline"; % "pop_cleanline" | "off"
cfg.prep03.line_noise_frequencies_hz  = [50 100];
cfg.prep03.pop_cleanline_bandwidth_hz = 2;
cfg.prep03.pop_cleanline_p_value      = 0.01;
cfg.prep03.pop_cleanline_verbose      = false;

% ICA-prep epochs + rejection (FORICA dataset only)
cfg.prep03.ica_prep_use_regepochs           = true;
cfg.prep03.ica_prep_regepoch_length_sec     = 1;

cfg.prep03.ica_prep_use_mad_epoch_rejection = true;
cfg.prep03.ica_prep_mad_z_threshold         = 3;
cfg.prep03.ica_prep_mad_use_logvar          = true;

cfg.prep03.ica_prep_use_jointprob_rejection = true;
cfg.prep03.ica_prep_jointprob_local         = 2;
cfg.prep03.ica_prep_jointprob_global        = 2;


%% ========================================================================
%  CONFIG: STEP 04 (ICA)
% ========================================================================
cfg.prep04 = struct();
cfg.prep04.ica_method = "runica";          % "runica" | "amica"
cfg.prep04.use_extended_infomax = true;
cfg.prep04.interrupt_ica        = 'off';
cfg.prep04.use_pca_rank_if_interpolated = true;
cfg.prep04.amica_require_no_spaces_on_windows = true;
cfg.paths.branch_by_ica_method = true;   

%% ========================================================================
%  CONFIG: STEP 05 (ICLabel rejection until epoching)
% ========================================================================
cfg.prep05 = struct();

cfg.prep05.clear_subject_ica_comps_dir = true;

% thresholds for rejection of components
cfg.prep05.iclabel_eye_remove_thr       = 0.80;
cfg.prep05.iclabel_muscle_remove_thr    = 0.80;
cfg.prep05.iclabel_heart_remove_thr     = 0.80;
cfg.prep05.iclabel_linenoise_remove_thr = 0.80;
cfg.prep05.iclabel_channoise_remove_thr = 0.80;

cfg.prep05.iclabel_other_remove_thr     = 0.95;
cfg.prep05.iclabel_brain_min_keep_thr   = 0.05;

cfg.prep05.save_ic_topos_png    = true; %for manual checking
cfg.prep05.iclabel_edge_margin = 0.10; % which components to plot as edge cases

% cpomponent png specs
cfg.prep05.ic_topo_dpi        = 300;
cfg.prep05.ic_topo_fig_cm     = [0 0 18 18];
cfg.prep05.ic_topo_electrodes = 'off';

%% ========================================================================
%  CONFIG: STEP 06 (epoching + final artifact rejection)
% ========================================================================
cfg.prep06 = struct();

cfg.prep06.save_final_only         = true;   % default: single final output. each step produces one file. 
cfg.prep06.save_intermediate_steps = false;  % only used if save_final_only=false. save one file after each preprocessing operation. can quickly fill up your disk space
cfg.prep06.savemode                = 'twofiles';  % 'twofiles' | 'onefile'

cfg.prep06.reference_mode = "avg";           % "avg" | "mastoid"

cfg.prep06.do_artifact_rejection = true;
cfg.prep06.faster_z_thresh       = 3;
cfg.prep06.faster_use_robust_z   = false;
cfg.prep06.faster_warn_if_reject_prop_gt = 0.25; %warns if a subject has so many epochs rejected that they will be excluded
cfg.prep06.max_reject_prop = 0.25;   % exclude subject if % epochs rejected

% epoch rejection specs
cfg.prep06.faster_use_amplitude         = true;
cfg.prep06.faster_use_variance          = true;
cfg.prep06.faster_use_channel_deviation = true;

cfg.prep06.epoching_mode = "regular";
cfg.prep06.regepoch_length_sec = 10;
cfg.prep06.regepoch_step_sec   = 10;

cfg.prep06.epoch_start_s   = -0.4;
cfg.prep06.epoch_end_s     =  2.6;
% Baseline correction
cfg.prep06.do_baseline_correction = false;   % 
cfg.prep06.base_start_ms          = -200;   
cfg.prep06.base_end_ms            = 0;      % default 0ms


cfg.prep06.events_phase = { ...
    'S 201','S 241', ...
    'S 2021','S 2421','S 2022','S 2422', ...
    'S 203','S 213','S 223','S 233','S 243', ...
    'S 2041','S 2441','S 2042','S 2442','S 2043','S 2443', ...
    'S 205','S 245' ...
};

%% ========================================================================
%  OPTIONAL: PARSE INPUTS (e.g., run_eeg_pipeline('001','002') or cellstr)
% ========================================================================
cfg = parse_inputs(cfg, varargin{:});

%% ========================================================================
%  PREP: ENSURE DIRECTORIES + MASTER LOG
% ========================================================================
ensure_dir(cfg.paths.logs_dir);

master_log = fullfile(cfg.paths.logs_dir, ...
    sprintf('%s_%s.log', cfg.constants.log_prefix_master, datestr(now, cfg.constants.datestr_master)));

helpers = build_helpers(master_log);

helpers.logmsg(master_log, '=== PIPELINE START %s ===', datestr(now));
helpers.logmsg(master_log, 'root_dir  : %s', cfg.root_dir);
helpers.logmsg(master_log, 'env.mode  : %s', string(cfg.env.mode));
helpers.logmsg(master_log, 'env.is_slurm: %d | SLURM_JOB_ID=%s | SLURM_CLUSTER_NAME=%s', ...
    cfg.env.is_slurm, cfg.env.slurm_job_id, cfg.env.slurm_cluster);
helpers.logmsg(master_log, 'paths.profile: %s', string(cfg.paths.profile));
helpers.logmsg(master_log, 'bids_root : %s', cfg.paths.bids_root);
helpers.logmsg(master_log, 'out_root  : %s', cfg.paths.out_root);
helpers.logmsg(master_log, 'overwrite : %s', string(cfg.io.overwrite_mode));
helpers.logmsg(master_log, 'dry_run   : %d', cfg.io.dry_run);

helpers.logmsg(master_log, 'Step05: eye=%.2f mus=%.2f heart=%.2f line=%.2f ch=%.2f other=%.2f brain_min=%.2f edge=%.2f',...
    cfg.prep05.iclabel_eye_remove_thr, cfg.prep05.iclabel_muscle_remove_thr, cfg.prep05.iclabel_heart_remove_thr, ...
    cfg.prep05.iclabel_linenoise_remove_thr, cfg.prep05.iclabel_channoise_remove_thr, ...
    cfg.prep05.iclabel_other_remove_thr, cfg.prep05.iclabel_brain_min_keep_thr, cfg.prep05.iclabel_edge_margin);

helpers.logmsg(master_log, 'Step06: ref=%s | epoch_mode=%s | regular=%gs | baseline_apply=%d | baseline=[%d %d]ms | faster_z=%.2f robust=%d', ...
    string(cfg.prep06.reference_mode), string(cfg.prep06.epoching_mode), cfg.prep06.regepoch_length_sec, cfg.prep06.do_baseline_correction, ...
    cfg.prep06.base_start_ms, cfg.prep06.base_end_ms, cfg.prep06.faster_z_thresh, cfg.prep06.faster_use_robust_z);

%% ========================================================================
%  TOOLBOX PATHS (client process)
% ========================================================================
init_toolboxes(cfg);
helpers.logmsg(master_log, 'Toolboxes initialized (master).');

%% ========================================================================
%  SUBJECT DISCOVERY
% ========================================================================
sub_ids = discover_subjects(cfg, helpers, master_log);
helpers.logmsg(master_log, 'Found %d subject(s).', numel(sub_ids));

%% ========================================================================
%  PARALLEL POOL (optional)
% ========================================================================
use_parallel = resolve_parallel_enable(cfg);

if use_parallel

    % ---- HPC safety: avoid corrupt MATLAB prefs on shared home ------------
    if isempty(getenv('MATLAB_PREFDIR'))
        setenv('MATLAB_PREFDIR', fullfile(tempdir, 'matlab_prefs'));
        if ~exist(getenv('MATLAB_PREFDIR'),'dir'); mkdir(getenv('MATLAB_PREFDIR')); end
    end

    n_workers = resolve_worker_count(cfg, helpers, master_log);
    helpers.logmsg(master_log, 'Parallel enabled (%d workers).', n_workers);

    pool_obj = gcp('nocreate');
    if isempty(pool_obj)
        % NOTE: depending on MATLAB config, 'local' can become ThreadPool.
        parpool('local', n_workers);
        pool_obj = gcp('nocreate');
    end

    % ---- detect pool type (ThreadPool vs process pool) --------------------
    cfg.parallel.pool_is_thread = false;
    cfg.parallel.pool_type = "none";

    if ~isempty(pool_obj)
        cfg.parallel.pool_is_thread = isa(pool_obj, 'parallel.ThreadPool');
        cfg.parallel.pool_type = string(class(pool_obj));
    end

    helpers.logmsg(master_log, 'Parallel pool type: %s | thread_based=%d', ...
        cfg.parallel.pool_type, cfg.parallel.pool_is_thread);

    % ---- IMPORTANT: if thread pool, do ALL init on master (client) --------
    if cfg.parallel.pool_is_thread
        helpers.logmsg(master_log, 'Thread pool detected -> initializing EEGLAB in master (workers cannot addpath).');

        % You already did init_toolboxes(cfg) above (master).
        % Ensure EEGLAB is initialized once here:
        if cfg.toolboxes.eeglab.nogui
            if cfg.env.mode == "hpc" && cfg.toolboxes.eeglab.no_update_check_on_hpc
                try
                    setpref('eeglab','plugin_update_check',0);
                    setpref('eeglab','update_check',0);
                    setpref('eeglab','version_check',0);
                catch me
                    helpers.logmsg(master_log, 'WARNING: setpref failed (%s). Continuing.', me.message);
                end
            end
            eeglab('nogui');
        else
            eeglab;
        end
        helpers.logmsg(master_log, 'EEGLAB initialized (master, thread pool).');
    end

else
    helpers.logmsg(master_log, 'Parallel disabled (serial run).');
    cfg.parallel.pool_is_thread = false;
    cfg.parallel.pool_type = "none";
end


%% ========================================================================
%  RUN PIPELINE (status collection)
% ========================================================================

% decide: AMICA forces serial subject loop (parfor workers cannot call system/unix)
force_serial_due_to_amica = ...
    use_parallel && ...
    (cfg.env.mode == "hpc") && ...
    cfg.steps.prep04_ica.run && ...
    (string(cfg.prep04.ica_method) == "amica");

if force_serial_due_to_amica
    helpers.logmsg(master_log, 'HPC+parfor+AMICA -> forcing serial subject loop (unix/system blocked on workers).');
    use_parallel = false;
end
% NOTE: HOPE THERE WILL BE A FIX FOR THIS SOON!

if force_serial_due_to_amica && use_parallel
    helpers.logmsg(master_log, 'AMICA selected -> disabling subject-level parfor (system/unix blocked on workers).');
    use_parallel = false;
end

n_sub = numel(sub_ids);
status = repmat(struct('subj','', 'ok',false, 'message','', 'logfile',''), n_sub, 1);

% executing pipeline
if use_parallel
    parfor i = 1:n_sub
        subj_id = sub_ids{i};
        status(i) = run_one_subject(subj_id, cfg); %#ok<PFOUS>
    end
else
    for i = 1:n_sub
        subj_id = sub_ids{i};
        status(i) = run_one_subject(subj_id, cfg);
    end
end


%% ========================================================================
%  SUMMARY
% ========================================================================
ok_mask = [status.ok];
n_ok = sum(ok_mask);
n_fail = sum(~ok_mask);

helpers.logmsg(master_log, '=== PIPELINE END %s ===', datestr(now));
helpers.logmsg(master_log, 'Completed: %d ok | %d failed', n_ok, n_fail);

if n_fail > 0
    helpers.logmsg(master_log, 'Failed subjects:');
    for k = find(~ok_mask)
        helpers.logmsg(master_log, '  sub-%s | %s | log=%s', ...
            status(k).subj, status(k).message, status(k).logfile);
    end
    error('Pipeline finished with failures (%d/%d). See logs.', n_fail, n_sub);
end

end % run_eeg_pipeline

%% ========================================================================
%  SUBJECT RUNNER (parfor-safe: self-contained)
% ========================================================================
%% ========================================================================
%  SUBJECT RUNNER (parfor-safe: self-contained)
% ========================================================================
function out = run_one_subject(subj_id, cfg)

out = struct('subj', subj_id, 'ok', false, 'message','', 'logfile','');

ensure_dir(cfg.paths.logs_dir);

sub_log = fullfile(cfg.paths.logs_dir, ...
    sprintf('%s-%s_%s.log', cfg.constants.log_prefix_subject, subj_id, datestr(now, cfg.constants.datestr_subject)));
out.logfile = sub_log;

helpers = build_helpers(sub_log);

try
    helpers.logmsg(sub_log, '--- START sub-%s ---', subj_id);

    % ==========================================================
    % Toolboxes + EEGLAB per worker
    %
    % CRITICAL FIX:
    % Thread-based workers cannot modify MATLAB path (addpath/matlabpath).
    % Therefore:
    %   - If ThreadPool: init must happen on the client BEFORE parfor
    %   - If process pool / serial: OK to init here
    % ==========================================================
    is_thread_pool = isfield(cfg,'parallel') && isfield(cfg.parallel,'pool_is_thread') && cfg.parallel.pool_is_thread;

    if is_thread_pool
        helpers.logmsg(sub_log, 'Thread pool -> skipping init_toolboxes + eeglab init inside worker (done in master).');
    else
        % Toolboxes + EEGLAB per worker
        init_toolboxes(cfg);

        if cfg.toolboxes.eeglab.nogui
            if cfg.env.mode == "hpc" && cfg.toolboxes.eeglab.no_update_check_on_hpc
                try
                    setpref('eeglab','plugin_update_check',0);
                    setpref('eeglab','update_check',0);
                    setpref('eeglab','version_check',0);
                catch me
                    helpers.logmsg(sub_log, 'WARNING: setpref failed (%s). Continuing without changing EEGLAB prefs.', me.message);
                end
            end
            eeglab('nogui');
        else
            eeglab;
        end
        helpers.logmsg(sub_log, 'EEGLAB initialized.');
    end

    % Build per-subject paths
    paths = build_paths(cfg, subj_id);

    % ===== Pipeline steps =====

    if cfg.steps.prep02_triggerfix.run
        helpers.logmsg(sub_log, 'Step 02: triggerfix');
        step_out = feval(cfg.step_fns.prep02_triggerfix, subj_id, cfg, paths, helpers);
        if ~step_out.ok
            error('prep02_triggerfix failed for sub-%s: %s', subj_id, step_out.message);
        end
    end

    if cfg.steps.prep03_untilica.run
        helpers.logmsg(sub_log, 'Step 03: untilICA');
        step_out = feval(cfg.step_fns.prep03_untilica, subj_id, cfg, paths, helpers);
        if ~step_out.ok
            error('prep03_untilica failed for sub-%s: %s', subj_id, step_out.message);
        end
    end

    if cfg.steps.prep04_ica.run
        helpers.logmsg(sub_log, 'Step 04: ICA');
        step_out = feval(cfg.step_fns.prep04_ica, subj_id, cfg, paths, helpers);
        if ~step_out.ok
            error('prep04_ica failed for sub-%s: %s', subj_id, step_out.message);
        end
    end

    if cfg.steps.prep05_after_ica.run
        helpers.logmsg(sub_log, 'Step 05: IC rejection (ICLabel)');
        step_out = feval(cfg.step_fns.prep05_after_ica, subj_id, cfg, paths, helpers);
        if ~step_out.ok
            error('prep05_after_ica failed for sub-%s: %s', subj_id, step_out.message);
        end
    end

    if cfg.steps.prep06_epoching.run
        helpers.logmsg(sub_log, 'Step 06: epoching + final rejection');
        step_out = feval(cfg.step_fns.prep06_epoching, subj_id, cfg, paths, helpers);
        if ~step_out.ok
            error('prep06_epoching failed for sub-%s: %s', subj_id, step_out.message);
        end
    end

    helpers.logmsg(sub_log, '--- END sub-%s OK ---', subj_id);
    out.ok = true;

catch me
    out.ok = false;
    out.message = me.message;

    helpers.logmsg(sub_log, 'ERROR: %s', me.message);
    helpers.logmsg(sub_log, '%s', getReport(me,'extended','hyperlinks','off'));

    % Rename subject log to include ERR suffix
    try
        [p, f, e] = fileparts(sub_log);
        err_log = fullfile(p, sprintf('%s_ERR%s', f, e));
        if exist(sub_log,'file')
            movefile(sub_log, err_log);
            out.logfile = err_log;
        end
    catch
    end
end
end


%% ========================================================================
%  PATH BUILDERS
% ========================================================================
function paths = build_paths(cfg, subj_id)

paths = struct();
paths.root_dir  = cfg.root_dir;
paths.bids_root = cfg.paths.bids_root;
paths.out_root  = cfg.paths.out_root;

paths.subj_label = sprintf('sub-%s', subj_id);

% Common BIDS locations
paths.bids_sub_dir = fullfile(paths.bids_root, paths.subj_label);
paths.bids_ses_dir = fullfile(paths.bids_sub_dir, 'ses-01');

% ---------- STEP ROOTS (top-level per step) ----------
paths.step02_root = fullfile(paths.out_root, '01_trigger_fix');
paths.step03_untilica_root = fullfile(paths.out_root, '02_until_ica');
paths.step03_forica_root   = fullfile(paths.out_root, '03_for_ica');
% branch depending on ICA type for 4 - 6
ica_tag = "runica";
if isfield(cfg,'prep04') && isfield(cfg.prep04,'ica_method')
    ica_tag = string(cfg.prep04.ica_method);
end

suffix = "";
if isfield(cfg.paths,'branch_by_ica_method') && cfg.paths.branch_by_ica_method
    suffix = "_" + ica_tag;  % -> "_runica" or "_amica"
end

paths.step04_root = fullfile(paths.out_root, "04_after_ica"      + suffix);
paths.step05_root = fullfile(paths.out_root, "05_until_epoching" + suffix);
paths.step06_root = fullfile(paths.out_root, "06_epoched"        + suffix);


ensure_dir(paths.step02_root);
ensure_dir(paths.step03_untilica_root);
ensure_dir(paths.step03_forica_root);
ensure_dir(paths.step04_root);
ensure_dir(paths.step05_root);
ensure_dir(paths.step06_root);

% ---------- SUBJECT FOLDERS WITHIN EACH STEP ----------
paths.prep02_out_dir = fullfile(paths.step02_root, paths.subj_label);
ensure_dir(paths.prep02_out_dir);

paths.prep03_out_dir_untilica = fullfile(paths.step03_untilica_root, paths.subj_label);
ensure_dir(paths.prep03_out_dir_untilica);

paths.prep03_out_dir_forica = fullfile(paths.step03_forica_root, paths.subj_label);
ensure_dir(paths.prep03_out_dir_forica);

paths.prep04_out_dir = fullfile(paths.step04_root, paths.subj_label);
ensure_dir(paths.prep04_out_dir);

paths.prep05_out_dir = fullfile(paths.step05_root, paths.subj_label);
ensure_dir(paths.prep05_out_dir);

paths.prep06_out_dir = fullfile(paths.step06_root, paths.subj_label);
ensure_dir(paths.prep06_out_dir);

% ---------- CHECKS (QA artifacts, NOT logs) ----------
paths.checks_root = fullfile(paths.out_root, 'checks');
ensure_dir(paths.checks_root);

paths.checks_ica_comps_root = fullfile(paths.checks_root, 'ica_comps');
ensure_dir(paths.checks_ica_comps_root);

paths.checks_ica_comps_subj_dir = fullfile(paths.checks_ica_comps_root, paths.subj_label);
paths.checks_ica_comps_rej_dir  = fullfile(paths.checks_ica_comps_subj_dir, 'rej');
paths.checks_ica_comps_edge_dir = fullfile(paths.checks_ica_comps_subj_dir, 'edge');

ensure_dir(paths.checks_ica_comps_subj_dir);
ensure_dir(paths.checks_ica_comps_rej_dir);
ensure_dir(paths.checks_ica_comps_edge_dir);

% Optional QC root
paths.qc_root = fullfile(paths.out_root, 'qc');
ensure_dir(paths.qc_root);
paths.qc_dir = fullfile(paths.qc_root, paths.subj_label);
ensure_dir(paths.qc_dir);

end

%% ========================================================================
%  SUBJECT DISCOVERY
% ========================================================================
function sub_ids = discover_subjects(cfg, helpers, master_log)

sub_ids = cfg.subjects.list;

if isempty(sub_ids)
    ds = dir(fullfile(cfg.paths.bids_root, 'sub-*'));
    ds = ds([ds.isdir]);
    sub_ids = cellfun(@(x) erase(x,'sub-'), {ds.name}, 'uni', false);
end

sub_ids = sub_ids(:);
rx = cfg.constants.valid_sub_id_regex;
sub_ids = sub_ids(~cellfun(@isempty, regexp(sub_ids, rx, 'once')));

if isempty(sub_ids)
    error('No subjects found in %s', cfg.paths.bids_root);
end

end

%% ========================================================================
%  PARALLEL POLICY
% ========================================================================
function use_parallel = resolve_parallel_enable(cfg)
use_parallel = cfg.parallel.enable;

if cfg.env.mode == "pc"
    % keep
elseif cfg.env.mode == "server"
    % keep
elseif cfg.env.mode == "hpc"
    % keep
else
    use_parallel = false;
end
end


function n_workers = resolve_worker_count(cfg, helpers, master_log)

% 1) explicit cfg override
if ~isempty(cfg.parallel.force_workers)
    n_workers = cfg.parallel.force_workers;
    helpers.logmsg(master_log, 'Resolved worker count from cfg.parallel.force_workers=%d', n_workers);
    return;
end

% 2) env override (recommended on hummel without slurm)
v = getenv('PROOF_WORKERS');
if ~isempty(v)
    tmp = str2double(v);
    if ~isnan(tmp) && tmp >= 1
        n_workers = tmp;
        helpers.logmsg(master_log, 'Resolved worker count from PROOF_WORKERS=%d', n_workers);
        return;
    end
end

% 3) fallback: MATLAB-reported cores
n_workers = feature('numcores');
n_workers = max(1, n_workers);

helpers.logmsg(master_log, 'Resolved worker count from feature(numcores)=%d', n_workers);
end


%% ========================================================================
%  HELPERS (INJECTED VIA HANDLES)
% ========================================================================
function helpers = build_helpers(default_log_file)

helpers = struct();

helpers.getenv_or_empty = @getenv_or_empty;

helpers.logmsg = @(log_file, varargin) logmsg_impl(log_file, varargin{:});
helpers.logmsg_default = @(varargin) logmsg_impl(default_log_file, varargin{:});

helpers.ensure_dir = @ensure_dir;
helpers.get_slurm_cpus_per_task = @get_slurm_cpus_per_task;

% Overwrite / output policy helpers
helpers.resolve_overwrite_mode    = @resolve_overwrite_mode;
helpers.step_should_run_outputs   = @step_should_run_outputs;
helpers.safe_delete_set           = @safe_delete_set;
helpers.safe_saveset = @safe_saveset;
helpers.safe_loadset = @safe_loadset;

% BIDS EEG fallback (for Step 03 if Step 02 is skipped)
helpers.find_bids_vhdr = @find_bids_vhdr;
helpers.safe_loadbv    = @safe_loadbv;

% EEG/comment + trigger normalization
helpers.append_eeg_comment = @append_eeg_comment;
helpers.normalize_trigger_type = @normalize_trigger_type;

% EEG utilities used by Step 03 (centralized)
helpers.find_first_event_latency               = @find_first_event_latency;
helpers.ensure_channel_types                   = @ensure_channel_types;
helpers.find_flat_or_invalid_channels          = @find_flat_or_invalid_channels;
helpers.detect_bad_channels_emulation_style    = @detect_bad_channels_emulation_style;
helpers.apply_filter_to_subset_only            = @apply_filter_to_subset_only;
helpers.apply_pop_cleanline_to_subset          = @apply_pop_cleanline_to_subset;
helpers.apply_jointprob_safely                 = @apply_jointprob_safely;
helpers.reject_ica_prep_epochs_by_mad_variance = @reject_ica_prep_epochs_by_mad_variance;

% Behavior log helpers
helpers.find_behavior_log = @find_behavior_log;
helpers.read_behavior_log = @read_behavior_log;

% RAW QC helper
helpers.raw_qc_behavior_vs_eeg_and_write_csv = @raw_qc_behavior_vs_eeg_and_write_csv;

end

function logmsg_impl(log_file, varargin)
msg = sprintf(varargin{:});
ts  = datestr(now,'yyyy-mm-dd HH:MM:SS');
fprintf('[%s] %s\n', ts, msg);

fid = fopen(log_file, 'a');
if fid >= 0
    fprintf(fid, '[%s] %s\n', ts, msg);
    fclose(fid);
end
end

function ensure_dir(pth)
if ~exist(pth,'dir')
    mkdir(pth);
end
end

function n_workers = get_slurm_cpus_per_task()
n_workers = [];
val = getenv('SLURM_CPUS_PER_TASK');
if ~isempty(val)
    tmp = str2double(val);
    if ~isnan(tmp) && tmp >= 1
        n_workers = tmp;
    end
end
end

function v = getenv_or_empty(name)
tmp = getenv(name);
if isempty(tmp)
    v = "";
else
    v = string(tmp);
end
end

function cfg = parse_inputs(cfg, varargin)
if nargin < 2 || isempty(varargin)
    return;
end

if numel(varargin) == 1 && iscell(varargin{1})
    cfg.subjects.list = varargin{1};
else
    cfg.subjects.list = varargin;
end
end

%% ========================================================================
%  HELPER: overwrite resolution + output existence checks
% ========================================================================
function overwrite_mode = resolve_overwrite_mode(cfg, step_overwrite_mode)
    overwrite_mode = string(cfg.io.overwrite_mode);
    if nargin >= 2 && strlength(string(step_overwrite_mode)) > 0
        overwrite_mode = string(step_overwrite_mode);
    end
    if overwrite_mode ~= "delete" && overwrite_mode ~= "skip"
        overwrite_mode = "delete";
    end
    end
    
    function [do_run, reason, needs_regen] = step_should_run_outputs(out_files, overwrite_mode, cfg)
    % STEP_SHOULD_RUN_OUTPUTS
    % Accepts:
    %   - cell array of file paths
    %   - string scalar / char row path (single output)
    % Returns:
    %   do_run, reason, needs_regen (partial outputs)
    
    needs_regen = false;
    
    % ---- normalize input to cellstr of scalar char paths ----------------------
    if nargin < 1 || isempty(out_files)
        out_files = {};
    end
    
    if ischar(out_files) || isstring(out_files)
        out_files = {out_files};
    end
    
    if ~iscell(out_files)
        out_files = {out_files};
    end
    
    exists_mask = false(size(out_files));
    for k = 1:numel(out_files)
        f = out_files{k};
        if iscell(f); f = f{1}; end
        f = char(string(f));           % normalize to char row
        exists_mask(k) = exist(f, 'file') == 2;
    end
    
    n_exist = sum(exists_mask);
    
    if n_exist == 0
        do_run = true;
        reason = "no outputs present";
        return;
    end
    
    if n_exist == numel(out_files)
        if overwrite_mode == "skip"
            do_run = false;
            reason = "all outputs exist -> skip";
            return;
        else
            do_run = true;
            reason = "all outputs exist -> delete + regenerate";
            return;
        end
    end
    
    needs_regen = true;
    do_run = true;
    reason = sprintf('partial outputs exist (%d/%d) -> regenerate', n_exist, numel(out_files));
    
    if cfg.io.dry_run
        % no-op
    end
end


function safe_delete_set(set_file)
    % SAFE_DELETE_SET  Robust delete helper for .set/.fdt pairs.
    % Accepts char, string scalar, string array, cellstr.
    % Intentionally designed to be called via helpers.safe_delete_set (used by Step 02).
    
    % ---- normalize input to scalar char -------------------------------------
    if nargin < 1
        return;
    end
    
    if iscell(set_file)
        if isempty(set_file); return; end
        set_file = set_file{1};
    end
    
    % string(...) makes everything string; char(...) makes it a char row vector
    set_file = char(string(set_file));
    
    if isempty(set_file)
        return;
    end
    
    % ---- derive pair paths ---------------------------------------------------
    [p, f, ~] = fileparts(set_file);
    
    set_path = fullfile(p, [f '.set']);
    fdt_path = fullfile(p, [f '.fdt']);
    
    % normalize again (paranoia against string arrays)
    set_path = char(string(set_path));
    fdt_path = char(string(fdt_path));
    
    % ---- delete if present ---------------------------------------------------
    if exist(set_path, 'file') == 2
        delete(set_path);
    end
    if exist(fdt_path, 'file') == 2
        delete(fdt_path);
    end
end


%% ========================================================================
%  HELPER: EEG comment append
% ========================================================================
function EEG = append_eeg_comment(EEG, line)
try
    if ~isfield(EEG,'comments') || isempty(EEG.comments)
        EEG.comments = line;
    else
        EEG.comments = sprintf('%s\n%s', EEG.comments, line);
    end
catch
end
end

%% ========================================================================
%  HELPER: trigger normalization
% ========================================================================
function tok = normalize_trigger_type(t)

if isnumeric(t)
    tok = strtrim(num2str(t));
    return;
end

tok = char(string(t));
tok = strtrim(tok);
tok = regexprep(tok, '\s+', ' ');

m = regexp(tok, '^S(\d+)$', 'tokens', 'once');
if ~isempty(m)
    tok = ['S ' m{1}];
    return;
end

m = regexp(tok, '^S\s+(\d+)$', 'tokens', 'once');
if ~isempty(m)
    tok = ['S ' m{1}];
    return;
end
end

%% ========================================================================
%  EEG UTIL HELPERS (centralized for Step 03+)
% ========================================================================
function latency = find_first_event_latency(EEG, event_type)
latency = [];
if ~isfield(EEG,'event') || isempty(EEG.event); return; end

target = normalize_trigger_type(event_type);

for k = 1:numel(EEG.event)
    t = normalize_trigger_type(EEG.event(k).type);
    if strcmp(t, target)
        latency = EEG.event(k).latency;
        return;
    end
end
end


function EEG = ensure_channel_types(EEG, step_cfg)

if ~isfield(EEG,'chanlocs') || isempty(EEG.chanlocs)
    return;
end

labels = {EEG.chanlocs.labels};

for k = 1:numel(EEG.chanlocs)
    EEG.chanlocs(k).type = 'EEG';
end

set_type_by_labels(step_cfg.eog_channel_labels,     'EOG');
set_type_by_labels(step_cfg.scr_channel_labels,     'SCR');
set_type_by_labels(step_cfg.startle_channel_labels, 'Startle');
set_type_by_labels(step_cfg.ekg_channel_labels,     'EKG');

EEG = eeg_checkset(EEG);

    function set_type_by_labels(lbls, typ)
        for i = 1:numel(lbls)
            idx = find(strcmpi(labels, lbls{i}));
            for j = 1:numel(idx)
                EEG.chanlocs(idx(j)).type = typ;
            end
        end
    end
end

function [flat_indices, flat_labels] = find_flat_or_invalid_channels(EEG, candidate_indices, variance_epsilon)
flat_indices = [];
flat_labels  = {};

if isempty(candidate_indices); return; end

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
bad_indices = [];
bad_labels  = {};

if isempty(eeg_indices); return; end
if exist('clean_rawdata','file') ~= 2
    return;
end

EEG_tmp = EEG;
EEG_tmp = pop_select(EEG_tmp, 'channel', eeg_indices);
EEG_tmp = eeg_checkset(EEG_tmp);

labels_before = {EEG_tmp.chanlocs.labels};

EEG_clean = clean_rawdata(EEG_tmp, flatline_sec, -1, corr_threshold, -1, -1, -1);
EEG_clean = eeg_checkset(EEG_clean);

labels_after = {EEG_clean.chanlocs.labels};
removed_labels = setdiff(labels_before, labels_after, 'stable');

if isempty(removed_labels); return; end

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
if isempty(subset_indices); return; end

original_data = EEG.data;

EEG = pop_eegfiltnew(EEG, 'locutoff', locutoff_hz, 'hicutoff', hicutoff_hz, 'usefftfilt', 1);
EEG = eeg_checkset(EEG);

non_subset = setdiff(1:EEG.nbchan, subset_indices);
EEG.data(non_subset, :) = original_data(non_subset, :);

EEG = eeg_checkset(EEG);

if nargin >= 5 && ~isempty(label_for_log)
    EEG = append_eeg_comment(EEG, sprintf('%s: applied only to channels %s', label_for_log, mat2str(subset_indices)));
end
end

function [EEG, did_apply] = apply_pop_cleanline_to_subset(EEG, subset_indices, step_cfg)
did_apply = false;

if isempty(subset_indices); return; end
if exist('pop_cleanline','file') ~= 2; return; end

original_data = EEG.data;

try
    EEG_tmp = EEG;
    EEG_tmp.data = EEG.data(subset_indices, :);

    Fs = EEG_tmp.srate;
    freqs = step_cfg.line_noise_frequencies_hz;
    freqs = freqs(freqs < Fs/2);

    if isempty(freqs)
        did_apply = true;
        return;
    end

    EEG_tmp = pop_cleanline(EEG_tmp, ...
        'bandwidth',        step_cfg.pop_cleanline_bandwidth_hz, ...
        'chanlist',         1:size(EEG_tmp.data,1), ...
        'computepower',     0, ...
        'linefreqs',        freqs, ...
        'normSpectrum',     0, ...
        'p',                step_cfg.pop_cleanline_p_value, ...
        'pad',              2, ...
        'plotfigures',      0, ...
        'scanforlines',     0, ...
        'sigtype',          'Channels', ...
        'taperbandwidth',   2, ...
        'tau',              100, ...
        'verb',             double(step_cfg.pop_cleanline_verbose), ...
        'winsize',          4, ...
        'winstep',          1);

    EEG.data(subset_indices, :) = EEG_tmp.data;
    did_apply = true;

catch
    EEG.data = original_data;
    did_apply = false;
end

EEG = eeg_checkset(EEG);
end

function [EEG, did_apply] = apply_jointprob_safely(EEG, local_threshold, global_threshold)
did_apply = false;
if EEG.nbchan < 2; return; end

try
    if isfield(EEG,'chanlocs') && isfield(EEG.chanlocs,'type')
        types = lower(string({EEG.chanlocs.type}));
        cand_mask = (types == "eeg") | (types == "eog");
        cand_idx  = find(cand_mask);
    else
        cand_idx = 1:EEG.nbchan;
    end

    if numel(cand_idx) < 2; return; end

    data_2d = double(reshape(EEG.data(cand_idx, :, :), numel(cand_idx), []));
    chan_var = var(data_2d, 0, 2);

    valid_mask = isfinite(chan_var) & (chan_var > 0);
    valid_idx_local = find(valid_mask);
    if numel(valid_idx_local) < 2; return; end

    valid_idx = cand_idx(valid_idx_local);

    EEG = pop_jointprob(EEG, 1, valid_idx, local_threshold, global_threshold, 0, 1, 0, [], 0);
    EEG = eeg_checkset(EEG);
    did_apply = true;

catch me
    EEG = append_eeg_comment(EEG, sprintf('ica-prep: pop_jointprob failed: %s', me.message));
    did_apply = false;
end
end

function [EEG, info] = reject_ica_prep_epochs_by_mad_variance(EEG, chan_idx, z_thresh, use_logvar)
info = struct();
info.did_apply   = false;
info.z_thresh    = z_thresh;
info.n_before    = EEG.trials;
info.n_rejected  = 0;
info.rejected_epochs = [];

if EEG.trials < 2 || isempty(chan_idx); return; end

X = double(EEG.data(chan_idx, :, :));
nChan  = size(X, 1);
nEpoch = size(X, 3);

v = zeros(nChan, nEpoch);
for e = 1:nEpoch
    v(:,e) = var(X(:,:,e), 0, 2);
end

if use_logvar
    v = log10(v + eps);
end

z = zeros(size(v));
for c = 1:nChan
    xc = v(c,:);
    med = median(xc);
    madv = median(abs(xc - med));
    denom = (1.4826 * madv) + eps;
    z(c,:) = (xc - med) ./ denom;
end

bad_epoch_mask = any(abs(z) > z_thresh, 1);
bad_epochs = find(bad_epoch_mask);

if isempty(bad_epochs); return; end

EEG = pop_rejepoch(EEG, bad_epoch_mask, 0);
EEG = eeg_checkset(EEG);

if ~isfield(EEG,'etc') || isempty(EEG.etc); EEG.etc = struct(); end
EEG.etc.ica_prep_mad_rejection = struct();
EEG.etc.ica_prep_mad_rejection.z_thresh = z_thresh;
EEG.etc.ica_prep_mad_rejection.use_logvar = use_logvar;
EEG.etc.ica_prep_mad_rejection.rejected_epochs = bad_epochs;

info.did_apply = true;
info.n_rejected = numel(bad_epochs);
info.rejected_epochs = bad_epochs;
end

%% ========================================================================
%  HELPER: find behavior log in BIDS
% ========================================================================
function beh_file = find_behavior_log(path_bids_root, subj_id)

beh_dir = fullfile(path_bids_root, ['sub-' subj_id], 'ses-01', 'beh');
if ~exist(beh_dir,'dir')
    error('No beh directory: %s', beh_dir);
end

tag = sprintf('CF_%s', subj_id);

cands = [dir(fullfile(beh_dir, '*.log')); dir(fullfile(beh_dir, '*.txt'))];

if isempty(cands)
    error('No .log/.txt files in %s', beh_dir);
end

keep = false(size(cands));
for k = 1:numel(cands)
    keep(k) = contains(cands(k).name, tag, 'IgnoreCase', true);
end
cands_tagged = cands(keep);

if ~isempty(cands_tagged)
    cands = cands_tagged;
end

idx2 = find(arrayfun(@(d) contains(d.name, '_2', 'IgnoreCase', true), cands));
if ~isempty(idx2)
    cands = cands(idx2);
end

is_log = arrayfun(@(d) endsWith(lower(d.name), '.log'), cands);
if any(is_log)
    cands = cands(is_log);
end

[~, ix] = max([cands.datenum]);
beh_file = fullfile(beh_dir, cands(ix).name);
end

%% ========================================================================
%  HELPER: read behavior log
% ========================================================================
function beh = read_behavior_log(beh_file)

raw = fileread(beh_file);
lines = regexp(raw, '\r\n|\n|\r', 'split');

header_idx = 0;
for i = 1:numel(lines)
    if startsWith(strtrim(lines{i}), 'Subject')
        header_idx = i;
        break;
    end
end
if header_idx == 0
    error('Could not find header line starting with "Subject" in %s', beh_file);
end

tmp = [tempname '.txt'];
fid = fopen(tmp,'w');
for i = header_idx:numel(lines)
    fprintf(fid, '%s\n', lines{i});
end
fclose(fid);

opts = detectImportOptions(tmp, 'Delimiter', '\t', 'FileType', 'text');
T = readtable(tmp, opts);
delete(tmp);

T.Properties.VariableNames = matlab.lang.makeValidName(T.Properties.VariableNames);
beh = T;
end

%% ========================================================================
%  HELPER: RAW QC behavior vs EEG order CSV writer
% ========================================================================
function raw_qc_behavior_vs_eeg_and_write_csv(beh, EEG, subj_id, bids_base, out_dir, varargin)

arguments
    beh table
    EEG struct
    subj_id char
    bids_base char
    out_dir char
end
arguments (Repeating)
    varargin
end

opts = struct();
opts.bin_size_s       = 1;
opts.max_rows         = 20000;
opts.keep_tokens      = ["S 20","S 21","S 22","S 23","S 24","S 15","S 5"];
opts.write_csv_on_ok  = false;

if numel(varargin) == 1 && isstruct(varargin{1})
    u = varargin{1};
    f = fieldnames(u);
    for k = 1:numel(f); opts.(f{k}) = u.(f{k}); end
elseif ~isempty(varargin)
    for k = 1:2:numel(varargin)
        key = string(varargin{k});
        opts.(char(key)) = varargin{k+1};
    end
end

ensure_dir(out_dir);

[beh_tok, beh_t_s] = build_beh_key_token_stream_with_time(beh);
[eeg_tok, eeg_t_s] = build_eeg_key_token_stream_with_time(EEG);

keepB = ismember(beh_tok, opts.keep_tokens);
beh_tok = beh_tok(keepB); beh_t_s = beh_t_s(keepB);

keepE = ismember(eeg_tok, opts.keep_tokens);
eeg_tok = eeg_tok(keepE); eeg_t_s = eeg_t_s(keepE);

if isempty(beh_tok) || isempty(eeg_tok)
    return;
end

[ok, rep] = check_subsequence_order_detailed(beh_tok, eeg_tok);

if ok && ~opts.write_csv_on_ok
    return;
end

isStimB = ismember(beh_tok, ["S 20","S 21","S 22","S 23","S 24"]);
isStimE = ismember(eeg_tok, ["S 20","S 21","S 22","S 23","S 24"]);

if any(isStimB) && any(isStimE)
    tB0 = beh_t_s(find(isStimB, 1, 'first'));
    tE0 = eeg_t_s(find(isStimE, 1, 'first'));
    delay_s = tE0 - tB0;
else
    delay_s = NaN;
end

if any(isStimB)
    beh_rel = beh_t_s - beh_t_s(find(isStimB, 1, 'first'));
else
    beh_rel = beh_t_s - beh_t_s(1);
end

if any(isStimE)
    eeg_rel = eeg_t_s - eeg_t_s(find(isStimE, 1, 'first'));
else
    eeg_rel = eeg_t_s - eeg_t_s(1);
end

if ~isnan(delay_s)
    beh_rel_aligned = beh_rel + delay_s;
else
    beh_rel_aligned = beh_rel;
end

bin = opts.bin_size_s;

minT = min([0; beh_rel_aligned; eeg_rel]);
maxT = max([beh_rel_aligned; eeg_rel]);

b0 = floor(minT/bin) * bin;
b1 = ceil(maxT/bin)  * bin;

edges = b0:bin:b1;
if numel(edges) < 2
    edges = [b0, b0+bin];
end

nBins = numel(edges)-1;
if nBins > opts.max_rows
    nBins = opts.max_rows;
    edges = edges(1:nBins+1);
end

beh_in_bin = cell(nBins,1);
eeg_in_bin = cell(nBins,1);
n_beh      = zeros(nBins,1);
n_eeg      = zeros(nBins,1);

for bi = 1:nBins
    t1 = edges(bi);
    t2 = edges(bi+1);

    idxB = beh_rel_aligned >= t1 & beh_rel_aligned < t2;
    idxE = eeg_rel         >= t1 & eeg_rel         < t2;

    if any(idxB)
        beh_in_bin{bi} = strjoin(beh_tok(idxB), '|');
        n_beh(bi) = sum(idxB);
    else
        beh_in_bin{bi} = "";
    end

    if any(idxE)
        eeg_in_bin{bi} = strjoin(eeg_tok(idxE), '|');
        n_eeg(bi) = sum(idxE);
    else
        eeg_in_bin{bi} = "";
    end
end

T = table();
T.bin_start_s  = edges(1:nBins)';
T.bin_end_s    = edges(2:nBins+1)';
T.beh_events   = string(beh_in_bin);
T.eeg_events   = string(eeg_in_bin);
T.n_beh_events = n_beh;
T.n_eeg_events = n_eeg;

out_csv = fullfile(out_dir, sprintf('order_mismatch_sub-%s_%s.csv', subj_id, bids_base));
fid = fopen(out_csv, 'w');
if fid < 0
    return;
end

fprintf(fid, 'subject;%s\n', subj_id);
fprintf(fid, 'bids_base;%s\n', bids_base);
fprintf(fid, 'delay_s;%s\n', num2str(delay_s));
fprintf(fid, 'bin_size_s;%g\n', bin);
fprintf(fid, 'mismatch;%d\n', ~ok);
if ~ok
    fprintf(fid, 'first_missing_token;%s\n', rep.missing_token);
    fprintf(fid, 'beh_missing_index;%d\n', rep.beh_i);
    fprintf(fid, 'last_match_eeg_index;%d\n', rep.last_match_eeg_idx);
end
fprintf(fid, '\n');
fprintf(fid, 'bin_start_s;bin_end_s;beh_events;eeg_events;n_beh_events;n_eeg_events\n');

for r = 1:height(T)
    fprintf(fid, '%.3f;%.3f;%s;%s;%d;%d\n', ...
        T.bin_start_s(r), T.bin_end_s(r), ...
        escape_semicolons(T.beh_events(r)), ...
        escape_semicolons(T.eeg_events(r)), ...
        T.n_beh_events(r), T.n_eeg_events(r));
end
fclose(fid);
end

function s = escape_semicolons(s)
s = string(s);
s = replace(s, ";", ",");
end

function [tokens, times_s] = build_beh_key_token_stream_with_time(beh)
vars = beh.Properties.VariableNames;
if ~ismember('EventType', vars) || ~ismember('Code', vars) || ~ismember('Time', vars)
    error('Behavior log missing required columns among EventType/Code/Time');
end

[~, ix] = sort(beh.Time);
beh = beh(ix,:);

tokens  = strings(0,1);
times_s = zeros(0,1);

for r = 1:height(beh)
    et = string(beh.EventType(r));
    cd = string(beh.Code(r));
    t  = double(beh.Time(r)) / 1000;

    if strcmpi(et, 'Picture')
        cdl = lower(strtrim(cd));

        if ismember(cdl, ["cs-","csminus","cs_min","csmin","cs1"])
            tokens(end+1,1) = "S 20"; times_s(end+1,1) = t; continue;
        end

        if strcmpi(cd,'GS1'); tokens(end+1,1) = "S 21"; times_s(end+1,1) = t; continue; end
        if strcmpi(cd,'GSU'); tokens(end+1,1) = "S 22"; times_s(end+1,1) = t; continue; end
        if strcmpi(cd,'GS2'); tokens(end+1,1) = "S 23"; times_s(end+1,1) = t; continue; end

        if ismember(cdl, ["cs+","csplus","cs_pls","cspls","cs2"])
            tokens(end+1,1) = "S 24"; times_s(end+1,1) = t; continue;
        end
    end

    if strcmpi(et, 'Sound') && strcmpi(cd, 'Startle')
        tokens(end+1,1) = "S 15"; times_s(end+1,1) = t; continue;
    end

    if strcmpi(et, 'Nothing') && strcmpi(cd, 'Shock')
        tokens(end+1,1) = "S 5"; times_s(end+1,1) = t; continue;
    end
end
end

function [tokens, times_s] = build_eeg_key_token_stream_with_time(EEG)
if ~isfield(EEG,'event') || isempty(EEG.event)
    tokens  = strings(0,1);
    times_s = zeros(0,1);
    return;
end
if ~isfield(EEG,'srate') || isempty(EEG.srate)
    error('EEG.srate missing/empty');
end

n = numel(EEG.event);
tokens  = strings(0,1);
times_s = zeros(0,1);

for k = 1:n
    t = normalize_trigger_type(EEG.event(k).type);
    if strcmpi(t, 'boundary'); continue; end
    tokens(end+1,1)  = string(t);
    times_s(end+1,1) = double(EEG.event(k).latency) / double(EEG.srate);
end
end

function [ok, rep] = check_subsequence_order_detailed(beh_tokens, eeg_tokens)
i = 1; j = 1;
lastMatchEegIdx = 0;

while i <= numel(beh_tokens) && j <= numel(eeg_tokens)
    if beh_tokens(i) == eeg_tokens(j)
        lastMatchEegIdx = j;
        i = i + 1;
        j = j + 1;
    else
        j = j + 1;
    end
end

ok = (i > numel(beh_tokens));

rep = struct();
rep.last_match_eeg_idx = lastMatchEegIdx;

if ok
    rep.summary = sprintf('OK: %d behavior tokens found in EEG stream (in-order subsequence).', numel(beh_tokens));
    rep.missing_token = "";
    rep.beh_i = NaN;
    rep.beh_ctx = strings(0,1);
    rep.eeg_ctx = strings(0,1);
    rep.beh_ctx_i1 = NaN; rep.beh_ctx_i2 = NaN;
    rep.eeg_ctx_j1 = NaN; rep.eeg_ctx_j2 = NaN;
    return;
end

rep.missing_token = beh_tokens(i);
rep.beh_i = i;

rep.beh_ctx_i1 = max(1, i-10);
rep.beh_ctx_i2 = min(numel(beh_tokens), i+10);
rep.beh_ctx = beh_tokens(rep.beh_ctx_i1:rep.beh_ctx_i2);

rep.eeg_ctx_j1 = max(1, lastMatchEegIdx-10);
rep.eeg_ctx_j2 = min(numel(eeg_tokens), lastMatchEegIdx+30);
rep.eeg_ctx = eeg_tokens(rep.eeg_ctx_j1:rep.eeg_ctx_j2);
end

%% ========================================================================
%  TOOLBOX INIT
% ========================================================================
function init_toolboxes(cfg)
    
    addpath(cfg.root_dir);
    
    eeglab_root = resolve_toolbox_root(cfg, "eeglab");
    faster_root = resolve_toolbox_root(cfg, "faster");
    
    % EEGLAB: only top folder
    if strlength(eeglab_root) > 0
        addpath(char(eeglab_root));
    end
    
    % FASTER: genpath ok
    if strlength(faster_root) > 0
        if cfg.toolboxes.use_genpath
            addpath(genpath(char(faster_root)));
        else
            addpath(char(faster_root));
        end
    end
    
    if exist('eeglab','file') ~= 2
        error('EEGLAB not found. Expected eeglab.m under: %s', eeglab_root);
    end
end

function root = resolve_toolbox_root(cfg, which)
    
    envname = upper(which) + "_ROOT";
    root = string(getenv(envname));
    if strlength(root) > 0
        return;
    end
    
    mode = string(cfg.env.mode);
    switch mode
        case "pc"
            root = string(cfg.toolboxes.("path_" + which + "_pc"));
        case "hpc"
            root = string(cfg.toolboxes.("path_" + which + "_hpc"));
        case "server"
            % treat like pc unless you add server paths later
            root = string(cfg.toolboxes.("path_" + which + "_pc"));
        otherwise
            root = "";
    end
end

function mode = detect_env_mode()
% Priority:
%  1) explicit override via PROOF_ENV_MODE
%  2) hostname looks like hummel -> hpc
%  3) SLURM present -> hpc
%  4) desktop available -> pc
%  5) otherwise -> server

v = string(getenv('PROOF_ENV_MODE'));
v = lower(strtrim(v));
if v == "pc" || v == "server" || v == "hpc"
    mode = v;
    return;
end

% --- NEW: detect hummel by hostname (works even without slurm)
hn = string(getenv('HOSTNAME'));
hn = lower(strtrim(hn));
if strlength(hn) > 0 && contains(hn, "hummel")
    mode = "hpc";
    return;
end

% keep SLURM detection as extra safety
if ~isempty(getenv('SLURM_JOB_ID'))
    mode = "hpc";
    return;
end

if usejava('desktop')
    mode = "pc";
else
    mode = "server";
end
end


function prof = default_profile_for_mode(mode)
    mode = string(lower(strtrim(mode)));
    switch mode
        case "hpc"
            prof = "hpc_hummel";
        case "pc"
            prof = "pc_now";
        otherwise
            prof = "pc_shared"; % or "pc_now" – choose what makes sense as your default "server"
    end
end

function EEG = safe_saveset(EEG, out_dir, out_fname, helpers, cfg)
% SAFE_SAVESET  Robust wrapper around pop_saveset for HPC + MATLAB string issues.

    if nargin < 5 || isempty(cfg); cfg = struct(); end
    if ~isfield(cfg,'io') || ~isfield(cfg.io,'dry_run'); cfg.io.dry_run = false; end

    out_dir   = force_char_scalar(out_dir);
    out_fname = force_char_scalar(out_fname);

    ensure_dir(out_dir);

    % Harden EEG fields that pop_saveset compares internally
    EEG.filename = force_char_scalar(getfield_safe(EEG,'filename',''));
    EEG.filepath = force_char_scalar(getfield_safe(EEG,'filepath',''));

    % Some loaders store paths in filename; avoid that
    if contains(EEG.filename, filesep) || contains(EEG.filename, '/')
        EEG.filename = '';
    end

    if cfg.io.dry_run
        helpers.logmsg_default('DRY RUN: would pop_saveset to %s', fullfile(out_dir, out_fname));
        return;
    end

    EEG = pop_saveset(EEG, 'filename', out_fname, 'filepath', out_dir);
end

function out = force_char_scalar(x)
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
        if isempty(x); out = ''; else; out = x(1,:); end
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

function [vhdr_dir, vhdr_name] = find_bids_vhdr(paths, subj_id, helpers)
% FIND_BIDS_VHDR  Find a BrainVision *.vhdr in standard BIDS locations.
% Policy:
%   - check a few plausible eeg/ directories
%   - if multiple vhdr exist, pick most recent

vhdr_dir  = '';
vhdr_name = '';

cand_dirs = {};

% preferred (mother build_paths sets these)
if isfield(paths,'bids_ses_dir') && strlength(string(paths.bids_ses_dir)) > 0
    cand_dirs{end+1} = fullfile(char(string(paths.bids_ses_dir)), 'eeg');
end

% paranoid fallbacks
if isfield(paths,'bids_sub_dir') && strlength(string(paths.bids_sub_dir)) > 0
    cand_dirs{end+1} = fullfile(char(string(paths.bids_sub_dir)), 'ses-01', 'eeg');
    cand_dirs{end+1} = fullfile(char(string(paths.bids_sub_dir)), 'eeg');
end

% de-dupe
cand_dirs = unique(cand_dirs, 'stable');

best = [];
best_dir = '';

for d = 1:numel(cand_dirs)
    eeg_dir = cand_dirs{d};
    if exist(eeg_dir,'dir') ~= 7
        continue;
    end

    cands = dir(fullfile(eeg_dir, '*.vhdr'));
    if isempty(cands)
        continue;
    end

    % pick most recent
    [~, ix] = max([cands.datenum]);
    best = cands(ix);
    best_dir = eeg_dir;
    break;
end

if isempty(best)
    if nargin >= 3 && isfield(helpers,'logmsg_default')
        helpers.logmsg_default('prep03_untilica: BIDS fallback: no *.vhdr found for sub-%s (checked: %s)', ...
            subj_id, strjoin(string(cand_dirs), ' | '));
    end
    return;
end

vhdr_dir  = best_dir;
vhdr_name = best.name;

if nargin >= 3 && isfield(helpers,'logmsg_default')
    helpers.logmsg_default('prep03_untilica: BIDS fallback: using vhdr=%s', fullfile(vhdr_dir, vhdr_name));
end
end


function EEG = safe_loadbv(vhdr_dir, vhdr_name, helpers)
% SAFE_LOADBV  Robust wrapper around pop_loadbv (BrainVision loader)

vhdr_dir  = force_char_scalar(vhdr_dir);
vhdr_name = force_char_scalar(vhdr_name);

if exist(vhdr_dir,'dir') ~= 7
    error('safe_loadbv: directory not found: %s', vhdr_dir);
end

fullp = fullfile(vhdr_dir, vhdr_name);
if exist(fullp,'file') ~= 2
    error('safe_loadbv: file not found: %s', fullp);
end

if exist('pop_loadbv','file') ~= 2
    error('safe_loadbv: pop_loadbv not found (EEGLAB BrainVision loader missing).');
end

EEG = pop_loadbv(vhdr_dir, vhdr_name);
EEG = eeg_checkset(EEG);

if nargin >= 3 && isstruct(helpers) && isfield(helpers,'logmsg_default')
    helpers.logmsg_default('Loaded BrainVision: %s', fullp);
end
end



function EEG = safe_loadset(in_dir, in_fname, helpers)
% SAFE_LOADSET  Robust wrapper around pop_loadset (fixes string/char issues).

    in_dir   = force_char_scalar(in_dir);
    in_fname = force_char_scalar(in_fname);

    if ~exist(in_dir, 'dir')
        error('safe_loadset: input directory not found: %s', in_dir);
    end

    fullp = fullfile(in_dir, in_fname);
    if exist(fullp, 'file') ~= 2
        error('safe_loadset: file not found: %s', fullp);
    end

    EEG = pop_loadset('filename', in_fname, 'filepath', in_dir);
    EEG = eeg_checkset(EEG);

    if nargin >= 3 && isstruct(helpers) && isfield(helpers,'logmsg_default')
        helpers.logmsg_default('Loaded set: %s', fullp);
    end
end


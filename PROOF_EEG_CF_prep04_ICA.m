%% ANALYSIS SCRIPT - EEG - PROOF - Classical Paradigm (Real Data)
% Metin Ozyagcilar & Saskia Wilken
% RUN ICA ON ICA-PREP DATA AND APPLY WEIGHTS TO PRE-ICA DATA
%
% Original ICA approach: Metin Ozyagcilar (Nov 2023)
% Extensions / refactor + prereg-aligned rank handling: Saskia Wilken (Jan 2026)
% MATLAB 2025b
%
% PURPOSE
%   - Read ICA-prepared datasets from:
%       ...\03_for_ica\<sub>\*_forica.set
%   - Read corresponding PRE-ICA analysis datasets from:
%       ...\02_until_ica\<sub>\*_preica.set
%   - Run ICA on the ICA-prepared dataset (default runica extended; AMICA optional)
%   - If channels were interpolated prior to ICA, reduce rank by number interpolated (prereg)
%   - Transfer ICA weights to the PRE-ICA dataset (original high-pass 0.01)
%   - Save to:
%       ...\04_after_ica\<sub>\*_ica_applied.set
%   - Append all steps to EEG.comments
%   - Save run records to scripts/logs and a composite report to MATRICS/reports
%
% IMPORTANT NOTE (Jan 2026):
%   - AMICA on Windows can fail if EEGLAB/AMICA is installed in a path that contains spaces
%     (internal system calls may not quote paths properly).
%   - If you want AMICA: ensure PATH_EEGLAB (and the AMICA plugin path) contain NO spaces.
%     Otherwise, remove spaces from the installation path or switch config.ica_method to "runica".

clear all; close all; clc;

%% =========================
%  CONFIG
%  =========================
config = struct();

% ICA method
% options: "runica" (default) | "amica"
config.ica_method                   = "amica";

% runica parameters
config.use_extended_infomax         = true;
config.interrupt_ica                = 'on';  % used only for runica

% Rank handling (prereg): reduce by number of interpolated channels (if any)
config.use_pca_rank_if_interpolated = true;

%% =========================
%  DEFINE FOLDERS
%  =========================

THIS_FILE = matlab.desktop.editor.getActiveFilename();
THIS_DIR  = fileparts(THIS_FILE);

CONFIG_DIR = fullfile(THIS_DIR, 'config');
LOGS_DIR   = fullfile(THIS_DIR, 'logs');

if ~exist(CONFIG_DIR,'dir'); mkdir(CONFIG_DIR); end
if ~exist(LOGS_DIR,'dir');   mkdir(LOGS_DIR);   end

% go up 3 levels (match your project style)
BASE_PATH   = fileparts(fileparts(fileparts(THIS_DIR)));

% EEGLAB path
PATH_EEGLAB = fullfile(BASE_PATH, 'MATLAB', 'eeglab_current', 'eeglab2025.1.0');

% MATRICS root
OUTPUT_ROOT_MATRICS   = fullfile(BASE_PATH, 'Preprocessed_data', 'MATRICS', 'eeg');

INPUT_DIR_FOR_ICA     = fullfile(OUTPUT_ROOT_MATRICS, '03_for_ica');
INPUT_DIR_PRE_ICA     = fullfile(OUTPUT_ROOT_MATRICS, '02_until_ica');

% IMPORTANT: output folder depends on ICA choice:
% - AMICA => 04_after_ica
% - Infomax (runica with extended) => 04_after_ica_infomax
if string(config.ica_method) == "runica" && config.use_extended_infomax
    OUTPUT_DIR_AFTER_ICA = fullfile(OUTPUT_ROOT_MATRICS, '04_after_ica_infomax');
else
    OUTPUT_DIR_AFTER_ICA = fullfile(OUTPUT_ROOT_MATRICS, '04_after_ica');
end

OUTPUT_DIR_REPORTS    = fullfile(OUTPUT_ROOT_MATRICS, 'reports');

if ~exist(OUTPUT_DIR_AFTER_ICA,'dir'); mkdir(OUTPUT_DIR_AFTER_ICA); end
if ~exist(OUTPUT_DIR_REPORTS,'dir');   mkdir(OUTPUT_DIR_REPORTS);   end

%% SAVE CONFIG (MAT + JSON) INTO ./config
CONFIG_MAT_PATH  = fullfile(CONFIG_DIR, 'config_04_run_ica.mat');
save(CONFIG_MAT_PATH, 'config');

CONFIG_JSON_PATH = fullfile(CONFIG_DIR, 'config_04_run_ica.json');
try
    fid = fopen(CONFIG_JSON_PATH, 'w');
    fwrite(fid, jsonencode(config, 'PrettyPrint', true), 'char');
    fclose(fid);
catch
    warning('Could not write JSON config. MAT file was saved.');
end

%% START EEGLAB ONCE (NO RESTARTS IN LOOPS)
% Important: running EEGLAB initializes plugins (including AMICA) and adds them to path
cd(PATH_EEGLAB);
[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab('nogui'); %#ok<NASGU,ASGLU>

%% AMICA GUARD (AFTER EEGLAB INIT): require no spaces + plugin available
if string(config.ica_method) == "amica"

    if contains(PATH_EEGLAB, ' ')
        error(['AMICA requested (config.ica_method="amica"), but EEGLAB is installed in a path that contains spaces:\n' ...
               '  PATH_EEGLAB = %s\n\n' ...
               'AMICA on Windows can fail when EEGLAB/AMICA paths contain spaces.\n' ...
               'Fix: reinstall/move EEGLAB (and AMICA plugin) to a no-space path (e.g., C:\\MATLAB\\eeglab\\...)\n' ...
               'OR switch to RUNICA by setting: config.ica_method = "runica";'], PATH_EEGLAB);
    end

    AMICA_SCRIPT_PATH = which('runamica15');
    if isempty(AMICA_SCRIPT_PATH)
        error(['AMICA requested (config.ica_method="amica") but runamica15 was not found on the MATLAB path.\n' ...
               'This usually means the AMICA plugin is not installed/enabled in EEGLAB.\n\n' ...
               'Fix: install/enable the AMICA plugin in EEGLAB, or switch to RUNICA:\n' ...
               '  config.ica_method = "runica";']);
    end

    if contains(AMICA_SCRIPT_PATH, ' ')
        error(['AMICA requested (config.ica_method="amica"), but the AMICA plugin is located in a path that contains spaces:\n' ...
               '  runamica15 path = %s\n\n' ...
               'Fix: move/reinstall EEGLAB+AMICA so that their paths contain no spaces,\n' ...
               'OR switch to RUNICA (config.ica_method="runica").'], AMICA_SCRIPT_PATH);
    end
end

%% SUBJECT IDS FROM 03_for_ica
ds = dir(INPUT_DIR_FOR_ICA);
ds = ds([ds.isdir]);
ds = ds(~ismember({ds.name},{'.','..'}));
subject_ids = {ds.name};

%% RUN RECORDS
ica_run_records = [];

%% =========================
%  MAIN LOOP
%  =========================
for subject_index = 2:min(3, numel(subject_ids)) % CHANGE to 1:numel(subject_ids) for all

    subject_id = subject_ids{subject_index};

    SUBJECT_IN_DIR_FOR_ICA = fullfile(INPUT_DIR_FOR_ICA, subject_id);
    SUBJECT_IN_DIR_PRE_ICA = fullfile(INPUT_DIR_PRE_ICA, subject_id);
    SUBJECT_OUT_DIR_AFTER  = fullfile(OUTPUT_DIR_AFTER_ICA, subject_id);

    if ~exist(SUBJECT_OUT_DIR_AFTER,'dir'); mkdir(SUBJECT_OUT_DIR_AFTER); end

    forica_sets = dir(fullfile(SUBJECT_IN_DIR_FOR_ICA, '*_forica.set'));
    if isempty(forica_sets)
        fprintf('Skipping %s: no *_forica.set files found.\n', subject_id);
        continue;
    end

    for file_index = 1:numel(forica_sets)

        FORICA_SET_NAME = forica_sets(file_index).name;
        RUN_BASE_NAME   = erase(FORICA_SET_NAME, '_forica.set');

        PREICA_SET_NAME = [RUN_BASE_NAME '_preica.set'];
        PREICA_SET_PATH = fullfile(SUBJECT_IN_DIR_PRE_ICA, PREICA_SET_NAME);

        if ~exist(PREICA_SET_PATH, 'file')
            fprintf('Skipping %s (%s): missing pre-ica dataset: %s\n', subject_id, RUN_BASE_NAME, PREICA_SET_PATH);
            continue;
        end

        % Load datasets
        ica_prep_eeg = pop_loadset('filename', FORICA_SET_NAME, 'filepath', SUBJECT_IN_DIR_FOR_ICA);
        ica_prep_eeg = eeg_checkset(ica_prep_eeg);

        preica_eeg  = pop_loadset('filename', PREICA_SET_NAME, 'filepath', SUBJECT_IN_DIR_PRE_ICA);
        preica_eeg  = eeg_checkset(preica_eeg);

        ica_prep_eeg = append_to_eeg_comments(ica_prep_eeg, '--- run ICA (Saskia Wilken, Jan 2026) ---');
        preica_eeg   = append_to_eeg_comments(preica_eeg,   '--- apply ICA weights (Saskia Wilken, Jan 2026) ---');

        ica_prep_eeg = append_to_eeg_comments(ica_prep_eeg, sprintf('loaded ica-prep dataset: %s', FORICA_SET_NAME));
        preica_eeg   = append_to_eeg_comments(preica_eeg,   sprintf('loaded pre-ica dataset: %s', PREICA_SET_NAME));

        %% DETERMINE INTERPOLATED COUNT (PREREG LOGIC)
        interpolated_count = 0;
        if isfield(preica_eeg, 'etc') && isfield(preica_eeg.etc, 'interpolated_channel_indices') ...
                && ~isempty(preica_eeg.etc.interpolated_channel_indices)
            interpolated_count = numel(preica_eeg.etc.interpolated_channel_indices);
        elseif isfield(preica_eeg, 'chaninfo') && isfield(preica_eeg.chaninfo, 'bad') && ~isempty(preica_eeg.chaninfo.bad)
            interpolated_count = numel(preica_eeg.chaninfo.bad);
        end

        use_pca  = false;
        pca_rank = [];

        if config.use_pca_rank_if_interpolated && interpolated_count > 0
            use_pca  = true;
            pca_rank = max(ica_prep_eeg.nbchan - interpolated_count, 1);
            ica_prep_eeg = append_to_eeg_comments(ica_prep_eeg, sprintf( ...
                'ICA rank reduction (prereg): interpolated_count=%d => pca_rank=%d', interpolated_count, pca_rank));
        else
            ica_prep_eeg = append_to_eeg_comments(ica_prep_eeg, 'ICA: no PCA rank reduction applied.');
        end

        %% RUN ICA
        ica_rank_used = ica_prep_eeg.nbchan;

        switch config.ica_method

            case "amica"
                % Prepare data matrix for AMICA (channels x samples)
                x = double(reshape(ica_prep_eeg.data, ica_prep_eeg.nbchan, ica_prep_eeg.pnts * ica_prep_eeg.trials));

                if use_pca
                    pcakeep = pca_rank;
                else
                    pcakeep = rank(x');
                end

                % Run AMICA (requires no spaces in EEGLAB/AMICA install paths)
                [ica_prep_eeg.icaweights, ica_prep_eeg.icasphere, mods] = runamica15( ...
                    x, ...
                    'pcakeep', pcakeep);

                % Compute mixing matrix
                ica_prep_eeg.icawinv = pinv(ica_prep_eeg.icaweights * ica_prep_eeg.icasphere);
                ica_rank_used = pcakeep;

                ica_prep_eeg = eeg_checkset(ica_prep_eeg);
                ica_prep_eeg = append_to_eeg_comments(ica_prep_eeg, sprintf('AMICA completed. rank used: %d', ica_rank_used));

            otherwise
                % RUNICA
                if use_pca
                    ica_prep_eeg = pop_runica(ica_prep_eeg, 'pca', pca_rank, 'interrupt', config.interrupt_ica);
                    ica_rank_used = pca_rank;
                else
                    if config.use_extended_infomax
                        ica_prep_eeg = pop_runica(ica_prep_eeg, 'extended', 1, 'interrupt', config.interrupt_ica);
                    else
                        ica_prep_eeg = pop_runica(ica_prep_eeg, 'interrupt', config.interrupt_ica);
                    end
                    ica_rank_used = ica_prep_eeg.nbchan;
                end

                ica_prep_eeg = eeg_checkset(ica_prep_eeg);
                ica_prep_eeg = append_to_eeg_comments(ica_prep_eeg, sprintf('runica completed. rank used: %d', ica_rank_used));
        end

        %% TRANSFER ICA WEIGHTS TO PRE-ICA DATA
        preica_eeg.icawinv     = ica_prep_eeg.icawinv;
        preica_eeg.icasphere   = ica_prep_eeg.icasphere;
        preica_eeg.icaweights  = ica_prep_eeg.icaweights;
        preica_eeg.icachansind = ica_prep_eeg.icachansind;

        preica_eeg = eeg_checkset(preica_eeg);
        preica_eeg = append_to_eeg_comments(preica_eeg, sprintf('ICA weights transferred from: %s', FORICA_SET_NAME));
        preica_eeg = append_to_eeg_comments(preica_eeg, 'NOTE: component rejection (pop_subcomp) not performed in this script yet.');

        %% SAVE AFTER-ICA DATASET
        AFTER_ICA_SET_NAME = [RUN_BASE_NAME '_ica_applied.set'];
        preica_eeg = pop_saveset(preica_eeg, 'filename', AFTER_ICA_SET_NAME, 'filepath', SUBJECT_OUT_DIR_AFTER);

        %% RUN RECORD
        ica_run_record = struct();
        ica_run_record.subject_id = subject_id;
        ica_run_record.run_base_name = RUN_BASE_NAME;
        ica_run_record.ica_method = string(config.ica_method);

        ica_run_record.interpolated_count = interpolated_count;
        ica_run_record.used_pca_rank = use_pca;
        ica_run_record.ica_rank_used = ica_rank_used;

        ica_run_records = [ica_run_records; ica_run_record]; %#ok<AGROW>

        fprintf('DONE ICA: %s | %s\n', subject_id, RUN_BASE_NAME);

    end
end

%% SAVE RUN RECORDS TO ./logs
timestamp_str = datestr(now, 'yyyymmdd_HHMMSS');
ICA_RECORDS_MAT_PATH = fullfile(LOGS_DIR, ['run_records_04_after_ica_' timestamp_str '.mat']);
save(ICA_RECORDS_MAT_PATH, 'ica_run_records', 'config');

%% WRITE ICA COMPOSITE REPORT
REPORT_PATH = fullfile(OUTPUT_DIR_REPORTS, 'summary_04_after_ica.txt');
write_ica_composite_summary_report(REPORT_PATH, ica_run_records, config);

fprintf('\nICA report written to:\n%s\n', REPORT_PATH);
fprintf('ICA run records saved to:\n%s\n', ICA_RECORDS_MAT_PATH);

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

function write_ica_composite_summary_report(report_path, run_records, config)

    fid = fopen(report_path, 'w');
    if fid == -1
        warning('Could not write report: %s', report_path);
        return;
    end

    fprintf(fid, 'SUMMARY REPORT - ICA RUN + WEIGHTS APPLIED\n');
    fprintf(fid, 'Generated: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(fid, 'Edits: Saskia Wilken (Jan 2026)\n\n');

    fprintf(fid, 'CONFIG SNAPSHOT\n');
    fprintf(fid, '  ica_method: %s\n', string(config.ica_method));
    fprintf(fid, '  use_pca_rank_if_interpolated: %d\n', config.use_pca_rank_if_interpolated);
    fprintf(fid, '\n');

    if isempty(run_records)
        fprintf(fid, 'No runs processed.\n');
        fclose(fid);
        return;
    end

    ica_ranks = arrayfun(@(r) r.ica_rank_used, run_records);
    interp_counts = arrayfun(@(r) r.interpolated_count, run_records);
    used_pca = arrayfun(@(r) r.used_pca_rank, run_records);

    fprintf(fid, 'PER-RUN DETAILS\n');
    for k = 1:numel(run_records)
        r = run_records(k);

        fprintf(fid, '\n  subject: %s\n', r.subject_id);
        fprintf(fid, '  run: %s\n', r.run_base_name);
        fprintf(fid, '  ica_method: %s\n', r.ica_method);
        fprintf(fid, '  interpolated_count: %d\n', r.interpolated_count);
        fprintf(fid, '  used_pca_rank: %d\n', r.used_pca_rank);
        fprintf(fid, '  ica_rank_used: %d\n', r.ica_rank_used);
    end

    fprintf(fid, '\n\nAGGREGATES ACROSS ALL RUNS\n');
    fprintf(fid, 'ICA rank used:\n');
    fprintf(fid, '  mean: %.2f | sd: %.2f | range: %d - %d\n', mean(ica_ranks), std(ica_ranks), min(ica_ranks), max(ica_ranks));

    fprintf(fid, 'Interpolated channels (prereg rank logic):\n');
    fprintf(fid, '  mean: %.2f | sd: %.2f | range: %d - %d\n', mean(interp_counts), std(interp_counts), min(interp_counts), max(interp_counts));

    fprintf(fid, 'PCA rank reduction used in %d/%d runs.\n', sum(used_pca), numel(used_pca));

    fclose(fid);
end

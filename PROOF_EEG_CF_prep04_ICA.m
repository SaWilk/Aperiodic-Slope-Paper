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
%   - (optional) re-reference to average (DEFAULT ON for ERP use; excludes non-EEG from reference)
%   - Save to:
%       ...\04_after_ica\<sub>\*_ica_applied.set
%   - Append all steps to EEG.comments
%   - Save run records to scripts/logs and a composite report to MATRICS/reports

%% TOOLBOXES / PLUG-INs
% (1) EEGLAB (v2023.1 & 2025.1)
% (2) AMICA plugin (optional) - runamica15

%%

clear all; close all; clc;

%% =========================
%  CONFIG 
%  =========================
config = struct();

% ICA method
% options: "runica" (default) | "amica"
config.ica_method                 = "amica";

% runica parameters
config.use_extended_infomax        = true;
config.interrupt_ica               = 'on';

% Rank handling (prereg): reduce by number of interpolated channels (if any)
config.use_pca_rank_if_interpolated = true;


%% =========================
%  DEFINE FOLDERS
%  =========================

this_file = matlab.desktop.editor.getActiveFilename();
this_dir  = fileparts(this_file);

config_dir = fullfile(this_dir, 'config');
logs_dir   = fullfile(this_dir, 'logs');

if ~exist(config_dir,'dir'); mkdir(config_dir); end
if ~exist(logs_dir,'dir');   mkdir(logs_dir);   end

base_path = fileparts(fileparts(fileparts(this_dir)));

path_eeglab = [base_path, '\MATLAB\eeglab_current\eeglab2025.1.0'];

OUTPUT_ROOT_MATRICS = 'K:\Wilken Arbeitsordner\Preprocessed_data\MATRICS';

INPUT_DIR_FOR_ICA    = fullfile(OUTPUT_ROOT_MATRICS, '03_for_ica');
INPUT_DIR_PRE_ICA    = fullfile(OUTPUT_ROOT_MATRICS, '02_until_ica');
OUTPUT_DIR_AFTER_ICA = fullfile(OUTPUT_ROOT_MATRICS, '04_after_ica');
OUTPUT_DIR_REPORTS   = fullfile(OUTPUT_ROOT_MATRICS, 'reports');

if ~exist(OUTPUT_DIR_AFTER_ICA,'dir'); mkdir(OUTPUT_DIR_AFTER_ICA); end
if ~exist(OUTPUT_DIR_REPORTS,'dir');   mkdir(OUTPUT_DIR_REPORTS);   end

%% SAVE CONFIG (MAT + JSON) INTO ./config
config_mat_path  = fullfile(config_dir, 'config_04_run_ica.mat');
save(config_mat_path, 'config');

config_json_path = fullfile(config_dir, 'config_04_run_ica.json');
try
    fid = fopen(config_json_path, 'w');
    fwrite(fid, jsonencode(config, 'PrettyPrint', true), 'char');
    fclose(fid);
catch
    warning('Could not write JSON config. MAT file was saved.');
end

%% START EEGLAB ONCE
cd(path_eeglab);
eeglab nogui;
eeglab redraw

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
for subject_index = 1:3%length(subject_ids)

    subject_id = subject_ids{subject_index};

    subject_in_dir_for_ica = fullfile(INPUT_DIR_FOR_ICA, subject_id);
    subject_in_dir_pre_ica = fullfile(INPUT_DIR_PRE_ICA, subject_id);
    subject_out_dir_after  = fullfile(OUTPUT_DIR_AFTER_ICA, subject_id);

    if ~exist(subject_out_dir_after,'dir'); mkdir(subject_out_dir_after); end

    forica_sets = dir(fullfile(subject_in_dir_for_ica, '*_forica.set'));
    if isempty(forica_sets)
        fprintf('Skipping %s: no *_forica.set files found.\n', subject_id);
        continue;
    end

    for file_index = 1:numel(forica_sets)

        eeglab redraw

        forica_set_name = forica_sets(file_index).name;
        run_base_name = erase(forica_set_name, '_forica.set');

        preica_set_name = [run_base_name '_preica.set'];
        preica_set_path = fullfile(subject_in_dir_pre_ica, preica_set_name);

        if ~exist(preica_set_path, 'file')
            fprintf('Skipping %s (%s): missing pre-ica dataset: %s\n', subject_id, run_base_name, preica_set_path);
            continue;
        end

        [ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab; 

        ica_prep_eeg = pop_loadset('filename', forica_set_name, 'filepath', subject_in_dir_for_ica);
        ica_prep_eeg = eeg_checkset(ica_prep_eeg);

        preica_eeg  = pop_loadset('filename', preica_set_name, 'filepath', subject_in_dir_pre_ica);
        preica_eeg  = eeg_checkset(preica_eeg);

        ica_prep_eeg = append_to_eeg_comments(ica_prep_eeg, '--- run ICA (Saskia Wilken, Jan 2026) ---');
        preica_eeg   = append_to_eeg_comments(preica_eeg,   '--- apply ICA weights (Saskia Wilken, Jan 2026) ---');

        ica_prep_eeg = append_to_eeg_comments(ica_prep_eeg, sprintf('loaded ica-prep dataset: %s', forica_set_name));
        preica_eeg   = append_to_eeg_comments(preica_eeg,   sprintf('loaded pre-ica dataset: %s', preica_set_name));

        %% DETERMINE INTERPOLATED COUNT (PREREG LOGIC)
        interpolated_count = 0;
        if isfield(preica_eeg, 'etc') && isfield(preica_eeg.etc, 'interpolated_channel_indices') ...
                && ~isempty(preica_eeg.etc.interpolated_channel_indices)
            interpolated_count = numel(preica_eeg.etc.interpolated_channel_indices);
        elseif isfield(preica_eeg, 'chaninfo') && isfield(preica_eeg.chaninfo, 'bad') && ~isempty(preica_eeg.chaninfo.bad)
            % fallback: if chaninfo.bad exists, and interpolation was prereg default, this is often identical
            interpolated_count = numel(preica_eeg.chaninfo.bad);
        end

        use_pca = false;
        pca_rank = [];

        if config.use_pca_rank_if_interpolated && interpolated_count > 0
            use_pca = true;
            pca_rank = max(ica_prep_eeg.nbchan - interpolated_count, 1);
            ica_prep_eeg = append_to_eeg_comments(ica_prep_eeg, sprintf('ICA rank reduction (prereg): interpolated_count=%d => pca_rank=%d', ...
                interpolated_count, pca_rank));
        else
            ica_prep_eeg = append_to_eeg_comments(ica_prep_eeg, 'ICA: no PCA rank reduction applied.');
        end

        %% RUN ICA
        ica_rank_used = ica_prep_eeg.nbchan;

        switch config.ica_method
            case "amica"
                if exist('runamica15','file') ~= 2
                    error('config.ica_method="amica" but runamica15 is not available (AMICA plugin missing).');
                end

                % Prepare data matrix for AMICA (channels x samples)
                x = double(reshape(ica_prep_eeg.data, ica_prep_eeg.nbchan, ica_prep_eeg.pnts * ica_prep_eeg.trials));

                if use_pca
                    pcakeep = pca_rank;
                else
                    pcakeep = rank(x'); % conservative fallback if no getrank() available
                end

                [ica_prep_eeg.icaweights, ica_prep_eeg.icasphere, mods] = runamica15( ...
                    x, 'pcakeep', pcakeep);

                ica_prep_eeg.icawinv = pinv(ica_prep_eeg.icaweights * ica_prep_eeg.icasphere);
                ica_rank_used = pcakeep;

                ica_prep_eeg = eeg_checkset(ica_prep_eeg);
                ica_prep_eeg = append_to_eeg_comments(ica_prep_eeg, sprintf('AMICA completed. rank used: %d', ica_rank_used));

            otherwise
                if use_pca
                    ica_prep_eeg = pop_runica(ica_prep_eeg, 'pca', pca_rank, 'interupt', config.interrupt_ica);
                    ica_rank_used = pca_rank;
                else
                    if config.use_extended_infomax
                        ica_prep_eeg = pop_runica(ica_prep_eeg, 'extended', 1, 'interupt', config.interrupt_ica);
                    else
                        ica_prep_eeg = pop_runica(ica_prep_eeg, 'interupt', config.interrupt_ica);
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
        preica_eeg = append_to_eeg_comments(preica_eeg, sprintf('ICA weights transferred from: %s', forica_set_name));
        preica_eeg = append_to_eeg_comments(preica_eeg, 'NOTE: component rejection (pop_subcomp) not performed in this script yet.');

        %% SAVE AFTER-ICA DATASET
        after_ica_set_name = [run_base_name '_ica_applied.set'];
        preica_eeg = pop_saveset(preica_eeg, 'filename', after_ica_set_name, 'filepath', subject_out_dir_after);

        %% RUN RECORD
        ica_run_record = struct();
        ica_run_record.subject_id = subject_id;
        ica_run_record.run_base_name = run_base_name;
        ica_run_record.ica_method = string(config.ica_method);

        ica_run_record.interpolated_count = interpolated_count;
        ica_run_record.used_pca_rank = use_pca;
        ica_run_record.ica_rank_used = ica_rank_used;

        ica_run_records = [ica_run_records; ica_run_record]; %#ok<AGROW>

        fprintf('DONE ICA: %s | %s\n', subject_id, run_base_name);

    end
end

%% SAVE RUN RECORDS TO ./logs
timestamp_str = datestr(now, 'yyyymmdd_HHMMSS');
ica_records_mat_path = fullfile(logs_dir, ['run_records_04_after_ica_' timestamp_str '.mat']);
save(ica_records_mat_path, 'ica_run_records', 'config');

%% WRITE ICA COMPOSITE REPORT
report_path = fullfile(OUTPUT_DIR_REPORTS, 'summary_04_after_ica.txt');
write_ica_composite_summary_report(report_path, ica_run_records, config);

fprintf('\nICA report written to:\n%s\n', report_path);
fprintf('ICA run records saved to:\n%s\n', ica_records_mat_path);

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

%% ANALYSIS SCRIPT - EEG - PROOF - Classical Paradigm (Real Data)
% Saskia Wilken & Metin Ozyagcilar
% SCRIPT 05: AUTOMATIC ICA COMPONENT REJECTION (ICLabel) UNTIL EPOCHING
% Jan 2026 | MATLAB 2025b | EEGLAB 2025.1
%
% PURPOSE
%   - Input:  ...\04_after_ica\<sub>\*_ica_applied.set
%   - Automatic IC rejection using ICLabel (eye/muscle/heart thresholds below)
%   - Output: ...\05_until_epoching\<sub>\*_until_epoching.set
%   - QA: Save ONE PNG per dataset with ALL IC topoplots to scripts/checks/ica_comps
%   - Logging: append-per-run TSV to scripts/logs (written DURING execution)
%
% IMPORTANT
%   - This script does NOT epoch. Epoching is a separate script later.
%   - This script does NOT reference (to avoid invalidating ICA fields).

clear; close all; clc;

%% =========================
%  CONFIG (simple)
%  =========================
config = struct();

% --- IO ---
config.skip_if_output_exists   = false;

% --- ICLabel thresholds (your changed criteria) ---
config.iclabel_eye_remove_thr     = 0.80;  % remove if P(eye)    > thr
config.iclabel_muscle_remove_thr  = 0.80;  % remove if P(muscle) > thr
config.iclabel_heart_remove_thr   = 0.80;  % remove if P(heart)  > thr

% --- QA ---
config.save_ic_topos_png       = true;
config.ic_topo_grid            = [8 8];    % good for ~64 ICs
config.ic_topo_dpi             = 200;      % keeps file sizes manageable

%% =========================
%  DEFINE FOLDERS
%  =========================
this_file = matlab.desktop.editor.getActiveFilename();
this_dir  = fileparts(this_file);
base_path = fileparts(fileparts(fileparts(this_dir)));

% EEGLAB path (your MATRICS style)
path_eeglab = [base_path, '\MATLAB\eeglab_current\eeglab2025.1.0'];

% MATRICS root
OUTPUT_ROOT_MATRICS   = 'K:\Wilken Arbeitsordner\Preprocessed_data\MATRICS';
INPUT_DIR_AFTER_ICA   = fullfile(OUTPUT_ROOT_MATRICS, '04_after_ica');
OUTPUT_DIR_UNTIL_EPOC = fullfile(OUTPUT_ROOT_MATRICS, '05_until_epoching');

if ~exist(OUTPUT_DIR_UNTIL_EPOC,'dir'); mkdir(OUTPUT_DIR_UNTIL_EPOC); end

% script-local logs + checks
logs_dir   = fullfile(this_dir, 'logs');
checks_dir = fullfile(this_dir, 'checks', 'ica_comps');
if ~exist(logs_dir,'dir');   mkdir(logs_dir);   end
if ~exist(checks_dir,'dir'); mkdir(checks_dir); end

runlog_path = fullfile(logs_dir, '05_until_epoching_icrejection_runlog.tsv');

%% =========================
%  START EEGLAB (no GUI)
%  =========================
cd(path_eeglab);
eeglab nogui;
eeglab redraw;

%% =========================
%  DISCOVER SUBJECTS
%  =========================
ds = dir(INPUT_DIR_AFTER_ICA);
ds = ds([ds.isdir]);
ds = ds(~ismember({ds.name},{'.','..'}));
subject_ids = {ds.name};

%% =========================
%  RUNLOG HEADER
%  =========================
ensure_runlog_header(runlog_path);

%% =========================
%  MAIN LOOP
%  =========================
for si = 1:3%numel(subject_ids)

    subject_id = subject_ids{si};
    subj_in_dir  = fullfile(INPUT_DIR_AFTER_ICA, subject_id);
    subj_out_dir = fullfile(OUTPUT_DIR_UNTIL_EPOC, subject_id);
    if ~exist(subj_out_dir,'dir'); mkdir(subj_out_dir); end

    in_sets = dir(fullfile(subj_in_dir, '*_ica_applied.set'));
    if isempty(in_sets)
        append_runlog(runlog_path, subject_id, '', 'skipped_no_input', config, struct());
        continue;
    end

    for fi = 1:numel(in_sets)

        in_name  = in_sets(fi).name;
        run_base = erase(in_name, '_ica_applied.set');
        in_path  = fullfile(subj_in_dir, in_name);

        out_name = [run_base '_until_epoching.set'];
        out_path = fullfile(subj_out_dir, out_name);

        if exist(out_path,'file') && config.skip_if_output_exists
            append_runlog(runlog_path, subject_id, run_base, 'skipped_output_exists', config, struct('input', in_path, 'output', out_path));
            continue;
        end

        try
            EEG = pop_loadset('filename', in_name, 'filepath', subj_in_dir);
            EEG = eeg_checkset(EEG);

            EEG = append_to_eeg_comments(EEG, '--- SCRIPT 05: ICLabel IC rejection until epoching (Jan 2026) ---');
            EEG = append_to_eeg_comments(EEG, sprintf('input: %s', in_name));
            EEG = append_to_eeg_comments(EEG, sprintf('ICLabel thresholds: eye>%.2f | muscle>%.2f | heart>%.2f', ...
                config.iclabel_eye_remove_thr, config.iclabel_muscle_remove_thr, config.iclabel_heart_remove_thr));

            % Require ICA present
            nIC = 0;
            if isfield(EEG,'icawinv') && ~isempty(EEG.icawinv)
                nIC = size(EEG.icawinv,2);
            end

            if nIC < 2
                EEG = append_to_eeg_comments(EEG, sprintf('SKIP: dataset has insufficient ICA components (nIC=%d).', nIC));
                append_runlog(runlog_path, subject_id, run_base, 'skipped_no_ica', config, struct('nIC', nIC, 'input', in_path));
                continue;
            end

            %% QA: plot ALL IC topoplots (one PNG) -- robust
            if config.save_ic_topos_png
                fig = figure('Visible','off');

                try
                    nIC = size(EEG.icawinv,2);

                    % Use chanlocs corresponding to ICA channels (usually all, but robust)
                    if isfield(EEG,'icachansind') && ~isempty(EEG.icachansind)
                        chanlocs_ica = EEG.chanlocs(EEG.icachansind);
                    else
                        chanlocs_ica = EEG.chanlocs(1:size(EEG.icawinv,1));
                    end

                    nRows = config.ic_topo_grid(1);
                    nCols = config.ic_topo_grid(2);

                    for ic = 1:nIC
                        subplot(nRows, nCols, ic);
                        topoplot(EEG.icawinv(:,ic), chanlocs_ica, 'electrodes','on');
                        title(sprintf('%d', ic), 'Interpreter','none');
                    end
                    sgtitle(sprintf('%s | IC topoplots (n=%d)', EEG.setname, nIC), 'Interpreter','none');

                catch ME
                    clf(fig); axis off;
                    text(0, 0.5, sprintf('%s | Could not plot IC topoplots\n%s', EEG.setname, ME.message), ...
                        'Interpreter','none');
                    fprintf('Topoplot failed for %s: %s\n', EEG.setname, ME.message);
                end

                png_name = sprintf('%s_%s_all%dICs.png', subject_id, run_base, nIC);
                png_path = fullfile(checks_dir, png_name);

                set(fig,'PaperUnits','centimeters','PaperPosition',[0 0 24 24]);
                print(fig, '-dpng', sprintf('-r%d', config.ic_topo_dpi), png_path);
                close(fig);
            end


            %% ICLabel + select ICs to remove
            EEG = iclabel(EEG);

            classif  = EEG.etc.ic_classification.ICLabel.classifications; % [nIC x 7]
            % ICLabel columns: 1 Brain, 2 Muscle, 3 Eye, 4 Heart, 5 Line Noise, 6 Channel Noise, 7 Other
            p_muscle = classif(:,2);
            p_eye    = classif(:,3);
            p_heart  = classif(:,4);

            eyes   = find(p_eye    > config.iclabel_eye_remove_thr);
            muscle = find(p_muscle > config.iclabel_muscle_remove_thr);
            heart  = find(p_heart  > config.iclabel_heart_remove_thr);

            ic2rem = unique([eyes; muscle; heart]);

            info = struct();
            info.nIC = nIC;
            info.ic_remove = ic2rem(:)';
            info.input  = in_path;
            info.output = out_path;

            EEG.etc.ic_rejection = struct();
            EEG.etc.ic_rejection.mode = "iclabel_thresholds_eye_muscle_heart";
            EEG.etc.ic_rejection.ic2rem = info.ic_remove;
            EEG.etc.ic_rejection.eye_thr = config.iclabel_eye_remove_thr;
            EEG.etc.ic_rejection.muscle_thr = config.iclabel_muscle_remove_thr;
            EEG.etc.ic_rejection.heart_thr = config.iclabel_heart_remove_thr;
            EEG.etc.ic_rejection.timestamp = datestr(now,'yyyy-mm-dd HH:MM:SS');

            EEG = append_to_eeg_comments(EEG, sprintf('ICLabel: nIC=%d | eyes=%d | muscle=%d | heart=%d | remove=%d', ...
                nIC, numel(eyes), numel(muscle), numel(heart), numel(ic2rem)));

            %% Apply removal
            if ~isempty(ic2rem)
                EEG = pop_subcomp(EEG, ic2rem, 0); % 0=no confirmation
                EEG = eeg_checkset(EEG);
                EEG = append_to_eeg_comments(EEG, sprintf('Removed ICs: %s', mat2str(ic2rem(:)')));
            else
                EEG = append_to_eeg_comments(EEG, 'No ICs removed by ICLabel thresholds.');
            end

            %% Save output
            EEG.setname = [run_base '_until_epoching'];
            EEG = pop_saveset(EEG, 'filename', out_name, 'filepath', subj_out_dir);

            append_runlog(runlog_path, subject_id, run_base, 'processed', config, info);
            fprintf('DONE: %s | %s\n', subject_id, run_base);

        catch ME
            append_runlog(runlog_path, subject_id, run_base, 'error', config, struct('input', in_path, 'output', out_path, 'error', ME.message));
            fprintf('ERROR: %s | %s\n  %s\n', subject_id, run_base, ME.message);
        end

    end
end

fprintf('\nRun log written incrementally to:\n%s\n', runlog_path);

%% =================
%  LOCAL FUNCTIONS
%  =================
function EEG = append_to_eeg_comments(EEG, message_text)
time_stamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
line_text  = sprintf('[%s] %s', time_stamp, message_text);

if ~isfield(EEG,'comments') || isempty(EEG.comments)
    EEG.comments = line_text;
else
    EEG.comments = sprintf('%s\n%s', EEG.comments, line_text);
end
end

function ensure_runlog_header(runlog_path)
if exist(runlog_path,'file')
    return;
end
fid = fopen(runlog_path, 'w');
if fid == -1
    warning('Could not create runlog file: %s', runlog_path);
    return;
end
fprintf(fid, 'timestamp\tsubject\trun\tstatus\ticlabel_eye_thr\ticlabel_muscle_thr\ticlabel_heart_thr\tnIC\tnRemoved\tremovedICs\tinput\toutput\terror\n');
fclose(fid);
end

function append_runlog(runlog_path, subject_id, run_base, status, config, info)
ts = datestr(now,'yyyy-mm-dd HH:MM:SS');

nIC = NaN;
if isfield(info,'nIC'); nIC = info.nIC; end

removed = [];
if isfield(info,'ic_remove'); removed = info.ic_remove; end
nRemoved = numel(removed);
removed_str = '';
if ~isempty(removed)
    removed_str = mat2str(removed(:)');
end

inpath  = '';
outpath = '';
errtxt  = '';

if isfield(info,'input');  inpath  = string(info.input);  end
if isfield(info,'output'); outpath = string(info.output); end
if isfield(info,'error');  errtxt  = string(info.error);  end

fid = fopen(runlog_path, 'a');
if fid == -1
    warning('Could not open runlog file for append: %s', runlog_path);
    return;
end

fprintf(fid, '%s\t%s\t%s\t%s\t%.3f\t%.3f\t%.3f\t%.0f\t%d\t%s\t%s\t%s\t%s\n', ...
    ts, subject_id, run_base, status, ...
    config.iclabel_eye_remove_thr, config.iclabel_muscle_remove_thr, config.iclabel_heart_remove_thr, ...
    nIC, nRemoved, removed_str, inpath, outpath, errtxt);

fclose(fid);
end


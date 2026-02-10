%% ANALYSIS SCRIPT - EEG - PROOF - Classical Paradigm / Saskia Wilken
% BIDS ORGANIZATION (BrainVision RAW -> BIDS structure)
% MATLAB 2025b

clear all; close all; clc;

%% DEFINE FOLDERS

% Get full path of this script
this_file  = matlab.desktop.editor.getActiveFilename();  % works in .m files
this_dir   = fileparts(this_file);                       % folder the script is in

% Go up 3 levels (kept from your version, but you can ignore if not needed)
base_path  = fileparts(fileparts(fileparts(this_dir)));

BASE_PATH_II = 'K:\Wilken_Arbeitsordner';

% (Not used in this script, kept as-is)
MAINPATH     = [base_path, '\Aperiodic\Saskia\Aperiodic-Slope-Paper'];

PATH_EEGLAB  = [BASE_PATH_II, '\MATLAB\eeglab_current\eeglab2025.1.0']; % adjust if needed
PATH_RAWDATA = [BASE_PATH_II, '\Raw_data\'];                            % where raw data is located
PATH_EEG     = fullfile(PATH_RAWDATA, 'RTG_Metin_Nilay_EEG_Baseline');  % raw BrainVision files live here

% BIDS root (output)
bids_root    = fullfile(PATH_RAWDATA, 'BIDS_RTGMN_Baseline');

%% CONFIG

TASK_LABEL    = 'baseline';
SESSION_LABEL = '01';   % all data recorded in session 01

% Re-add EEG to BIDS (copy/rename raw BrainVision)
DO_EEG = true;

% --- Regex for your BrainVision headers ---
% Matches:
%   B_012.vhdr
%   B_012_001.vhdr   (optional run)
RE_VHDR = '^B_(\d{3})(?:_(\d{3}))?\.vhdr$';

% Regex for existing BIDS EEG headers (only used if DO_EEG == false)
% sub-012_ses-01_task-baseline(_run-001)?_eeg.vhdr
RE_BIDS_VHDR = '^sub-(\d+)_ses-(\d+)_task-([A-Za-z0-9]+)(?:_run-(\d+))?_eeg\.vhdr$';

%% START EEGLAB (optional exporter attempt)
cd(PATH_EEGLAB);
[ALLEEG, EEG, CURRENTSET, ~] = eeglab;

%% PREP BIDS ROOT
if ~exist(bids_root, 'dir'); mkdir(bids_root); end
wrote_description = false;

%% LIST EEG FILES (two modes)
if DO_EEG
    vhdr_files = dir(fullfile(PATH_EEG, '*.vhdr'));                 % raw BrainVision headers
else
    vhdr_files = dir(fullfile(bids_root, '**', '*_eeg.vhdr'));      % already BIDS headers
end

%% LOOP OVER FILES AND ORGANIZE INTO BIDS
for k = 1:numel(vhdr_files)

    if DO_EEG
        % --- RAW -> BIDS ---
        src_vhdr = vhdr_files(k).name;
        tokens   = regexp(src_vhdr, RE_VHDR, 'tokens', 'once');
        if isempty(tokens)
            % not matching your B_### pattern -> skip
            continue;
        end

        subj_num_raw = tokens{1};  % e.g., '012' (already 3-digit)

        hasRun = numel(tokens) >= 2 && ~isempty(tokens{2});
        if hasRun
            run_label = tokens{2};                 % '001', '002', ...
            run_tag   = ['_run-' run_label];
        else
            run_label = '';
            run_tag   = '';
        end

        % Ensure 3-digit subject label for BIDS (sub-012)
        subj_num = sprintf('%03d', str2double(subj_num_raw));

        sub_label = sprintf('sub-%s', subj_num);
        ses_label = sprintf('ses-%s', SESSION_LABEL);

        % BIDS destination folders
        eeg_dir = fullfile(bids_root, sub_label, ses_label, 'eeg');
        if ~exist(eeg_dir, 'dir'); mkdir(eeg_dir); end

        % Compose BIDS base filename (run only if present)
        bids_base = sprintf('%s_%s_task-%s%s', sub_label, ses_label, TASK_LABEL, run_tag);

        % Source trio (BrainVision)
        [~, base_noext] = fileparts(src_vhdr);   % e.g., 'B_012' or 'B_012_001'
        src_vmrk = [base_noext '.vmrk'];

        % .eeg could be '.eeg' or '.dat'
        if exist(fullfile(PATH_EEG, [base_noext '.eeg']), 'file')
            src_eeg = [base_noext '.eeg'];
        else
            src_eeg = [base_noext '.dat'];
        end

        % Destination trio (BrainVision renamed to BIDS)
        dst_vhdr = fullfile(eeg_dir, [bids_base '_eeg.vhdr']);
        dst_vmrk = fullfile(eeg_dir, [bids_base '_eeg.vmrk']);
        [~, ~, eeg_ext] = fileparts(src_eeg);
        dst_eeg  = fullfile(eeg_dir, [bids_base '_eeg' eeg_ext]);

        % Copy/rename the files
        copyfile(fullfile(PATH_EEG, src_vhdr), dst_vhdr);
        if exist(fullfile(PATH_EEG, src_vmrk), 'file')
            copyfile(fullfile(PATH_EEG, src_vmrk), dst_vmrk);
        else
            warning('Missing .vmrk for %s', src_vhdr);
        end

        if exist(fullfile(PATH_EEG, src_eeg), 'file')
            copyfile(fullfile(PATH_EEG, src_eeg), dst_eeg);
        else
            warning('Missing data file (.eeg/.dat) for %s', src_vhdr);
        end

    else
        % --- EEG already BIDS ---
        src_vhdr = vhdr_files(k).name;
        eeg_dir  = vhdr_files(k).folder;

        tokens = regexp(src_vhdr, RE_BIDS_VHDR, 'tokens', 'once');
        if isempty(tokens); continue; end

        subj_num = tokens{1};
        ses_from_name = tokens{2};
        task_from_name = tokens{3};

        hasRun = numel(tokens) >= 4 && ~isempty(tokens{4});
        run_tag = '';
        if hasRun
            run_tag = ['_run-' tokens{4}];
        end

        sub_label = sprintf('sub-%s', subj_num);
        ses_label = sprintf('ses-%s', ses_from_name);

        bids_base = sprintf('%s_%s_task-%s%s', sub_label, ses_label, task_from_name, run_tag);
    end

    % --- OPTIONAL: EEGLAB BIDS exporter attempt (not required; renamed files already BIDS-valid) ---
    if DO_EEG
        try
            EEG = pop_loadbv(eeg_dir, [bids_base '_eeg.vhdr']);
            [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, 1, 'gui', 'off');

            export_args = {'subject', subj_num, ...
                           'session', SESSION_LABEL, ...
                           'task',    TASK_LABEL, ...
                           'dataformat', 'BrainVision', ...
                           'overwrite', 'on', ...
                           'bidsevent', 'off'};  % no behavior/events in baseline

            if hasRun
                export_args = [export_args, {'run', str2double(run_label)}]; %#ok<AGROW>
            end
               
            EEG = eeg_checkset(EEG);
            pop_exportbids(EEG, bids_root, export_args{:});
            wrote_description = true;

            eeglab redraw;
        catch ME
            % If exporter differs by EEGLAB version, copied/renamed files remain valid BIDS structure.
            warning('EEGLAB exportbids failed for %s (%s). Keeping copied BIDS structure.', bids_base, ME.message);
        end
    end

end

%% OPTIONAL: write a minimal README if exporter didn't
if ~wrote_description
    fid = fopen(fullfile(bids_root, 'README'), 'w');
    if fid>0
        fprintf(fid, 'BIDS dataset: RTG_Metin_Nilay EEG (baseline)\n');
        fprintf(fid, 'Data organized via script: BrainVision RAW (B_###) -> BIDS folders + renamed files.\n');
        fprintf(fid, 'No behavioral/events files for this baseline activity.\n');
        fclose(fid);
    end
end

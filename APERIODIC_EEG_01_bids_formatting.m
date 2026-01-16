%% ANALYSIS SCRIPT - EEG - PROOF - Classical Paradigm (Real Data) / Saskia Wilken / BIDS ORGANIZATION / DEZ 2025
% MATLAB 2025b

%% TOOLBOXES / PLUG-INs
% (1) EEGLAB (2025.1)
% Delorme A & Makeig S (2004) EEGLAB: an open-source toolbox for analysis of single-trial EEG dynamics,
% Journal of Neuroscience Methods 134:9-21

%%

clear all; close all; clc;

%% DEFINE FOLDERS

% Get full path of this script
this_file  = matlab.desktop.editor.getActiveFilename();           % works in .m files
this_dir   = fileparts(this_file);                                % folder the script is in

% Go up 3 levels
base_path_remote  = [fileparts(fileparts(fileparts(this_dir))),filesep, 'Aperiodic',filesep, 'Saskia'];
base_path_local = 'K:\Wilken Arbeitsordner';

% mainpath = 'D:\PROOF';
mainpath     = [base_path_remote, '\Aperiodic-Slope-Paper']; % if you work laptop
path_eeglab  = [base_path_local, '\MATLAB\eeglab_current\eeglab2025.1.0'];         % where eeglab is located
path_rawdata = [base_path_local, '\Raw_data\RTG_Metin_Nilay_EEG_Baseline'];    % where raw data is located

% BIDS root will live *inside* the RTG_Metin_Nilay folder
bids_root    = fullfile([base_path_remote, filesep, 'rawdata']);

%% CONFIG

task_label    = 'classical';
session_label = '01';   % all data recorded in session 01

% Regex for BrainVision headers:
% B_<subject>(_<run>)?.vhdr  e.g., CF_211.vhdr  or CF_211_002.vhdr
re_vhdr = '^B_(\d+)(?:_(\d{3}))?\.vhdr$';

%% START EEGLAB (for metadata export)
cd(path_eeglab);
eeglab; eeglab redraw;

%% PREP BIDS ROOT
if ~exist(bids_root, 'dir'); mkdir(bids_root); end
wrote_description = false;  % track if exporter wrote dataset_description

%% LIST ALL VHDR FILES
vhdr_files = dir(fullfile(path_rawdata, '*.vhdr'));

%% LOOP OVER FILES AND ORGANIZE INTO BIDS
for k = 1:numel(vhdr_files)

    src_vhdr = vhdr_files(k).name;
    tokens   = regexp(src_vhdr, re_vhdr, 'tokens', 'once');
    if isempty(tokens); continue; end

    subj_num = tokens{1};                                  % e.g., '211'
    hasRun   = numel(tokens) >= 2 && ~isempty(tokens{2});  % true if _### was present
    if hasRun
        run_label = tokens{2};                             % '001', '002', ...
        run_tag   = ['_run-' run_label];
    else
        run_label = '';
        run_tag   = '';
    end

    sub_label = sprintf('sub-%s', subj_num);
    ses_label = sprintf('ses-%s', session_label);

    % BIDS destination folders
    eeg_dir   = fullfile(bids_root, sub_label, ses_label, 'eeg');
    if ~exist(eeg_dir, 'dir'); mkdir(eeg_dir); end

    % Compose BIDS base filename (run only if present)
    bids_base = sprintf('%s_%s_task-%s%s', sub_label, ses_label, task_label, run_tag);

    % Source trio (BrainVision)
    [~, base_noext] = fileparts(src_vhdr);                 % e.g., 'CF_211' or 'CF_211_002'
    src_vmrk = [base_noext '.vmrk'];

    % .eeg could be '.eeg' or '.dat' depending on recorder; prefer .eeg if present
    if exist(fullfile(path_rawdata, [base_noext '.eeg']), 'file')
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
    copyfile(fullfile(path_rawdata, src_vhdr), dst_vhdr);
    if exist(fullfile(path_rawdata, src_vmrk), 'file'); copyfile(fullfile(path_rawdata, src_vmrk), dst_vmrk); end
    if exist(fullfile(path_rawdata, src_eeg),  'file'); copyfile(fullfile(path_rawdata, src_eeg),  dst_eeg);  end

    % Rename/relocate the one experiment .log per subject (if present) -> *_events.log
    % looks for CF_<subj>.log or CF_<subj>_*.log (also accepts .txt)
    log_candidates = [ dir(fullfile(path_rawdata, sprintf('CF_%s*.log', subj_num))) ; ...
                       dir(fullfile(path_rawdata, sprintf('CF_%s*.txt', subj_num))) ];
    if ~isempty(log_candidates)
        src_log = fullfile(log_candidates(1).folder, log_candidates(1).name);
        dst_log = fullfile(eeg_dir, [bids_base '_events.log']);
        copyfile(src_log, dst_log);
    end

    % --- Use EEGLAB's BIDS exporter to write minimal sidecars/description ---
    [ALLEEG, EEG, CURRENTSET, ~] = eeglab;
    EEG = pop_loadbv(eeg_dir, [bids_base '_eeg.vhdr']);            % load the BIDS-renamed header
    [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, 1, 'gui', 'off');

    % Build export args; only pass 'run' when present
    export_args = {'subject', subj_num, ...
                   'session', session_label, ...
                   'task',    task_label, ...
                   'dataformat', 'BrainVision', ...
                   'overwrite', 'on', ...
                   'bidsevent', 'off'};  % we placed *_events.log already

    if hasRun
        export_args = [export_args, {'run', str2double(run_label)}]; %#ok<AGROW>
    end

    try
        pop_exportbids(EEG, bids_root, export_args{:});
        wrote_description = true;
    catch
        % If exporter differs by EEGLAB version, copied/renamed files remain valid BIDS structure.
    end

    eeglab redraw;
end

%% OPTIONAL: write a minimal README if exporter didn't (kept short)
if ~wrote_description
    fid = fopen(fullfile(bids_root, 'README'), 'w');
    if fid>0
        fprintf(fid, 'BIDS dataset: RTG_Metin_Nilay EEG (baseline)\n');
        fprintf(fid, 'Data organized via script using BrainVision to BIDS renaming.\n');
        fclose(fid);
    end
end
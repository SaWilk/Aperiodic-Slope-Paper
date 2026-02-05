%% ANALYSIS SCRIPT - EEG - PROOF - Classical Paradigm / Saskia Wilken / BIDS ORGANIZATION / DEZ 2025
% MATLAB 2025b

%% TOOLBOXES / PLUG-INs
% (1) EEGLAB (2025.1)
% Delorme A & Makeig S (2004) EEGLAB: an open-source toolbox for analysis of single-trial EEG dynamics,
% Journal of Neuroscience Methods 134:9-21

%% HOW TO USE
% Standalone script; put in appropriate ROOT folder and adjust the relative
% paths to it (you are defining the ROOT folder by putting the script in
% it)

%%

clear all; close all; clc;

%% DEFINE FOLDERS

% Get full path of this script
this_file  = matlab.desktop.editor.getActiveFilename();           % works in .m files
this_dir   = fileparts(this_file);                                % folder the script is in

% Go up 3 levels
base_path  = fileparts(fileparts(fileparts(this_dir)));

MAINPATH     = [base_path, '\Paper\2025-11-03 MATRICS Study\MATRICS-Study']; % if you work laptop
PATH_EEGLAB  = [base_path, '\MATLAB\eeglab_current\eeglab2025.1.0'];         % where eeglab is located
PATH_RAWDATA = [base_path, '\Raw_data\'];    % where raw data is located
PATH_EEG     = [PATH_RAWDATA, 'RTG_Metin_Nilay_EEG_Classic_Task'];
PATH_BEH     = [PATH_RAWDATA, 'RTG_Metin_Nilay_Behav_Classic_Task\fear_learning_logs'];

% BIDS root will live *inside* the RTG_Metin_Nilay folder
bids_root    = fullfile(PATH_RAWDATA, 'BIDS_RTGMN_Classic');

%% CONFIG

TASK_LABEL    = 'classical';
SESSION_LABEL = '01';   % all data recorded in session 01

% Select what to (re-)add to BIDS
DO_EEG   = true;   % if false: assume EEG already BIDS in bids_root, do not copy/rename EEG
DO_BEH   = true;   % copy behavioral logs into /beh
DO_OTHER = false;  % placeholder for future modalities (e.g., eye, physio, etc.)

% Regex for BrainVision headers:
% CF_<subject>(_<run>)?.vhdr  e.g., CF_211.vhdr  or CF_211_002.vhdr
RE_VHDR = '^CF_(\d+)(?:_(\d{3}))?\.vhdr$';

% Regex for behavioral logs:
% CF_<subject>-<desc>.log   e.g., CF_010-GRK_Cond.log
RE_BEH = '^CF_(\d{3})-(.+)\.(log|txt)$';

% Regex for existing BIDS EEG headers (when DO_EEG == false)
% sub-010_ses-01_task-classical(_run-001)?_eeg.vhdr
RE_BIDS_VHDR = '^sub-(\d+)_ses-(\d+)_task-([A-Za-z0-9]+)(?:_run-(\d+))?_eeg\.vhdr$';

%% START EEGLAB (for metadata export)
cd(PATH_EEGLAB);
[ALLEEG, EEG, CURRENTSET, ~] = eeglab;

%% PREP BIDS ROOT
if ~exist(bids_root, 'dir'); mkdir(bids_root); end
wrote_description = false;  % track if exporter wrote dataset_description

%% LIST EEG FILES (two modes)
if DO_EEG
    vhdr_files = dir(fullfile(PATH_EEG, '*.vhdr'));   % raw BrainVision headers
else
    vhdr_files = dir(fullfile(bids_root, '**', '*_eeg.vhdr'));  % already BIDS headers
end

%% LOOP OVER FILES AND ORGANIZE INTO BIDS
for k = 1:numel(vhdr_files)

    if DO_EEG
        % --- RAW -> BIDS  ---
        src_vhdr = vhdr_files(k).name;
        tokens   = regexp(src_vhdr, RE_VHDR, 'tokens', 'once');
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
        ses_label = sprintf('ses-%s', SESSION_LABEL);

        % BIDS destination folders
        eeg_dir   = fullfile(bids_root, sub_label, ses_label, 'eeg');
        if ~exist(eeg_dir, 'dir'); mkdir(eeg_dir); end

        % (beh_dir created below only if DO_BEH)

        % Compose BIDS base filename (run only if present)
        bids_base = sprintf('%s_%s_task-%s%s', sub_label, ses_label, TASK_LABEL, run_tag);

        % Source trio (BrainVision)
        [~, base_noext] = fileparts(src_vhdr);                 % e.g., 'CF_211' or 'CF_211_002'
        src_vmrk = [base_noext '.vmrk'];

        % .eeg could be '.eeg' or '.dat' depending on recorder; prefer .eeg if present
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
        if exist(fullfile(PATH_EEG, src_vmrk), 'file'); copyfile(fullfile(PATH_EEG, src_vmrk), dst_vmrk); end
        if exist(fullfile(PATH_EEG, src_eeg),  'file'); copyfile(fullfile(PATH_EEG, src_eeg),  dst_eeg);  end

        % Rename/relocate the one experiment .log per subject (if present) -> *_events.log
        % looks for CF_<subj>.log or CF_<subj>_*.log (also accepts .txt)
        log_candidates = [ dir(fullfile(PATH_EEG, sprintf('CF_%s*.log', subj_num))) ; ...
                           dir(fullfile(PATH_EEG, sprintf('CF_%s*.txt', subj_num))) ];
        if ~isempty(log_candidates)
            src_log = fullfile(log_candidates(1).folder, log_candidates(1).name);
            dst_log = fullfile(eeg_dir, [bids_base '_events.log']);
            copyfile(src_log, dst_log);
        end

    else
        % --- EEG already BIDS ---
        src_vhdr = vhdr_files(k).name;
        eeg_dir  = vhdr_files(k).folder;

        tokens = regexp(src_vhdr, RE_BIDS_VHDR, 'tokens', 'once');
        if isempty(tokens); continue; end

        subj_num = tokens{1};  % may be '010' etc.
        ses_from_name = tokens{2};
        task_from_name = tokens{3};
        run_from_name = '';
        run_tag = '';
        hasRun = numel(tokens) >= 4 && ~isempty(tokens{4});
        if hasRun
            run_from_name = tokens{4};
            run_tag = ['_run-' run_from_name];
        end

        sub_label = sprintf('sub-%s', subj_num);
        ses_label = sprintf('ses-%s', ses_from_name);

        % keep using your configured task_label if you want, but by default align to filename
        TASK_LABEL = task_from_name; %#ok<NASGU>

        % Compose BIDS base filename (from parsed labels)
        bids_base = sprintf('%s_%s_task-%s%s', sub_label, ses_label, task_from_name, run_tag);
    end

    % --- BEH: Copy behavioral log files into /beh with BIDS-style names ---
    if DO_BEH
        beh_dir = fullfile(bids_root, sub_label, ses_label, 'beh');
        if ~exist(beh_dir, 'dir'); mkdir(beh_dir); end

        % looks for CF_<subj>-*.log or .txt in the behavioral folder
        beh_candidates = [ dir(fullfile(PATH_BEH, sprintf('CF_%s-*.log', subj_num))) ; ...
                           dir(fullfile(PATH_BEH, sprintf('CF_%s-*.txt', subj_num))) ];

        for b = 1:numel(beh_candidates)

            beh_name = beh_candidates(b).name;
            btokens  = regexp(beh_name, RE_BEH, 'tokens', 'once');
            if isempty(btokens); continue; end

            % btokens{1} is subj (3 digits), btokens{2} is desc, btokens{3} is ext
            beh_desc_raw = btokens{2};                       % e.g., 'GRK_Cond'
            beh_desc     = regexprep(beh_desc_raw, '[^A-Za-z0-9]+', '');  % sanitize -> 'GRKCond'
            if isempty(beh_desc); beh_desc = 'log'; end

            beh_ext      = btokens{3};                       % 'log' or 'txt'
            beh_base     = sprintf('%s_%s_task-%s%s_desc-%s', sub_label, ses_label, TASK_LABEL, run_tag, beh_desc);

            src_beh = fullfile(beh_candidates(b).folder, beh_name);
            dst_beh = fullfile(beh_dir, [beh_base '_beh.' beh_ext]);

            copyfile(src_beh, dst_beh);
        end
    end

    % --- EEGLAB BIDS exporter (only when we actually processed EEG here) ---
    if DO_EEG
        EEG = pop_loadbv(eeg_dir, [bids_base '_eeg.vhdr']);            % load the BIDS-renamed header
        [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, 1, 'gui', 'off');

        % Build export args; only pass 'run' when present
        export_args = {'subject', subj_num, ...
                       'session', SESSION_LABEL, ...
                       'task',    TASK_LABEL, ...
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

end

%% OPTIONAL: write a minimal README if exporter didn't (kept short)
if ~wrote_description
    fid = fopen(fullfile(bids_root, 'README'), 'w');
    if fid>0
        fprintf(fid, 'BIDS dataset: RTG_Metin_Nilay EEG (classical task)\n');
        fprintf(fid, 'Data organized via script using BrainVision to BIDS renaming.\n');
        fclose(fid);
    end
end

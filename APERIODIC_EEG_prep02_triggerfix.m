%% ANALYSIS SCRIPT - EEG - PROOF - Classical Paradigm (Real Data) / Metin Ozyagcilar & Saskia Wilken / RE-ORGANIZING TRIGGERZ / NOV 2023 & DEZ 2025
% MATLAB 2025b

%% TOOLBOXES / PLUG-INs
% (1) EEGLAB (v2023.1 & 2025.1)
% Delorme A & Makeig S (2004) EEGLAB: an open-source toolbox for analysis of single-trial EEG dynamics,
% Journal of Neuroscience Methods 134:9-21

%%

clear all; close all; clc;

%% DEFINE FOLDERS

% Get full path of this script
this_file  = matlab.desktop.editor.getActiveFilename();      % works in .m files
this_dir   = fileparts(this_file);                           % folder the script is in

% Go up 3 levels
base_path = fileparts(fileparts(fileparts(this_dir)));

mainpath = [base_path, '\Paper\2025-11-03 MATRICS Study\MATRICS-Study']; % if you work on laptop
path_eeglab = [base_path, '\MATLAB\eeglab_current\eeglab2025.1.0'];       % where eeglab is located

% Read from BIDS folder inside RTG_Metin_Nilay
path_bids_root = [base_path, '\Raw_data\RTG_Metin_Nilay_EEG_Classic_Task\BIDS_RTGMN']; % BIDS root

% Outputs
path_sets_raw   = [base_path, '\Preprocessed_data\MATRICS\00_eeglab_set'];   % NEW: plain .set destination
path_preprocessed = [base_path, '\Preprocessed_data\MATRICS\01_trigger_fix']; % trigger-fixed .set destination
path_condspecific = [base_path, '\Preprocessed_data\MATRICS\cond_specific'];

%% SUBJECT IDs 
ds = dir(fullfile(path_bids_root,'sub-*')); 
ds = ds([ds.isdir]); 
sub = arrayfun(@(d) [erase(d.name,'sub-')], ds, 'uni', false);

%% CREATE SUBJECT FOLDERS (ensure roots exist)
if ~exist(path_sets_raw,'dir'); mkdir(path_sets_raw); end
if ~exist(path_preprocessed,'dir'); mkdir(path_preprocessed); end
if ~exist(path_condspecific,'dir'); mkdir(path_condspecific); end
for i = 1:length(sub)
    if ~exist(fullfile(path_sets_raw, sub{i}), 'dir'); mkdir(fullfile(path_sets_raw, sub{i})); end
    if ~exist(fullfile(path_preprocessed, sub{i}), 'dir'); mkdir(fullfile(path_preprocessed, sub{i})); end
    if ~exist(fullfile(path_condspecific, sub{i}), 'dir'); mkdir(fullfile(path_condspecific, sub{i})); end
end

cd(path_eeglab);
eeglab;

%% START FIXING THE TRIGGERS

for i = 1:length(sub)   % loops through subjects

    % PURGE both subject output folders before writing fresh results
    sub_out_dir_raw   = fullfile(path_sets_raw, sub{i});
    sub_out_dir_fixed = fullfile(path_preprocessed, sub{i});
    if exist(sub_out_dir_raw,   'dir'); rmdir(sub_out_dir_raw,   's'); end
    if exist(sub_out_dir_fixed, 'dir'); rmdir(sub_out_dir_fixed, 's'); end
    mkdir(sub_out_dir_raw);
    mkdir(sub_out_dir_fixed);

    % Derive BIDS subject path and list all appropriate .vhdr files
    eeg_dir  = fullfile(path_bids_root, ['sub-' sub{i}], 'ses-01', 'eeg');

    % Match either with or without run tag
    pattern   = sprintf('sub-%s_ses-01_task-classical*_eeg.vhdr', sub{i});
    vhdr_list = dir(fullfile(eeg_dir, pattern));
    if isempty(vhdr_list)
        fprintf('No BIDS EEG files found for %s in %s\n', sub{i}, eeg_dir);
        continue;
    end

    % Process all runs/files for this subject
    for f = 1:numel(vhdr_list)

        eeglab redraw
        a = 0;

        % LOAD THE RAW DATA (from BIDS path)
        bids_vhdr = vhdr_list(f).name;                 % e.g., sub-189_ses-01_task-classical_run-01_eeg.vhdr
        [ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;
        EEG = pop_loadbv(eeg_dir, bids_vhdr, [], [1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66]);
        [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, a, 'gui', 'off'); % create a dataset on EEGLAB
        a = a + 1;

        % SAVE the plain .set (RAW) in 00_eeglab_set
        [~, bids_base] = fileparts(bids_vhdr); % base filename without extension
        EEG = eeg_checkset(EEG);
        EEG = pop_saveset(EEG, 'filename', [bids_base '.set'], 'filepath', sub_out_dir_raw);
        [ALLEEG, EEG] = eeg_store(ALLEEG, EEG, CURRENTSET);
        eeglab redraw;

        %% GENERAL FIX (switch/case)

        hab_start = 0;
        acq_start = 0;
        gen_start = 0;
        ext_start = 0;
        rof_start = 0;

        acq_block_csmin  = 0;
        acq_block_csplus = 0;

        ext_block_csmin  = 0;
        ext_block_csplus = 0;

        for x = 1:length(EEG.event)

            % Phase markers
            switch EEG.event(x).type
                case 'S 91' % habituation start
                    hab_start = 1; acq_start = 0; gen_start = 0; ext_start = 0; rof_start = 0;
                case 'S 92' % acquisition start
                    hab_start = 0; acq_start = 1; gen_start = 0; ext_start = 0; rof_start = 0;
                case 'S 93' % generalization start
                    hab_start = 0; acq_start = 0; gen_start = 1; ext_start = 0; rof_start = 0;
                case 'S 94' % extinction start
                    hab_start = 0; acq_start = 0; gen_start = 0; ext_start = 1; rof_start = 0;
                case 'S 95' % recovery of fear start
                    hab_start = 0; acq_start = 0; gen_start = 0; ext_start = 0; rof_start = 1;
            end

            % Remap by phase
            if hab_start == 1
                switch EEG.event(x).type
                    case 'S 20', EEG.event(x).type = 'S 201';
                    case 'S 21', EEG.event(x).type = 'S 211';
                    case 'S 22', EEG.event(x).type = 'S 221';
                    case 'S 23', EEG.event(x).type = 'S 231';
                    case 'S 24', EEG.event(x).type = 'S 241';
                end
            end

            if acq_start == 1
                if (acq_block_csmin < 10) || (acq_block_csplus < 10)
                    switch EEG.event(x).type
                        case 'S 20', EEG.event(x).type = 'S 2021'; acq_block_csmin  = acq_block_csmin  + 1;
                        case 'S 24', EEG.event(x).type = 'S 2421'; acq_block_csplus = acq_block_csplus + 1;
                    end
                else
                    switch EEG.event(x).type
                        case 'S 20', EEG.event(x).type = 'S 2022'; acq_block_csmin  = acq_block_csmin  + 1;
                        case 'S 24', EEG.event(x).type = 'S 2422'; acq_block_csplus = acq_block_csplus + 1;
                    end
                end
            end

            if gen_start == 1
                switch EEG.event(x).type
                    case 'S 20', EEG.event(x).type = 'S 203';
                    case 'S 21', EEG.event(x).type = 'S 213';
                    case 'S 22', EEG.event(x).type = 'S 223';
                    case 'S 23', EEG.event(x).type = 'S 233';
                    case 'S 24', EEG.event(x).type = 'S 243';
                end
            end

            if ext_start == 1
                if (ext_block_csmin < 11) || (ext_block_csplus < 11)
                    switch EEG.event(x).type
                        case 'S 20', EEG.event(x).type = 'S 2041'; ext_block_csmin  = ext_block_csmin  + 1;
                        case 'S 24', EEG.event(x).type = 'S 2441'; ext_block_csplus = ext_block_csplus + 1;
                    end
                end
            end

            if rof_start == 1
                switch EEG.event(x).type
                    case 'S 20', EEG.event(x).type = 'S 205';
                    case 'S 21', EEG.event(x).type = 'S 215';
                    case 'S 22', EEG.event(x).type = 'S 225';
                    case 'S 23', EEG.event(x).type = 'S 235';
                    case 'S 24', EEG.event(x).type = 'S 245';
                end
            end
        end

        % 2nd part
        ext_block_csmin_2  = 0;
        ext_block_csplus_2 = 0;

        for x = 1:length(EEG.event)
            if (ext_block_csmin_2 < 10) || (ext_block_csplus_2 < 10)
                switch EEG.event(x).type
                    case 'S 20', EEG.event(x).type = 'S 2042'; ext_block_csmin_2  = ext_block_csmin_2  + 1;
                    case 'S 24', EEG.event(x).type = 'S 2442'; ext_block_csplus_2 = ext_block_csplus_2 + 1;
                end
            else
                switch EEG.event(x).type
                    case 'S 20', EEG.event(x).type = 'S 2043'; ext_block_csmin_2  = ext_block_csmin_2  + 1;
                    case 'S 24', EEG.event(x).type = 'S 2443'; ext_block_csplus_2 = ext_block_csplus_2 + 1;
                end
            end
        end

        % 3rd part :P (turn first of specific extinction codes back so epoching skips them)
        first_ext_stim_plus  = 0;
        first_ext_stim_minus = 0;
        for x = 1:length(EEG.event)
            if first_ext_stim_plus == 0
                switch EEG.event(x).type
                    case 'S 2041'
                        EEG.event(x).type = 'S 20';
                        first_ext_stim_plus = first_ext_stim_plus + 1;
                end
            end
            if first_ext_stim_minus == 0
                switch EEG.event(x).type
                    case 'S 2441'
                        EEG.event(x).type = 'S 24';
                        first_ext_stim_minus = first_ext_stim_minus + 1;
                end
            end
        end
        clear x;

        % Additional code for deleting first CS trials in ACQ
        acqdelete_one = 0;
        acqdelete_two = 0;

        for x = 1:length(EEG.event) % makes them 20999 or 24999 so that epoching does not work on them later
            if acqdelete_one ~= 1
                switch EEG.event(x).type
                    case 'S 2021'
                        EEG.event(x).type = 'S 20999';
                        acqdelete_one = acqdelete_one + 1;
                end
            end
            if acqdelete_two ~= 1
                switch EEG.event(x).type
                    case 'S 2421'
                        EEG.event(x).type = 'S 24999';
                        acqdelete_two = acqdelete_two + 1;
                end
            end
        end

        %% SAVE THE NEW DATASET w FIXED TRIGGERS (per file) -- separate folder
        EEG = eeg_checkset(EEG);
        [~, bids_base] = fileparts(bids_vhdr);
        EEG = pop_saveset(EEG, 'filename', [bids_base '_triggersfixed.set'], 'filepath', sub_out_dir_fixed);
        [ALLEEG, EEG] = eeg_store(ALLEEG, EEG, CURRENTSET);

        %% CHECK TRIGGERS (optional per file)
        num245 = 0;
        for x = 1:length(EEG.event)
            switch EEG.event(x).type
                case 'S 245'
                    num245 = num245 + 1;
            end
        end
        fprintf('%s: %d occurrences of S 245\n', bids_base, num245);

    end % file loop (runs)

end % subject loop

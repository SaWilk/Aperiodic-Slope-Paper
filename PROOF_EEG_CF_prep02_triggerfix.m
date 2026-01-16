%% ANALYSIS SCRIPT - EEG - PROOF - Classical Paradigm (Real Data)
% Metin Ozyagcilar & Saskia Wilken / RE-ORGANIZING TRIGGERS / NOV 2023 & DEZ 2025
% MATLAB 2025b
%
% WHAT WAS FIXED (minimal logic fixes, no new features):
%  1) Extinction "2nd part" remap was NOT gated to extinction phase -> could remap S20/S24 outside extinction.
%     FIX: only remap S20/S24 to 2042/2442/2043/2443 while ext_start==1 (i.e., after S94 and before S95).
%  2) "3rd part" variable names were swapped (plus/minus counters) and it reverted the wrong codes.
%     FIX: revert FIRST 'S 2441' (CS+) to 'S 24' and FIRST 'S 2041' (CS-) to 'S 20' with correctly named counters.
%  3) Removed the unconditional second-pass loop over all EEG.event and replaced it with a safe gated pass.
%
% NOTE: This still does NOT implement counterbalancing. (handle that later.)
% NOTE: This still assumes extinction has only S20/S24 streams for CS-/CS+.

clear all; close all; clc;

%% DEFINE FOLDERS

this_file  = matlab.desktop.editor.getActiveFilename();
this_dir   = fileparts(this_file);

base_path = fileparts(fileparts(fileparts(this_dir)));

mainpath    = [base_path, '\Paper\2025-11-03 MATRICS Study\MATRICS-Study'];
path_eeglab = [base_path, '\MATLAB\eeglab_current\eeglab2025.1.0'];

path_bids_root = [base_path, '\Raw_data\RTG_Metin_Nilay_EEG_Classic_Task\BIDS_RTGMN'];

path_sets_raw     = [base_path, '\Preprocessed_data\MATRICS\00_eeglab_set'];
path_preprocessed = [base_path, '\Preprocessed_data\MATRICS\01_trigger_fix'];
path_condspecific = [base_path, '\Preprocessed_data\MATRICS\cond_specific'];

%% SUBJECT IDs
ds = dir(fullfile(path_bids_root,'sub-*'));
ds = ds([ds.isdir]);
sub = arrayfun(@(d) [erase(d.name,'sub-')], ds, 'uni', false);

%% CREATE SUBJECT FOLDERS (ensure roots exist)
if ~exist(path_sets_raw,'dir');     mkdir(path_sets_raw); end
if ~exist(path_preprocessed,'dir'); mkdir(path_preprocessed); end
if ~exist(path_condspecific,'dir'); mkdir(path_condspecific); end

for i = 1:length(sub)
    if ~exist(fullfile(path_sets_raw, sub{i}), 'dir');     mkdir(fullfile(path_sets_raw, sub{i})); end
    if ~exist(fullfile(path_preprocessed, sub{i}), 'dir'); mkdir(fullfile(path_preprocessed, sub{i})); end
    if ~exist(fullfile(path_condspecific, sub{i}), 'dir'); mkdir(fullfile(path_condspecific, sub{i})); end
end

cd(path_eeglab);
eeglab;

%% START FIXING THE TRIGGERS

for i = 1:length(sub)   % loop subjects

    % PURGE subject output folders before writing fresh results
    sub_out_dir_raw   = fullfile(path_sets_raw, sub{i});
    sub_out_dir_fixed = fullfile(path_preprocessed, sub{i});

    if exist(sub_out_dir_raw,   'dir'); rmdir(sub_out_dir_raw,   's'); end
    if exist(sub_out_dir_fixed, 'dir'); rmdir(sub_out_dir_fixed, 's'); end
    mkdir(sub_out_dir_raw);
    mkdir(sub_out_dir_fixed);

    eeg_dir  = fullfile(path_bids_root, ['sub-' sub{i}], 'ses-01', 'eeg');

    pattern   = sprintf('sub-%s_ses-01_task-classical*_eeg.vhdr', sub{i});
    vhdr_list = dir(fullfile(eeg_dir, pattern));
    if isempty(vhdr_list)
        fprintf('No BIDS EEG files found for %s in %s\n', sub{i}, eeg_dir);
        continue;
    end

    for f = 1:numel(vhdr_list)

        eeglab redraw
        a = 0;

        bids_vhdr = vhdr_list(f).name;
        [ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;

        EEG = pop_loadbv(eeg_dir, bids_vhdr, [], ...
            [1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 ...
             25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 ...
             47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66]);

        [ALLEEG, EEG, CURRENTSET] = pop_newset(ALLEEG, EEG, a, 'gui', 'off');
        a = a + 1;

        % SAVE raw .set
        [~, bids_base] = fileparts(bids_vhdr);
        EEG = eeg_checkset(EEG);
        EEG = pop_saveset(EEG, 'filename', [bids_base '.set'], 'filepath', sub_out_dir_raw);
        [ALLEEG, EEG] = eeg_store(ALLEEG, EEG, CURRENTSET);
        eeglab redraw;

        %% ==========================
        %  PASS 1: PHASE-GATED REMAP
        % ==========================

        hab_start = 0;
        acq_start = 0;
        gen_start = 0;
        ext_start = 0;
        rof_start = 0;

        acq_block_csmin  = 0;
        acq_block_csplus = 0;

        % Extinction first-pass counters (for 2041/2441 only)
        ext_block_csmin_early  = 0;
        ext_block_csplus_early = 0;

        for x = 1:length(EEG.event)

            % Phase markers
            switch EEG.event(x).type
                case 'S 91'
                    hab_start = 1; acq_start = 0; gen_start = 0; ext_start = 0; rof_start = 0;
                case 'S 92'
                    hab_start = 0; acq_start = 1; gen_start = 0; ext_start = 0; rof_start = 0;
                case 'S 93'
                    hab_start = 0; acq_start = 0; gen_start = 1; ext_start = 0; rof_start = 0;
                case 'S 94'
                    hab_start = 0; acq_start = 0; gen_start = 0; ext_start = 1; rof_start = 0;
                case 'S 95'
                    hab_start = 0; acq_start = 0; gen_start = 0; ext_start = 0; rof_start = 1;
            end

            % Habituation remap
            if hab_start == 1
                switch EEG.event(x).type
                    case 'S 20', EEG.event(x).type = 'S 201';
                    case 'S 21', EEG.event(x).type = 'S 211';
                    case 'S 22', EEG.event(x).type = 'S 221';
                    case 'S 23', EEG.event(x).type = 'S 231';
                    case 'S 24', EEG.event(x).type = 'S 241';
                end
            end

            % Acquisition remap (CS only)
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

            % Generalization remap
            if gen_start == 1
                switch EEG.event(x).type
                    case 'S 20', EEG.event(x).type = 'S 203';
                    case 'S 21', EEG.event(x).type = 'S 213';
                    case 'S 22', EEG.event(x).type = 'S 223';
                    case 'S 23', EEG.event(x).type = 'S 233';
                    case 'S 24', EEG.event(x).type = 'S 243';
                end
            end

            % Extinction early segment remap (first-pass mapping)
            if ext_start == 1
                % Map only the early segment to 2041/2441 (keep your original logic: <11)
                if (ext_block_csmin_early < 11) || (ext_block_csplus_early < 11)
                    switch EEG.event(x).type
                        case 'S 20', EEG.event(x).type = 'S 2041'; ext_block_csmin_early  = ext_block_csmin_early  + 1;
                        case 'S 24', EEG.event(x).type = 'S 2441'; ext_block_csplus_early = ext_block_csplus_early + 1;
                    end
                end
            end

            % ROF remap
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

        %% ==========================================================
        %  PASS 2: EXTINCTION "SECOND-PASS" REMAP (GATED TO EXT ONLY)
        %    - maps remaining S20/S24 in extinction to 2042/2442 then 2043/2443
        % ==========================================================

        ext_start = 0;  % re-derive phase state for this pass
        rof_start = 0;

        ext_block_csmin_2  = 0;
        ext_block_csplus_2 = 0;

        for x = 1:length(EEG.event)

            switch EEG.event(x).type
                case 'S 94'
                    ext_start = 1; rof_start = 0;
                case 'S 95'
                    ext_start = 0; rof_start = 1;
            end

            if ext_start ~= 1
                continue; % <- critical fix: only touch events inside extinction phase
            end

            % Only remap STILL-RAW extinction CS events (i.e., those that remained S20/S24)
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

        %% ==========================================================
        %  PASS 3: "disable" first extinction trial per stream for epoching
        %    (your original intent; bugfix: correct variables + correct codes)
        % ==========================================================

        first_ext_minus_done = 0; % CS- stream (2041)
        first_ext_plus_done  = 0; % CS+ stream (2441)

        for x = 1:length(EEG.event)

            if first_ext_minus_done == 0 && strcmp(EEG.event(x).type, 'S 2041')
                EEG.event(x).type = 'S 20'; % revert first CS- extinction marker to raw so epoching skips it
                first_ext_minus_done = 1;
            end

            if first_ext_plus_done == 0 && strcmp(EEG.event(x).type, 'S 2441')
                EEG.event(x).type = 'S 24'; % revert first CS+ extinction marker to raw so epoching skips it
                first_ext_plus_done = 1;
            end

            if first_ext_minus_done && first_ext_plus_done
                break;
            end
        end

        %% ==========================================================
        %  PASS 4: disable first acquisition trials (keep exactly as before)
        % ==========================================================

        acqdelete_one = 0;
        acqdelete_two = 0;

        for x = 1:length(EEG.event)
            if acqdelete_one ~= 1 && strcmp(EEG.event(x).type, 'S 2021')
                EEG.event(x).type = 'S 20999';
                acqdelete_one = 1;
            end
            if acqdelete_two ~= 1 && strcmp(EEG.event(x).type, 'S 2421')
                EEG.event(x).type = 'S 24999';
                acqdelete_two = 1;
            end
            if acqdelete_one && acqdelete_two
                break;
            end
        end

        %% SAVE trigger-fixed dataset
        EEG = eeg_checkset(EEG);
        EEG = pop_saveset(EEG, 'filename', [bids_base '_triggersfixed.set'], 'filepath', sub_out_dir_fixed);
        [ALLEEG, EEG] = eeg_store(ALLEEG, EEG, CURRENTSET);

        %% CHECK TRIGGERS (optional)
        num245 = 0;
        for x = 1:length(EEG.event)
            if strcmp(EEG.event(x).type, 'S 245')
                num245 = num245 + 1;
            end
        end
        fprintf('%s: %d occurrences of S 245\n', bids_base, num245);

    end % file loop
end % subject loop

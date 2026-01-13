% Data Analysis Pursuit-Tracking Paradigm
% Emulation main study 2022/2023

% Script 01 contains:
% - read raw EEG data
% - preprocessing (filter, re-referencing etc)
% - export in EEGlab format

% originial script created by:
% Adriana Boettcher
% 06.06.2022
% adaptation of script for main study by:
% Saskia Wilken
% 10.01.2023


%% Notes on Subjects, Hagen

% S 53 seems to have intact Task D but Task D start trigger was missing.
% Manually inserted it 
% S 41 exactly the same.
% S 31 has many buffer overflow errors in the .vmrk file and also each TASK
% in a separate file. The start TASK D trigger was also missing. I inserted
% it at what I believe should be the end of practice. Also inserted the end
% experiment trigger.
% S 42 has no end experiment tirgger at the end of TASK D. The recording
% was likely interrupted or alternatively, the investigator ended the
% experiment with ESC instead of by clicking the joystick


%% Start of Script

clear
grandparent_path = empty_everything_and_get_path(); % stem from which to 
% navigate to all other folders
input_dir = strjoin([grandparent_path, "Emulation_2022_Input", "EEG_data", "Hagen"], filesep);
% directory for raw sets 
raw_set_dir = strjoin([grandparent_path, "Emulation_2022_Output", "00_raw_EEG_sets"], filesep);
mkdir(raw_set_dir);
% folder for storing eeg sets after preprocessing
output_dir = strjoin([grandparent_path, "Emulation_2022_Output", "01_EEG_sets"], filesep);
mkdir(output_dir);
chan_dir = 'C:\wilken\MATLAB_toolboxen\\eeglab2022.1\\plugins\\dipfit5.0\\standard_BEM\\elec\\standard_1005.elc';
% directory of questionnaire data (Unipark)
sub_info_dir = strjoin([grandparent_path, "Emulation_2022_Input", "questionnaire"], filesep);
quest_output_dir = strjoin([grandparent_path, "Emulation_2022_Output", "subject_info"], filesep);
mkdir(quest_output_dir);


%% Set parameters

% which TASK do we want to export?
TASK = 'task_A_B_C'; 
% which group do we want to preprocess?
GROUP = 'both';
EOGs = {'LO1', 'SO2', 'LO2', 'IO2'};


%% Get EEG Files to Read in

[files2read_all, files2read_add] = get_file_names(input_dir, TASK);


%% exclude files with missing data

% If you want to contrast data with task D, you still need to exclude the
% task D subjects. 

% look in function to see explanation of why and which subjects are
% excluded

% stores subjcects to be removed in cell. 
exclude = exclude_bad_subjects(TASK);

% empty vector for indexing files2read
exclude_files = zeros(1, length(files2read_all));

% loop through files to be excluded and remove from files2read
for i = 1:length(exclude)
    exclude_files = exclude_files + contains(files2read_all, exclude{i});
    if ~any(contains(files2read_all, exclude{i}))
        warning(["Can't find subject "+ exclude{i}+ " in files2read_all. Might be in files2read_add"])
    end
end

% remove chosen files
files2read_all(logical(exclude_files)) = [];
for ex = 1:length(exclude)
    files2read_add(contains(files2read_add, exclude{ex})) = []; 
end


%% Adjust entries

% read in csv with unipark data
cd(sub_info_dir)
quest_files = dir('*.csv');
[athletes, controls] = correct_unipark_output(quest_files);
% TODO: add s41 to the athletes, not controls
% TODO: subject s78 is probably not usable. was very unmotivated.
% save the ids per groups.
groups.athletes = athletes;
groups.controls = controls;
groups.both = [athletes; controls];

cd(quest_output_dir)
save group_ids.mat groups -mat


%% Get group we are interested in

files2read = select_group_subj(files2read_all, GROUP, quest_output_dir);
if strcmp(TASK, 'task_A_B_C')
    files2read_add = select_group_subj(files2read_add, GROUP, quest_output_dir);
end


%% Static Info about EEG

EOG_elecs = {'LO1', 'SO2', 'IO2', 'LO2'};
elecs_yellow_ordered = {'AF7','AF3','AFz','F1','F5','FT7','FC3','C1','C5','TP7','CP3','P1','P5','PO7','PO3','POz','PO4','PO8','P6','P2','CPz','CP4','TP8','C6','C2','FC4','FT8','F6','AF8','AF4','F2'};
elecs_green_ordered =  {'Fp1','Fz','F3','F7','LO1','FC5','FC1','C3','IO2','TP9','CP5','CP1','Pz','P3','P7','O1','Oz','O2','P4','P8','TP10','CP6','CP2','Cz','C4','SO2','LO2','FC6','FC2','F4','F8','Fp2'};
for i = 1:length(athletes); num_athletes(i) = str2num(athletes(i)); end
sort(num_athletes');


%% If Task A-B-C - concatenate Tasks into one

SKIP = false;
if ~SKIP
    if strcmp(TASK, 'task_A_B_C')
        % switch to input directory
        [NEWEEG] = merge_datasets(input_dir, files2read_add);

    end
end


%% Find a specific File to read in

find(contains(files2read_all, 'S65'))


%% Loop through files
% load data
% apply preprocessing steps
% save preprocessed EEGlab data

eeglab;
% run everything again for S66 and ... 

for ind = 53%1:length(files2read) 

    % switch to input directory
    cd(input_dir);

    %import raw data from brainvision
    EEG = pop_loadbv(input_dir, files2read{ind});
    % takes around 6 seconds per dataset - not necessary to only read in a
    % part of it

    eeglab redraw

%% Set Description
    EEG.comment = '';
    % extract only the TASK and discard the rest.
    EEG = extract_only_task(EEG, TASK);
    
    %define setname (remove file ending)
    EEG.setname = files2read{ind}(1:end-4);
    
    %store original filename in set
    EEG.comment = files2read{ind};

    % define subject name
    substring = strsplit(files2read{ind}, "_");
    EEG.subject = substring{3};

    if contains(EEG.subject, controls)
        EEG.group = 'Control';     
    elseif contains(EEG.subject, athletes)
        EEG.group = 'Athletes';
    end

    % Add channel locations
    EEG = pop_chanedit(EEG, 'lookup',chan_dir);
    % change type of electrodes according to their purpose
    [EEG.chanlocs.type] = deal("EEG");
    % assign type to non-eeg electrodes
    for lab = 1:length(EOG_elecs)
        idx = find(strcmp({EEG.chanlocs.labels}, EOG_elecs{lab}));
        EEG.chanlocs(idx).type = "EOG";
    end

    % Edit channel info, mark FCz as ref electrode
    EEG = pop_chanedit(EEG, 'append',60,'changefield',{61,'labels','FCz'});
    EEG = pop_chanedit(EEG, 'setref',{'1:60','FCz'});
    EEG.comment = EEG.comment + "  *** edited channel info";

    % downsampling tp 250 Hz
    EEG = pop_resample( EEG, 250); 
    EEG.comment = EEG.comment + "  *** apply downsampling";

    %hp filter
    EEG = pop_eegfiltnew(EEG, 0.5, []);
    EEG.comment = EEG.comment + "  *** applied hp filter";


    %% Channel Editing

    if contains(EEG.subject, "S04") % subject S04: EEG cables were 
        % plugged in the wrong way around.
        warning("fixing electrode tree script is executed")
        EEG = switch_eeg_electrode_trees(EEG,elecs_yellow_ordered, elecs_green_ordered);

    end

    %save preprocessed data
    file_name = strjoin([{substring{1:3}}, TASK, 'downsampled_low_pass'], '_');
    EEG = pop_saveset(EEG,'filename',file_name, 'filepath', char(raw_set_dir));

    %remove line noise
    EEG = pop_cleanline(EEG, 'bandwidth',2,'chanlist', 1:EEG.nbchan ,...
       'computepower',1,'linefreqs',[50 100],'normSpectrum',0,'p',0.01,'pad',2,...
       'plotfigures',0,'scanforlines',1,'sigtype','Channels','tau',100,'verb',1,...
       'winsize',4,'winstep',4);
    EEG.comment = EEG.comment + "  *** remove line noise";


    %% remove bad channels 

    % store old channel locations
    EEG.oldchanslocs = EEG.chanlocs;

    % Store EOG electrodes so they are not removed 
    TMPEOG = pop_select(EEG, 'channel',EOGs);

    % clean_rawdata parameters: disable highpass, line noise and ASR
    % ONLY remove flat channels and channels with minimum channel correlation
    EEG = clean_rawdata(EEG, 5, -1, 0.8, -1, -1, -1); % deprecated function; use clean_artifacts instead

    % Insert EOG data back into the EEG dataset
    % I forgot why I am doing it this way with the if...
    for elec = 1:length(EOGs)
        if any(contains({EEG.chanlocs.labels}, EOGs{elec}))
            EOG_idx(elec) = find(contains({EEG.chanlocs.labels}, EOGs{elec}));
        else
            EOG_idx(elec) = size(EEG.data, 1)+1;
            EEG.chanlocs(size(EEG.data, 1)+1).labels = EOGs{elec};
        end
    end

    if length({EEG.chanlocs.labels}) > size(EEG.data, 1)
        EEG.chanlocs(size(EEG.data, 1)+1) = [];
    end


%     if strcmp(EEG.subject, 'S37')
%         % remove LO1 ddata because it is only a step curve
%         EEG.data(EOG_idx, :) = nan(4, ...
%             size(EEG.data, 2));
%     else
%         EEG.data(EOG_idx, :) = TMPEOG.data;
%     end

    % lowered to default 0.8 channel correlation threshold
    EEG.comment = EEG.comment + "  *** remove bad channels";

    %lowpass filter
    EEG = pop_eegfiltnew(EEG, [], 40);
    EEG.comment = EEG.comment + "  *** apply lp filter";

    % re-reference data
    EEG = pop_reref(EEG, []);
    EEG.comment = EEG.comment + "  *** rereferencing";

    %save preprocessed data
    file_name = strjoin([{substring{1:3}}, TASK, 'preprocessed'], '_');
    EEG = pop_saveset(EEG,'filename',file_name, 'filepath', char(output_dir));
     
    clear file_name substring
end


% S53: 
% Warning: Marker number discontinuity. 
% > In readbvconf (line 119)
% In pop_loadbv (line 382) 

% S 19: Inserted S 11 at end of A_B and _C .vmrk files. 
% S 31: Inserted S 11 at end of A_B .vmrk file. 
        % moved S 10 to latency 1
% Inserted S206 and S 10 subject S65
        % changed latency to buffer overflow error thingy of next subject
% deleted double_S19 behavioral data file
% deleted double S51 behavioral data file


%% Do Preprocessing for Merged Files

if strcmp(TASK, 'task_A_B_C')
    for set = 3%1:length(NEWEEG)

        % read merged datasets
        EEG = NEWEEG(set);

        eeglab redraw

        %% Set Description

        % extract only the TASK and discard the rest.
        EEG = extract_only_task(EEG, TASK);

        if contains(EEG.subject, controls)
            EEG.group = 'Control';
        elseif contains(EEG.subject, athletes)
            EEG.group = 'Athletes';
        end

        % Add channel locations
        EEG = pop_chanedit(EEG, 'lookup',chan_dir);
        % change type of electrodes according to their purpose
        [EEG.chanlocs.type] = deal("EEG");
        % assign type to non-eeg electrodes
        for lab = 1:length(EOG_elecs)
            idx = find(strcmp({EEG.chanlocs.labels}, EOG_elecs{lab}));
            EEG.chanlocs(idx).type = "EOG";
        end

        % Edit channel info, mark FCz as ref electrode
        EEG = pop_chanedit(EEG, 'append',60,'changefield',{61,'labels','FCz'});
        EEG = pop_chanedit(EEG, 'setref',{'1:60','FCz'});
        EEG.comment = EEG.comment + "  *** edited channel info";

        % downsampling tp 250 Hz
        EEG = pop_resample( EEG, 250);
        EEG.comment = EEG.comment + "  *** apply downsampling";

        %hp filter
        EEG = pop_eegfiltnew(EEG, 0.5, []);
        EEG.comment = EEG.comment + "  *** applied hp filter";


        %% Channel Editing

        if contains(EEG.subject, "S04") % subject S04: EEG cables were
            % plugged in the wrong way around.
            warning("fixing electrode tree script is exectued")
            EEG = switch_eeg_electrode_trees(EEG,elecs_yellow_ordered, elecs_green_ordered);

        end

        substring = strsplit(EEG.setname, '_');

        %save preprocessed data
        file_name = strjoin([{substring{1:3}}, TASK, 'downsampled_low_pass'], '_');
        EEG = pop_saveset(EEG,'filename',file_name, 'filepath', char(raw_set_dir));

        %remove line noise
        EEG = pop_cleanline(EEG, 'bandwidth',2,'chanlist', 1:EEG.nbchan ,...
            'computepower',1,'linefreqs',[50 100],'normSpectrum',0,'p',0.01,'pad',2,...
            'plotfigures',0,'scanforlines',1,'sigtype','Channels','tau',100,'verb',1,...
            'winsize',4,'winstep',4);
        EEG.comment = EEG.comment + "  *** remove line noise";

        %% remove bad channels

        % store old channel locations
        EEG.oldchanslocs = EEG.chanlocs;

        % Store EOG electrodes so they are not removed
        TMPEOG = pop_select(EEG, 'channel',EOGs);

        % clean_rawdata parameters: disable highpass, line noise and ASR
        % ONLY remove flat channels and channels with minimum channel correlation
        EEG = clean_rawdata(EEG, 5, -1, 0.8, -1, -1, -1); % deprecated function; use clean_artifacts instead

        % Insert EOG data back into the EEG dataset
        for elec = 1:length(EOGs)
            if any(contains({EEG.chanlocs.labels}, EOGs{elec}))
                EOG_idx(elec) = find(contains({EEG.chanlocs.labels}, EOGs{elec}));
            else
                EOG_idx(elec) = size(EEG.data, 1)+1;
                EEG.chanlocs(size(EEG.data, 1)+1).labels = EOGs{elec};
            end
        end
        EEG.data(EOG_idx, :) = TMPEOG.data;

        % lowered to default 0.8 channel correlation threshold
        EEG.comment = EEG.comment + "  *** remove bad channels";

        %lowpass filter
        EEG = pop_eegfiltnew(EEG, [], 40);
        EEG.comment = EEG.comment + "  *** apply lp filter";

        % re-reference data
        EEG = pop_reref(EEG, []);
        EEG.comment = EEG.comment + "  *** rereferencing";

        %save preprocessed data
        file_name = strjoin([{substring{1:3}}, TASK, 'preprocessed'], '_');
        EEG = pop_saveset(EEG,'filename',file_name, 'filepath', char(output_dir));

        clear file_name substring
    end
end
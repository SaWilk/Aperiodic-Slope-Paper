% Data Analysis Pursuit-Tracking Paradigm
% Emulation main study 2022/2023

% Interpolate missing channels and re-reference to average reference, also
% split groups of tasks into single tasks

% Requires Plugin fullRankAveRef()

% Creator
% Saskia Wilken
% 17.01.2023


%% Start of Script

clear
grandparent_path = empty_everything_and_get_path(); % stem from which to


%% Parameters

ICA_type = "amica"; % "infomax or "amica"
% which task do we want to run the ICA on?
TASK = 'task_A_B_C';
GROUP = 'both';
CONFIRM = 0; % whether to ask for confirmation before removing the IC detected by ICLabel
% identify EOG electrodes
EOGs = {'LO1', 'SO2', 'LO2', 'IO2'};
tmpEOGs = EOGs;


%% Set Paths

input_dir = strjoin([grandparent_path, "Emulation_2022_Output", strjoin(["04_IClabel_pruned_", ICA_type],"")], filesep);
output_dir = strjoin([grandparent_path, "Emulation_2022_Output", strjoin(["05_completely_preprocessed_", ICA_type],"")], filesep);
mkdir(output_dir)
chan_dir = 'C:\wilken\MATLAB_toolboxen\eeglab2022.1\\plugins\\dipfit\\standard_BEM\\elec\\standard_1005.elc';

% get dir with subject information
sub_info_dir = strjoin([grandparent_path, "Emulation_2022_Output", "subject_info"], filesep);

cd(input_dir);


%% Get filenames and start EEGLAB

%list all *.set files in data directory
files = dir('*.set');
file_names = {files.name};
%concatenate into one cell array
files2read_all = file_names(contains(file_names, TASK));
eeglab;


%% Get group we are interested in

files2read = select_group_subj(files2read_all, GROUP, sub_info_dir);


%% Find a specific File to read in

find(contains(files2read, 'S65'))


%% Interpolate, Re-Reference

for ind = [57]%1:length(files2read)

    % import the data file
    EEG = pop_loadset('filename', files2read(ind), 'filepath', char(input_dir));

    % Store EOG data in a temporary dataset during interpolation and
    % re-referencing
    if ~isempty(setdiff(EOGs,{EEG.chanlocs.labels}))
        tmpEOGs = EOGs;
        EOGs = setdiff(EOGs, setdiff(EOGs,{EEG.chanlocs.labels}));
    end
    TMPEOG = pop_select(EEG, 'channel',EOGs);

    % Add FCz to Dataset
    EEG = addFCz(EEG, true, true)
    
    %interpolate removed channels
    EEG = pop_interp(EEG, EEG.oldchanslocs, 'spherical');
    EEG.comment = EEG.comment + "  *** interpolate bad channels";

    % overwriting data in EOG channels with TMPEOG data so that ICA pruning
    % is not applied to EOGs
    EOG_idx = [];
    for elec = 1:length(EOGs)
        EOG_idx(elec) = find(contains({EEG.chanlocs.labels}, EOGs{elec}));
    end

    % Re-add EOG
    EEG.data(EOG_idx, :) = TMPEOG.data();

    EEG = fullRankAveRef(EEG); % This step deletes the ICA 
    % decomposition because the bad channels that were rejected before the 
    % ICA have since been (necessarily) interpolated.
    EEG.comment = EEG.comment + "  *** average reference";

    substrings = strsplit(files2read{ind}, '_');
    % save sets with automatic components rejected
    EEG.setname = strjoin([substrings(1:3), 'preprocessed', ICA_type, TASK], "_");
    EEG = pop_saveset(EEG,'filename', char(EEG.setname),'filepath', char(output_dir));
    EOGs = tmpEOGs;

end
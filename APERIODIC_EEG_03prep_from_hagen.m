% Data Analysis Pursuit-Tracking Paradigm
% Emulation main study 2022/2023

% This script contains:
% IC label for combined data
% dipfit
% automatic IC rejection
% prompt for manual IC rejection

% Original Script by:
% Sven Hoffmann adapted by Adriana Böttcher
% 23.06.22
% adaptation of script for main study by:
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
NUM_ICS = 5; % how many ICs to plot in the topoplots


%% Set Paths

input_dir = strjoin([grandparent_path, "Emulation_2022_Output", strjoin(["02_ICA_", ICA_type],"")], filesep);
% folder for storing IClabeled but not yet pruned eeg sets
IClabel_dir = strjoin([grandparent_path, "Emulation_2022_Output", strjoin(["03_IClabelled_", ICA_type],"")], filesep);
mkdir(IClabel_dir);
% folder for storing IClabel pruned eeg sets
IClabel_pruned_dir = strjoin([grandparent_path, "Emulation_2022_Output", strjoin(["04_IClabel_pruned_", ICA_type],"")], filesep);
mkdir(IClabel_pruned_dir);
% folder for storing pruned eeg sets
output_dir = strjoin([grandparent_path, "Emulation_2022_Output", strjoin(["05_ICA_pruned_", ICA_type],"")], filesep);
mkdir(output_dir);
% get dir with subject information
sub_info_dir = strjoin([grandparent_path, "Emulation_2022_Output", "subject_info"], filesep);
% ICA Topos Plot
ICA_topos_plot = strjoin([grandparent_path, "Emulation_2022_Output", strjoin(["ICA_Topos_", ICA_type],"")], filesep);


%% Get filenames and start EEGLAB

cd(input_dir);
%list all *.set files in data directory
files = dir('*.set');
file_names = {files.name};
%concatenate into one cell array
files2read_all = file_names(contains(file_names, TASK));
eeglab;


%% Get group we are interested in

files2read = select_group_subj(files2read_all, GROUP, sub_info_dir);
% {'2023-04-05_VS_S81_iclabelled_amica_task_A_B_C.set'} has only one IC
% :((((((( 
% {'2022-08-27_SL_S54_iclabelled_amica_task_A_B_C.set'} has only 2 ICs
% 2022-10-08_SL_S60_iclabelled_amica_task_A_B_C.set has only 1 IC :( 

% lAST RUN 14.04.
% S05 has only 3 
% S19 has only 2
% S50 has only 4

%% Find a specific File to read in

find(contains(files2read, 'S65'))


%% Apply ICLabel to all datasets, save datasets

for ind = [55]%length(files2read)

    % import the data file
    EEG = pop_loadset('filename', files2read(ind), 'filepath', char(input_dir));
    %     eeglab redraw

    %% iclabel

    %run IClabel to classify components
    EEG = iclabel(EEG);

    %extract brain components
    neurocomps  = find(EEG.etc.ic_classification.ICLabel.classifications(:,1) > 0.5);

    %extract occular components
    eyes = find(EEG.etc.ic_classification.ICLabel.classifications(:,3) > 0.6);

    %     https://eeglab.org/tutorials/09_source/DIPFIT.html

    % Specify head model
    EEG = pop_dipfit_settings( EEG, 'hdmfile', ...
        'C:\wilken\MATLAB_toolboxen\eeglab2022.1\\eeglab2022.1\\plugins\\dipfit\\standard_BEM\\standard_vol.mat', ...
        'coordformat','MNI','mrifile', ...
        'C:\wilken\MATLAB_toolboxen\eeglab2022.1\\eeglab2022.1\\plugins\\dipfit\\standard_BEM\\standard_mri.mat','chanfile', ...
        'C:\wilken\MATLAB_toolboxen\eeglab2022.1\\eeglab2022.1\\plugins\\dipfit\\standard_BEM\\elec\\standard_1005.elc', ...
        'coord_transform',[0 0 0 0 0 -1.5708 1 1 1] );

    % automatic dipfit procedure
    EEG = pop_multifit(EEG, []);
    rv_above_15 = find([EEG.dipfit.model.rv] >= .2); % residual variance, keep below 15 %

    %identify components to exclude (all non-brain components as well as all
    % components that are with at least 60 % probability eye components)
    ic2rem = unique([eyes' setdiff(1:size(EEG.icawinv,2), neurocomps), rv_above_15]);
    % same criterion as Consico, Ferres & Downey (2023) plus tha twe remove
    % 60 % chance eye artifacts.

    % save inverse and weights of comps excluded by IClabel
    EEG.IClabel_excl.icawinv = EEG.icawinv(:, ic2rem);
    EEG.IClabel_excl.icasphere = EEG.icasphere(:, ic2rem);
    EEG.IClabel_excl.icaweights = EEG.icaweights(:, ic2rem);
    EEG.IClabel_excl.ic2rem = ic2rem;

    substrings = strsplit(files2read{ind}, '_');

    % save sets with components labelled
    EEG.setname = strjoin([substrings(1:3), 'iclabelled', ICA_type, TASK], "_");
    EEG = pop_saveset(EEG,'filename', char(EEG.setname),'filepath', char(IClabel_dir));

end


%% Get filenames for next step

cd(IClabel_dir)
%list all *.set files in data directory
files = dir('*.set');
file_names = {files.name};
%concatenate into one cell array
files2read_all = file_names(contains(file_names, TASK));
files2read = select_group_subj(files2read_all, GROUP, sub_info_dir);


%% Find a specific File to read in

find(contains(files2read, 'S65'))
% TODO: S79 (69) looks super weird :(  

%% Remove ICLabel Components (and Manually Select Artifactual Components)

for ind = 55%1:54%56:length(files2read)

    cd(IClabel_dir)
    % import the data file
    EEG = pop_loadset(char(files2read{ind}));

    % save in temporary data set
    if ~isempty(setdiff(EOGs,{EEG.chanlocs.labels}))
        tmpEOGs = EOGs;
        EOGs = setdiff(EOGs, setdiff(EOGs,{EEG.chanlocs.labels}));
    end
    TMPEOG = pop_select(EEG, 'channel',EOGs);

    % keep only brain components
    EEG = pop_subcomp(EEG, EEG.IClabel_excl.ic2rem , CONFIRM);
    EEG.comment = EEG.comment + "  *** remove ICs automatically";

    EEG = eeg_checkset(EEG);
    % overwriting data in EOG channels with TMPEOG data so that ICA pruning
    % is not applied to EOGs
    EOG_idx = [];
    for elec = 1:length(EOGs)
        EOG_idx(elec) = find(contains({EEG.chanlocs.labels}, EOGs{elec}));
    end
    EEG.data(EOG_idx, :) = TMPEOG.data;

    %     ALLEEG = EEG;
    %     eeglab redraw
    % remove now unnecessary dataset
    clear TMPEOG
    if size(EEG.icaact, 1) < NUM_ICS
        tmp_NUM_ICS = size(EEG.icaact, 1);
    else
        tmp_NUM_ICS = NUM_ICS;
    end

    % visual checks:
    %     EEG = pop_selectcomps(EEG, [1:tmp_NUM_ICS]);
    %     pause;
    % uncomment if you want to check manually, for reproducibility reason will
    % leave this commented out.

    pop_topoplot(EEG, 0, [1:tmp_NUM_ICS] ,EEG.setname,[2 3] ,1, 'electrodes','on');
    cd(ICA_topos_plot)
    set(gcf,'PaperUnits','centimeters','PaperPosition',[0 , 0, 15, 15])
    print('-djpeg', strjoin([EEG.subject, "first_five_comps.jpg"],"_"), '-r600');
    %     pause;
    %     ics = input('Number of IC to remove?:');
    %
    %     %save weights and inverse of manually excluded comps
    %     EEG.manual_excl.icawinv = EEG.icawinv(:, ics);
    %     EEG.manual_excl.icasphere = EEG.icasphere(:, ics);
    %     EEG.manual_excl.icaweights = EEG.icaweights(:, ics);
    %     pause;

    substrings = strsplit(files2read{ind}, '_');
    % save sets with automatic components rejected
    EEG.setname = strjoin([substrings(1:3), 'ic_pruned', ICA_type, TASK], "_");
    EEG = pop_saveset(EEG,'filename', char(EEG.setname),'filepath', char(IClabel_pruned_dir));
    if exist('tmpEOGs', 'var')
        EOGs = tmpEOGs;
    end

end


%% Note of subjects with issues

weird_subs = [43, 37, 34, 30, 12, 4]
weird_subs_cell = {'S54', 'S48', 'S19', 'S05'}
% can't find 43... 
% 29 has more than five ICs, but all the components look sort of the same. 
% s81 has only one ic
% s37 as well 

%% Get filenames for next step

% cd(IClabel_pruned_dir)
%
% %list all *.set files in data directory
% files = dir('*.set');
% file_names = {files.name};
% %concatenate into one cell array
% files2read_all = file_names(contains(file_names, TASK));
% files2read = select_group_subj(files2read_all, GROUP, sub_info_dir);
% tmpEOGs = EOGs;

%% Remove manually selected components and save datasets
%
% for ind = 1:length(files2read)
%
%     % import the data file
%     EEG = pop_loadset(char(files2read{ind}));
%     % save in temporary data set
%     TMPEOG = pop_select(EEG, 'channel',EOGs);
%
%     try
%         EEG = pop_subcomp( EEG, 1);
%     catch
%         lasterr
%         pause
%     end
%
%     % overwriting data in EOG channels with TMPEOG data so that ICA pruning
%     % is not applied to EOGs
%     if ~isempty(setdiff(EOGs,{EEG.chanlocs.labels}))
%         tmpEOGs = EOGs;
%         EOGs = setdiff(EOGs, setdiff(EOGs,{EEG.chanlocs.labels}));
%     end
%     EOG_idx = [];
%     for elec = 1:length(EOGs)
%         EOG_idx(elec) = find(contains({EEG.chanlocs.labels}, EOGs{elec}));
%     end
%     EEG.data(EOG_idx, :) = TMPEOG.data;
%     % add comment
%     EEG.setname = strjoin([substrings(1:3), 'icaclean_continuous', ICA_type, TASK], "_");
%     EEG.comment = EEG.comment + "  *** remove ICs manually";
%
%     substrings = strsplit(files2read{ind}, '_');
%     % save dataset
%     EEG = pop_saveset(EEG,'filename',char(EEG.setname),'filepath', char(output_dir));
%     EOGs = tmpEOGs ;
% end
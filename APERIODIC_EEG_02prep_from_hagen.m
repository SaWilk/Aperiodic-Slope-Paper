% Data Analysis Pursuit-Tracking and Pursuit-Occlusion Paradigm
% Emulation pilot study 2021

% This script contains: 
% ICA for combined data sets
% steps:
% read preprocessed data for task
% create new structure ICA, run ICA and save merged datasets
% Requires Plugin: AMICA

% Script by
% Saskia Wilken
% 26.01.2023


%% Start of Script

clear
% TODO: Add here the sciebo path: C:\wilken\Sciebo_Cloud_Projekt
grandparent_path = empty_everything_and_get_path(); % stem from which to 
% navigate to all other folders
input_dir = strjoin([grandparent_path, "Emulation_2022_Output", "01_EEG_sets"], filesep);
% folder for storing eeg sets
output_dir = strjoin([grandparent_path, "Emulation_2022_Output", "02_ICA_amica"], filesep);
mkdir(output_dir);
sub_info_dir = strjoin([grandparent_path, "Emulation_2022_Output", "subject_info"], filesep);
cd(input_dir);


%% Set parameters

% which task do we want to run the ICA on?
TASK = 'task_A_B_C'; 
GROUP = 'both';


%% Get filenames and start EEGLAB

%list all *.set files in data directory
files = dir('*.set');
file_names = {files.name};
%concatenate into one cell array
files2read_all = file_names(contains(file_names, TASK));
eeglab;


%% Get group we are interested in

files2read = select_group_subj(files2read_all, GROUP, sub_info_dir);

for ind = 1:length(files2read)
    strsplit(files2read{ind}, "_")
end

%% Find a specific File to read in

find(contains(files2read, 'S65'))


%% Loop through files

% load data
% apply ICA
% save new data

% NOTE: amica takes around 20 min for one EEG recording of 25 to 30 min on
% my PC (Saskia Wilken). 
for ind = [55]%:length(files2read)

    % load preprocessed EEG data for A and B
    TMPEEG = pop_loadset('filename', files2read(ind), 'filepath', char(input_dir));

    %% prepare data for ICA (to exclude occular artifacts)
    
    %prepare ICA via data subset

    %create 1s epochs
    ICA = eeg_regepochs(TMPEEG);

    %detrend eeg data
    ICA = eeg_detrend(ICA); 
    %code copied from https://github.com/widmann/erptools/blob/master/eeg_detrend.m

    %artifact rejection
    ICA = pop_jointprob(ICA, 1, 1:ICA.nbchan, 5, 5, 0, 1);
    
    %select only a quarter of the epochs randomly
    trl = 1:ICA.trials;
    trl = shuffle(trl);
    ICA = pop_select(ICA, 'trial', trl(1:round(length(trl)/4))) ;
    
    %prepare data for ICA 
    x = double(ICA.data);
    
    %reshape for ICA
%     x = reshape(x,size(x,1),size(x,2)*size(x,3));
    x = double(reshape(TMPEEG.data,TMPEEG.nbchan,TMPEEG.pnts*TMPEEG.trials));

    %get rank (use function modified by SH)
    rnk = getrank(x);
    
    % now run amica on subset of data 
    % help file: https://sccn.ucsd.edu/~jason/amica_help.html
    % x(:, 1000:round(size(x,2)/4))
    % tutorial on how to run AMICA on nsg
    % https://sccn.ucsd.edu/githubwiki/files/eeg_nonstationarity_and_amica.pdf
    % didn't work yet
    [TMPEEG.icaweights, TMPEEG.icasphere, mods] = runamica15(x(:, 1000:round(size(x,2)/4)), ...
        'do_reject', 1, 'numrej', 20, 'rejsig', 3, 'rejint', 1,'pcakeep',rnk);
    % Takes 10 to 30 min per subject
    TMPEEG.icawinv = pinv(TMPEEG.icaweights*TMPEEG.icasphere);
    TMPEEG = eeg_checkset(TMPEEG);

    TMPEEG.comment = TMPEEG.comment + "  *** perform amica ICA";

%     TMPEEG.icachansind  = ICA.icachansind; % do i need this?
    %save new data
    substrings = strsplit(files2read{ind}, '_');
    save_file_name = strjoin([{substrings{1:length(substrings)-1}}, 'ICA_amica', TASK, '.set'], '_');
    TMPEEG = pop_saveset(TMPEEG,'filename',save_file_name, 'filepath', char(output_dir));
    clear substrings save_file_name

end
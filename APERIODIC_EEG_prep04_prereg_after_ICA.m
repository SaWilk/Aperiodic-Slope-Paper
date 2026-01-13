 %% ANALYSIS SCRIPT - ***EEG*** - PROOF - Classical Paradigm (Real Data) / Metin Ozyagcilar / PREPROCESSING AFTER ICA / NOV 2023

%% TOOLBOXES / PLUG-INs

% (1) EEGLAB (v2023.1) 
% Delorme A & Makeig S (2004) EEGLAB: an open-source toolbox for analysis of single-trial EEG dynamics, 
% Journal of Neuroscience Methods 134:9-21

%%

clear all; close all; clc;


%% DEFINE FOLDERS

% mainpath = 'D:\PROOF'; 
%mainpath = 'C:\Users\metin\Desktop\PROOF_EEGSCRFPS_Analysis\AnalysisHome'; % if you work  laptop
% mainpath ='C:\Users\metin\Desktop\PROOF_EEGSCRFPS_Analysis\AnalysisHome'; % if youwork on Uni comp
mainpath = 'D:\PROOF' % if you work on harddisk
path_eeglab = [mainpath, '\eeglab2023.1']; % where eeglab is located
%path_eeglab = [mainpath, '\eeglab2022.0']; % where eeglab is located
path_rawdata = [mainpath, '\Real\Raw\']; % where raw data is located
path_preprocessed = [mainpath, '\Real\Preprocessed\']; % where pre-processed data is saved
path_condspecific = [mainpath, '\Real\Epoched\']; % where pre-processed data is saved


%% EXTRACT SUBJECT IDs 

% Extract subject IDs (CHECKS ALL OF THE RAW DATA IN THE FOLDER):
%cd (path_rawdata)
%sub = dir('*.vhdr');
%sub = {sub.name}; % subject IDs are stored here 
%for i = 1:length(sub)
%sub{i} = sub{i}(1:7); % remove .vhdr extension and only keep the subject IDs
%end
%clear i;

% LOAD SUBJECT IDs
%load([mainpath, '\THESIS\Analysis\files.mat'], 'files');  

% DEFINE SUBJECT IDs MANUALLY
sub = {'CF_189' 'CF_193'}
%% TRIGGERS:

%  20: CS- / 24: CS+ / 21: GS- / 23: GS+ / 22: GSU % keep writing here[1

%% DEFINE PARAMETERS


irr_1 = 'SCR'; % irrelevant channel 1
irr_2 = 'Startle'; % irrelevant channel 2
irr_3 = 'EKG'; % irrelevant channel 2 % +++ CHECK THAT AGAIN +++
irr_4 = 'IO2' % irrelevant channel 3
highpass = .01; % cut-off for the first high-pass filter 
highpass_ica = 1; % cut-off for the high-pass filter to be applied for ICA preparetaion
lowpass = 30; % cut-off for the low-pass filter
%notch_1 = 45; % first cut-off for the notch filter
%notch_2 = 55; % second cut-off for the notch filter

events_phase_wholeacq = {'S 2021' 'S 2022' 'S 2421' 'S 2422'};
conds_phase_wholeacq = {'ACSMComb', 'ACSPComb'};

events_phase_wholeext= {'S 2041' 'S 2042' 'S 2043' 'S 2441' 'S 2442' 'S 2443'};
conds_phase_wholeext= {'ECSMComb', 'ECSPComb'};

events_phase = {'S 201'  'S 241'  'S 2021' 'S 2421' 'S 2022' 'S 2422' 'S 203'  'S 213'  'S 223' 'S 233'  'S 243' 'S 2041' 'S 2441' 'S 2042' 'S 2442' ...
    'S 2043' 'S 2443' 'S 205'  'S 245'}; % short version 
conds_phase = {'HCSM','HCSP','ACSMFirst', 'ACSPFirst', 'ACSMSecond', 'ACSPSecond', 'GCSM', 'GGSM', 'GGSU', 'GGSP', 'GCSP', ...
    'ECSMFirst', 'ECSPFirst', 'ECSMSecond', 'ECSPSecond', 'ECSMThird', 'ECSPThird', 'ROFCSM', 'ROFCS+'}; % short version / G2 = RO

%TEMP
%events_phase = {'S 2021' 'S 2421' 'S 2022' 'S 2422' 'S 203'  'S 213'  'S 223' 'S 233'  'S 243' 'S 2041' 'S 2441' 'S 2042' 'S 2442' ...
 %   'S 2043' 'S 2443' 'S 205'  'S 245'}; % short version 
%conds_phase = {'ACSMFirst', 'ACSPFirst', 'ACSMSecond', 'ACSPSecond', 'GCSM', 'GGSM', 'GGSU', 'GGSP', 'GCSP', ...
 %   'ECSMFirst', 'ECSPFirst', 'ECSMSecond', 'ECSPSecond', 'ECSMThird', 'ECSPThird', 'ROFCSM', 'ROFCS+'}; % short version / G2 = RO

epoch_start = -0.4;
epoch_end = 2.6;
base_start = -200;
nobad = 0;

%badcompz ={[1,3,'CF_001'], [1,2,'CF_002'],[1,4,'CF_003'], [1,4,'CF_004'], [1,2,5 'CF_006'], [1,7,'CF_0047'], ...
%    [1,2,'CF_009'], [1,5,'CF_013'], [1,5,'CF_015'], [1,2,'CF_016'], [1,2, 3,'CF_020'], [1,3,'CF_021'], [1,4,'CF_022'], ...
 %   [1,2,'CF_023'], [1,3,'CF_024'], [1,4,'CF_026'], [1,4,'CF_027_02'], [1,5,'CF_028'], [1,3,'CF_031'], [1,4,'CF_032'], ...
  %  [1,3,'CF_033'], [1,4,'CF_034'], [1,8,'CF_035'], [1,5,'CF_036'], [1,3,'CF_038'], [1,2,'CF_039'], [1,6,'CF_41'], ...
   % [2,3,5,'CF_043'], [2,3,'CF_044'], [1,5,'CF_045'], [1,3,'CF_046'], [1,7,'CF_048'], [1,3,'CF_049'], [1,4,'CF_051'], ...
    %[1,2,'CF_052'], [1,3,'CF_054'], [1,3,'CF_055'], [1,3,'CF_056'], [1,2,'CF_057'], [1,3,'CF_058'], ... 
    %[1,2,'CF_061'], [1,3,'CF_063'], [1,3 'CF_064'],}; % TEMP for automatic comp rejection in the loop with predefined comp indexes

%% PREPROCESSING AFTER ICA  

a = 0; % create and index variable here to create seperate datasets on EEGLAB after each step

for i = 1:length(sub); % loops through subjects 
%% OCULAR CORRECTION (ICA) - REJECT BAD COMPONENTS

cd(path_eeglab);
eeglab;  % first, re-start the eeglab
eeglab redraw

EEG = pop_loadset('filename',[sub{i}, '_icaed', '.set'],'filepath', [path_preprocessed, '\', sub{i}]); 

% pop_topoplot(EEG,0,[1:size(EEG.icawinv,2)],EEG.setname,[9 9] ,0,'electrodes','on'); % plot the components
pop_selectcomps(EEG, [1:size(EEG.icawinv,2)] ); % plot the components - this one is better because you can also click on them to see the properties
pop_eegplot(EEG, 0, 1, 1); % ? 
EEG.badcomps = input('Enter bad component indices [] : '); % enter bad component indices (after visually inspecting them on the plot) 
badcomp = EEG.badcomps;
EEG = pop_subcomp(EEG, badcomp, 0); % bye bye bad components
%EEG = pop_subcomp(EEG, badcompz{i}, 0); % bye bye bad components % TEMP for automatic comp rejection in the loop with predefined comp indexes
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_icapruned'],'savenew',[path_preprocessed,'\\', ...
sub{i} '\\', sub{i}, '_icapruned', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data 
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next ste


 %for i = 1:length(sub); % loops through subjects % TEMP
%%
for r = 1:2 % (first rerefav then rerefmast, with another inner loop starting here)

cd(path_eeglab);
eeglab;  % first, re-start the eeglab
eeglab redraw

a = 0; % re-set the index variable a

EEG = pop_loadset('filename',[sub{i}, '_icapruned', '.set'],'filepath', [path_preprocessed, '\', sub{i}]); 

 % EEG = pop_loadset('filename',[sub{i}, '_50hzremoved', '.set'],'filepath', [path_preprocessed, '\', sub{i}]); 
 % TEMP for comparing data with & withouth eyeblinks removed

if r == 1;
%% RE-REFERENE (AVERAGE)

chan_IO_reref_av = find(strcmpi('IO1',{EEG.chanlocs.labels})); % find the channel index of IO1

EEG = pop_reref( EEG, [],'exclude', chan_IO_reref_av);
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_rerefav'],'savenew',[path_preprocessed,'\\', ...
sub{i} '\\', sub{i}, '_rerefav', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data 
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next ste

end

if r == 2;
%% RE-REFERENCE (MASTOIDS)

chan_IO_reref_mast = find(strcmpi('IO1',{EEG.chanlocs.labels})); % find the channel index of IO1

chan_mast_1 = find(strcmpi('T9',{EEG.chanlocs.labels})); % find the channel index of the mastoid elec 1
chan_mast_2 = find(strcmpi('T10',{EEG.chanlocs.labels})); % find the channel index of the mastoid elec 2

EEG = pop_reref( EEG, [chan_mast_1 chan_mast_2], 'exclude', chan_IO_reref_mast); 
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_rerefmast'],'savenew',[path_preprocessed,'\\', ...
sub{i} '\\', sub{i}, '_rerefmast', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data 
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next ste

end

end

 %for i = 1:length(sub); % loops through subjects % TEMP
 %a = 0; %TEMP

%% CREATE EPOCHS

for z = 1:2 % load the datasets (load first rerefav then rerefmast and do the rest, with another loop starting here)

eeglab;  % first, re-start the eeglab
eeglab redraw

a = 0; % re-set the index variable a

if z == 1; % for rerefav dataset
EEG = pop_loadset('filename',[sub{i}, '_rerefav', '.set'],'filepath', [path_preprocessed, '\', sub{i}]); % this may not work check it
end

if z == 2; % for rerefmast dataset
EEG = pop_loadset('filename',[sub{i}, '_rerefmast', '.set'],'filepath', [path_preprocessed, '\', sub{i}]); % this may not work check it
end

EEG = pop_epoch(EEG, events_phase, [epoch_start epoch_end], 'newname', [sub{i}, '_epoched'], 'epochinfo', 'yes'); % create epochs 
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'gui','off'); 

if z == 1;
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_rerefav', '_epoched'],'savenew',[path_preprocessed,'\\', ...
sub{i}, '\\', sub{i}, '_rerefav', '_epoched', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data 
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next step
end

if z == 2;
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_rerefmast', '_epoched'],'savenew',[path_preprocessed,'\\', ...
sub{i}, '\\', sub{i}, '_rerefmast', '_epoched', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data 
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next step
end

EEG = eeg_checkset( EEG );
eeglab redraw;
%% ARTEFACT REJECTION

% (Criteria: amplitude, variance and channel deviation larger than 3-z scores)

% +++ maybe add again a temporary loop here to change stuff post processesing?

if nobad == 0;
    
datachan = [1:size(EEG.data,1)];
list_props = epoch_properties(EEG,datachan); % determine contaminated epochs
marked_trials = find(min_z(list_props,prep_rej_opt(list_props,3))); % store indices of contaminated epochs
bad_trials = zeros(1,EEG.trials);
bad_trials(marked_trials) = 1; % index to bad trials in the data
EEG = pop_rejepoch(EEG,bad_trials,0); % bad trials are removed
eeglab redraw;

if z == 1;
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_rerefav', '_badtrialsrejected'],'savenew',[path_preprocessed,'\\', ...
sub{i}, '\\', sub{i}, '_rerefav', '_badtrialsrejected', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data 
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next step
end

if z == 2;
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_rerefmast', '_badtrialsrejected'],'savenew',[path_preprocessed,'\\', ...
sub{i}, '\\', sub{i}, '_rerefmast', '_badtrialsrejected', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data 
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next step
end

elseif nobad == 1;
    
end
eeglab redraw;

%% ARTEFACT REJECTION Option 2 EPOCH INT

% Option A

% EEG = pop_eegmaxmin(EEG, [],[], 75, [], 1, 0);

% EEG = pop_TBT(EEG, EEG.reject.rejmaxminE , 10, 0.15, 1); % can I put here the last stuff from below [] EEG.chanlocs? ASK?

% ~~ %

% Option B (To add back all channels from the input EEG data-set) IS IT BETTER THAN A? WITH A YOU GET MISSING CHANNELS...:

% EEG = pop_eegmaxmin(EEG); % Is this then takes the default stuff? Is it the same as above?

% EEG = pop_eegmaxmin(EEG, [],[], 150, [], 1, 0); %START FROM HERE

% my_bads = EEG.reject.rejmaxminE;

% EEG = pop_TBT(EEG,my_bads,10,0.3,[],EEG.chanlocs); % or any other chanloc
% struct, this is like option 1

 %EEG = pop_TBT(EEG,my_bads,[],0.3,[],EEG.chanlocs); % or any other chanloc struct --> I've put [] instead of 10, now it is doing option 4 (in the notes), I hope??


%if z == 1;
%[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_rerefav', '_badtrialsrejected'],'savenew',[path_preprocessed,'\\', ...
%sub{i}, '\\', sub{i}, '_rerefav', '_badtrialsrejected', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data 
%eeglab redraw;
%a = a+1; % increase a by 1 so that it creates a different dataset on the next step
%end

%if z == 2;
%[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_rerefmast', '_badtrialsrejected'],'savenew',[path_preprocessed,'\\', ...
%sub{i}, '\\', sub{i}, '_rerefmast', '_badtrialsrejected', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data 
%eeglab redraw;
%a = a+1; % increase a by 1 so that it creates a different dataset on the next step
%end

%eeglab redraw;

% Option A explaination
% Epoched data were subjected to an automated bad-channel and artifact detection using EEGPLAB's TBT plugin (Ben-Shachar, 2018): within each 
% epoch, channels that exceeded a differential average amplitude of 75μV were marked for rejection. Channels that were marked as bad 
% on more then 15/% of all epochs were excluded. Epochs having more than 10 bad channels were excluded. Epochs with less
% than 10 bad channels were included, while replacing the bad-channel data with spherical interpolation of the neighboring channel values.
                  
%% ARTEFACT REJECTION Option 3 like BVA

% ?

%% BASELINE CORRECTION

EEG = eeg_checkset( EEG );
EEG = pop_rmbase(EEG, [base_start 0], []); % baseline correction

if z == 1;
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_rerefav', '_baselineremoved'],'savenew',[path_preprocessed,'\\', ...
sub{i}, '\\', sub{i}, '_rerefav', '_baselineremoved', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data 
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next step
end

if z == 2;
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_rerefmast', '_baselineremoved'],'savenew',[path_preprocessed,'\\', ...
sub{i}, '\\', sub{i}, '_rerefmast', '_baselineremoved', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data 
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next step
end

eeglab redraw;

%% CREATE SEPERATE DATASETS 

idx = length(ALLEEG);
e = 1;
while e <= size(events_phase) % loop through triggers
    
    for c = 1:size(conds_phase,2) % loop through condition names
        
     EEG = pop_selectevent(ALLEEG(idx), 'latency','-2<=2','type',{events_phase{e}},...
         'deleteevents','off','deleteepochs','on','invertepochs','off');    % create a condition specific dataset

    
if z == 1;
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_rerefav', '_', conds_phase{c}],'savenew',[path_condspecific,'\\', ...
sub{i}, '\\', sub{i}, '_rerefav', '_', conds_phase{c}, '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data 
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next step
end

if z == 2;
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_rerefmast', '_', conds_phase{c}],'savenew',[path_condspecific,'\\', ...
sub{i}, '\\', sub{i}, '_rerefmast', '_', conds_phase{c}, '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data 
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next step
end
     EEG = eeg_checkset(EEG);
   [ALLEEG, EEG, CURRENTSET] = eeg_store(ALLEEG, EEG); 
     e = e+1; 
    end
end

end
end 

%% CREATE SEPERATE DATASETS FOR ACQ AS A WHOLE 



for i = 1:length(sub); % loop through all subjects
for z = 1:2 % load the datasets (load first rerefav then rerefmast and do the rest, with another loop starting here)
e= 1;
a = 1;
cd(path_eeglab);
eeglab;  % first, re-start the eeglab
eeglab redraw


if z == 1;
EEG = pop_loadset('filename',[sub{i}, '_rerefav', '_baselineremoved', '.set'],'filepath', [path_preprocessed, '\', sub{i}]); 
     EEG = eeg_checkset(EEG);
   [ALLEEG, EEG, CURRENTSET] = eeg_store(ALLEEG, EEG); 
idx = length(ALLEEG);
end
if z == 2;
EEG = pop_loadset('filename',[sub{i}, '_rerefmast', '_baselineremoved', '.set'],'filepath', [path_preprocessed, '\', sub{i}]); 
     EEG = eeg_checkset(EEG);
   [ALLEEG, EEG, CURRENTSET] = eeg_store(ALLEEG, EEG); 
idx = length(ALLEEG);
end


while e <= size(events_phase_wholeacq) % loop through triggers
    
    for c = 1:size(conds_phase_wholeacq,2) % loop through condition names
        
     EEG = pop_selectevent(ALLEEG(idx), 'latency','-2<=2','type',{events_phase_wholeacq{e}, events_phase_wholeacq{e+1}},...
         'deleteevents','off','deleteepochs','on','invertepochs','off');    % create a condition specific dataset

if z == 1;
  
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_rerefav', '_', conds_phase_wholeacq{c}],'savenew',[path_condspecific,'\\', ...
sub{i}, '\\', sub{i}, '_rerefav', '_', conds_phase_wholeacq{c}, '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data 
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next step

end

if z == 2;
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_rerefmast', '_', conds_phase_wholeacq{c}],'savenew',[path_condspecific,'\\', ...
sub{i}, '\\', sub{i}, '_rerefmast', '_', conds_phase_wholeacq{c}, '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data 
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next step

end
     EEG = eeg_checkset(EEG);
   [ALLEEG, EEG, CURRENTSET] = eeg_store(ALLEEG, EEG); 
     e = e+2; 
    end
end
end
end
eeglab redraw;

%% CREATE SEPERATE DATASETS FOR EXT AS A WHOLE 

for i = 1:length(sub); % loop through all subjects
for z = 1:2 % load the datasets (load first rerefav then rerefmast and do the rest, with another loop starting here)
e= 1;
a = 1;
cd(path_eeglab);
eeglab;  % first, re-start the eeglab
eeglab redraw    

if z == 1;
EEG = pop_loadset('filename',[sub{i}, '_rerefav', '_baselineremoved', '.set'],'filepath', [path_preprocessed, '\', sub{i}]);
     EEG = eeg_checkset(EEG);
   [ALLEEG, EEG, CURRENTSET] = eeg_store(ALLEEG, EEG); 
idx = length(ALLEEG);
end
if z == 2;
EEG = pop_loadset('filename',[sub{i}, '_rerefmast', '_baselineremoved', '.set'],'filepath', [path_preprocessed, '\', sub{i}]); 
     EEG = eeg_checkset(EEG);
   [ALLEEG, EEG, CURRENTSET] = eeg_store(ALLEEG, EEG); 
idx = length(ALLEEG);
end

while e <= size(events_phase_wholeext) % loop through triggers
    
    for c = 1:size(conds_phase_wholeext,2) % loop through condition names
        
     EEG = pop_selectevent(ALLEEG(idx), 'latency','-2<=2','type',{events_phase_wholeext{e}, events_phase_wholeext{e+1}, events_phase_wholeext{e+2}},...
         'deleteevents','off','deleteepochs','on','invertepochs','off');    % create a condition specific dataset

    
if z == 1;
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_rerefav', '_', conds_phase_wholeext{c}],'savenew',[path_condspecific,'\\', ...
sub{i}, '\\', sub{i}, '_rerefav', '_', conds_phase_wholeext{c}, '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data 
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next step
end

if z == 2;
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_rerefmast', '_', conds_phase_wholeext{c}],'savenew',[path_condspecific,'\\', ...
sub{i}, '\\', sub{i}, '_rerefmast', '_', conds_phase_wholeext{c}, '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data 
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next step
end
     EEG = eeg_checkset(EEG);
   [ALLEEG, EEG, CURRENTSET] = eeg_store(ALLEEG, EEG); 
     e = e+3; 
    end
end
end
end
eeglab redraw;

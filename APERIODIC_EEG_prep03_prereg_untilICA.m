 %% ANALYSIS SCRIPT - ***EEG*** - PROOF - Classical Paradigm (Real Data) / Metin Ozyagcilar / PREPROCESSING UNTIL ICA / NOV 2023

%% TOOLBOXES / PLUG-INs

% (1) EEGLAB (v2023.1) 
% Delorme A & Makeig S (2004) EEGLAB: an open-source toolbox for analysis of single-trial EEG dynamics, 
% Journal of Neuroscience Methods 134:9-21

%%

clear all; close all; clc;


%% DEFINE FOLDERS

% mainpath = 'D:\PROOF'; 
mainpath = 'C:\Users\metin\Desktop\PROOF_EEGSCRFPS_Analysis\AnalysisHome'; % if you work  laptop
% mainpath ='C:\Users\metin\Desktop\PROOF_EEGSCRFPS_Analysis\AnalysisHome'; % if youwork on Uni comp
path_eeglab = [mainpath, '\eeglab2023.1']; % where eeglab is located
%path_eeglab = [mainpath, '\eeglab2022.0']; % where eeglab is located
path_rawdata = [mainpath, '\Real\Raw\']; % where raw data is located
path_preprocessed = [mainpath, '\Real\Preprocessed\']; % where pre-processed data is saved
path_condspecific = [mainpath, '\Real\Epoched\']; % where condition specific datasets are saved

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

sub = {'CF_189' 'CF_193'} ;

%% CREATE INDIVIDUAL FOLDERS % Done in the other script, skip here

%for i = 1:length(sub)
    %mkdir([path_preprocessed, '\', sub{i}]); 
%end
%clear i;
 
% Create individual folders in a different folder (a folder for condition specific datasets):
%for i = 1:length(sub)
    %mkdir([path_condspecific, '\', sub{i}]); 
%end
%clear i;


%% TRIGGERS:

%  20: CS- / 24: CS+ / 21: GS- / 23: GS+ / 22: GSU % keep writing here

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

epoch_start = -0.4;
epoch_end = 2.6;
base_start = -200;
nobad = 0;

%% PREPROCESSING BEGINS

a = 0; % create and index variable here to create seperate datasets on EEGLAB after each step

for i = 1:length(sub); % loops through subjects
    
%% START EEGLAB

cd(path_eeglab);
eeglab;
eeglab redraw

%% LOAD THE RAW DATA

% Raw data is saved as .set in another script (the script for fixing the triggers), so, we skip that part

%[ALLEEG EEG CURRENTSET ALLCOM] = eeglab;
%EEG = pop_loadbv([path_rawdata, '\'], [sub{i}, '.vhdr'], [], [1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65]);
%[ALLEEG EEG CURRENTSET = pop_newset(ALLEEG, EEG, a,'gui','off'); % create a dataset on EEGLAB 
%a = a+1; % increase a by 1 so that it creates a different dataset on the next step

%% SAVE THE DATA AS .set

% Raw data is saved as .set in another script (the script for fixing the triggers), so, we skip that part

%EEG = eeg_checkset( EEG );
%EEG = pop_saveset( EEG, 'filename',[sub{i}, '.set'],'filepath',[path_preprocessed,'\\', sub{i} '\\']); % save the data as .set
%[ALLEEG EEG] = eeg_store(ALLEEG, EEG, CURRENTSET);
%EEG = pop_editset(EEG, 'setname', sub{i}, 'run', []); % assign a name to the dataset
%eeglab redraw;

%% LOAD THE DATA (TRIGGERSFIXED)

EEG = pop_loadset('filename',[sub{i}, '_triggersfixed', '.set'],'filepath',[path_preprocessed, '\', sub{i}]); 


%% RAW DATA INSPECTION? 

%pop_eegplot(EEG, 1, 1); % plot channel scroll data, reject manually and save the new dataset on GUI
%uiwait; % this prevents script keeping running... (it will run after you are done here)
% a = a+1; % increase a by 1 so that it creates a different dataset on the next step -> this will be done on the GUI, therefore commented out

%% DELETE UNNECESARRY PARTS (Qs etc) ? +++ TEST IT - IT RUNS BUT CHECK THE DATA TO SEE WHETHER CORRECT PARTS WERE DELETED+++

%index91 = contains({EEG.event.type}, 'S 91'); % find the index for events (i.e triggers fo the time when phases start)
%index92 = contains({EEG.event.type}, 'S 92');
%index93 = contains({EEG.event.type}, 'S 93');
%index94 = contains({EEG.event.type}, 'S 94');
%index95 = contains({EEG.event.type}, 'S 95');
%index97 = contains({EEG.event.type}, 'S 97');

%index91Latency = round(EEG.event(index91).latency); % find the (rounded) latencies for these events
%index92Latency = round(EEG.event(index92).latency); % find the (rounded) latencies for these events
%index93Latency = round(EEG.event(index93).latency); % find the (rounded) latencies for these events
%index94Latency = round(EEG.event(index94).latency); % find the (rounded) latencies for these events
%index95Latency = round(EEG.event(index95).latency); % find the (rounded) latencies for these events
%index97Latency = round(EEG.event(index97).latency);

%lastStim_HAB = find(index92, 1, 'first'); % find the triggers for the last stimuli of each phase
%indexlastStim_HAB = lastStim_HAB-1; 
%lastStim_ACQ = find(index93, 1, 'first'); % find the triggers for the last stimuli of each phase
%indexlastStim_ACQ = lastStim_ACQ-1; 
%lastStim_GEN = find(index94, 1, 'first'); % find the triggers for the last stimuli of each phase
%indexlastStim_GEN = lastStim_GEN-1; 
%lastStim_EXT = find(index95, 1, 'first'); % find the triggers for the last stimuli of each phase
%indexlastStim_EXT = lastStim_EXT-1; 
%lastStim_ROF = find(index97, 1, 'first'); % find the triggers for the last stimuli of each phase
%indexlastStim_ROF = lastStim_ROF-1; 

%indexlastStim_HABLatency = round(EEG.event(indexlastStim_HAB).latency);  % find the (rounded) latencies for these events
%indexlastStim_ACQLatency = round(EEG.event(indexlastStim_ACQ).latency);  % find the (rounded) latencies for these events
%indexlastStim_GENLatency = round(EEG.event(indexlastStim_GEN).latency);  % find the (rounded) latencies for these events
%indexlastStim_EXTLatency = round(EEG.event(indexlastStim_EXT).latency);  % find the (rounded) latencies for these events
%indexlastStim_ROFLatency = round(EEG.event(indexlastStim_ROF).latency);  % find the (rounded) latencies for these events

%indexENDEEG= round(size(EEG.data,2)) % latency of the last data point

%deletingIndex_1 = [indexlastStim_ROFLatency+5000:indexENDEEG]; % +++TEST IT+++
%EEG.data(:, deletingIndex_1) = []; % bye bye unnecessary data (data at the very end, last part of the Qs)

%deletingIndex_2 = [1:index91Latency]; % +++TEST IT+++
%EEG.data(:, deletingIndex_2) = []; % bye bye unnecessary data (data during first part of the Qs)

%deletingIndex_3 = [indexlastStim_HABLatency+5000:index92Latency]; % +++TEST IT+++
%EEG.data(:, deletingIndex_3) = []; % bye bye unnecessary data (data during second part of the Qs)

%deletingIndex_4 = [indexlastStim_ACQLatency+5000:index93Latency]; % +++TEST IT+++
%EEG.data(:, deletingIndex_4) = []; % bye bye unnecessary data (data during third part of the Qs)

%deletingIndex_5 = [indexlastStim_GENLatency+5000:index94Latency]; % +++TEST IT+++
%EEG.data(:, deletingIndex_5) = []; % bye bye unnecessary data (data during fourth part of the Qs)

%deletingIndex_6 = [indexlastStim_EXTLatency+5000:index95Latency]; % +++TEST IT+++ +++MAYBE INCREASE 5000+++
%EEG.data(:, deletingIndex_5) = []; % bye bye unnecessary data (data during fifth part of the Qs)
%% REMOVE UNNECESSARY CHANNELS

EEG = pop_select( EEG, 'nochannel',{irr_1, irr_2, irr_3, irr_4}); 
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_irrchansremove'],'savenew',[path_preprocessed,'\\', ...
sub{i} '\\', sub{i}, '_irrchansremoved', '.set'],'gui','off'); % create a dataset on EEGLAB and assign a name to the data
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next step
%a = a+2; % increase a by 2 so that it creates a different dataset on the next step (2 because the previous one was done on GUI), if you uncomment the last step of raw data inspection... +++TEST IT+++


%% ADD ONLINE REFERENCE CHANNEL BACK

% SKIPPING THIS PART BECAUSE WE DON'T USE THAT CHANNEL FOR ANALYSIS

% EEG.chanlocs(size(EEG.data,1)+1).labels = ''; % add a new channel info to chanlocs struct (for REF)
% EEG.data(size(EEG.data,1)+1,:) = 0; % add a new line on data (for REF)
% EEG.nbchan = size(EEG.data,1); % update the number of channels

% EEG.chanlocs(EEG.nbchan).sph_radius = [92.8028435728669] ; % start adding
% channel locations for REF (values below must be changed)

% EEG.chanlocs(EEG.nbchan).sph_theta = [-0.786695454154317];
% EEG.chanlocs(EEG.nbchan).sph_phi = [72.8322899189667];
% EEG.chanlocs(EEG.nbchan).theta = [0.786695454154317];
% EEG.chanlocs(EEG.nbchan).radius = [0.0953761671168517] ;
% EEG.chanlocs(EEG.nbchan).X = [27.3900000000000] ;
% EEG.chanlocs(EEG.nbchan).Y = [-0.376099999999998];
% EEG.chanlocs(EEG.nbchan).Z = [88.6680000000000];

% [ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_FCzadded'],'savenew',[path_preprocessed,'\\', ...
% sub{i} '\\', sub{i}, '_FCzadded', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
% eeglab redraw;
% a = a+1; % increase a by 1 so that it creates a different dataset on the next step


%% CORRECT LOC FOR IO --> NOT NECESSARY

%chan_IO = find(strcmpi('IO1',{EEG.chanlocs.labels})); % find the channel index of IO1

%EEG.chanlocs(chan_IO).sph_radius = [1] ; % start correcting the channel locations of IO1 
%EEG.chanlocs(chan_IO).sph_theta = [42];
%EEG.chanlocs(chan_IO).sph_phi = [-28.1000000000000];
%EEG.chanlocs(chan_IO).theta = [-42];
%EEG.chanlocs(chan_IO).radius = [0.656000000000000] ;
%EEG.chanlocs(chan_IO).X = [0.656000000000000] ;
%EEG.chanlocs(chan_IO).Y = [0.590000000000000];
%EEG.chanlocs(chan_IO).Z = [-0.471000000000000];

%[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_IOlocscorrected'],'savenew',[path_preprocessed,'\\', ...
%sub{i} '\\', sub{i}, '_IOlocscorrected', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
%eeglab redraw;
%a = a+1; % increase a by 1 so that it creates a different dataset on the next step

%% INTERPOLATE BAD CHANNELS 
    
pop_eegplot( EEG, 1, 0, 1); % plot channel scroll data to visually detect bad channels
EEG.badchan = input('Enter bad channel indices [] : '); % enter bad channel indices (after visually inspecting them on the plot) 
badchan = EEG.badchan;
EEG = pop_interp(EEG, badchan, 'spherical'); % remove and interpolate (method: spherical)

if length(badchan) > 0
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_badchansinterpolated'],'savenew',[path_preprocessed,'\\', ...
sub{i} '\\', sub{i}, '_badchansinterpolated', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next step
end

%badchan = []; % TEMP

%% INTERPOLATE BAD CHANNELS - AUTOMATIZED ()

%index_badchan = [];
%[~, indelec1] = pop_rejchan(EEG, 'elec',[1:42] ,'threshold',3.29,'norm','on','measure','prob');
%[~, indelec2] = pop_rejchan(EEG, 'elec',[1:42] ,'threshold',3.29,'norm','on','measure','kurt');
%[~, indelec3] = pop_rejchan(EEG, 'elec',[1:42] ,'threshold',3.29,'norm','on','measure','spec','freqrange',[1 125] )
%badchan = sort(unique([indelec1,indelec2,indelec3])); % index is the bad channel array (bad channels according to MULTIPLE criteria tested above)
%if size(badchan,2) >= 1
%xlswrite([path_preprocessed,'\\', sub{i}, '\\' 'badchannels.xlsx'], badchan) % save the bad channels
%end


% Interpolate bad channels (spherical):
%if size(badchan,2) >= 1
%[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_badchansinterpolated'],'savenew',[path_preprocessed,'\\', ...
%sub{i} '\\', sub{i}, '_badchansinterpolated', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
%eeglab redraw;
%a = a+1; % increase a by 1 so that it creates a different dataset on the next step
%end
%if exist ('indelec1')
%clear indelec1 
%end
%if exist ('indelec2')
%clear indelec2 
%end
%if exist ('indelec3')
%clear indelec3 
%end
%
%% LOW / HIGHPASS FILTER - OLD CODE

% EEG = pop_eegfiltnew(EEG, 'locutoff', highpass, 'hicutoff', lowpass); % apply high- and low-pass filter to data
% [ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_lowhighfilter'],'savenew',[path_preprocessed,'\\', ...
% sub{i} '\\', sub{i}, '_lowhighfilter', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
% eeglab redraw;

%%  LOW / HIGHPASS FILTER - DO IT SEPERATELY, FIRST HIGH THEN LOW - OLD CODE
%EEG = pop_eegfiltnew(EEG, ); % apply high-pass filter to data
%[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_highfilter'],'savenew',[path_preprocessed,'\\', ...
%sub{i} '\\', sub{i}, '_highfilter', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
%eeglab redraw;
%a = a+1; % increase a by 1 so that it creates a different dataset on the next step

%EEG = pop_eegfiltnew(EEG, [], 1.5, ); % apply low-pass filter to data
%[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_lowfilter'],'savenew',[path_preprocessed,'\\', ...
%sub{i} '\\', sub{i}, '_lowfilter', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
%eeglab redraw;
%a = a+1; % increase a by 1 so that it creates a different dataset on the next step

%%  LOW / HIGHPASS FILTER - WITH FFT ALGORITHM

EEG = pop_eegfiltnew(EEG, 'locutoff', highpass, 'usefftfilt', 1);
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_highfilter'],'savenew',[path_preprocessed,'\\', ...
sub{i} '\\', sub{i}, '_highfilter', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next step

EEG = pop_eegfiltnew(EEG, 'hicutoff', lowpass, 'usefftfilt', 1);
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_lowfilter'],'savenew',[path_preprocessed,'\\', ...
sub{i} '\\', sub{i}, '_lowfilter', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next step

%%  LOW / HIGHPASS FILTER - WITH ERPLAB FUNCTION

%EEG = pop_basicfilter( EEG, 1:62, 'Boundary', 'boundary', 'Filter', 'highpass', 'Design', 'butter', 'Cutoff', 0.05,'Order', 2, 'RemoveDC', 'on' );
%[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_highfilter'],'savenew',[path_preprocessed,'\\', ...
%sub{i} '\\', sub{i}, '_highfilter', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data (roll off is 12 by default)
%eeglab redraw;
%a = a+1; % increase a by 1 so that it creates a different dataset on the next step

%EEG = pop_basicfilter( EEG, 1:62, 'Boundary', 'boundary', 'Filter', 'lowpass', 'Design', 'butter', 'Cutoff', 30, 'Order', 2, 'RemoveDC', 'on' );
%[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_lowfilter'],'savenew',[path_preprocessed,'\\', ...
%sub{i} '\\', sub{i}, '_lowfilter', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
%eeglab redraw;
%a = a+1; % increase a by 1 so that it creates a different dataset on the next step

%% NOTCH FILTER (50 Hz)

%EEG = pop_eegfiltnew(EEG, 'locutoff', notch_1, 'hicutoff', notch_2, 'revfilt', 1); % apply notch filter to data
%[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_notchfiltered'],'savenew',[path_preprocessed,'\\', ...
%sub{i} '\\', sub{i}, '_notchfiltered', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
%eeglab redraw;
%a = a+1; % increase a by 1 so that it creates a different dataset on the next step

%% NOTCH FILTER (50 Hz) - WITH FFT ALGORITHM?

%EEG = pop_eegfiltnew(EEG, 'locutoff', notch_1, 'hicutoff', notch_2, 'revfilt', 1,  'usefftfilt', 1); % apply notch filter to data
%[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_notchfiltered'],'savenew',[path_preprocessed,'\\', ...
%sub{i} '\\', sub{i}, '_notchfiltered', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
%eeglab redraw;
%a = a+1; % increase a by 1 so that it creates a different dataset on the next step

%% NOTCH FILTER (50 Hz) w Clean Line Noise?

linenoisefreq = [50 100 150 200]; % line noise frequency (to be removed)
lineNoiseIn = struct('lineNoiseChannels', [1:size(EEG.chanlocs,1)], 'lineFrequencies', linenoisefreq);
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_50hzremoved'],'savenew',[path_preprocessed,'\\', ...
sub{i} '\\', sub{i}, '_50hzremoved', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next step

%% DETREND?
%EEG.data = (detrend(EEG.data'))';
%[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_detrend'],'savenew',[path_preprocessed,'\\', ...
%sub{i} '\\', sub{i}, '_detrend', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
%eeglab redraw;
%a = a+1; % increase a by 1 so that it creates a different dataset on the next step


%% OCULAR CORRECTION (ICA) - RUN ICA

eeglab redraw;

TMP = EEG; % create a temporary dataset for ICA


% Raw data inspection and cleaning some part of data before ICA 
% pop_eegplot(TMP, 1, 1); % plot channel scroll data, reject manually and save the new dataset on GUI
% uiwait; % this prevents script keeping running... (it will run after you are done here)
% add a code here that makes the EEG, TMP?
% a = a+1; % increase a by 1 so that it creates a different dataset on the next step this will be done on the GUI OR WE SIMPLY WON'T SAVE IT?
 
TMP = pop_eegfiltnew(EEG, 'locutoff', highpass_ica, 'usefftfilt', 1);
% high-pass filter the data for ICA (1 Hz) 

% Cleaning segments for better ICA on TEMP data
TMP = eeg_regepochs(TMP);
TMP = pop_jointprob(TMP,1,[1:size(EEG.nbchan)],2,2,0,1,0,[],0);

% Delete IO1
%TMP = pop_select( TMP, 'rmchannel',{'IO1'});
%badchan = [1] % TEMP


if size(badchan,2) >= 1
TMP = pop_runica(TMP, 'pca', EEG.nbchan-size(badchan,2), 'interupt','on');
rankue = EEG.nbchan-size(badchan,2);
else
TMP = pop_runica(TMP, 'extended', 1, 'interupt', 'on'); % run ICA on that dataset (extended)
end
EEG.icawinv = TMP.icawinv; % transfer the ica weights etc to the original dataset 
EEG.icasphere = TMP.icasphere;
EEG.icaweights = TMP.icaweights;
EEG.icachansind = TMP.icachansind;
EEG = eeg_checkset(EEG);
[ALLEEG, EEG, CURRENTSET] = eeg_store(ALLEEG, EEG, CURRENTSET); 
[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_icaed'],'savenew',[path_preprocessed,'\\', ...
sub{i} '\\', sub{i}, '_icaed', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data (the dataset that has the ica weights but bad components are still there)
eeglab redraw;
a = a+1; % increase a by 1 so that it creates a different dataset on the next step

clear TMP; % delete the TMP data
end

%% ANALYSIS SCRIPT - ***EEG*** - PROOF - Classical Paradigm (Real Data) / Metin Ozyagcilar / PREPROCESSING UNTIL ICA / NOV 2023

%% TOOLBOXES / PLUG-INs

% (1) EEGLAB (v2023.1)
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
path_eeglab = [base_path, '\MATLAB\eeglab_current\eeglab2025.1.0'];      % where eeglab is located

% Inputs
path_in = [base_path, '\Preprocessed_data\MATRICS\01_trigger_fix']; % trigger-fixed .set destination
% Outputs
path_out = [base_path, '\Preprocessed_data\MATRICS\02_before_ica']; % trigger-fixed .set destination


%% SUBJECT IDs
ds = dir(fullfile(path_in,'sub-*'));
ds = ds([ds.isdir]);
sub = arrayfun(@(d) [erase(d.name,'sub-')], ds, 'uni', false);

%% CREATE SUBJECT FOLDERS (ensure roots exist)
if ~exist(path_sets_raw,'dir'); mkdir(path_sets_raw); end
if ~exist(path_out,'dir'); mkdir(path_out); end
if ~exist(path_condspecific,'dir'); mkdir(path_condspecific); end
for i = 1:length(sub)
    if ~exist(fullfile(path_sets_raw, sub{i}), 'dir'); mkdir(fullfile(path_sets_raw, sub{i})); end
    if ~exist(fullfile(path_out, sub{i}), 'dir'); mkdir(fullfile(path_out, sub{i})); end
    if ~exist(fullfile(path_condspecific, sub{i}), 'dir'); mkdir(fullfile(path_condspecific, sub{i})); end
end

cd(path_eeglab);
eeglab;

sub = {'189' '193'} ;

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


%% PREPROCESSING BEGINS

a = 0; % create and index variable here to create seperate datasets on EEGLAB after each step

for i = 1:length(sub); % loops through subjects

    %% START EEGLAB

    cd(path_eeglab);
    eeglab


    %% LOAD THE DATA (TRIGGERSFIXED)

    EEG = pop_loadset('filename',[sub{i}, '_triggersfixed', '.set'],'filepath',[path_out, '\', sub{i}]);


    %% RAW DATA INSPECTION?

    %pop_eegplot(EEG, 1, 1); % plot channel scroll data, reject manually and save the new dataset on GUI
    %uiwait; % this prevents script keeping running... (it will run after you are done here)
    % a = a+1; % increase a by 1 so that it creates a different dataset on the next step -> this will be done on the GUI, therefore commented out

    %% DELETE UNNECESARRY PARTS (Qs etc) ? +++ TEST IT - IT RUNS BUT CHECK THE DATA TO SEE WHETHER CORRECT PARTS WERE DELETED+++

   % ---- trim questionnaire/idle segments between phases ----
buffer_samples = 5000;                                  
event_types    = {EEG.event.type};
n_ev           = numel(EEG.event);
is_stim        = startsWith(event_types, 'S 2');        % any stimulus code (incl. remapped)

first_idx  = @(code) find(strcmp(event_types, code), 1, 'first');
idx_91     = first_idx('S 91');  % habituation start
idx_92     = first_idx('S 92');  % acquisition start
idx_93     = first_idx('S 93');  % generalization start
idx_94     = first_idx('S 94');  % extinction start
idx_95     = first_idx('S 95');  % recovery start

rej_segments = [];  % Nx2 [start_sample end_sample] to remove

% head: remove data before first phase start
if ~isempty(idx_91)
    rej_segments(end+1, :) = [1, round(EEG.event(idx_91).latency)];
end

% between-phase removals: [current_start -> next_start]
phase_pairs = [idx_91 idx_92; idx_92 idx_93; idx_93 idx_94; idx_94 idx_95];
for p = 1:size(phase_pairs,1)
    a = phase_pairs(p,1); b = phase_pairs(p,2);
    if ~isempty(a) && ~isempty(b)
        last_stim_idx   = find(is_stim & (1:n_ev) < b, 1, 'last');
        if ~isempty(last_stim_idx)
            last_stim_lat   = round(EEG.event(last_stim_idx).latency);
            next_start_lat  = round(EEG.event(b).latency);
            rej_segments(end+1, :) = [last_stim_lat + buffer_samples, next_start_lat];
        end
    end
end

% tail: remove data after last ROF stimulus to end
if ~isempty(idx_95)
    last_stim_after_95 = find(is_stim & (1:n_ev) > idx_95, 1, 'last');
    if ~isempty(last_stim_after_95)
        last_lat = round(EEG.event(last_stim_after_95).latency);
        rej_segments(end+1, :) = [last_lat + buffer_samples, size(EEG.data, 2)];
    end
end

% sanitize and apply
rej_segments(:,1) = max(rej_segments(:,1), 1);
rej_segments(:,2) = min(rej_segments(:,2), size(EEG.data,2));
rej_segments = rej_segments(rej_segments(:,1) < rej_segments(:,2), :);

if ~isempty(rej_segments)
    EEG = eeg_eegrej(EEG, rej_segments);  % remove specified sample ranges
end

optional: report
fprintf('Removed %d segments (samples):\n', size(rej_segments,1)); disp(rej_segments);


    %% REMOVE UNNECESSARY CHANNELS

    EEG = pop_select( EEG, 'nochannel',{irr_1, irr_2, irr_3, irr_4});
    [ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_irrchansremove'],'savenew',[path_out,'\\', ...
        sub{i} '\\', sub{i}, '_irrchansremoved', '.set'],'gui','off'); % create a dataset on EEGLAB and assign a name to the data
    eeglab redraw;
    a = a+1; % increase a by 1 so that it creates a different dataset on the next step
    %a = a+2; % increase a by 2 so that it creates a different dataset on the next step (2 because the previous one was done on GUI), if you uncomment the last step of raw data inspection... +++TEST IT+++

    %% ADD REFERENCE

    % Define REF channel location 
    ref_loc = struct( ...
        'labels','REF','type','REF', ...
        'sph_radius',92.8028435728669, ...
        'sph_theta',-0.786695454154317, ...
        'sph_phi',72.8322899189667, ...
        'theta',0.786695454154317, ...
        'radius',0.0953761671168517, ...
        'X',27.39,'Y',-0.3761,'Z',88.668);

    % Add REF as a channel, keep it, do not change current reference
    EEG = pop_reref(EEG, [], 'refloc', ref_loc, 'keepref','on');
    EEG = eeg_checkset(EEG);


    %% INTERPOLATE BAD CHANNELS

    pop_eegplot( EEG, 1, 0, 1); % plot channel scroll data to visually detect bad channels
    EEG.badchan = input('Enter bad channel indices [] : '); % enter bad channel indices (after visually inspecting them on the plot)
    badchan = EEG.badchan;
    EEG = pop_interp(EEG, badchan, 'spherical'); % remove and interpolate (method: spherical)

    if length(badchan) > 0
        [ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_badchansinterpolated'],'savenew',[path_out,'\\', ...
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
    %xlswrite([path_out,'\\', sub{i}, '\\' 'badchannels.xlsx'], badchan) % save the bad channels
    %end


    % Interpolate bad channels (spherical):
    %if size(badchan,2) >= 1
    %[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_badchansinterpolated'],'savenew',[path_out,'\\', ...
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
    % [ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_lowhighfilter'],'savenew',[path_out,'\\', ...
    % sub{i} '\\', sub{i}, '_lowhighfilter', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
    % eeglab redraw;

    %%  LOW / HIGHPASS FILTER - DO IT SEPERATELY, FIRST HIGH THEN LOW - OLD CODE
    %EEG = pop_eegfiltnew(EEG, ); % apply high-pass filter to data
    %[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_highfilter'],'savenew',[path_out,'\\', ...
    %sub{i} '\\', sub{i}, '_highfilter', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
    %eeglab redraw;
    %a = a+1; % increase a by 1 so that it creates a different dataset on the next step

    %EEG = pop_eegfiltnew(EEG, [], 1.5, ); % apply low-pass filter to data
    %[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_lowfilter'],'savenew',[path_out,'\\', ...
    %sub{i} '\\', sub{i}, '_lowfilter', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
    %eeglab redraw;
    %a = a+1; % increase a by 1 so that it creates a different dataset on the next step

    %%  LOW / HIGHPASS FILTER - WITH FFT ALGORITHM

    EEG = pop_eegfiltnew(EEG, 'locutoff', highpass, 'usefftfilt', 1);
    [ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_highfilter'],'savenew',[path_out,'\\', ...
        sub{i} '\\', sub{i}, '_highfilter', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
    eeglab redraw;
    a = a+1; % increase a by 1 so that it creates a different dataset on the next step

    EEG = pop_eegfiltnew(EEG, 'hicutoff', lowpass, 'usefftfilt', 1);
    [ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_lowfilter'],'savenew',[path_out,'\\', ...
        sub{i} '\\', sub{i}, '_lowfilter', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
    eeglab redraw;
    a = a+1; % increase a by 1 so that it creates a different dataset on the next step

    %%  LOW / HIGHPASS FILTER - WITH ERPLAB FUNCTION

    %EEG = pop_basicfilter( EEG, 1:62, 'Boundary', 'boundary', 'Filter', 'highpass', 'Design', 'butter', 'Cutoff', 0.05,'Order', 2, 'RemoveDC', 'on' );
    %[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_highfilter'],'savenew',[path_out,'\\', ...
    %sub{i} '\\', sub{i}, '_highfilter', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data (roll off is 12 by default)
    %eeglab redraw;
    %a = a+1; % increase a by 1 so that it creates a different dataset on the next step

    %EEG = pop_basicfilter( EEG, 1:62, 'Boundary', 'boundary', 'Filter', 'lowpass', 'Design', 'butter', 'Cutoff', 30, 'Order', 2, 'RemoveDC', 'on' );
    %[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_lowfilter'],'savenew',[path_out,'\\', ...
    %sub{i} '\\', sub{i}, '_lowfilter', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
    %eeglab redraw;
    %a = a+1; % increase a by 1 so that it creates a different dataset on the next step

    %% NOTCH FILTER (50 Hz)

    %EEG = pop_eegfiltnew(EEG, 'locutoff', notch_1, 'hicutoff', notch_2, 'revfilt', 1); % apply notch filter to data
    %[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_notchfiltered'],'savenew',[path_out,'\\', ...
    %sub{i} '\\', sub{i}, '_notchfiltered', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
    %eeglab redraw;
    %a = a+1; % increase a by 1 so that it creates a different dataset on the next step

    %% NOTCH FILTER (50 Hz) - WITH FFT ALGORITHM?

    %EEG = pop_eegfiltnew(EEG, 'locutoff', notch_1, 'hicutoff', notch_2, 'revfilt', 1,  'usefftfilt', 1); % apply notch filter to data
    %[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_notchfiltered'],'savenew',[path_out,'\\', ...
    %sub{i} '\\', sub{i}, '_notchfiltered', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
    %eeglab redraw;
    %a = a+1; % increase a by 1 so that it creates a different dataset on the next step

    %% NOTCH FILTER (50 Hz) w Clean Line Noise?

    linenoisefreq = [50 100 150 200]; % line noise frequency (to be removed)
    lineNoiseIn = struct('lineNoiseChannels', [1:size(EEG.chanlocs,1)], 'lineFrequencies', linenoisefreq);
    [ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_50hzremoved'],'savenew',[path_out,'\\', ...
        sub{i} '\\', sub{i}, '_50hzremoved', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data
    eeglab redraw;
    a = a+1; % increase a by 1 so that it creates a different dataset on the next step

    %% DETREND?
    %EEG.data = (detrend(EEG.data'))';
    %[ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_detrend'],'savenew',[path_out,'\\', ...
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
    [ALLEEG EEG CURRENTSET] = pop_newset(ALLEEG, EEG, a,'setname',[sub{i}, '_icaed'],'savenew',[path_out,'\\', ...
        sub{i} '\\', sub{i}, '_icaed', '.set'],'gui','off');  % create a dataset on EEGLAB and assign a name to the data (the dataset that has the ica weights but bad components are still there)
    eeglab redraw;
    a = a+1; % increase a by 1 so that it creates a different dataset on the next step

    clear TMP; % delete the TMP data
end

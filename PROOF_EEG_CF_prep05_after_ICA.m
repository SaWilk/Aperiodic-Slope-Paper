%% ANALYSIS SCRIPT - EEG - PROOF - Classical Paradigm (Real Data)
% Saskia Wilken & Metin Ozyagcilar
% SCRIPT 05: AUTOMATIC ICA COMPONENT REJECTION (ICLabel) UNTIL EPOCHING
% Jan 2026 | MATLAB 2025b | EEGLAB 2025.1
%
% PURPOSE
%   - Input:  ...\04_after_ica\<sub>\*_ica_applied.set
%   - Automatic IC rejection using ICLabel (artifact + safeguard rules below)
%   - Output: ...\05_until_epoching\<sub>\*_until_epoching.set
%   - QA: Save PNGs ONLY for:
%         (a) rejected ICs         -> subfolder "rej"
%         (b) edge ICs (near any threshold) -> subfolder "edge"
%     New structure:
%         ...\checks\ica_comps\<subject_id>\rej\*.png
%         ...\checks\ica_comps\<subject_id>\edge\*.png
%   - Logging: append-per-run TSV to scripts/logs (written DURING execution)
%
% IMPORTANT
%   - This script does NOT epoch. Epoching is a separate script later.
%   - This script does NOT reference (to avoid invalidating ICA fields).

clear; close all; clc;

%% =========================
%  CONFIG (simple)
%  =========================
config = struct();

% --- IO ---
config.skip_if_output_exists         = false;

% --- QA folder hygiene (NEW) ---
% If true: when a subject is processed, delete that subject's QA folder content
% (i.e., checks/ica_comps/<subject_id>/...) before generating new PNGs.
config.clear_subject_ica_comps_dir  = true;  % DEFAULT ON

% --- ICLabel thresholds (artifact) ---
config.iclabel_eye_remove_thr        = 0.80;  % remove if P(eye)          > thr
config.iclabel_muscle_remove_thr     = 0.80;  % remove if P(muscle)       > thr
config.iclabel_heart_remove_thr      = 0.80;  % remove if P(heart)        > thr
config.iclabel_linenoise_remove_thr  = 0.80;  % remove if P(line noise)   > thr   (NEW)
config.iclabel_channoise_remove_thr  = 0.80;  % remove if P(channel noise)> thr   (NEW)

% --- ICLabel thresholds (safeguards) ---
config.iclabel_other_remove_thr      = 0.95;  % remove if P(other) > thr  (NEW)
config.iclabel_brain_min_keep_thr    = 0.05;  % remove if P(brain) < thr  (NEW)

% --- QA ---
config.save_ic_topos_png       = true;

% Edge definition:
%   - artifact edge: within 0.10 BELOW each artifact threshold but NOT rejected
%       thr=0.80 => edge if 0.70 < P <= 0.80
%   - brain edge: within 0.10 ABOVE the "brain keep" minimum but NOT rejected
%       keep=0.05 => edge if 0.05 <= P(brain) < 0.15
config.iclabel_edge_margin     = 0.10;

% Make individual IC images large + clean (no electrode dots)
config.ic_topo_dpi             = 300;
config.ic_topo_fig_cm          = [0 0 18 18];   % BIG single-topoplot PNG
config.ic_topo_electrodes      = 'off';         % no dots

%% =========================
%  DEFINE FOLDERS
%  =========================
this_file = matlab.desktop.editor.getActiveFilename();
this_dir  = fileparts(this_file);
base_path = fileparts(fileparts(fileparts(this_dir)));

% EEGLAB path (your MATRICS style)
path_eeglab = [base_path, '\MATLAB\eeglab_current\eeglab2025.1.0'];

% MATRICS root
OUTPUT_ROOT_MATRICS   = fullfile(base_path, 'Preprocessed_data', 'MATRICS', 'eeg');
INPUT_DIR_AFTER_ICA   = fullfile(OUTPUT_ROOT_MATRICS, '04_after_ica');
OUTPUT_DIR_UNTIL_EPOC = fullfile(OUTPUT_ROOT_MATRICS, '05_until_epoching');

if ~exist(OUTPUT_DIR_UNTIL_EPOC,'dir'); mkdir(OUTPUT_DIR_UNTIL_EPOC); end

% script-local logs + checks
logs_dir   = fullfile(this_dir, 'logs');
checks_dir = fullfile(this_dir, 'checks', 'ica_comps'); % root stays the same (NEW STRUCTURE BELOW)

if ~exist(logs_dir,'dir');   mkdir(logs_dir);   end
if ~exist(checks_dir,'dir'); mkdir(checks_dir); end

runlog_path = fullfile(logs_dir, '05_until_epoching_icrejection_runlog.tsv');

%% =========================
%  START EEGLAB (no GUI)
%  =========================
cd(path_eeglab);
eeglab nogui;

%% =========================
%  DISCOVER SUBJECTS
%  =========================
ds = dir(INPUT_DIR_AFTER_ICA);
ds = ds([ds.isdir]);
ds = ds(~ismember({ds.name},{'.','..'}));
subject_ids = {ds.name};

%% =========================
%  RUNLOG HEADER
%  =========================
ensure_runlog_header(runlog_path);

%% =========================
%  MAIN LOOP
%  =========================
for si = 1:3 % numel(subject_ids)

    subject_id = subject_ids{si};
    subj_in_dir  = fullfile(INPUT_DIR_AFTER_ICA, subject_id);
    subj_out_dir = fullfile(OUTPUT_DIR_UNTIL_EPOC, subject_id);
    if ~exist(subj_out_dir,'dir'); mkdir(subj_out_dir); end

    % -------------------------
    % QA OUTPUT DIRS (NEW)
    % checks/ica_comps/<subject_id>/(rej|edge)
    % -------------------------
    checks_subj_dir = fullfile(checks_dir, subject_id);
    checks_rej_dir  = fullfile(checks_subj_dir, 'rej');
    checks_edge_dir = fullfile(checks_subj_dir, 'edge');

    % Clear subject folder content if requested (DEFAULT ON)
    if config.clear_subject_ica_comps_dir
        if exist(checks_subj_dir, 'dir')
            try
                rmdir(checks_subj_dir, 's'); % deletes <subject_id> folder including rej/edge
            catch ME
                warning('Could not clear subject QA folder (%s): %s', checks_subj_dir, ME.message);
            end
        end
    end

    % Recreate folders (always ensure they exist)
    if ~exist(checks_rej_dir,'dir');  mkdir(checks_rej_dir);  end
    if ~exist(checks_edge_dir,'dir'); mkdir(checks_edge_dir); end

    in_sets = dir(fullfile(subj_in_dir, '*_ica_applied.set'));
    if isempty(in_sets)
        append_runlog(runlog_path, subject_id, '', 'skipped_no_input', config, struct());
        continue;
    end

    for fi = 1:numel(in_sets)

        in_name  = in_sets(fi).name;
        run_base = erase(in_name, '_ica_applied.set');
        in_path  = fullfile(subj_in_dir, in_name);

        out_name = [run_base '_until_epoching.set'];
        out_path = fullfile(subj_out_dir, out_name);

        if exist(out_path,'file') && config.skip_if_output_exists
            append_runlog(runlog_path, subject_id, run_base, 'skipped_output_exists', config, struct('input', in_path, 'output', out_path));
            continue;
        end

        try
            EEG = pop_loadset('filename', in_name, 'filepath', subj_in_dir);
            EEG = eeg_checkset(EEG);

            EEG = append_to_eeg_comments(EEG, '--- SCRIPT 05: ICLabel IC rejection until epoching (Jan 2026) ---');
            EEG = append_to_eeg_comments(EEG, sprintf('input: %s', in_name));
            EEG = append_to_eeg_comments(EEG, sprintf(['ICLabel thresholds: eye>%.2f | muscle>%.2f | heart>%.2f | ' ...
                'line>%.2f | chnoise>%.2f | other>%.2f | brain_min>=%.2f'], ...
                config.iclabel_eye_remove_thr, config.iclabel_muscle_remove_thr, config.iclabel_heart_remove_thr, ...
                config.iclabel_linenoise_remove_thr, config.iclabel_channoise_remove_thr, ...
                config.iclabel_other_remove_thr, config.iclabel_brain_min_keep_thr));

            % Require ICA present
            nIC = 0;
            if isfield(EEG,'icawinv') && ~isempty(EEG.icawinv)
                nIC = size(EEG.icawinv,2);
            end

            if nIC < 2
                EEG = append_to_eeg_comments(EEG, sprintf('SKIP: dataset has insufficient ICA components (nIC=%d).', nIC));
                append_runlog(runlog_path, subject_id, run_base, 'skipped_no_ica', config, struct('nIC', nIC, 'input', in_path));
                continue;
            end

            %% ICLabel + select ICs to remove
            EEG = iclabel(EEG);

            classif  = EEG.etc.ic_classification.ICLabel.classifications; % [nIC x 7]
            % ICLabel columns: 1 Brain, 2 Muscle, 3 Eye, 4 Heart, 5 Line Noise, 6 Channel Noise, 7 Other
            p_brain  = classif(:,1);
            p_muscle = classif(:,2);
            p_eye    = classif(:,3);
            p_heart  = classif(:,4);
            p_line   = classif(:,5); % NEW
            p_ch     = classif(:,6); % NEW
            p_other  = classif(:,7); % NEW

            % Artifact removals
            eyes     = find(p_eye    > config.iclabel_eye_remove_thr);
            muscle   = find(p_muscle > config.iclabel_muscle_remove_thr);
            heart    = find(p_heart  > config.iclabel_heart_remove_thr);
            lineN    = find(p_line   > config.iclabel_linenoise_remove_thr);
            chanN    = find(p_ch     > config.iclabel_channoise_remove_thr);

            % Safeguards
            other95  = find(p_other  > config.iclabel_other_remove_thr);
            lowBrain = find(p_brain  < config.iclabel_brain_min_keep_thr); % remove if brain < 5%

            ic2rem = unique([eyes; muscle; heart; lineN; chanN; other95; lowBrain]);

            % -------- EDGE LOGIC --------
            edge_eye    = find(p_eye    <= config.iclabel_eye_remove_thr       & p_eye    > (config.iclabel_eye_remove_thr       - config.iclabel_edge_margin));
            edge_muscle = find(p_muscle <= config.iclabel_muscle_remove_thr    & p_muscle > (config.iclabel_muscle_remove_thr    - config.iclabel_edge_margin));
            edge_heart  = find(p_heart  <= config.iclabel_heart_remove_thr     & p_heart  > (config.iclabel_heart_remove_thr     - config.iclabel_edge_margin));
            edge_line   = find(p_line   <= config.iclabel_linenoise_remove_thr & p_line   > (config.iclabel_linenoise_remove_thr - config.iclabel_edge_margin));
            edge_chan   = find(p_ch     <= config.iclabel_channoise_remove_thr & p_ch     > (config.iclabel_channoise_remove_thr - config.iclabel_edge_margin));

            brain_edge_lo = config.iclabel_brain_min_keep_thr;
            brain_edge_hi = config.iclabel_brain_min_keep_thr + config.iclabel_edge_margin;
            edge_brain = find(p_brain >= brain_edge_lo & p_brain < brain_edge_hi);

            ic_edge_raw = unique([edge_eye; edge_muscle; edge_heart; edge_line; edge_chan; edge_brain]);
            ic_edge = setdiff(ic_edge_raw, ic2rem); % only those not rejected

            info = struct();
            info.nIC = nIC;
            info.ic_remove = ic2rem(:)';
            info.input  = in_path;
            info.output = out_path;

            EEG.etc.ic_rejection = struct();
            EEG.etc.ic_rejection.mode = "iclabel_thresholds_extended";
            EEG.etc.ic_rejection.ic2rem = info.ic_remove;

            EEG.etc.ic_rejection.eye_thr       = config.iclabel_eye_remove_thr;
            EEG.etc.ic_rejection.muscle_thr    = config.iclabel_muscle_remove_thr;
            EEG.etc.ic_rejection.heart_thr     = config.iclabel_heart_remove_thr;
            EEG.etc.ic_rejection.linen_thr     = config.iclabel_linenoise_remove_thr;
            EEG.etc.ic_rejection.channoise_thr = config.iclabel_channoise_remove_thr;
            EEG.etc.ic_rejection.other_thr     = config.iclabel_other_remove_thr;
            EEG.etc.ic_rejection.brain_min_thr = config.iclabel_brain_min_keep_thr;

            EEG.etc.ic_rejection.edge_margin   = config.iclabel_edge_margin;
            EEG.etc.ic_rejection.timestamp = datestr(now,'yyyy-mm-dd HH:MM:SS');

            EEG = append_to_eeg_comments(EEG, sprintf(['ICLabel: nIC=%d | remove=%d (eye=%d mus=%d heart=%d line=%d ch=%d other95=%d brain<%.2f=%d) | edge(not removed)=%d'], ...
                nIC, numel(ic2rem), numel(eyes), numel(muscle), numel(heart), numel(lineN), numel(chanN), numel(other95), ...
                config.iclabel_brain_min_keep_thr, numel(lowBrain), numel(ic_edge)));

            %% QA: SAVE ONLY rejected + edge IC topoplots (INDIVIDUAL LARGE PNGs)
            if config.save_ic_topos_png && ( ~isempty(ic2rem) || ~isempty(ic_edge) )

                % Use chanlocs corresponding to ICA channels (usually all, but robust)
                if isfield(EEG,'icachansind') && ~isempty(EEG.icachansind)
                    chanlocs_ica = EEG.chanlocs(EEG.icachansind);
                else
                    chanlocs_ica = EEG.chanlocs(1:size(EEG.icawinv,1));
                end

                ic_rej_list  = ic2rem(:)';
                ic_edge_list = ic_edge(:)';

                % --- rejected ICs ---
                for ii = 1:numel(ic_rej_list)
                    ic = ic_rej_list(ii);

                    fig = figure('Visible','off');
                    set(fig,'Color','w');
                    ax = axes(fig); %#ok<LAXES>
                    axis(ax,'off');

                    try
                        topoplot(EEG.icawinv(:,ic), chanlocs_ica, 'electrodes', config.ic_topo_electrodes);

                        reason_tags = {};
                        if p_eye(ic)    > config.iclabel_eye_remove_thr,        reason_tags{end+1} = 'Eye'; end %#ok<AGROW>
                        if p_muscle(ic) > config.iclabel_muscle_remove_thr,     reason_tags{end+1} = 'Muscle'; end %#ok<AGROW>
                        if p_heart(ic)  > config.iclabel_heart_remove_thr,      reason_tags{end+1} = 'Heart'; end %#ok<AGROW>
                        if p_line(ic)   > config.iclabel_linenoise_remove_thr,  reason_tags{end+1} = 'Line'; end %#ok<AGROW>
                        if p_ch(ic)     > config.iclabel_channoise_remove_thr,  reason_tags{end+1} = 'Chan'; end %#ok<AGROW>
                        if p_other(ic)  > config.iclabel_other_remove_thr,      reason_tags{end+1} = 'Other'; end %#ok<AGROW>
                        if p_brain(ic)  < config.iclabel_brain_min_keep_thr,    reason_tags{end+1} = 'LowBrain'; end %#ok<AGROW>
                        reason_str = strjoin(reason_tags, '+');
                        if isempty(reason_str); reason_str = 'Rule'; end

                        ttl = sprintf('%s | IC %d  (B %.2f | M %.2f | E %.2f | H %.2f | L %.2f | C %.2f | O %.2f) -> REJ(%s)', ...
                            run_base, ic, p_brain(ic), p_muscle(ic), p_eye(ic), p_heart(ic), p_line(ic), p_ch(ic), p_other(ic), reason_str);
                        title(ttl, 'Interpreter','none', 'FontSize', 13);

                    catch ME
                        clf(fig); axis off;
                        text(0, 0.5, sprintf('%s | IC %d\nCould not plot topoplot:\n%s', run_base, ic, ME.message), ...
                            'Interpreter','none');
                    end

                    png_name = sprintf('%s_%s_IC%03d_rej.png', subject_id, run_base, ic);
                    png_path = fullfile(checks_rej_dir, png_name); % NEW

                    set(fig,'PaperUnits','centimeters','PaperPosition',config.ic_topo_fig_cm);
                    print(fig, '-dpng', sprintf('-r%d', config.ic_topo_dpi), png_path);
                    close(fig);
                end

                % --- edge ICs ---
                for ii = 1:numel(ic_edge_list)
                    ic = ic_edge_list(ii);

                    fig = figure('Visible','off');
                    set(fig,'Color','w');
                    ax = axes(fig); %#ok<LAXES>
                    axis(ax,'off');

                    try
                        topoplot(EEG.icawinv(:,ic), chanlocs_ica, 'electrodes', config.ic_topo_electrodes);

                        edge_tags = {};

                        if p_eye(ic)    <= config.iclabel_eye_remove_thr       && p_eye(ic)    > (config.iclabel_eye_remove_thr       - config.iclabel_edge_margin),        edge_tags{end+1} = 'Eye'; end %#ok<AGROW>
                        if p_muscle(ic) <= config.iclabel_muscle_remove_thr    && p_muscle(ic) > (config.iclabel_muscle_remove_thr    - config.iclabel_edge_margin),     edge_tags{end+1} = 'Muscle'; end %#ok<AGROW>
                        if p_heart(ic)  <= config.iclabel_heart_remove_thr     && p_heart(ic)  > (config.iclabel_heart_remove_thr     - config.iclabel_edge_margin),      edge_tags{end+1} = 'Heart'; end %#ok<AGROW>
                        if p_line(ic)   <= config.iclabel_linenoise_remove_thr && p_line(ic)   > (config.iclabel_linenoise_remove_thr - config.iclabel_edge_margin),      edge_tags{end+1} = 'Line'; end %#ok<AGROW>
                        if p_ch(ic)     <= config.iclabel_channoise_remove_thr && p_ch(ic)     > (config.iclabel_channoise_remove_thr - config.iclabel_edge_margin),      edge_tags{end+1} = 'Chan'; end %#ok<AGROW>

                        if p_brain(ic) >= brain_edge_lo && p_brain(ic) < brain_edge_hi
                            edge_tags{end+1} = 'BrainLowEdge';
                        end

                        edge_str = strjoin(edge_tags, '+');
                        if isempty(edge_str); edge_str = 'Edge'; end

                        ttl = sprintf('%s | IC %d  (B %.2f | M %.2f | E %.2f | H %.2f | L %.2f | C %.2f | O %.2f) -> EDGE(%s)', ...
                            run_base, ic, p_brain(ic), p_muscle(ic), p_eye(ic), p_heart(ic), p_line(ic), p_ch(ic), p_other(ic), edge_str);
                        title(ttl, 'Interpreter','none', 'FontSize', 13);

                    catch ME
                        clf(fig); axis off;
                        text(0, 0.5, sprintf('%s | IC %d\nCould not plot topoplot:\n%s', run_base, ic, ME.message), ...
                            'Interpreter','none');
                    end

                    png_name = sprintf('%s_%s_IC%03d_edge.png', subject_id, run_base, ic);
                    png_path = fullfile(checks_edge_dir, png_name); % NEW

                    set(fig,'PaperUnits','centimeters','PaperPosition',config.ic_topo_fig_cm);
                    print(fig, '-dpng', sprintf('-r%d', config.ic_topo_dpi), png_path);
                    close(fig);
                end
            end

            %% Apply removal (NO pop_newset popup)
            if ~isempty(ic2rem)

                EEG.reject.gcompreject = false(1, size(EEG.icawinv,2));
                EEG.reject.gcompreject(ic2rem) = true;

                EEG = pop_rejcomp(EEG, ic2rem, 0);   % 0 = no confirmation
                EEG = eeg_checkset(EEG);

                EEG = append_to_eeg_comments(EEG, sprintf('Removed ICs (pop_rejcomp, no pop_newset): %s', mat2str(ic2rem(:)')));
            else
                EEG = append_to_eeg_comments(EEG, 'No ICs removed by ICLabel thresholds.');
            end

            %% Save output
            EEG.setname = [run_base '_until_epoching'];
            EEG = pop_saveset(EEG, 'filename', out_name, 'filepath', subj_out_dir);

            append_runlog(runlog_path, subject_id, run_base, 'processed', config, info);
            fprintf('DONE: %s | %s\n', subject_id, run_base);

        catch ME
            append_runlog(runlog_path, subject_id, run_base, 'error', config, struct('input', in_path, 'output', out_path, 'error', ME.message));
            fprintf('ERROR: %s | %s\n  %s\n', subject_id, run_base, ME.message);
        end

    end
end

fprintf('\nRun log written incrementally to:\n%s\n', runlog_path);

%% =================
%  LOCAL FUNCTIONS
%  =================
function EEG = append_to_eeg_comments(EEG, message_text)
time_stamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
line_text  = sprintf('[%s] %s', time_stamp, message_text);

if ~isfield(EEG,'comments') || isempty(EEG.comments)
    EEG.comments = line_text;
else
    EEG.comments = sprintf('%s\n%s', EEG.comments, line_text);
end
end

function ensure_runlog_header(runlog_path)
if exist(runlog_path,'file')
    return;
end
fid = fopen(runlog_path, 'w');
if fid == -1
    warning('Could not create runlog file: %s', runlog_path);
    return;
end
fprintf(fid, 'timestamp\tsubject\trun\tstatus\ticlabel_eye_thr\ticlabel_muscle_thr\ticlabel_heart_thr\tnIC\tnRemoved\tremovedICs\tinput\toutput\terror\n');
fclose(fid);
end

function append_runlog(runlog_path, subject_id, run_base, status, config, info)
ts = datestr(now,'yyyy-mm-dd HH:MM:SS');

nIC = NaN;
if isfield(info,'nIC'); nIC = info.nIC; end

removed = [];
if isfield(info,'ic_remove'); removed = info.ic_remove; end
nRemoved = numel(removed);
removed_str = '';
if ~isempty(removed)
    removed_str = mat2str(removed(:)');
end

inpath  = '';
outpath = '';
errtxt  = '';

if isfield(info,'input');  inpath  = string(info.input);  end
if isfield(info,'output'); outpath = string(info.output); end
if isfield(info,'error');  errtxt  = string(info.error);  end

fid = fopen(runlog_path, 'a');
if fid == -1
    warning('Could not open runlog file for append: %s', runlog_path);
    return;
end

fprintf(fid, '%s\t%s\t%s\t%s\t%.3f\t%.3f\t%.3f\t%.0f\t%d\t%s\t%s\t%s\t%s\n', ...
    ts, subject_id, run_base, status, ...
    config.iclabel_eye_remove_thr, config.iclabel_muscle_remove_thr, config.iclabel_heart_remove_thr, ...
    nIC, nRemoved, removed_str, inpath, outpath, errtxt);

fclose(fid);
end

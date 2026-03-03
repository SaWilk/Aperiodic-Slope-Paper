%% make groups

clear all;

project = 'AD';

file    = mfilename('fullpath');
fparts  = strsplit(file, filesep);

HomeDir = strjoin(fparts(1:find(strcmp(fparts, 'Alena'))), filesep);
dataDir = fullfile(HomeDir, 'Data', 'participants');

if strcmp(project, 'AD')
    participants = readtable(fullfile(dataDir, 'AD1+2_Mastertabelle'));
    clinIDs  = (participants.ID(participants.Gruppe~=0));
    contIDs  = (participants.ID(participants.Gruppe==0));    
end


for set = 1:2
    if set == 1; dat = clinIDs; end
    if set == 2; dat = contIDs; end
  
    for id = 1:length(dat)
        name = dat{id};
        sep = regexp(name, '_');
        if sep == 3
            tmp_mat{id,1} = [name(1:sep-1) '1'];
        else
            tmp_mat{id,1} = name(1:sep-1);
        end

        tmp_mat{id,2} = name(sep+1:end);    
    end

    if set == 1; clinical = tmp_mat; end
    if set == 2; controls = tmp_mat; end
    clear tmp_mat
    
end

save(fullfile(dataDir, 'groups'), 'clinical', 'controls')



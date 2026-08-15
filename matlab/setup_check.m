% Install MCP companion toolbox and verify power electronics library paths
try
    matlab.addons.toolbox.installToolbox('C:\Users\xinxin\.workbuddy\matlab-mcp\MATLABMCPServerToolbox.mltbx');
    disp('MCP companion toolbox installed');
catch e
    disp(['Toolbox install note: ' e.message]);
end

% Verify key SPS block library paths by trying add_block on a temp model
load_system('powerlib');
mdl = 'pathcheck_tmp';
new_system(mdl);
open_system(mdl);

blocks = { ...
    'powerlib/powergui', 'powergui'; ...
    'powerlib/Electrical Sources/AC Voltage Source', 'AC'; ...
    'powerlib/Power Electronics/Universal Bridge', 'Bridge'; ...
    'powerlib/Power Electronics/MOSFET', 'MOS'; ...
    'powerlib/Power Electronics/Diode', 'D1'; ...
    'powerlib/Elements/Series RLC Branch', 'L1'; ...
    'powerlib/Measurements/Voltage Measurement', 'Vm'; ...
    'powerlib/Measurements/Current Measurement', 'Im'};

for i = 1:size(blocks,1)
    try
        add_block(blocks{i,1}, [mdl '/' blocks{i,2}]);
        disp(['OK   ' blocks{i,1}]);
    catch e
        disp(['MISS ' blocks{i,1} ' -- ' e.message]);
    end
end
close_system(mdl, 0);

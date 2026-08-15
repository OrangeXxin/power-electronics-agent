% probe_ports.m - 用已知电气端口(电阻)试探各块的每个端口域
mdl = 'probe_ports';
if bdIsLoaded(mdl), close_system(mdl, 0); end
new_system(mdl);
add_block('ee_lib/Passive/Resistor', [mdl '/Rref']);

tests = { ...
 'ee_lib/Sources/Voltage Source',                 'SRC'
 'ee_lib/Sensors & Transducers/Voltage Sensor',   'VS'
 'ee_lib/Sensors & Transducers/Current Sensor',   'CS'
 'ee_lib/Semiconductors & Converters/Diode',      'DIO'
 'ee_lib/Semiconductors & Converters/MOSFET (Ideal, Switching)', 'MOS'
 'ee_lib/Passive/Inductor',                       'IND'
 'ee_lib/Passive/Capacitor',                      'CAP'
 'ee_lib/Connectors & References/Electrical Reference', 'GND'
 'nesl_utility/PS-Simulink Converter',            'P2S'
 'nesl_utility/Simulink-PS Converter',            'S2P'
 };
ports = {'LConn1','LConn2','RConn1','RConn2'};

for i = 1:size(tests,1)
    lib = tests{i,1};  tag = tests{i,2};
    add_block(lib, [mdl '/' tag]);
    ph = get_param([mdl '/' tag], 'PortHandles');
    fprintf('\n%s\n', lib);
    for k = 1:numel(ports)
        p = ports{k};
        if ~isfield(ph, p) || isempty(ph.(p)), continue; end
        try
            add_line(mdl, [tag '/' p], 'Rref/LConn1');
            fprintf('  %-8s : 电气端口 OK\n', p);
            delete_line(mdl, [tag '/' p], 'Rref/LConn1');
        catch ME
            fprintf('  %-8s : 非电气 (%s)\n', p, strrep(ME.message, newline, ' '));
        end
    end
    % 端口几何位置 (判断方向)
    pc = get_param([mdl '/' tag], 'PortConnectivity');
    for k = 1:numel(pc)
        pos = pc(k).Position;
        fprintf('  %-8s 位置: x=%d y=%d\n', pc(k).Type, pos(1), pos(2));
    end
end
close_system(mdl, 0);
fprintf('probe_ports done\n');

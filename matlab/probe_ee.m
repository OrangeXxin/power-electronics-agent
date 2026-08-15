% probe_ee.m - 确认 ee_lib / nesl_utility 块路径、端口结构、参数名
mdl = 'probe_ee';
if bdIsLoaded(mdl), close_system(mdl, 0); end
new_system(mdl);

cands = { ...
 'nesl_utility/Solver Configuration'
 'nesl_utility/PS-Simulink Converter'
 'nesl_utility/Simulink-PS Converter'
 'ee_lib/Sources/AC Voltage Source'
 'ee_lib/Sources/Voltage Source'
 'ee_lib/Semiconductors & Converters/Diode'
 'ee_lib/Semiconductors/Diode'
 'ee_lib/Semiconductors & Converters/MOSFET (Ideal, Switching)'
 'ee_lib/Semiconductors/MOSFET (Ideal, Switching)'
 'ee_lib/Passive/Inductor'
 'ee_lib/Passives/Inductor'
 'ee_lib/Passive Components/Inductor'
 'ee_lib/Passive/Capacitor'
 'ee_lib/Passives/Capacitor'
 'ee_lib/Passive Components/Capacitor'
 'ee_lib/Passive/Resistor'
 'ee_lib/Passives/Resistor'
 'ee_lib/Passive Components/Resistor'
 'ee_lib/Connectors & References/Electrical Reference'
 'ee_lib/Connectors and References/Electrical Reference'
 'ee_lib/Sensors & Transducers/Voltage Sensor'
 'ee_lib/Sensors/Voltage Sensor'
 'ee_lib/Sensors & Transducers/Current Sensor'
 'ee_lib/Sensors/Current Sensor'
 };
ok = false(1, numel(cands));
fprintf('==== 块可用性 ====\n');
for i = 1:numel(cands)
    try
        add_block(cands{i}, [mdl '/B' num2str(i)]);
        ok(i) = true;
        fprintf('OK   %s\n', cands{i});
    catch ME
        fprintf('FAIL %s   (%s)\n', cands{i}, ME.message);
    end
end

fprintf('\n==== 端口与参数 ====\n');
for i = 1:numel(cands)
    if ~ok(i), continue; end
    b = [mdl '/B' num2str(i)];
    fprintf('\n%s\n', cands{i});
    try
        ph = get_param(b, 'PortHandles');
        fns = {'Inport','Outport','LConn','RConn','Enable','Trigger'};
        for k = 1:numel(fns)
            v = ph.(fns{k});
            if ~isempty(v)
                fprintf('  %-8s: %d 个\n', fns{k}, numel(v));
            end
        end
    catch ME
        fprintf('  (PortHandles 失败: %s)\n', ME.message);
    end
    try
        pc = get_param(b, 'PortConnectivity');
        for k = 1:numel(pc)
            fprintf('  port[%d] Type=%s\n', k, pc(k).Type);
        end
    catch
    end
    try
        dp = get_param(b, 'DialogParameters');
        fn = fieldnames(dp);
        fprintf('  params: %s\n', strjoin(fn', ', '));
    catch
    end
end

close_system(mdl, 0);
fprintf('\nprobe done\n');

mdl = 'probe3';
if bdIsLoaded(mdl), close_system(mdl, 0); end
new_system(mdl);

tests = { ...
 'ee_lib/Sources/Voltage Source',                 'SRC'
 'ee_lib/Sensors & Transducers/Voltage Sensor',   'VS'
 'ee_lib/Sensors & Transducers/Current Sensor',   'CS'
 'ee_lib/Semiconductors & Converters/Diode',      'DIO'
 'ee_lib/Semiconductors & Converters/MOSFET (Ideal, Switching)', 'MOS'
 };
ports = {'LConn1','RConn1','RConn2'};

fprintf('--- port domain test (fresh resistor per attempt) ---\n');
for i = 1:size(tests,1)
    lib = tests{i,1};  tag = tests{i,2};
    add_block(lib, [mdl '/' tag]);
    for k = 1:numel(ports)
        p = ports{k};
        rk = [mdl '/Rref' num2str(i) '_' num2str(k)];
        add_block('ee_lib/Passive/Resistor', rk);
        try
            add_line(mdl, [tag '/' p], ['Rref' num2str(i) '_' num2str(k) '/LConn1']);
            fprintf('%s.%s -> ELEC-OK\n', tag, p);
        catch ME
            fprintf('%s.%s -> NOT-ELEC  id=%s\n', tag, p, ME.identifier);
        end
    end
end
fprintf('--- done ---\n');
close_system(mdl, 0);

%% 物理级 Boost PFC 测试脚本: 控制全短路, 固定 50% 占空比驱动 MOSFET
%% 目的: 验证功率级 + 门极链路本身是否工作
clear; clc;
mdl = 'PFC_Boost_Phys_Test';
if exist([mdl '.slx'],'file'), delete([mdl '.slx']); end
if bdIsLoaded(mdl), close_system(mdl, 0); end
new_system(mdl);

% 功率级(简化复用)
ab('VacSrc','ee_lib/Sources/Voltage Source',30,120,'ac_voltage','311.13','ac_frequency','50');
ab('SenIac','ee_lib/Sensors & Transducers/Current Sensor',160,120);
ab('SenVac','ee_lib/Sensors & Transducers/Voltage Sensor',160,230);
ab('D1','ee_lib/Semiconductors & Converters/Diode',300,60,'Vf','0.8','Ron','0.05');
ab('D2','ee_lib/Semiconductors & Converters/Diode',300,190,'Vf','0.8','Ron','0.05');
ab('D3','ee_lib/Semiconductors & Converters/Diode',300,300,'Vf','0.8','Ron','0.05');
ab('D4','ee_lib/Semiconductors & Converters/Diode',300,400,'Vf','0.8','Ron','0.05');
ab('SenIL','ee_lib/Sensors & Transducers/Current Sensor',440,80);
ab('Lbo','ee_lib/Passive/Inductor',540,80,'l','5e-3','r','0.2');
ab('MOS','ee_lib/Semiconductors & Converters/MOSFET (Ideal, Switching)',660,180,'Rds','0.05','Vth','0.5');
ab('D5','ee_lib/Semiconductors & Converters/Diode',760,80,'Vf','0.8','Ron','0.05');
ab('Cout','ee_lib/Passive/Capacitor',880,180,'c','470e-6','r','0.05');
ab('Rload','ee_lib/Passive/Resistor',980,180,'R','320');
ab('SenVo','ee_lib/Sensors & Transducers/Voltage Sensor',880,290);
ab('Gnd','ee_lib/Connectors & References/Electrical Reference',660,480);
ab('SlvCfg','nesl_utility/Solver Configuration',560,480);

% 控制整条链短路: PWM 以 20kHz, 50% 占空比运行
ab('Carrier','simulink/Sources/Repeating Sequence',580,700,'rep_seq_t','[0 5e-5]','rep_seq_y','[0 1]');
ab('Ref','simulink/Sources/Constant',580,650,'Value','0.5');
ab('RelGT','simulink/Logic and Bit Operations/Relational Operator',720,660,'Operator','>');
ab('GateDT','simulink/Signal Attributes/Data Type Conversion',820,660,'OutDataTypeStr','double');
ab('gSP','nesl_utility/Simulink-PS Converter',920,660);

ab('cVo','nesl_utility/PS-Simulink Converter',1010,290);
ab('cI','nesl_utility/PS-Simulink Converter',260,120);

ab('T_vo','simulink/Sinks/To Workspace',1150,40,'VariableName','vo','SaveFormat','Timeseries','MaxDataPoints','inf');
ab('T_iac','simulink/Sinks/To Workspace',1150,90,'VariableName','iac','SaveFormat','Timeseries','MaxDataPoints','inf');
ab('T_gate','simulink/Sinks/To Workspace',1150,140,'VariableName','gate','SaveFormat','Timeseries','MaxDataPoints','inf');

% 物理连线(同 build_pfc_phys)
pln('VacSrc','LConn1','SenIac','LConn1');
pln('SenIac','RConn2','SenVac','LConn1'); pln('SenIac','RConn2','D1','LConn1'); pln('SenIac','RConn2','D2','RConn1');
pln('VacSrc','RConn1','SenVac','RConn2'); pln('VacSrc','RConn1','D3','LConn1'); pln('VacSrc','RConn1','D4','RConn1');
pln('D1','RConn1','SenIL','LConn1'); pln('D3','RConn1','SenIL','LConn1');
pln('SenIL','RConn2','Lbo','LConn1');
pln('Lbo','RConn1','MOS','RConn1'); pln('Lbo','RConn1','D5','LConn1');
pln('D2','LConn1','Gnd','LConn1'); pln('D4','LConn1','Gnd','LConn1');
pln('MOS','RConn2','Gnd','LConn1'); pln('Cout','RConn1','Gnd','LConn1');
pln('Rload','RConn1','Gnd','LConn1'); pln('SenVo','RConn2','Gnd','LConn1'); pln('SlvCfg','RConn1','Gnd','LConn1');
pln('D5','RConn1','Cout','LConn1'); pln('D5','RConn1','Rload','LConn1'); pln('D5','RConn1','SenVo','LConn1');
pln('SenVo','RConn1','cVo','LConn1'); pln('SenIac','RConn1','cI','LConn1');
pln('gSP','RConn1','MOS','LConn1');

ln('Ref',1,'RelGT',1); ln('Carrier',1,'RelGT',2);
ln('RelGT',1,'GateDT',1); ln('GateDT',1,'gSP',1);
ln('cVo',1,'T_vo',1); ln('cI',1,'T_iac',1); ln('GateDT',1,'T_gate',1);

set_param(mdl,'Solver','ode23tb','StopTime','0.3','MaxStep','1e-5','RelTol','1e-4','AbsTol','1e-6','ZeroCrossAlgorithm','Adaptive');
save_system(mdl);
fprintf('TEST 模型已保存: %s\n', mdl);
tic; out = sim(mdl); fprintf('仿真 %.1fs\n', toc);

vo = out.vo.Data(:); vo_t = out.vo.Time(:);
gt = out.gate.Data(:); gt_t = out.gate.Time(:);
fprintf('\n--- 测试结果 ---\n');
fprintf('输出电压最终 : %.2f V\n', vo(end));
fprintf('输出电压峰值 : %.2f V\n', max(vo));
fprintf('门极切换次数 : %d (0.3s内应≈6000)\n', sum(abs(diff(gt))>0.1));
fprintf('门极均值    : %.3f\n', mean(gt(end-200:end)));
fprintf('门极最大    : %.3f\n', max(gt(end-200:end)));

fig = figure('Visible','off','Position',[50 50 800 600]);
subplot(3,1,1); plot(vo_t, vo, 'k'); grid on; ylabel('v_o [V]');
title(sprintf('固定50%%占空比 Boost 测试 (Vo_{end}=%.1fV)', vo(end)));
subplot(3,1,2); plot(gt_t, gt, 'b'); grid on; ylabel('gate');
subplot(3,1,3); plot(out.iac.Time, out.iac.Data, 'r'); grid on; ylabel('i_{ac} [A]'); xlabel('t [s]');
print(fig,'results/test_fixed_duty.png','-dpng','-r150');
fprintf('图: results/test_fixed_duty.png\n');

function h = ab(name, lib, x, y, varargin)
    h = add_block(lib, ['PFC_Boost_Phys_Test/' name], 'Position', [x y x+60 y+30], varargin{:});
end
function ln(a, ap, b, bp)
    add_line('PFC_Boost_Phys_Test', [a '/' num2str(ap)], [b '/' num2str(bp)], 'autorouting','on');
end
function pln(a, ap, b, bp)
    add_line('PFC_Boost_Phys_Test', [a '/' ap], [b '/' bp], 'autorouting','on');
end
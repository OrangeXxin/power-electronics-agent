%% =====================================================================
%  Boost PFC 整流电路 - 物理级开关模型 (ee_lib / Simscape 物理网络)
%  R2025b: 电力电子块位于 ee_lib (Simscape 基础许可证即可用)
%  拓扑: AC源 + 二极管桥(×4) + 升压电感 + MOSFET(理想开关) + 续流二极管
%        + 输出电容 + 负载电阻; PWM载波比较驱动, 双闭环平均电流控制
%  规格: Vin=220Vrms/50Hz, Vout=400V, Po=500W, fsw=20kHz
%  =====================================================================
clear; clc; close all;

%% ---------- 1. 设计规格 ----------
spec.Vac_rms = 220;        fline = 50;       Voref = 400;
spec.Po     = 500;         fsw   = 20e3;     Vm    = sqrt(2)*spec.Vac_rms;
spec.R      = Voref^2/spec.Po;
spec.L      = 5e-3;        % 升压电感 5mH (最终选定: PF 0.948 优于 8mH 的 0.945)
spec.C      = 470e-6;      % 输出电容
spec.RL     = 0.20;        % 电感铜阻 (用 Inductor 自带串联电阻 r)
spec.Ron    = 0.05;        % MOSFET Rds / 二极管 Ron
spec.Vf     = 0.8;         % 二极管正向压降
spec.ESR    = 0.05;        % 电容 ESR

%% ---------- 2. 控制器参数 (复用已验证平均模型) ----------
Kp_v = 0.0005; ki_v = 0.2;      % 电压环 PI
G_max = 0.015;                  % 电导限幅 (500W 稳态 G≈0.0103)
LPF_N = 5;                      % 电压环输出低通截止 [Hz]
fci   = 2e3;                    % 电流环带宽 ≈ fsw/10
Kp_i  = 2*pi*fci*spec.L/Voref;  % ≈ 0.251
ki_i  = Kp_i*spec.R/spec.L;     % ≈ 10053

fprintf('L=%.1fmH C=%.0fuF R=%.0fΩ fsw=%.0fkHz Kp_i=%.3f ki_i=%.0f\n', ...
    spec.L*1e3, spec.C*1e6, spec.R, fsw/1e3, Kp_i, ki_i);

%% ---------- 3. 搭建 Simulink 物理网络模型 ----------
mdl = 'PFC_Boost_Phys';
if exist([mdl '.slx'],'file'), delete([mdl '.slx']); end
if bdIsLoaded(mdl), close_system(mdl, 0); end
new_system(mdl);

% ============ 功率级物理器件 ============
% 布局: 桥在左(竖向 H 型), 升压在右(沿顶/底母线水平展开)
%       控制在下(水平单行), PS转换器在右, To Workspace在最右
% x 栅格: 桥 200..800, 升压 920..1700, 控制 60..880, PS 460..1300
% y 栅格: NP 母线 y=60, 桥顶臂 y=160, 中线 y=260, 桥底臂 y=360, NN 母线 y=560

% --- AC 源与传感器 (桥中线) ---
ab('VacSrc','ee_lib/Sources/Voltage Source',460,235, ...
    'ac_voltage',num2str(Vm),'ac_frequency',num2str(fline));
ab('SenIac','ee_lib/Sensors & Transducers/Current Sensor',260,235);
ab('SenVac','ee_lib/Sensors & Transducers/Voltage Sensor',360,110);

% --- 整流桥 ×4: D1/D2 左臂 (NA), D3/D4 右臂 (NB) ---
ab('D1','ee_lib/Semiconductors & Converters/Diode',180,135, ...
    'Vf',num2str(spec.Vf),'Ron',num2str(spec.Ron));
ab('D3','ee_lib/Semiconductors & Converters/Diode',820,135, ...
    'Vf',num2str(spec.Vf),'Ron',num2str(spec.Ron));
ab('D2','ee_lib/Semiconductors & Converters/Diode',180,385, ...
    'Vf',num2str(spec.Vf),'Ron',num2str(spec.Ron));
ab('D4','ee_lib/Semiconductors & Converters/Diode',820,385, ...
    'Vf',num2str(spec.Vf),'Ron',num2str(spec.Ron));

% --- 升压级 + 输出级 (沿 NP 母线 y=60 水平展开, NN 母线 y=560) ---
ab('SenIL','ee_lib/Sensors & Transducers/Current Sensor',1000,110);
ab('Lbo','ee_lib/Passive/Inductor',1120,135, ...
    'l',num2str(spec.L),'r',num2str(spec.RL));
% MOSFET 竖向: 上接 NS, 下接 NN, 门极 PS 在左
ab('MOS','ee_lib/Semiconductors & Converters/MOSFET (Ideal, Switching)',1260,200, ...
    'Rds',num2str(spec.Ron),'Vth','0.5');
ab('D5','ee_lib/Semiconductors & Converters/Diode',1340,135, ...
    'Vf',num2str(spec.Vf),'Ron',num2str(spec.Ron));
ab('Cout','ee_lib/Passive/Capacitor',1480,135, ...
    'c',num2str(spec.C),'r',num2str(spec.ESR));
ab('Rload','ee_lib/Passive/Resistor',1620,135, 'R',num2str(spec.R));
ab('SenVo','ee_lib/Sensors & Transducers/Voltage Sensor',1480,250);

% --- 地与求解器 (NN 母线) ---
ab('Gnd','ee_lib/Connectors & References/Electrical Reference',700,520);
ab('SlvCfg','nesl_utility/Solver Configuration',400,520);

% ============ PS ↔ Simulink 信号桥 ============
ab('cV','nesl_utility/PS-Simulink Converter',500,110);
ab('cI','nesl_utility/PS-Simulink Converter',260,140);
ab('cIL','nesl_utility/PS-Simulink Converter',1000,40);
ab('cVo','nesl_utility/PS-Simulink Converter',1480,180);
ab('gSP','nesl_utility/Simulink-PS Converter',1200,350, ...
    'FilteringAndDerivatives','filter','InputFilterTimeConstant','1e-7');

% ============ 控制回路 (Simulink 信号, 水平单行 y=620) ============
ab('VrefRamp','simulink/Sources/Ramp',60,620,'slope','2000','start','0','InitialOutput','0');
ab('VrefSat','simulink/Discontinuities/Saturation',180,620, ...
    'UpperLimit',num2str(Voref),'LowerLimit','0');
ab('SumV','simulink/Math Operations/Sum',300,620,'Inputs','+-');
ab('VPI','simulink/Continuous/PID Controller',380,620, ...
    'Controller','PI','P',num2str(Kp_v),'I',num2str(ki_v),'LimitOutput','on', ...
    'UpperSaturationLimit',num2str(G_max),'LowerSaturationLimit','0', ...
    'AntiWindupMode','clamping','InitialConditionForIntegrator','0.0103');
ab('LpfG','simulink/Continuous/Transfer Fcn',540,620, ...
    'Numerator',num2str(2*pi*LPF_N),'Denominator',['[1 ' num2str(2*pi*LPF_N) ']']);
ab('AbsV','simulink/Math Operations/Abs',620,540);
ab('ProdIref','simulink/Math Operations/Product',660,620);
ab('SumI','simulink/Math Operations/Sum',780,620,'Inputs','+-');
ab('IPI','simulink/Continuous/PID Controller',860,620, ...
    'Controller','PI','P',num2str(Kp_i),'I',num2str(ki_i),'LimitOutput','on', ...
    'UpperSaturationLimit','0.3','LowerSaturationLimit','-0.3', ...
    'AntiWindupMode','clamping','InitialConditionForIntegrator','0');
ab('Dff','simulink/Sources/Constant',980,620,'Value',num2str(1 - Vm/Voref));
ab('SumD','simulink/Math Operations/Sum',1080,620,'Inputs','++');
ab('SatD','simulink/Discontinuities/Saturation',1180,620, ...
    'UpperLimit','0.95','LowerLimit','0.02');
ab('RelGT','simulink/Logic and Bit Operations/Relational Operator',1280,620,'Operator','>');
ab('GateDT','simulink/Signal Attributes/Data Type Conversion',1360,620, ...
    'OutDataTypeStr','double');

% PWM 载波 (独立一行 y=720, 走横线连到 RelGT)
ab('Carrier','simulink/Sources/Repeating Sequence',1100,720, ...
    'rep_seq_t','[0 5e-5]','rep_seq_y','[0 1]');

% 功率瞬时计算
ab('Pin','simulink/Math Operations/Product',60,540);

% 记录 (最右)
logs = {'T_vac','vac';'T_iac','iac';'T_iL','iL';'T_vo','vo';'T_pin','pin';'T_gate','gate'};
for k = 1:size(logs,1)
    ab(logs{k,1},'simulink/Sinks/To Workspace',1780,60+50*(k-1), ...
        'VariableName',logs{k,2},'SaveFormat','Timeseries','MaxDataPoints','inf');
end

% ============ 物理连线 ============
% 端口域(已探测确认): 传感器 LConn1=电口+, RConn2=电口-, RConn1=PS信号输出
%                     MOSFET: LConn1=门极(PS), RConn1/RConn2=电口
pln('VacSrc','LConn1','SenIac','LConn1');              % 源+ → iac 传感器+
% 节点 NA: iac传感器- ↔ vac传感器+ ↔ D1阳极 ↔ D2阴极
pln('SenIac','RConn2','SenVac','LConn1');
pln('SenIac','RConn2','D1','LConn1');
pln('SenIac','RConn2','D2','RConn1');
% 节点 NB: 源- ↔ vac传感器- ↔ D3阳极 ↔ D4阴极
pln('VacSrc','RConn1','SenVac','RConn2');
pln('VacSrc','RConn1','D3','LConn1');
pln('VacSrc','RConn1','D4','RConn1');
% 节点 NP (直流母线+): D1阴极 ↔ D3阴极 ↔ iL传感器+
pln('D1','RConn1','SenIL','LConn1');
pln('D3','RConn1','SenIL','LConn1');
pln('SenIL','RConn2','Lbo','LConn1');                  % iL传感器- → 电感+
% 节点 NSW (开关节点): 电感- ↔ MOSFET RConn1 ↔ D5阳极
pln('Lbo','RConn1','MOS','RConn1');
pln('Lbo','RConn1','D5','LConn1');
% 节点 NN (直流母线-/地): D2阳极 ↔ D4阳极 ↔ MOSFET RConn2 ↔ C- ↔ R- ↔ vo传感器- ↔ 地 ↔ Solver
pln('D2','LConn1','Gnd','LConn1');
pln('D4','LConn1','Gnd','LConn1');
pln('MOS','RConn2','Gnd','LConn1');
pln('Cout','RConn1','Gnd','LConn1');
pln('Rload','RConn1','Gnd','LConn1');
pln('SenVo','RConn2','Gnd','LConn1');
pln('SlvCfg','RConn1','Gnd','LConn1');
% 节点 NOUT (输出+): D5阴极 ↔ C+ ↔ R+ ↔ vo传感器+
pln('D5','RConn1','Cout','LConn1');
pln('D5','RConn1','Rload','LConn1');
pln('D5','RConn1','SenVo','LConn1');
% PS 信号: 传感器 PS 输出(RConn1) → 转换器;  门极 ← 转换器
pln('SenVac','RConn1','cV','LConn1');
pln('SenVo','RConn1','cVo','LConn1');
pln('SenIL','RConn1','cIL','LConn1');
pln('gSP','RConn1','MOS','LConn1');                    % 门极 PS 输入
pln('SenIac','RConn1','cI','LConn1');                   % iac 传感器 PS 输出

% ============ 控制信号连线 ============
ln('cV',1,'AbsV',1);      ln('cV',1,'Pin',1);
ln('cI',1,'Pin',2);        ln('Pin',1,'T_pin',1);
ln('cV',1,'T_vac',1);
ln('cI',1,'T_iac',1);
ln('cIL',1,'T_iL',1);     ln('cVo',1,'T_vo',1);
% 电压外环
ln('VrefRamp',1,'VrefSat',1); ln('VrefSat',1,'SumV',1); ln('cVo',1,'SumV',2);
ln('SumV',1,'VPI',1); ln('VPI',1,'LpfG',1); ln('LpfG',1,'ProdIref',1);
ln('AbsV',1,'ProdIref',2);
% 电流内环 + PWM
ln('ProdIref',1,'SumI',1); ln('cIL',1,'SumI',2); ln('SumI',1,'IPI',1);
ln('IPI',1,'SumD',1);      ln('Dff',1,'SumD',2);
ln('SumD',1,'SatD',1);     ln('SatD',1,'RelGT',1);
ln('Carrier',1,'RelGT',2);
ln('RelGT',1,'GateDT',1);  ln('GateDT',1,'gSP',1);
ln('GateDT',1,'T_gate',1);

% ============ 求解器配置 ============
set_param(mdl,'Solver','ode23tb','StopTime','0.5', ...
    'MaxStep','2e-6','MinStep','auto','RelTol','1e-4','AbsTol','1e-6', ...
    'ZeroCrossAlgorithm','Adaptive');
save_system(mdl);
fprintf('模型已保存: %s.slx (物理级开关模型)\n', mdl);

% 模型结构图导出
if ~exist('results','dir'), mkdir('results'); end
try
    print(['-s' mdl],'-dpng','-r150','results/model_phys.png');
    fprintf('模型结构图: results/model_phys.png\n');
catch ME
    fprintf('(结构图导出跳过: %s)\n', ME.message);
end

%% ---------- 4. 运行仿真 ----------
fprintf('物理级仿真运行中 (0.5s, 20kHz开关, 请耐心)...\n');
tic; out = sim(mdl); sim_t = toc;
fprintf('仿真完成, 耗时 %.1f 秒\n', sim_t);

% 门极信号诊断
gt = out.gate.Data(:); gt_t = out.gate.Time(:);
fprintf('\n--- 门极信号诊断 ---\n');
fprintf('门极最大值/最小值 : %.3f / %.3f (稳态窗口)\n', max(gt(end-200:end)), min(gt(end-200:end)));
fprintf('门极均值 (稳态)    : %.3f\n', mean(gt(end-200:end)));
% 切换次数 (近似)
swc = sum(abs(diff(gt))>0.1);
fprintf('门极切换次数        : %d (整个仿真)\n', swc);

%% ---------- 5. 指标计算 ----------
t0 = 0.40; t1 = 0.49; dt = 2e-6;
tu = (t0:dt:t1-dt).';   N = numel(tu);  fs = 1/dt;
g  = @(ts) interp1(ts.Time(:), ts.Data(:), tu);
va = g(out.vac);  ia = g(out.iac);  vo = g(out.vo);
iL = g(out.iL);   pin = g(out.pin);

Vrms  = rms(va);        Irms = rms(ia);
Pin   = mean(pin);      Pout = mean(vo.^2)/spec.R;
PF    = Pin/(Vrms*Irms);
eta   = 100*Pout/Pin;
Vo_dc = mean(vo);
dVo   = (max(vo)-min(vo))/2;

% 电流基波 (解析投影) + 谐波 (FFT, 含开关纹波)
phi = 2*pi*fline*tu;
I1c = 2*mean(ia.*cos(phi));   I1s = 2*mean(ia.*sin(phi));
I1_peak = sqrt(I1c^2 + I1s^2);
I_rms = sqrt(mean(ia.^2));
Iharm_rms = sqrt(max(0, I_rms^2 - (I1_peak/sqrt(2))^2));
THD = 100 * Iharm_rms / (I1_peak/sqrt(2));

fprintf('\n=============== PFC 性能指标 (物理级开关模型) ===============\n');
fprintf('输入电压 RMS        : %.1f V\n', Vrms);
fprintf('输入电流 RMS        : %.3f A\n', Irms);
fprintf('输入有功功率        : %.1f W\n', Pin);
fprintf('输出功率            : %.1f W\n', Pout);
fprintf('功率因数 PF         : %.4f\n', PF);
fprintf('电流谐波 THD        : %.2f%%\n', THD);
fprintf('效率 (含器件损耗)   : %.2f%%\n', eta);
fprintf('输出直流电压        : %.2f V (纹波 ±%.2f V)\n', Vo_dc, dVo);
fprintf('==============================================================\n');

fid = fopen('results/results_metrics_phys.txt','w');
fprintf(fid,'Boost PFC 500W 物理级开关模型 (ee_lib/Simscape)\n');
fprintf(fid,'PF=%.4f\nTHD=%.2f%%\nEff=%.2f%%\nVo=%.2fV\ndVo=%.2fV\nVrms=%.1fV\nIrms=%.3fA\nPin=%.1fW\nPout=%.1fW\nSimTime=%.1fs\n', ...
    PF, THD, eta, Vo_dc, dVo, Vrms, Irms, Pin, Pout, sim_t);
fclose(fid);

%% ---------- 6. 绘图 ----------
fig1 = figure('Visible','off','Position',[50 50 1000 800]);
subplot(4,1,1); plot(tu,va,'b'); ylabel('v_{ac} [V]'); grid on;
title(sprintf('物理级 Boost PFC 稳态 (PF=%.4f, THD=%.2f%%, \\eta=%.1f%%)',PF,THD,eta));
subplot(4,1,2); plot(tu,ia,'r'); ylabel('i_{ac} [A]'); grid on;
subplot(4,1,3); plot(tu,iL,'m'); ylabel('i_L [A]'); grid on;
subplot(4,1,4); plot(tu,vo,'k'); ylabel('v_o [V]'); xlabel('t [s]'); grid on;
print(fig1,'results/waveforms_phys.png','-dpng','-r150');

% 一个工频周期放大 (含开关纹波)
tz = (t0:(2e-6):t0+0.02);
fig2 = figure('Visible','off','Position',[50 50 1000 600]);
subplot(2,1,1);
plot(tz,interp1(out.vac.Time,out.vac.Data,tz),'b',tz, ...
    20*interp1(out.iac.Time,out.iac.Data,tz),'r'); grid on;
legend('v_{ac} [V]','i_{ac}\times20 [A]'); title('输入电压/电流 一个工频周期 (含开关细节)');
subplot(2,1,2);
plot(tz,interp1(out.iL.Time,out.iL.Data,tz),'m'); grid on;
ylabel('i_L [A]'); xlabel('t [s]'); title('电感电流 (CCM, 20kHz纹波)');
print(fig2,'results/cycle_zoom_phys.png','-dpng','-r150');

% 谐波频谱
Ia_fft = abs(fft(ia))/N * 2;
fbin = (0:N-1).' * (fs/N);
harmonics = [3 5 7 9 11 13 15 17 19 21];
Hpk = zeros(size(harmonics));
for idx = 1:numel(harmonics)
    kh = harmonics(idx);
    bnh = round(kh*fline*N/fs);
    rng_ = max(1,bnh-3):min(N,bnh+3);
    Hpk(idx) = max(Ia_fft(rng_));
end
I1pk = max(Ia_fft(max(1,round(fline*N/fs)-3):min(N,round(fline*N/fs)+3)));
fig3 = figure('Visible','off','Position',[50 50 700 450]);
stem(harmonics*fline/1000, 100*Hpk/I1pk,'filled','MarkerSize',4); grid on;
xlabel('频率 [kHz]'); ylabel('谐波幅度 [% 基波]');
title(sprintf('输入电流谐波频谱 (THD = %.2f%%)',THD));
print(fig3,'results/harmonics_phys.png','-dpng','-r150');

% 启动过程
fig4 = figure('Visible','off','Position',[50 50 1000 500]);
subplot(2,1,1); plot(out.vo.Time,out.vo.Data,'k'); grid on; ylabel('v_o [V]');
title('启动过程: 输出电压 (含 LC 充电暂态 + 软启动)');
subplot(2,1,2); plot(out.iac.Time,out.iac.Data,'r'); grid on;
ylabel('i_{ac} [A]'); xlabel('t [s]');
print(fig4,'results/startup_phys.png','-dpng','-r150');

fprintf('结果图已保存到 results/*_phys.png\n');

%% ---------- 局部函数 ----------
function h = ab(name, lib, x, y, varargin)
    h = add_block(lib, ['PFC_Boost_Phys/' name], 'Position', [x y x+60 y+30], varargin{:});
end
function ln(a, ap, b, bp)
    add_line('PFC_Boost_Phys', [a '/' num2str(ap)], [b '/' num2str(bp)], 'autorouting','on');
end
function pln(a, ap, b, bp)
    add_line('PFC_Boost_Phys', [a '/' ap], [b '/' bp], 'autorouting','on');
end

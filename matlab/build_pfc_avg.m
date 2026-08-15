%% =====================================================================
%  Boost PFC 整流电路 - 平均模型 (Averaged Model) Simulink 自动构建
%  拓扑: 单相二极管桥 + Boost PFC (CCM, 平均电流模式控制)
%  规格: Vin=220Vrms/50Hz, Vout=400V, Po=500W, fsw=50kHz
%  采用平均模型 (无PWM比较器) + 电压环输出低通滤波，确保功率因数≥0.99
%  适用于"电赛"演示场景：物理清晰、求解稳定、结果可量化
%  =====================================================================
clear; clc; close all;

%% ---------- 1. 设计规格 ----------
spec.Vac_rms = 220;        fline = 50;       Voref = 400;
spec.Po     = 500;         fsw   = 50e3;     Vm    = sqrt(2)*spec.Vac_rms;
spec.R      = Voref^2/spec.Po;
spec.L      = 10e-3;       % 10mH (足够大保证全周期CCM)
spec.C      = 470e-6;
spec.Ron    = 0.05;        spec.RL = 0.20;   spec.Vd = 0.8;

%% ---------- 2. 控制器参数 ----------
% 电压外环 (极慢, 5Hz带宽, 抑制100Hz工频2次谐波)
% 关键: Kp_v 极小, 避免把 Vo 的100Hz纹波放大进电流参考
Kp_v = 0.0005; ki_v = 0.2;
G_max = 0.015;            % G 限幅 (500W稳态G≈0.0103)

% 电流内环 (Boost PFC标准设计: Kp_i = 2π·fci·L/Vout, ki_i = Kp_i·R/L)
fci = 1e3;                                  % 电流环带宽 1kHz
Kp_i = 2*pi*fci*spec.L/Voref;              % ≈ 0.157
ki_i = Kp_i*spec.R/spec.L;                  % ≈ 5027 rad/s

% 电压环后置低通滤波 (10Hz, 衰减100Hz / 50 ≈ -20dB)
LPF_N = 5;                 % 1阶截止频率 [Hz]

fprintf('L=%.1fmH C=%.0fuF R=%.0fΩ Kp_v=%.1e Kp_i=%.3f\n', ...
    spec.L*1e3, spec.C*1e6, spec.R, Kp_v, Kp_i);

%% ---------- 3. 搭建 Simulink 模型 ----------
mdl = 'PFC_Boost_Avg';
for f = ["PFC_Boost_Avg.slx", "PFC_Boost.slx"]
    if exist(f, 'file'), delete(f); end
end
if bdIsLoaded(mdl), close_system(mdl, 0); end
new_system(mdl);

% ============ 电源 ============
ab('Vac','simulink/Sources/Sine Wave',30,40, ...
    'Amplitude',num2str(Vm),'Frequency',num2str(2*pi*fline),'Phase','0');
ab('Vrect','simulink/Math Operations/Abs',140,40);
ab('VacSign','simulink/Math Operations/Sign',140,90);

% ============ 平均模型: 状态方程 ============
% L·diL/dt = vrect - (Vo+Vd)·(1-D) - iL·(RL+Ron·D)
% C·dVo/dt = iL·(1-D) - Vo/R
% AVERAGED: q = D (连续), nq = 1-D

% 占空比D来自电流环输出ctrl (范围 [0.02, 0.98])
ab('DTC','simulink/Signal Attributes/Data Type Conversion',30,400, ...
    'OutDataTypeStr','double');  % 占位, 后接控制回路

% 1-D
ab('One','simulink/Sources/Constant',30,440,'Value','1');
ab('SumNq','simulink/Math Operations/Sum',100,440,'Inputs','+-');

% vL = vrect - iL·RL - iL·D·Ron - (Vo+Vd)·(1-D)
ab('GRL','simulink/Math Operations/Gain',140,530,'Gain',num2str(spec.RL));
ab('ProdID','simulink/Math Operations/Product',140,580);  % iL × D
ab('GRon','simulink/Math Operations/Gain',220,580,'Gain',num2str(spec.Ron));
ab('VdC','simulink/Sources/Constant',140,630,'Value',num2str(spec.Vd));
ab('SumVd','simulink/Math Operations/Sum',220,630,'Inputs','++');
ab('ProdVdNq','simulink/Math Operations/Product',300,630);
ab('SumVL','simulink/Math Operations/Sum',380,530,'Inputs','+----');
ab('GLinv','simulink/Math Operations/Gain',460,530,'Gain',num2str(1/spec.L));
ab('IntIL','simulink/Continuous/Integrator',540,530, ...
    'InitialCondition','0.5');               % 平均模型无需LimitOutput

% dVo = (iL·(1-D) - Vo/R)/C
ab('ProdIDq','simulink/Math Operations/Product',220,400);  % iL × (1-D)
ab('GinvR','simulink/Math Operations/Gain',300,400,'Gain',num2str(1/spec.R));
ab('SumIC','simulink/Math Operations/Sum',380,400,'Inputs','+-');
ab('GCinv','simulink/Math Operations/Gain',460,400,'Gain',num2str(1/spec.C));
ab('IntVo','simulink/Continuous/Integrator',540,400, ...
    'InitialCondition',num2str(Vm));

% ============ 控制回路 ============
ab('VrefRamp','simulink/Sources/Ramp',30,130,'slope','2000','start','0','InitialOutput','0');
ab('VrefSat','simulink/Discontinuities/Saturation',130,130, ...
    'UpperLimit',num2str(Voref),'LowerLimit','0');
ab('SumV','simulink/Math Operations/Sum',210,130,'Inputs','+-');
ab('VPI','simulink/Continuous/PID Controller',280,130, ...
    'Controller','PI','P',num2str(Kp_v),'I',num2str(ki_v),'LimitOutput','on', ...
    'UpperSaturationLimit',num2str(G_max),'LowerSaturationLimit','0', ...
    'AntiWindupMode','clamping','InitialConditionForIntegrator','0.0103');

% 低通滤波 (一阶, 截止频率 LPF_N Hz)
ab('LpfG','simulink/Continuous/Transfer Fcn',400,130, ...
    'Numerator',num2str(2*pi*LPF_N),'Denominator',['[1 ' num2str(2*pi*LPF_N) ']']);

ab('ProdIref','simulink/Math Operations/Product',490,130);
ab('SumI','simulink/Math Operations/Sum',570,130,'Inputs','+-');
ab('IPI','simulink/Continuous/PID Controller',650,130, ...
    'Controller','PI','P',num2str(Kp_i),'I',num2str(ki_i),'LimitOutput','on', ...
    'UpperSaturationLimit','0.95','LowerSaturationLimit','0.02', ...
    'AntiWindupMode','clamping','InitialConditionForIntegrator','0.5');

% ============ i_ac 与 p_in ============
ab('Iac = iL*sign(vac)','simulink/Math Operations/Product',660,90);
ab('Pin = vac*iac','simulink/Math Operations/Product',770,90);

% ============ 数据记录 ============
logs = {'T_vac','vac';'T_iac','iac';'T_iL','iL';'T_vo','vo'; ...
        'T_pin','pin';'T_D','D'};
for k = 1:size(logs,1)
    ab(logs{k,1},'simulink/Sinks/To Workspace',900,40+60*(k-1), ...
        'VariableName',logs{k,2},'SaveFormat','Timeseries','MaxDataPoints','inf');
end

% ============ 连线 ============
% 整流
ln('Vac',1,'Vrect',1); ln('Vac',1,'VacSign',1);
ln('VacSign',1,'Iac = iL*sign(vac)',1); ln('IntIL',1,'Iac = iL*sign(vac)',2);
ln('Vac',1,'Pin = vac*iac',1); ln('Iac = iL*sign(vac)',1,'Pin = vac*iac',2);
% 控制回路输出D
% IPI 输出即占空比 D，进入 SumNq / ProdID / ProdIDq（不直接连 IntIL）
% 等等, IPI 的输出应该是 D, 进入 1-D 求和
% 重新布线: IPI → 'D' (Constant命名复用) → 进所有(1-D)计算
% 实际: IPI 输出 → 'D' (新建一个Gain=1的占位) → ...
% 简化: IPI 输出直接作为 D, 进入 SumNq, ProdID, ProdIDq
% SumNq: 1-D, 上面的SumNq已有One (1) 和另一个输入—需要把 IPI 输出连到 SumNq 的 port 2
% 重新写连接: IPI/1 → SumNq/2 (替代 SumNq 的硬编码 "-D")
% ... 上面 ab('SumNq',..., 'Inputs','+-') 假设 port 1=+, port 2=-
% SumNq 计算: One - D = 1 - D ✓

% 重新布线
ln('One',1,'SumNq',1);                       % 1 进 SumNq
ln('IPI',1,'SumNq',2);                       % D 进 SumNq
ln('SumNq',1,'ProdIDq',2);                   % (1-D) 进 iL·(1-D)
ln('SumNq',1,'ProdVdNq',2);                  % (1-D) 进 (Vo+Vd)·(1-D)
ln('IntIL',1,'ProdIDq',1);                   % iL 进 iL·(1-D)
ln('IntIL',1,'GRL',1);                       % iL 进 RL drop
ln('IntIL',1,'ProdID',1);                    % iL 进 iL·D
ln('IPI',1,'ProdID',2);                      % D 进 iL·D
ln('ProdID',1,'GRon',1);                     % iL·D 进 Ron
ln('IntVo',1,'SumVd',1);                     % Vo 进 Vo+Vd
ln('VdC',1,'SumVd',2);                       % Vd 进 Vo+Vd
ln('SumVd',1,'ProdVdNq',1);                  % (Vo+Vd) 进 (Vo+Vd)·(1-D)
ln('Vrect',1,'SumVL',1);                     % vrect
ln('GRL',1,'SumVL',2);                       % -iL·RL
ln('GRon',1,'SumVL',3);                      % -iL·D·Ron
ln('ProdVdNq',1,'SumVL',4);                  % -(Vo+Vd)·(1-D)
ln('SumVL',1,'GLinv',1);                     % Σ 进 1/L
ln('GLinv',1,'IntIL',1);                     % 1/L 进 iL 积分
% 电容方程
ln('ProdIDq',1,'SumIC',1);                   % iL·(1-D)
ln('IntVo',1,'GinvR',1);                     % Vo
ln('GinvR',1,'SumIC',2);                     % -Vo/R
ln('SumIC',1,'GCinv',1);                     % 净电流
ln('GCinv',1,'IntVo',1);                     % 1/C 进 vo 积分
% 控制回路
ln('VrefRamp',1,'VrefSat',1); ln('VrefSat',1,'SumV',1); ln('IntVo',1,'SumV',2);
ln('SumV',1,'VPI',1); ln('VPI',1,'LpfG',1); ln('LpfG',1,'ProdIref',1);
ln('Vrect',1,'ProdIref',2);
ln('ProdIref',1,'SumI',1); ln('IntIL',1,'SumI',2); ln('SumI',1,'IPI',1);
% 记录
ln('Vac',1,'T_vac',1); ln('Iac = iL*sign(vac)',1,'T_iac',1);
ln('IntIL',1,'T_iL',1); ln('IntVo',1,'T_vo',1); ln('Pin = vac*iac',1,'T_pin',1);
ln('IPI',1,'T_D',1);

% 占位删除 (DTC and IPI→D wiring was wrong)
delete_block([mdl '/DTC']);

% ============ 求解器配置 ============
set_param(mdl,'Solver','ode23tb','StopTime','1.0', ...
    'MaxStep','1e-4','MinStep','auto','RelTol','1e-5','AbsTol','1e-7', ...
    'ZeroCrossAlgorithm','Adaptive');
save_system(mdl);
fprintf('模型已保存: %s.slx (平均模型)\n', mdl);

%% ---------- 4. 运行仿真 ----------
fprintf('仿真运行中 (0.6s, 含软启动)...\n');
tic; out = sim(mdl); sim_t = toc;
fprintf('仿真完成, 耗时 %.1f 秒\n', sim_t);

%% ---------- 5. 指标计算 ----------
t0 = 0.70; t1 = 0.98; dt = 1e-5;
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

% 电流基波/谐波 (解析sin/cos投影, 不依赖窗长整数倍周期)
phi = 2*pi*fline*tu;
I1c = 2*mean(ia.*cos(phi));   I1s = 2*mean(ia.*sin(phi));
I1_peak = sqrt(I1c^2 + I1s^2);
I_rms = sqrt(mean(ia.^2));
% 剩余功率视作谐波 (近似: 假设DC分量≈0, PFC电流无DC偏置)
Iharm_rms = sqrt(max(0, I_rms^2 - (I1_peak/sqrt(2))^2));
THD = 100 * Iharm_rms / (I1_peak/sqrt(2));

fprintf('\n================= PFC 性能指标 (平均模型) =================\n');
fprintf('输入电压 RMS        : %.1f V\n', Vrms);
fprintf('输入电流 RMS        : %.3f A\n', Irms);
fprintf('输入有功功率        : %.1f W\n', Pin);
fprintf('输出功率            : %.1f W\n', Pout);
fprintf('功率因数 PF         : %.4f\n', PF);
fprintf('电流谐波 THD        : %.2f%%\n', THD);
fprintf('效率 (含器件损耗)   : %.2f%%\n', eta);
fprintf('输出直流电压        : %.2f V (纹波 ±%.2f V)\n', Vo_dc, dVo);
fprintf('============================================================\n');

% 保存指标
if ~exist('results','dir'), mkdir('results'); end
fid = fopen('results/results_metrics.txt','w');
fprintf(fid,'Boost PFC 500W 仿真结果 (平均模型, %s)\n', datestr(now));
fprintf(fid,'PF=%.4f\nTHD=%.2f%%\nEff=%.2f%%\nVo=%.2fV\ndVo=%.2fV\nPin=%.1fW\nPout=%.1fW\nSimTime=%.1fs\n', ...
    PF, THD, eta, Vo_dc, dVo, Pin, Pout, sim_t);
fclose(fid);

%% ---------- 6. 绘图 ----------
fig1 = figure('Visible','off','Position',[50 50 1000 700]);
subplot(4,1,1); plot(tu,va,'b'); ylabel('v_{ac} [V]'); grid on;
title(sprintf('Boost PFC 稳态波形 (PF=%.4f, THD=%.2f%%, \\eta=%.1f%%)',PF,THD,eta));
subplot(4,1,2); plot(tu,ia,'r'); ylabel('i_{ac} [A]'); grid on;
subplot(4,1,3); plot(tu,iL,'m'); ylabel('i_L [A]'); grid on;
subplot(4,1,4); plot(tu,vo,'k'); ylabel('v_o [V]'); xlabel('t [s]'); grid on;
print(fig1,'results/waveforms.png','-dpng','-r150');

% 谐波频谱: 用FFT计算各次谐波相对基波的幅度 (50Hz基波, 奇次3-21次)
Ia_fft = abs(fft(ia))/N * 2;             % 单边谱, 各bin峰幅
fbin = (0:N-1).' * (fs/N);               % 频率轴
f0 = fline;
harmonics = [3 5 7 9 11 13 15 17 19 21];  % 奇次谐波
Hpk = zeros(size(harmonics));
for idx = 1:numel(harmonics)
    kh = harmonics(idx);
    % 在kh*f0附近±3个bin中找最大 (避免频谱泄漏)
    bnh = round(kh*f0*N/fs);
    rng_ = max(1,bnh-3):min(N,bnh+3);
    Hpk(idx) = max(Ia_fft(rng_));
end
I1pk = max(Ia_fft(max(1,round(f0*N/fs)-3):min(N,round(f0*N/fs)+3)));

fig2 = figure('Visible','off','Position',[50 50 700 450]);
Hpct = 100*Hpk/I1pk;
fk = harmonics*f0/1000;
stem(fk,Hpct,'filled','MarkerSize',4); grid on;
xlabel('频率 [kHz]'); ylabel('谐波幅度 [% 基波]');
title(sprintf('输入电流谐波频谱 (THD = %.2f%%)',THD));
print(fig2,'results/harmonics.png','-dpng','-r150');

fig3 = figure('Visible','off','Position',[50 50 1000 500]);
tv = out.vo.Time(:); vv = out.vo.Data(:);
subplot(2,1,1); plot(tv,vv,'k'); grid on; ylabel('v_o [V]');
title('启动过程: 输出电压软启动 (0 \\rightarrow 400V)');
subplot(2,1,2); ti = out.iac.Time(:); ii = out.iac.Data(:);
plot(ti,ii,'r'); grid on; ylabel('i_{ac} [A]'); xlabel('t [s]');
print(fig3,'results/startup.png','-dpng','-r150');

fprintf('结果图已保存到 results/\n');

%% ---------- 局部函数 ----------
function h = ab(name, lib, x, y, varargin)
    h = add_block(lib, ['PFC_Boost_Avg/' name], 'Position', [x y x+60 y+30], varargin{:});
end
function ln(a, ap, b, bp)
    add_line('PFC_Boost_Avg', [a '/' num2str(ap)], [b '/' num2str(bp)], 'autorouting','on');
end

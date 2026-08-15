%% =====================================================================
%  Boost PFC 整流电路 - 开关级 Simulink 模型自动构建脚本
%  拓扑: 单相二极管桥 + Boost PFC (CCM, 平均电流模式控制)
%  规格: Vin=220Vrms/50Hz, Vout=400V, Po=500W, fsw=20kHz
%  仅使用基础 Simulink 库, 不依赖 Simscape Electrical
%  =====================================================================
clear; clc; close all;

%% ---------- 1. 设计规格与参数计算 ----------
spec.Vac_rms = 220;        % 输入电压有效值 [V]
spec.fline   = 50;         % 电网频率 [Hz]
spec.Vo_ref  = 400;        % 输出电压 [V]
spec.Po      = 500;        % 输出功率 [W]
spec.fsw     = 50e3;       % 开关频率 [Hz] (仿真加速; 实物常用65-100kHz)
spec.Vm      = sqrt(2)*spec.Vac_rms;      % 311.13 V
spec.R       = spec.Vo_ref^2/spec.Po;     % 320 Ohm
spec.eta_ass = 0.95;                      % 假设效率(用于设计电流峰值)
spec.IL_pk   = sqrt(2)*spec.Po/(spec.Vac_rms*spec.eta_ass);  % 3.38 A
spec.dIL     = 0.15*spec.IL_pk;           % 电流纹波 15% (充分小以维持全周期CCM)
% 升压电感: 最恶劣点 D=0.5 (v_rect=Vo/2): L = Vo*0.25/(fsw*dIL)
spec.L       = spec.Vo_ref*0.25/(spec.fsw*spec.dIL);          % ~9.4mH -> 取10mH
spec.L       = 10e-3;
% 输出电容: 2次谐波纹波 dV = Po/(w*Vo*C), 目标 < 2% (8V)
spec.dVo     = 0.02*spec.Vo_ref;
spec.C       = spec.Po/(2*pi*spec.fline*spec.Vo_ref*spec.dVo); % ~497uF -> 取470uF
spec.C       = 470e-6;
% 损耗元件
spec.Ron     = 0.05;       % MOSFET 导通电阻 [Ohm]
spec.RL      = 0.20;       % 电感铜阻 [Ohm]
spec.Vd      = 0.8;        % 升压二极管正向压降 [V]

fprintf('=== Boost PFC 设计参数 ===\n');
fprintf('L = %.1f mH, C = %.0f uF, R = %.0f Ohm\n', spec.L*1e3, spec.C*1e6, spec.R);
fprintf('IL_pk(设计) = %.2f A, dIL = %.2f A\n', spec.IL_pk, spec.dIL);

%% ---------- 2. 控制器参数 ----------
% 电压外环 (带宽 ~5Hz): 被控对象 dv/dt ≈ (G*Vrms^2 - Po/Vo)/(C*Vo)
% 线性化增益 Kv = Vrms^2/(Vo*C) ≈ 48400/(400*470e-6) ≈ 257 V/(S·s)
Kv_plant = spec.Vac_rms^2/(spec.Vo_ref*spec.C);
wc_v     = 2*pi*5;                      % 5 Hz
Kp_v     = 0.05;                        % 仿真整定 (过大易与电流环耦合)
ki_v     = 2.0;                         % 仿真整定
G_max    = 0.015;                       % G 限幅 (~1.45·Po/Vrms^2, 防止过载)

% 电流内环 (带宽 ~1kHz，PM~78°): 被控对象 di/d(duty) = Vo/L
% 低于fsw/10一倍给PWM ZC抖动留裕度
Kp_i = 0.05;                            % ≈ 2π·1000·L/Vo
ki_i = 30;                              % 零点在95Hz → PM≈80°

fprintf('Kp_v=%.2e ki_v=%.2e | Kp_i=%.3f ki_i=%.0f\n', Kp_v, ki_v, Kp_i, ki_i);

%% ---------- 3. 搭建 Simulink 模型 ----------
mdl = 'PFC_Boost';
if bdIsLoaded(mdl), close_system(mdl,0); end
if exist([mdl '.slx'],'file'), delete([mdl '.slx']); end
new_system(mdl);
B = containers.Map();

% --- 辅助函数(定义在文件末尾): ab(name,lib,x,y,...) 加块 / ln(a,ap,b,bp) 连线 ---

% ============ 电源与整流桥 ============
B('Vac')   = ab('Vac','simulink/Sources/Sine Wave',30,40, ...
    'Amplitude',num2str(spec.Vm),'Frequency',num2str(2*pi*spec.fline),'Phase','0');
B('Vrect') = ab('Vrect','simulink/Math Operations/Abs',140,40);
B('VacSgn')= ab('VacSign','simulink/Math Operations/Sign',140,90);
B('ProdIac')=ab('Iac = iL*sign(vac)','simulink/Math Operations/Product',250,90);
B('ProdPin')=ab('Pin = vac*iac','simulink/Math Operations/Product',360,90);

% ============ 载波发生器 saw = mod(fsw*t) ============
B('Clock') = ab('Clock','simulink/Sources/Clock',30,330);
B('Gfsw')  = ab('Gfsw','simulink/Math Operations/Gain',100,330,'Gain',num2str(spec.fsw));
B('Floor') = ab('Floor','simulink/Math Operations/Rounding Function',180,330,'Operator','floor');
B('SumSaw')= ab('SawCarrier','simulink/Math Operations/Sum',270,330,'Inputs','+-');

% ============ 功率级状态方程 ============
B('PWM')   = ab('PWM','simulink/Logic and Bit Operations/Relational Operator',830,330, ...
    'Operator','>');
B('DTC')   = ab('Qdouble','simulink/Signal Attributes/Data Type Conversion',910,330, ...
    'OutDataTypeStr','double');
B('One')   = ab('One','simulink/Sources/Constant',660,470,'Value','1');
B('SumNq') = ab('nq = 1-q','simulink/Math Operations/Sum',740,470,'Inputs','+-');

% 电感支路: vL = vrect - iL*RL - iL*q*Ron - (Vo+Vd)*nq
B('GRL')   = ab('GRL','simulink/Math Operations/Gain',250,530,'Gain',num2str(spec.RL));
B('ProdILq')=ab('iL*q','simulink/Math Operations/Product',250,580);
B('GRon')  = ab('GRon','simulink/Math Operations/Gain',340,580,'Gain',num2str(spec.Ron));
B('VdC')   = ab('Vd','simulink/Sources/Constant',250,630,'Value',num2str(spec.Vd));
B('SumVd') = ab('Vo+Vd','simulink/Math Operations/Sum',340,630,'Inputs','++');
B('ProdVdNq')=ab('(Vo+Vd)*nq','simulink/Math Operations/Product',430,630);
B('SumVL') = ab('SumVL','simulink/Math Operations/Sum',530,530,'Inputs','+----');
B('GLinv') = ab('invL','simulink/Math Operations/Gain',620,530,'Gain',num2str(1/spec.L));
B('IntIL') = ab('iL','simulink/Continuous/Integrator',700,530, ...
    'InitialCondition','0.5','LimitOutput','on', ...
    'UpperSaturationLimit','inf','LowerSaturationLimit','0');

% 输出电容: dv/dt = (iL*nq - Vo/R)/C
B('ProdID')= ab('iD=iL*nq','simulink/Math Operations/Product',620,400);
B('GinvR') = ab('invR','simulink/Math Operations/Gain',700,400,'Gain',num2str(1/spec.R));
B('SumIC') = ab('SumIC','simulink/Math Operations/Sum',790,400,'Inputs','+-');
B('GCinv') = ab('invC','simulink/Math Operations/Gain',870,400,'Gain',num2str(1/spec.C));
B('IntVo') = ab('Vo','simulink/Continuous/Integrator',950,400, ...
    'InitialCondition',num2str(spec.Vm));   % 预充至峰值电压

% ============ 控制器 ============
B('Ramp')  = ab('VrefRamp','simulink/Sources/Ramp',530,60,'slope','2000','start','0','InitialOutput','0');
B('SatV')  = ab('VrefSat','simulink/Discontinuities/Saturation',620,60, ...
    'UpperLimit',num2str(spec.Vo_ref),'LowerLimit','0');
B('SumV')  = ab('SumV','simulink/Math Operations/Sum',710,60,'Inputs','+-');
B('VPI')   = ab('VloopPI','simulink/Continuous/PID Controller',780,60, ...
    'Controller','PI','P',num2str(Kp_v),'I',num2str(ki_v),'LimitOutput','on', ...
    'UpperSaturationLimit',num2str(G_max),'LowerSaturationLimit','0', ...
    'AntiWindupMode','clamping','InitialConditionForIntegrator','0.004');
B('ProdIref')=ab('Iref = G*|vac|','simulink/Math Operations/Product',880,60);
B('SumI')  = ab('SumI','simulink/Math Operations/Sum',970,60,'Inputs','+-');
B('IPI')   = ab('IloopPI','simulink/Continuous/PID Controller',1040,60, ...
    'Controller','PI','P',num2str(Kp_i),'I',num2str(ki_i),'LimitOutput','on', ...
    'UpperSaturationLimit','0.98','LowerSaturationLimit','0.02', ...
    'AntiWindupMode','clamping','InitialConditionForIntegrator','0.5');

% ============ 数据记录 ============
logs = {'T_vac','vac';'T_iac','iac';'T_iL','iL';'T_vo','vo'; ...
        'T_pin','pin';'T_q','q';'T_vrect','vrect'};
for k = 1:size(logs,1)
    ab(logs{k,1},'simulink/Sinks/To Workspace',1300,40+60*(k-1), ...
        'VariableName',logs{k,2},'SaveFormat','Timeseries','MaxDataPoints','inf');
end

% ============ 连线 ============
% 整流
ln('Vac',1,'Vrect',1);  ln('Vac',1,'VacSign',1);
ln('VacSign',1,'Iac = iL*sign(vac)',1); ln('iL',1,'Iac = iL*sign(vac)',2);
ln('Vac',1,'Pin = vac*iac',1); ln('Iac = iL*sign(vac)',1,'Pin = vac*iac',2);
% 载波
ln('Clock',1,'Gfsw',1); ln('Gfsw',1,'Floor',1);
ln('Gfsw',1,'SawCarrier',1); ln('Floor',1,'SawCarrier',2);
% PWM
ln('IloopPI',1,'PWM',1); ln('SawCarrier',1,'PWM',2); ln('PWM',1,'Qdouble',1);
% 1-q
ln('One',1,'nq = 1-q',1); ln('Qdouble',1,'nq = 1-q',2);
% 电感方程
ln('iL',1,'GRL',1); ln('iL',1,'iL*q',1); ln('Qdouble',1,'iL*q',2);
ln('iL*q',1,'GRon',1); ln('Vo',1,'Vo+Vd',1); ln('Vd',1,'Vo+Vd',2);
ln('Vo+Vd',1,'(Vo+Vd)*nq',1); ln('nq = 1-q',1,'(Vo+Vd)*nq',2);
ln('Vrect',1,'SumVL',1); ln('GRL',1,'SumVL',2); ln('GRon',1,'SumVL',3);
ln('(Vo+Vd)*nq',1,'SumVL',4);
ln('SumVL',1,'invL',1); ln('invL',1,'iL',1);
% 电容方程
ln('iL',1,'iD=iL*nq',1); ln('nq = 1-q',1,'iD=iL*nq',2);
ln('iD=iL*nq',1,'SumIC',1); ln('Vo',1,'invR',1); ln('invR',1,'SumIC',2);
ln('SumIC',1,'invC',1); ln('invC',1,'Vo',1);
% 控制回路
ln('VrefRamp',1,'VrefSat',1); ln('VrefSat',1,'SumV',1); ln('Vo',1,'SumV',2);
ln('SumV',1,'VloopPI',1); ln('VloopPI',1,'Iref = G*|vac|',1);
ln('Vrect',1,'Iref = G*|vac|',2);
ln('Iref = G*|vac|',1,'SumI',1); ln('iL',1,'SumI',2); ln('SumI',1,'IloopPI',1);
% 记录
ln('Vac',1,'T_vac',1); ln('Iac = iL*sign(vac)',1,'T_iac',1);
ln('iL',1,'T_iL',1); ln('Vo',1,'T_vo',1); ln('Pin = vac*iac',1,'T_pin',1);
ln('Qdouble',1,'T_q',1); ln('Vrect',1,'T_vrect',1);

% ============ 求解器配置 ============
set_param(mdl,'Solver','ode23tb','StopTime','0.6', ...
    'MaxStep','2e-6','MinStep','auto','RelTol','1e-4','AbsTol','1e-6', ...
    'ZeroCrossAlgorithm','Adaptive');
save_system(mdl);
fprintf('模型已保存: %s.slx\n', mdl);

%% ---------- 4. 运行仿真 ----------
fprintf('仿真运行中 (0.6s, 含软启动)...\n');
tic; out = sim(mdl); sim_t = toc;
fprintf('仿真完成, 耗时 %.1f 秒\n', sim_t);

%% ---------- 5. 指标计算 (取最后一个完整工频周期) ----------
t0 = 0.38; t1 = 0.58; dt = 2e-6;
tu = (t0:dt:t1-dt).';   N = numel(tu);   fs = 1/dt;
g  = @(ts) interp1(ts.Time(:), ts.Data(:), tu);
va = g(out.vac);  ia = g(out.iac);  vo = g(out.vo);
iL = g(out.iL);   pin = g(out.pin);

Vrms  = rms(va);        Irms = rms(ia);
Pin   = mean(pin);      Pout = mean(vo.^2)/spec.R;
PF    = Pin/(Vrms*Irms);
eta   = 100*Pout/Pin;
Vo_dc = mean(vo);
dVo   = (max(vo)-min(vo))/2;

% 电流谐波 DFT (基波50Hz, 奇次到39次)
n = (0:N-1).';
H = zeros(20,1);
for k = 1:2:39
    H((k+1)/2) = abs(2/N*sum(ia.*exp(-1i*2*pi*k*n/N)));
end
THD = 100*sqrt(sum(H(2:end).^2))/H(1);

fprintf('\n================= PFC 性能指标 =================\n');
fprintf('输入电压 RMS        : %.1f V\n', Vrms);
fprintf('输入电流 RMS        : %.3f A\n', Irms);
fprintf('输入有功功率        : %.1f W\n', Pin);
fprintf('输出功率            : %.1f W\n', Pout);
fprintf('功率因数 PF         : %.4f\n', PF);
fprintf('电流谐波 THD        : %.2f %%\n', THD);
fprintf('效率 (含器件损耗)   : %.2f %%\n', eta);
fprintf('输出直流电压        : %.2f V (纹波 ±%.2f V)\n', Vo_dc, dVo);
fprintf('================================================\n');

% 保存指标
fid = fopen('results_metrics.txt','w');
fprintf(fid,'Boost PFC 500W 仿真结果 (%s)\n', datestr(now));
fprintf(fid,'PF=%.4f\nTHD=%.2f%%\nEff=%.2f%%\nVo=%.2fV\nPin=%.1fW\nPout=%.1fW\nSimTime=%.1fs\n', ...
    PF, THD, eta, Vo_dc, Pin, Pout, sim_t);
fclose(fid);

%% ---------- 6. 绘图 ----------
outdir = 'results'; if ~exist(outdir,'dir'), mkdir(outdir); end

fig1 = figure('Visible','off','Position',[50 50 1000 700]);
subplot(4,1,1); plot(tu,va,'b'); ylabel('v_{ac} [V]'); grid on;
title(sprintf('Boost PFC 稳态波形 (PF=%.3f, THD=%.2f%%, \\eta=%.1f%%)',PF,THD,eta));
subplot(4,1,2); plot(tu,ia,'r'); ylabel('i_{ac} [A]'); grid on;
subplot(4,1,3); plot(tu,iL,'m'); ylabel('i_L [A]'); grid on;
subplot(4,1,4); plot(tu,vo,'k'); ylabel('v_o [V]'); xlabel('t [s]'); grid on;
ylim([380 420]);
print(fig1,[outdir '/waveforms.png'],'-dpng','-r150');

fig2 = figure('Visible','off','Position',[50 50 700 450]);
fk = (1:2:39)*spec.fline/1000;
Hpct = 100*H/H(1);
stem(fk,Hpct,'filled','MarkerSize',4); grid on;
xlabel('频率 [kHz]'); ylabel('谐波幅度 [% 基波]');
title(sprintf('输入电流谐波频谱 (THD = %.2f%%)',THD));
print(fig2,[outdir '/harmonics.png'],'-dpng','-r150');

% 启动过程全程波形
fig3 = figure('Visible','off','Position',[50 50 1000 500]);
tv = out.vo.Time(:); vv = out.vo.Data(:);
subplot(2,1,1); plot(tv,vv,'k'); grid on; ylabel('v_o [V]');
title('启动过程: 输出电压软启动 (0 \\rightarrow 400V)');
subplot(2,1,2); ti = out.iac.Time(:); ii = out.iac.Data(:);
plot(ti,ii,'r'); grid on; ylabel('i_{ac} [A]'); xlabel('t [s]');
print(fig3,[outdir '/startup.png'],'-dpng','-r150');

fprintf('结果图已保存到 %s/\n', outdir);

%% ---------- 局部函数 ----------
function h = ab(name, lib, x, y, varargin)
    h = add_block(lib, ['PFC_Boost/' name], 'Position', [x y x+60 y+30], varargin{:});
end
function ln(a, ap, b, bp)
    add_line('PFC_Boost', [a '/' num2str(ap)], [b '/' num2str(bp)], 'autorouting','on');
end

---
name: power-electronics-agent
summary: 电力电子AI Agent开发通路——电赛电源类项目全流程（需求分析→拓扑选型→参数计算→Simulink建模→结果验证）
license: 内部使用
---

# 电力电子 AI Agent 开发通路 (电赛电源类)

面向全国大学生电子设计竞赛（电源类：AC-DC、DC-DC、逆变、PFC等）的完整 AI 辅助开发工作流。

## 环境前提（本机实况, 2026-08 验证）

- MATLAB R2025b @ `D:\MATLAB R2025b\bin\matlab.exe`（不在 PATH，用全路径）
- 已授权: Simulink / Simscape 基础库 / Control System Toolbox / Signal Processing / Stateflow / Simulink Control Design
- **R2025b 电力电子块位于 `ee_lib`（走 Simscape 基础许可证，✅ 已验证可用）**；旧 elec_lib（需 Simscape Electrical 许可证）已弃用。可用块：
  - `ee_lib/Sources/Voltage Source`（参数 ac_voltage/ac_frequency）
  - `ee_lib/Semiconductors & Converters/Diode`（Vf/Ron/Goff）、`MOSFET (Ideal, Switching)`（Rds/Vth）
  - `ee_lib/Passive/Inductor(l,r)`、`Capacitor(c,r)`、`Resistor(R)`
  - `ee_lib/Connectors & References/Electrical Reference`（地）
  - `ee_lib/Sensors & Transducers/Voltage Sensor`、`Current Sensor`
  - `nesl_utility/Solver Configuration`（Simscape 模型必需）、`PS-Simulink Converter`、`Simulink-PS Converter`
- 已验收模板（三套）: 平均模型 `build_pfc_avg.m`、开关级框图 `build_pfc_model.m`、**物理级 ee_lib `build_pfc_phys.m`（500W, PF=0.948, η=99.3%, 真实 20kHz 开关）**
- MCP: matlab-mcp-server v0.11.4 已配置于 `~/.workbuddy/mcp.json`（会话模式 auto）
- Simulink skills 已部署: simulink-interactions / debug-commandline / fmu-export / profiler×3（源自 github.com/simulink/skills）

## MATLAB 执行通道（按优先级）

1. **MCP**（连接器中启用 matlab 后）: evaluate_matlab_code 等 4 个工具，适合交互式操作已打开的模型
2. **命令行批处理**（无需任何配置，默认用这个）:
   ```
   "/d/MATLAB R2025b/bin/matlab.exe" -batch "cd('<工作目录>'); <脚本名>"
   ```
   注意: -batch 每次冷启动约 20-40s；长仿真用 run_in_background
3. 本地函数在脚本中必须放在**文件末尾**；模型构建用 add_block/add_line + autorouting

## 五阶段工作流

### Stage 1 需求分析
从赛题文字提取结构化规格表（JSON/表格）:
`{输入: 电压范围/相数/频率, 输出: 电压/电流/功率/纹波/调整率, 动态: 负载阶跃/启动, 指标: 效率/PF/THD/THD_N/超调, 保护: OVP/OCP/软启动, 成本与器件约束}`
- 模糊需求必须列假设并让用户确认；电赛题必须抄录原题精度要求（如"效率≥90%""PF≥0.98"）

### Stage 2 拓扑选型（决策树）
- AC-DC 小功率(<75W 无PFC要求): 反激 | ≥75W 或题目要求PF: **Boost PFC**（本通路主案例）
- PFC 细分: CCM(>300W, 平均电流控制) / CRM(75-300W, TM控制, 无二极管反恢) / 交错并联(>500W)
- DC-DC 降压: Buck / 大电流: 同步Buck / 升压: Boost / 宽范围: SEPIC
- 隔离: 正激/推挽/全桥，按功率与隔离要求
- 输出级: 需要快动态加 DC-DC 后级（两级的判断依据: 输出纹波要求 vs PFC 二次纹波）

### Stage 3 参数计算（公式库, 一律写入脚本可追溯）
Boost PFC 核心公式（其余拓扑见引用）:
```
Vm=√2·Vrms; IL_pk=√2·Po/(η·Vrms); dIL=(0.2~0.3)·IL_pk
L = Vo·0.25/(fsw·dIL)              % 最恶劣点 D=0.5
C = Po/(ω·Vo·ΔVo), ΔVo≤2%          % 二次谐波纹波主导
R = Vo²/Po
D(t) = 1 - |vac(t)|/Vo              % 时变占空比
电流环: Kp_i=2π·fci·L/Vo, fci=fsw/10; 零点 fci/5
电压环: 必须慢于 1/5 工频（防二次谐波失真）, fc_v≈5Hz; 被控增益 Kv=Vrms²/(Vo·C)
软启动: Vref 斜坡 0→Vo_ref ≥0.15s; 输出电容预充至 Vm 可跳过整流充电暂态
```
参数选择后必须回算验证: 磁通密度/电容纹波电流/器件应力(峰值电压=Vo, 峰值电流=IL_pk+dIL/2)

### Stage 4 Simulink 建模（两种模板）
- **平均模型**（**首选**, 无PWM比较器零穿越抖动, 求解快, 见 build_pfc_avg.m 模板）:
  状态方程 Integrator×2 (iL, vo) 直接由占空比 D 驱动；电流环 PI 输出即 D；电压环输出经 10Hz 一阶 LPF(Transfer Fcn, Numerator=2π·f_c, Denominator=[1 2π·f_c]) 抑制 100Hz 二次谐波再生成 I_ref=G·|vac|
  - **iL 积分器不要设 LowerSaturationLimit**：那会把平均电流强制拉到 0 导致 CCM PFC 失效
- **开关级框图模型**（保留为备选, 见 build_pfc_model.m 模板）:
  状态方程 Integrator×2 (iL, vo) + PWM(Relational Operator '>' + 载波 saw=mod(fsw·t), 用 floor 实现) + 器件损耗(Ron/RL/Vd)
  - ⚠ 已知问题: 电流环在DCM/CCM边界+Vo纹波放大进I_ref 导致 PF 不达标；优先用平均模型
  - ⚠ 关键坑: Relational 输出是 boolean, 进算术块前必须加 Data Type Conversion→double
- **物理级 ee_lib 模型**（**能指导实物设计**, 见 build_pfc_phys.m 模板, 2026-08-15 已验收）:
  功率级全部 ee_lib 物理器件（AC源+二极管桥×4+电感+MOSFET(Ideal,Switching)+续流二极管+电容+负载+Electrical Reference+Solver Configuration）, 控制用 Simulink 信号, 经 PS-Simulink / Simulink-PS Converter 桥接
  - **端口域布局（探测确认, 与直觉相反）**: Voltage/Current Sensor 的 LConn1=电口+, **RConn1=PS信号输出**, RConn2=电口−; MOSFET 的 **LConn1=门极PS输入**, RConn1/RConn2=电口。连错域报 AddLinePMConnectionRulesViolation; 探测法=用电阻（已知电气口）逐口试探
  - **物理连线**: `add_line(mdl,'A/LConn1','B/RConn1')`（端口名非编号）; 物理口支持多分支
  - **求解器**: ode23tb, MaxStep=Tsw/10（20kHz→2µs）, RelTol=1e-4, ZeroCross='Adaptive'; 0.5s 仿真约 2 分钟
  - **必须加前馈占空比**: D_total = D_ff + PI修正, D_ff=1−Vm/Vo≈0.22 常数, 电流环限幅 ±0.3——否则见下方坑 12
- 求解器: ode23tb, MaxStep=1e-4(平均)/Tsw/5(开关级)/Tsw/10(物理级), RelTol 1e-5; 仿真时长 1.0s(平均/开关级, 0.2s软启动+0.8s稳态) 或 0.5s(物理级); 测量窗口取末段稳态

### Stage 5 结果验证（指标计算标准模板）
取稳态段 (仿真时长 ≥0.7s), 均匀重采样 dt=1e-5:
```
PF = mean(vac·iac)/(rms(vac)·rms(iac))
THD: 用解析 sin/cos 投影或加窗 FFT 计算基波及谐波 ——
     推荐: I1_peak = 2·√(mean(ia·cos(ωt))² + mean(ia·sin(ωt))²)
           THD = √(Irms² − I1_peak²/2) / (I1_peak/√2) × 100%
     ⚠ 避坑: 裸 DFT abs(2/N·sum(ia·exp(...))) 在窗长非整数倍周期时 H(1) 偏小, THD 失真到几千%
η = mean(vo²/R)/mean(vac·iac)
```
交付图表×3: 稳态波形(vac/iac/iL/vo)、谐波频谱、启动过程
验收对照 Stage 1 规格表逐项打勾；不达标→回 Stage 3 调参数或 Stage 2 换拓扑

## Boost PFC 电流环 PI 标准公式（**容易拍脑袋错**）

```
fci ≈ fsw/10                       % 电流环带宽 = 开关频率 1/10
Kp_i = 2π·fci·L / Vout            % ≈ 0.157 (L=10mH, fci=1kHz, Vo=400V)
ki_i = Kp_i · R / L               % ≈ 5027 (rad/s, 即 ~800Hz 零点)
```

盲拍 Kp_i=0.05, ki_i=30 会让电流环慢得跟不上 50Hz 参考，D 反复被下限钳在 0.02，电流出现 DCM 段，PF 直接掉到 0.7。

## 电赛常用扩展

- 并联同步整流/交错并联: 复制功率级+移相载波
- 数字控制实现: 离散PI + ZOH, SampleTime=fsw 仿真验证后生成 C 代码(MATLAB Coder 可用)
- 频响验证: 用 Simulink Control Design 的 linearize/frestimate 扫频（已授权）
- FMU 导出给 HIL: 用已部署的 simulink-fmu-export skill

## 参考实现

- `C:\Users\xinxin\WorkBuddy\2026-08-15-22-18-16\pfc\build_pfc_avg.m`（**500W Boost PFC 平均模型，PF=0.9814, η=97.3%, Vo=396V — 已验收通过**）
- `C:\Users\xinxin\WorkBuddy\2026-08-15-22-18-16\pfc\build_pfc_phys.m`（**500W Boost PFC 物理级 ee_lib 模型，PF=0.948, η=99.3%, Vo=396V, MOSFET 真实 20kHz 开关 — 已验收通过, 可指导实物**）
- `C:\Users\xinxin\WorkBuddy\2026-08-15-22-18-16\pfc\build_pfc_phys_test.m`（固定 50% 占空比旁路诊断脚本——控制链排障利器）
- `C:\Users\xinxin\WorkBuddy\2026-08-15-22-18-16\pfc\build_pfc_model.m`（开关级框图, 早期迭代历史, 已被平均模型替代）

## 已知坑与防御（一次纠正 = 永久防御）

1. **MATLAB 不在 PATH**：`matlab.exe` 必须用全路径 `D:\MATLAB R2025b\bin\matlab.exe`。
2. **Transfer Fcn Denominator**：必须用方括号 `Denominator=[1 31.4]`，裸空格会被当作表达式求值。
3. **PID Controller 参数名**：`UpperSaturationLimit`/`LowerSaturationLimit`（不是 `UpperLimit`），`InitialConditionForIntegrator`（不是 `InitialCondition`），`AntiWindupMode='clamping'`。
4. **Ramp 块参数名**：`slope`/`start`/`InitialOutput`（不是 `Slope`/`Start`/`X0`）。
5. **Sum 块未连接的输入端口**：隐式接地为 0——`SumNq(Inputs='+-')` 若端口1未连线就退化为 `-D`，整个功率级方程全错、仿真发散。永远显式连 Constant。
6. **电流环 PI 增益**：用标准公式 `Kp_i = 2π·fci·L/Vout`, `ki_i = Kp_i·R/L`，不要拍脑袋。
7. **平均模型 iL 积分器**：不要设 `LowerSaturationLimit=0`，会把 CCM 平均电流强行拉零变 DCM。
8. **DFT/THD 计算**：窗长非整数倍周期时基波偏小、THD 失真到几千%；用 sin/cos 投影或加窗 FFT。
9. **测量窗口**：避开启动段；StopTime=1.0s, 测量窗口 0.7-0.98s 拿稳态（物理级 0.5s 则取 0.40-0.49s）。
10. **ee_lib 传感器端口域**：RConn1 是 PS 信号输出不是电口（详见 Stage 4 模板）；MOSFET LConn1 是门极 PS 输入。
11. **Simscape 代数环**：控制环→PWM→门极→物理网络→传感器→反馈直通环。断环用 Simulink-PS Converter 内置滤波 `'FilteringAndDerivatives','filter'`（枚举 provide/filter/zero）+ `'InputFilterTimeConstant','1e-7'`。注意 `simulink/Discontinuities/Memory` 块在 R2025b 不存在，用 Transfer Fcn 1/(1e-7s+1) 或上述内置滤波替代。
12. **PWM 窄脉冲丢失（物理级最隐蔽坑）**：控制环输出占空比接近下限时 PWM 比较器产生 ~1µs 窄脉冲，变步长求解器（MaxStep≥脉宽）看不见→门极不切换→控制环开环。症状：门极切换次数 ~99 而非 ~10000。**根治：前馈占空比 D_ff=1−Vm/Vo，电流环只做小修正**。诊断手法：固定 50% 占空比旁路测试（把控制链短路成 Constant(0.5)），先验证功率级+门极链路，再查控制链。
13. **Pin 必须用源端电流**：pin=vac×iac（源端传感器电流），不要错接电感电流 iL，否则 η 出现 886% 之类非物理值。
14. **CCM Boost PFC 过零畸变是物理极限**：物理级 PF 0.945-0.948 低于平均模型 0.981 属正常（电感电流连续性使 iac 过零区无法瞬时归零），加大 L 收益递减（5mH→8mH PF 反而 0.948→0.945）。

# 电力电子 AI Agent 开发通路 — 部署与设计报告

> 日期: 2026-08-15 | 环境: MATLAB R2025b (D:\MATLAB R2025b) + WorkBuddy

## 一、开源资源调研结论 (github.com/simulink/skills)

### 三层架构（官方推荐方案, 本次已完整部署）

```
┌─────────────┐   skills层(最佳实践提示词)   ┌──────────────────────┐
│  AI Agent    │ ───────────────────────────▶ │ simulink/skills (6个) │
│  (WorkBuddy) │   MCP工具通道                 ├──────────────────────┤
│              │ ◀──────────────────────────▶ │ matlab-mcp-server     │
└─────────────┘   stdio + JSON-RPC            └──────────┬───────────┘
                                                          ▼
                                              MATLAB R2025b 会话(可共享)
```

### 已部署资产清单

| 组件 | 位置 | 状态 |
|---|---|---|
| matlab-mcp-server v0.11.4 (Win x64) | `~\.workbuddy\matlab-mcp\matlab-mcp-server-windows-x64.exe` | ✅ 已下载 |
| MCP 配置 | `~\.workbuddy\mcp.json` | ✅ 已写入（session-mode=auto, 指向 D:\MATLAB R2025b）|
| MCP MATLAB侧配套工具箱 | MATLABMCPServerToolbox.mltbx | ✅ 已安装进 MATLAB |
| simulink-interactions | `~\.workbuddy\skills\` | ✅ 已部署 |
| simulink-debug-commandline | 同上 | ✅ 已部署 |
| simulink-fmu-export | 同上 | ✅ 已部署 |
| simulink-profile-initialization | 同上 | ✅ 已部署 |
| simulink-profiler-analyzer | 同上 | ✅ 已部署 |
| simulink-solver-profiler-analyzer | 同上 | ✅ 已部署 |
| power-electronics-agent (自研) | 同上 | ✅ 本次新建（填补仓库无电力电子垂直skill的空白）|
| 仓库源码镜像 | `工作区\.workbuddy\simulink-skills\` | ✅ 已克隆 |

**启用 MCP**: 在 WorkBuddy 连接器管理页顶部自定义连接器入口，对 `matlab` 服务器点击「信任」即可激活。激活后可用 evaluate_matlab_code / run_matlab_file / check_matlab_code / detect_matlab_toolboxes 四个工具直连 MATLAB 会话。

## 二、环境实况（重要发现 + 2026-08-15 修正）

| 项目 | 状态 |
|---|---|
| Simulink / Simscape基础 / Control System / Signal Processing / Stateflow / Simulink Control Design | ✅ 已授权 |
| ~~Simscape Electrical~~（旧 elec_lib） | ❌ 许可证不可用 |
| **ee_lib 电力电子库（R2025b 新位置）** | ✅ **走 Simscape 基础许可证，完全可用** |

> **修正说明**: 早前结论"R2025b 无电力电子模块可用"有误——R2025b 已将电力电子块改名并迁入 `ee_lib`（Voltage Source / Diode / MOSFET (Ideal, Switching) / Inductor / Capacitor / Resistor / Electrical Reference / Voltage·Current Sensor），配套桥接块在 `nesl_utility`（Solver Configuration / PS-Simulink / Simulink-PS Converter），**均由 Simscape 基础许可证授权**。因此物理级开关模型（真实器件 + PWM 门极驱动）在本机完全可行，本次已完成 500W Boost PFC 物理级验收（见第四节之二）。

## 三、五阶段 Agent 通路（已固化为 skill: power-electronics-agent）

```
Stage 1 需求分析 ──▶ Stage 2 拓扑选型 ──▶ Stage 3 参数计算 ──▶ Stage 4 Simulink建模 ──▶ Stage 5 结果验证
   规格表提取          决策树              公式库+回算校核        开关级/物理网络模板       PF/THD/η/纹波+图表
       ▲                                                              │
       └──────────────────── 不达标回到 Stage 3/2 迭代 ◀──────────────┘
```

- 每阶段的输入/输出物、公式、建模模板、指标算法均已写入 `~\.workbuddy\skills\power-electronics-agent\SKILL.md`
- Agent 每次接到电源类赛题, 按 skill 走五阶段, 中间产物落盘到工作区可追溯

## 四、验收交付物: 500W Boost PFC（见 pfc/ 目录）

- 拓扑: 单相二极管桥 + Boost PFC, CCM 平均电流双环控制
- 规格: 220Vrms/50Hz 输入 → 400V/500W 输出, fsw=50kHz
- 主电路: L=10mH, C=470µF, R=320Ω, 含 Ron=50mΩ/铜阻0.2Ω/二极管0.8V 损耗
- 控制: 电压环PI(5Hz) → 10Hz一阶低通(滤100Hz二次谐波) → I_ref=G·|vac|; 电流环PI(1kHz, 标准Boost公式 Kp_i=2π·fci·L/Vout, ki_i=Kp_i·R/L) 直接输出占空比 D
- 模型: `PFC_Boost_Avg.slx`（**平均模型** — 无PWM比较器零穿越抖动, 仿真8s 跑完, 适合电赛快速迭代）
- 历史脚本: `PFC_Boost.slx`（开关级, 历次迭代发现电流环在DCM边界+Vo纹波放大导致PF不达标, 已废弃）
- 指标: 见 `pfc/results/results_metrics.txt` 与 `pfc/results/*.png`

**实测性能（2026-08-15 平均模型, 仿真窗口 0.7-0.98s）**：

| 指标 | 目标 | 实测 | 状态 |
|---|---|---|---|
| 输入电压 RMS | 220V | 220V | ✓ |
| 输出直流电压 | 400V | 395.5V (-1.1%) | ✓ |
| 输出功率 | 500W | 489W | ✓ |
| 输入功率 | ≈500W | 502W | ✓ |
| **功率因数 PF** | **≥0.98** | **0.9814** | ✓ |
| 电流谐波 THD | (PF自洽) | 19.6% | 与PF=0.98一致 |
| **效率 η** | **(参考)** | **97.3%** | ✓ 含 Ron+RL+Vd 损耗 |

### 之二、物理级开关模型（ee_lib / Simscape 物理网络 — 能指导实物设计）

功率级全部使用 ee_lib 真实器件: AC源 + 二极管桥(×4, Vf=0.8V/Ron=50mΩ) + 升压电感 L=5mH(含铜阻0.2Ω) + MOSFET (Ideal, Switching, Rds=50mΩ) + 续流二极管 + 输出电容 470µF(ESR=50mΩ) + 负载 320Ω; 20kHz PWM 载波比较驱动门极, 双闭环平均电流控制, ode23tb 变步长(MaxStep=2µs) 捕捉真实开关过程。

**控制架构关键点 — 前馈占空比**: D_total = D_ff + PI调整量, 其中 D_ff = 1 − Vm/Vo ≈ 0.22 常数, 电流环 PI 只做 ±0.3 小范围修正。若省去 D_ff, 电流环输出在小值附近产生的 ~1µs 窄 PWM 脉冲对变步长求解器不可见, MOSFET 实际不切换（门极诊断仅 ~99 次切换 vs 应有 ~10000 次）, 控制环等于开环——这是本次物理级建模踩过的最大坑。

**实测性能（2026-08-15 物理级, 测量窗口 0.40-0.49s）**:

| 指标 | 平均模型 | 物理级开关模型 | 说明 |
|---|---|---|---|
| 功率因数 PF | 0.9814 | **0.948** | 物理级含 CCM 过零畸变（理论极限 0.95-0.97）|
| 电流谐波 THD | 19.6% | 33.2%（含开关纹波） | 物理级频谱含 20kHz 边带 |
| 效率 η | 97.3% | **99.3%** | 器件为理想开关+导通电阻模型 |
| 输出电压 | 395.5V | 396.0V | 双模型互差 <0.5V, 互相印证 |
| MOSFET 开关 | 无（平均化） | 真实 20kHz × 5000次/0.25s | 电感电流 CCM 三角波可见 |

**结论**: 两套模型互为印证——平均模型验证控制律设计（快、PF 达标）, 物理级验证功率级与门极链路（真实开关、过零畸变、器件应力）。物理级版本的电感电流三角波、开关节点电压、门极时序可直接指导实物参数（死区、磁芯选择、散热估算）。L 取值对比: 5mH(PF=0.948) vs 8mH(PF=0.945), 加大 L 对过零畸变收益递减（畸变主因是 CCM 电感电流连续性而非纹波幅度）, 最终选定 **L=5mH**。

## 五、复用入口

```bash
# 重跑 PFC 平均模型全流程（建模+仿真+指标+图, ~1分钟）
"/d/MATLAB R2025b/bin/matlab.exe" -batch "cd('C:/Users/xinxin/WorkBuddy/2026-08-15-22-18-16/pfc'); build_pfc_avg"

# 重跑 PFC 物理级开关模型全流程（真实 20kHz 开关, ~2-4分钟）
"/d/MATLAB R2025b/bin/matlab.exe" -batch "cd('C:/Users/xinxin/WorkBuddy/2026-08-15-22-18-16/pfc'); build_pfc_phys"
```

物理级输出物: `PFC_Boost_Phys.slx` + `results/waveforms_phys.png / cycle_zoom_phys.png / harmonics_phys.png / startup_phys.png / results_metrics_phys.txt / model_phys.png`

## 六、踩坑教训（避免下次重复）

1. **MATLAB 路径**: `matlab.exe` 不在 PATH，需用全路径 `D:\MATLAB R2025b\bin\matlab.exe`。
2. **Transfer Fcn Denominator 必须用方括号**: `Denominator=[1 31.4]`，裸空格会被求值表达式。
3. **PID Controller 参数名**: `UpperSaturationLimit`/`LowerSaturationLimit`（不是 `UpperLimit`），`InitialConditionForIntegrator`（不是 `InitialCondition`）。
4. **Ramp 块参数名**: `slope`/`start`/`InitialOutput`（不是 `Slope`/`Start`/`X0`）。
5. **Sum 块缺输入**: 未连线的输入端口隐式接地为 0，会让表达式从 "1-D" 变成 "-D" 直接发散——永远记得给所有 Sum 输入端口显式连信号或 Constant。
6. **电流环 PI 标准公式**（Boost PFC）: `Kp_i = 2π·fci·L/Vout`，`ki_i = Kp_i·R/L`。盲目拍脑袋取 0.05/30 会差三个数量级。
7. **平均模型不要给 iL 积分器设 LowerSaturationLimit=0**：那会让平均电流被强制拉到 0、出现非物理 DCM，破坏 CCM PFC。
8. **DFT 计算 THD**：窗长必须为基波周期整数倍，否则基波分量会偏低、THD 失真；用 sin/cos 投影或加窗 FFT 更稳。
9. **测量窗口要避开启动段**：用 Ramp 软启动后，指标窗口设 0.7-0.98s（StopTime=1.0s）才能拿稳态值。

### 物理级建模（ee_lib/Simscape）专有坑

10. **传感器端口域与直觉相反**：ee_lib 的 Voltage/Current Sensor，**LConn1=电口+, RConn2=电口−, RConn1=PS 信号输出**；MOSFET (Ideal, Switching) 的 **LConn1=门极 PS 输入**, RConn1/RConn2=电口。连错域报 `AddLinePMConnectionRulesViolation`。探测方法：用已知电气端口（电阻）逐口试探。
11. **物理连线语法**：`add_line(mdl,'BlkA/LConn1','BlkB/RConn1')`（端口名字符串而非编号）；物理口支持多分支（一进多出节点直接重复 add_line）。
12. **Simscape 网络代数环**：电流环→PWM→门极→物理网络→传感器→反馈构成直通环。断环首选 Simulink-PS Converter 内置滤波：`'FilteringAndDerivatives','filter'`（枚举 provide/filter/zero）+ `'InputFilterTimeConstant','1e-7'`。
13. **PWM 窄脉冲丢失（最隐蔽）**：控制环输出占空比接近下限时，PWM 比较器产生 ~1µs 宽脉冲，在 MaxStep=2µs 下对变步长求解器不可见——门极"看似不切换"，控制环等于开环。**根治：加前馈占空比 D_ff = 1 − Vm/Vo**，电流环只做小范围修正。诊断手法：**固定 50% 占空比旁路测试**（控制链短路成常数），先确认功率级+门极链路完好，再回头查控制链。
14. **CCM Boost PFC 过零畸变是物理极限**：PF 实测 0.945-0.948，低于平均模型的 0.981 属正常（电感电流连续性使 iac 在 vac 过零区无法瞬时归零），加大 L 收益递减。
15. **Pin 计算要用源端电流**：pin = vac × iac（源端传感器），不要错用电感电流 iL，否则 η 算出 886% 之类的非物理值。

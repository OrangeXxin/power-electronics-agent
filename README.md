# Power Electronics Agent — AI 自动搭建 MATLAB/Simulink 电力电子仿真全通路

> AI Agent + MATLAB R2025b + Simulink/Simscape：从一份"从入门到放弃"的失败帖，到一条完整跑通的物理级 Boost PFC 自动建模仿真通路。
>
> **An AI-agent workflow that auto-builds and validates physical-level Boost PFC simulations in MATLAB/Simulink R2025b (ee_lib / Simscape) — average-current-mode control, real 20 kHz switching, PF = 0.948, η = 99.3%. Includes a full pitfall map from a real failed attempt.**

---

## 这是什么

一条经过验收的 **AI Agent 电力电子仿真开发通路**，覆盖：

```
需求分析 → 拓扑选型 → 参数计算 → Simulink 自动建模 → 仿真验证 → 指标验收
```

验收案例：**单相 500W Boost PFC**（220 Vrms/50 Hz 输入 → 400 V/500 W 输出，fsw = 20 kHz）

| 指标 | 平均模型（控制律设计） | 物理级开关模型（指导实物） |
|---|---|---|
| 功率因数 PF | **0.9814** | **0.9484** |
| 效率 η | 97.3% | 99.34% |
| 输出电压 | 395.5 V | 395.99 V |
| THD | 19.6% | 33.2%（含开关纹波） |
| MOSFET | 无（平均化） | **真实 20 kHz 开关，16916 次切换/0.5 s** |
| 仿真耗时 | ~1 min | ~2-4 min |

两套模型互为印证：平均模型验证控制律（快、PF 达标），物理级验证功率级与门极链路（真实开关、过零畸变、器件应力），电感电流 CCM 三角波、开关节点、门极时序可直接指导实物设计。

物理级稳态波形（vac / iac / iL / vo）：

![物理级稳态波形](results/waveforms_phys.png)

## 背景：一份失败帖，和它断掉的地方

本项目的前身是一篇[《AI 跑 Matlab 仿真失败经验贴》](docs/AI跑Matlab仿真失败经验贴.md)：作者用 AI 搭自动仿真流水线，平均模型跑通了（PF 0.976），但物理级模型卡死在最后一关——**44 根线全连通，仿真报"静态方程和代数方程消不掉"（代数环），且模块叠成一团**。从入门到放弃。

本仓库把那条断路走完了。失败帖里的每一个坑，这里都有对应的探测脚本、解法或防御：

| 失败帖踩的坑 | 本仓库的解法 | 位置 |
|---|---|---|
| `elec_lib` 改名 `ee_lib`，找库名废大力气 | 块可用性探测脚本，一次性枚举全部路径/端口数/参数名 | `matlab/probe_ee.m` |
| 物理端口方向死结（RConn/LConn 挑方向） | 用已知电气口（电阻）逐口试探，确认端口域布局：传感器 RConn1=PS 信号输出、电口是 LConn1/RConn2；MOSFET LConn1=门极 | `matlab/probe3.m` |
| 44 根线连完，代数环不收敛 | ① Simulink-PS Converter 内置滤波 `'FilteringAndDerivatives','filter'` 断直通环；② **前馈占空比 D_ff = 1 − Vm/Vo** 根治 PWM 窄脉冲丢失（不收敛的真正元凶之一） | `matlab/build_pfc_phys.m` |
| 门极"看似不切换"、控制环等于开环 | 固定 50% 占空比旁路诊断法：把控制链短路成常数，先验证功率级+门极链路，再回头查控制链 | `matlab/build_pfc_phys_test.m` |
| 参数名各说各的（`LowerLimit` vs `LowerSaturationLimit` 等） | SKILL.md 固化 14 条"一次纠正 = 永久防御"坑清单 + 枚举值探测脚本 | `skill/SKILL.md`, `matlab/probe_enum.m` |
| 模块叠成一团，人没法看 | 栅格化坐标布局：桥 H 形居左、升压级沿母线水平展开、控制单行走通、PS 转换器/记录分列 | `matlab/build_pfc_phys.m` 布局段 |
| shell 访问不了 GitHub | 命令行批处理通道（`matlab -batch`）不依赖网络；MCP 通道可选 | `docs/电力电子AI_Agent通路部署与设计.md` |
| 分工错位（AI 拖 40 轮不如人拖 5 分钟） | 探测脚本把"试错检索"固化为可复用资产，AI 一次调用拿到全部端口/参数/枚举事实 | `matlab/probe_*.m` |

> 失败帖原话："AI 适合做反复试错、机械检索的活……可它没有物理直觉。" 本仓库的答案：把物理直觉（求解器配置、前馈架构、断环手法、布局美学）**写进 skill**，让下一个 AI 直接继承。

## 仓库结构

```
├── README.md
├── skill/
│   └── SKILL.md              # power-electronics-agent：五阶段工作流 + 公式库 + 14 条坑清单
├── matlab/                    # 全部脚本（MATLAB R2025b 验证通过）
│   ├── build_pfc_avg.m       #   平均模型（控制律验证，~1min）
│   ├── build_pfc_phys.m      #   物理级开关模型（ee_lib 真实器件 + PWM + 双闭环，主交付）
│   ├── build_pfc_phys_test.m #   固定占空比旁路诊断（控制链排障利器）
│   ├── probe_ee.m            #   ee_lib 块可用性探测（路径/端口数/参数名）
│   ├── probe_ports.m, probe3.m # 物理端口域布局探测
│   ├── probe_enum.m          #   块枚举参数值探测
│   ├── probe_pwm2.m          #   PWM 行为探测
│   ├── build_pfc_model.m     #   开关级框图模型（历史迭代，已废弃，保留供考古）
│   └── setup_check.m         #   环境/许可证自检
├── docs/
│   ├── AI跑Matlab仿真失败经验贴.md          # 原始失败帖（本项目起点）
│   └── 电力电子AI_Agent通路部署与设计.md    # 完整部署与设计报告
└── results/                   # 验收指标与图表（两套模型）
```

## 快速开始

### 环境要求

- MATLAB **R2025b**（含 Simulink + **Simscape 基础库**；物理级走 `ee_lib`，**不需要** Simscape Electrical 专用许可证）
- 任意能调用命令行的 AI Agent（Claude Code / Codex / WorkBuddy / 自建 Agent 均可）

### 跑通验收案例

```bash
# 1. 平均模型（控制律验证，约 1 分钟）
matlab -batch "cd('<本仓库>/matlab'); build_pfc_avg"

# 2. 物理级开关模型（真实 20kHz 开关，约 2-4 分钟）
matlab -batch "cd('<本仓库>/matlab'); build_pfc_phys"
```

脚本全自动：建模 → 仿真 → 指标计算（PF/THD/η/Vo/纹波）→ 出图（稳态波形/工频周期放大/谐波频谱/启动过程/模型结构图）。

### 接入你的 AI Agent

把 `skill/SKILL.md` 安装为 Agent 的技能文件（如 Claude Code / WorkBuddy 的 skills 目录），Agent 即获得：

- 五阶段工作流（需求→拓扑→参数→建模→验证）
- Boost PFC 电流环/电压环 PI 标准公式（`Kp_i = 2π·fci·L/Vout` 等，拒绝拍脑袋）
- 14 条实测坑清单（块参数名、端口域、代数环、PWM 窄脉冲、THD 计算……）
- 三套建模模板的选择依据（平均 vs 开关级框图 vs 物理级）

## 五阶段工作流（skill 核心逻辑）

```
Stage 1 需求分析 ──▶ Stage 2 拓扑选型 ──▶ Stage 3 参数计算 ──▶ Stage 4 Simulink建模 ──▶ Stage 5 结果验证
   规格表提取          决策树              公式库+回算校核        平均/开关级/物理级模板     PF/THD/η/纹波+图表
       ▲                                                              │
       └──────────────────── 不达标回到 Stage 3/2 迭代 ◀──────────────┘
```

**给 AI 开发者的三条核心经验**（完整版见 SKILL.md）：

1. **先探测再建模**：新环境先跑 `probe_*.m` 拿到块路径、端口域、参数名、枚举值的"事实表"，别让 AI 靠猜。
2. **物理级必须加前馈占空比**：`D_total = D_ff + PI修正`，`D_ff = 1 − Vm/Vo`。没有它，电流环输出小占空比 → 1 µs 窄 PWM 脉冲对变步长求解器不可见 → 门极不切换 → 仿真"连上了但不收敛/不工作"。
3. **控制环排障用旁路法**：控制链可疑时，先短路成固定 50% 占空比跑一遍——功率级正常就说明问题在控制链，反之在功率级。二分定位，别瞎调参。

## 适用场景

- 全国大学生电子设计竞赛（电源类：AC-DC、DC-DC、PFC、逆变）
- 用 AI Agent 辅助电力电子仿真教学/科研的工程师
- 研究人机分工的 AI 实践者（失败帖 + 解法对照本身就是一份"AI 能力边界"样本）

## 来源与致谢

- 失败经验来自真实项目复盘：[AI跑Matlab仿真失败经验贴](docs/AI跑Matlab仿真失败经验贴.md)
- 参考过社区仓库 `simulink/skills`（"Guy on Simulink" 博主维护，非 MathWorks 官方）与 `matlab/simulink-agentic-toolkit`（官方）；两者区别见设计报告
- 物理级拓扑：经典单相 Boost PFC（CCM 平均电流控制），教科书级拓扑，本仓库的价值在 **Agent 化的通路与坑地图**

## License

[MIT](LICENSE)

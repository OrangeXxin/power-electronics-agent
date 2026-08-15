# 贡献指南 / Contributing

感谢你愿意为 power-electronics-agent 出力！这个项目能存在，是因为有人把"从入门到放弃"的路走完了，并把坑记下来。把你的经验也加进来，下一个人就少走一段冤枉路。

## 我能贡献什么

特别欢迎的方向（按价值排序）：

1. **新坑 + 解法**：你在用 AI 跑电力电子仿真时踩过的坑，附复现脚本或防御代码
2. **新拓扑**：Buck / SEPIC / LLC 谐振 / 单相全桥逆变 / 三相 PFC 等，按五阶段工作流产出验收案例
3. **新版本事实表**：在 R2024a / R2024b / R2026a 等版本上跑 `probe_*.m`，把结果作为新版本的事实表提交
4. **真实赛题端到端案例**：电赛赛题文字 → 规格表 → 验收指标，可作为教学案例
5. **文档翻译**：英文版 SKILL.md、英文版 README 补充
6. **布局美化**：模型结构图的栅格化坐标改进

## 怎么提 PR

```bash
git clone https://github.com/OrangeXxin/power-electronics-agent.git
cd power-electronics-agent
git checkout -b feat/your-topic
# 改完跑一遍验证
matlab -batch "cd('matlab'); build_pfc_phys"
git commit -m "feat: add Buck topology template"
git push -u origin feat/your-topic
# 然后在 GitHub 上发起 PR
```

### 提交规范

- `feat:` 新功能（新拓扑、新模板）
- `fix:` 修 bug（坑、参数名错）
- `docs:` 文档
- `probe:` 探测脚本/事实表更新
- `chore:` 杂项

### 验收标准

- 新脚本必须在 **MATLAB R2025b** 上跑通，输出指标和图表
- 新坑必须有解法（不能只列问题不给答案）
- 新拓扑必须按五阶段工作流产出（规格表 → 参数 → 模型 → 验收指标）

## 怎么提 Issue

- 报 bug：贴 MATLAB 版本、报错原文、复现命令
- 提新拓扑/功能：说清楚应用场景（电赛？教学？科研？）
- 讨论：直接开 Issue 即可

## 行为准则

友善、专业、对事不对人。电力电子是硬骨头，大家一起啃。

## 致谢

所有贡献者都会在仓库 README 致谢区列出（PR 合并后自动添加）。

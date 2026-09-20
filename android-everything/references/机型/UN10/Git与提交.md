# UN10 Git 与提交

建档状态：部分确认  
适用工作区输入：V:\new_ssd1\workspace\android\un10

## 仓库结构

| 项目 | 当前记录 | 状态 | 如何验证 |
|---|---|---|---|
| 源码管理方式 | `repo` 多项目工作区；根目录不是单一 Git 仓库 | 已确认 | 2026-08-03：根目录含 `.repo/` 而无 `.git/`。根目录结构变化后重验。 |
| manifest 或远端 | `.repo/manifests/UN10.xml`；默认 remote 为 `QCOM`，默认 revision 为 `UN10-dev` | 已确认 | 2026-08-03：静态读取当前 manifest。部分项目显式覆盖 revision 或 remote，逐项目解析时应使用 `repo manifest -r`。 |
| 根目录与子项目关系 | `qssi14/`、`target/` 是多个 repo 项目的路径前缀，不是各自单一 Git 仓库 | 已确认 | 2026-08-03：`.repo/project.list` 含大量 `qssi14/...`、`target/...` 项目；两目录自身未见 `.git`。manifest 或 checkout 结构变化后重验。 |
| 当前分支策略 | 默认 `UN10-dev`，允许项目级别 revision 覆盖 | 部分确认 | 2026-08-03：manifest 的 `<default revision="UN10-dev">`，且部分 `project` 有显式 revision。未采集各项目当前 HEAD、上游和脏文件状态。 |

## 安全检查

| 动作 | 建档后仍需实时检查 |
|---|---|
| 查看状态 | 限定路径，避免大型工作区根目录全量扫描 |
| 创建分支 | 当前分支、上游、脏文件和目标项目 |
| 提交 | 精确文件列表、diff、提交信息和已有本地修改 |
| 推送 | 远端、目标分支、非快进风险和保护要求 |

## 规则

- 不把历史分支、远端地址、脏文件数量或提交号写成长期事实，除非注明证据和最后验证日期。
- 不执行 `repo sync`、`git reset --hard`、`git clean` 或强推，除非用户明确授权且已有保护方案。

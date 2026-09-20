# Mino1 Git 与提交

建档状态：部分确认  
适用工作区输入：V:\new_ssd1\workspace\android\mino1

## 仓库结构

| 项目 | 当前记录 | 状态 | 如何验证 |
|---|---|---|---|
| Recovery Git 根目录 | `/home/new_ssd1/caoyixi/workspace/android/mino1/A12/bootable/recovery` | 已确认 | 2026-08-04 `git rev-parse --show-toplevel` |
| 当前 Recovery 分支 | `cyx-mino1-auto-security-2` | 已确认 | 2026-08-04 `git branch --show-current` |
| 当前 HEAD | `c66b59b338ac5a5ac1f77fa7ec8c19a7684be0be` | 已确认 | 2026-08-04 `git log -1`；提交者日期为 2026-07-28，作者日期为 2026-07-22 |
| 当前工作树 | 无 `git status --short` 输出 | 已确认 | 仅适用于上述 Recovery 子项目在 2026-08-04 的快照；提交前必须重新检查 |
| `c66b59b` 改动范围 | `recovery.cpp`、`xgdrecovery/xgd_recovery.cpp` | 已确认 | 2026-08-04 `git show --stat --name-only` |
| sideload 工作树改动 | `xgdrecovery/xgd_recovery.h`、`xgdrecovery/xgd_recovery.cpp`，共 9 行新增，尚未提交 | 已确认 | 2026-08-04 构建后 `git status --short`、`git diff --stat`；提交前仍须重新检查 |
| Recovery 文件换行 | `xgdrecovery` 已检查文件使用 CRLF | 已确认 | 2026-08-04 补丁与构建前检查；修改此目录文件后需保持 CRLF |
| manifest 或其他子项目远端 |  | 待验证 | 本轮未执行 `repo manifest`、`repo list` 或远端探测 |

## 安全检查

| 动作 | 建档后仍需实时检查 |
|---|---|
| 查看状态 | 限定路径，避免大型工作区根目录全量扫描 |
| 创建分支 | 当前分支、上游、脏文件和目标项目 |
| 提交 | 精确文件列表、diff、提交信息和已有本地修改 |
| 推送 | 远端、目标分支、非快进风险和保护要求 |

## 规则

- 不把历史分支、远端地址、脏文件数量或提交号写成长期事实，除非注明证据和最后验证日期。
- 对 CRLF 的 `xgdrecovery` 文件，使用 `git -c core.whitespace=cr-at-eol diff --check` 检查补丁；普通 `git diff --check` 会把 CRLF 误报为尾随空白。该规则只适用于确认仍为 CRLF 的文件，修改前仍应执行 `git ls-files --eol -- <path>`。
- 不执行 `repo sync`、`git reset --hard`、`git clean` 或强推，除非用户明确授权且已有保护方案。

## memleakd 多仓快照

以下是 2026-09-10 经 Linux 原生工作区和 `git ls-remote` 核对的快照；之后提交、分支或远端变化后必须重新读取。

| 仓库路径 | 源分支提交 | N82L 移植分支提交 |
|---|---|---|
| `A13/vendor/nexgo` | `92501c53c67a1841c7d7330246c38416f53819cf` | `c4fc88f46aa7d8ca3af8770af0fa4b603d7907cf` |
| `A13/agenew` | `a491a7ec08cd08815b5668b5e16005f8cd45c3a0` | `0487a772492963e98a15d32cdda2209829c8ae63` |
| `A13/system/sepolicy` | `00006cd5f04c7f60661235f442b74e3bcc1a8d8f` | `ae3ac74ae6267b9f85884688355e533f805fc5c9` |
| `A13/vendor/nexgo/packages/apps/PosSystemServiceV2` | `a283599f3a9148acc27f874015169007a73d4a2b` | `67ba8cb9f8aa53ac09d6bf83a9843d8f70be322e` |

对应的 Mino1 源分支为 `cyx-mino1-memleakd`，N82L 移植分支为 `cyx-n82l-memleakd`。`A13/vendor/nexgo` 的未跟踪 `memleaktest` 和 `MemLeakTest` 文件不在这四个提交内。

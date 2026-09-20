# Git 安全

## 先读现场，再提出动作

| 阶段 | 可自动执行的只读动作 | 必须确认的动作 |
|---|---|---|
| 仓库识别 | `git rev-parse --show-toplevel`、`git status --short` | 切换分支、repo sync |
| 差异分析 | `git diff -- <path>`、`git diff --cached` | 修改暂存区 |
| 提交准备 | 列出精确文件、建议 message、检查 hook | `git add <path>`、commit |
| 远端操作 | 检查 remote、upstream、分叉关系 | push、强推 |

## 禁止默认执行

```text
git add .
git reset --hard
git clean
git checkout -- <path>
git push --force
repo sync -d
repo sync --force-sync
```

## 多仓与 repo

- 目录看起来像一个 Android 项目，不代表它是一个 Git 仓库。
- repo 管理的工作区必须用 `repo list`、`repo status` 和各子项目的 Git 根目录确认边界。
- detached HEAD、prepare-commit-msg 等 hook、未跟踪构建产物和 IDE 噪音都要在提交前单独检查。
- 不将本地旧分支、远端跟踪分支和真正要 push 的远端目的地混为一谈。

## 跨基线移植与脏工作区

- 当前工作树存在未提交 tracked 修改或 untracked 测试文件时，不要直接使用 `git switch`/`git checkout` 把目标分支切进同一工作区；未提交修改可能阻止切换，也可能被带到目标分支并在 cherry-pick 时与同一文件冲突。
- 优先使用 `git worktree add -b <new-branch> <temporary-path> <target-base>` 创建独立工作目录。worktree 共享原仓库对象库和 refs，但拥有独立工作区、index 和 HEAD，不会把原工作区的脏文件带入目标分支。
- 目标分支先按精确 remote 和 branch 获取；需要避免 repo 的 remote-tracking 更新问题时，可使用显式临时 ref 和 `--refmap=`。cherry-pick 后先核对 `git status`、`git diff`、父提交和提交列表，再推送。
- 临时 worktree 用完必须移除，删除前确认真实路径位于当前工作区或明确的临时目录；本地分支和远端分支不应随 worktree 目录删除。
- 用户明确授权强推时，优先使用 `--force-with-lease=<ref>:<expected-tip>`，先 live `git ls-remote` 核对目标 tip；没有用户明确授权时不得使用 `git push --force`。

## 历史重写与合并概念

- `commit id` 标识提交对象；它由完整快照、父提交、作者、时间和 message 计算。父提交变化后，即使改动相同，hash 也会变化。
- Git 文件内容保存在 `blob`，目录结构保存在 `tree`，提交指向一个 `tree` 和父提交。比较合并结果时不要把 `commit id` 等同于文件内容。
- merge 的核心是 `base / ours / theirs` 三方快照合并：两边对同一处改成相同结果时只保留一份；不同位置改动自动合并；同一区域改成不同结果才冲突。
- cherry-pick 和 rebase 都会重放 diff 并生成新提交。cherry-pick 通常是安全追加；rebase 会重写被搬范围的历史，已发布分支通常需要强推并影响依赖旧链的人。
- `patch-id` 是补丁指纹，受 diff 及其上下文影响。上下文完全一致时 patch-id 可相同，Git 能识别等价补丁；上下文变化后 patch-id 可能不同，rebase 会重新三方合并，可能冲突。
- 只搬某条旧链尾部的提交时优先明确范围：`git rebase --onto <new-base> <old-exclude> <branch>` 表示只重放 `<old-exclude>` 之后的提交，避免旧底座重复参与。
- 多个 feature 分支集成时优先创建独立 integration 分支：从最新 dev 基线 cherry-pick 已有功能，再接当前功能。原有分支不动；普通 push 公共分支必须 fast-forward，改写历史只能用明确授权的 `--force-with-lease`。

# EF930 Git 与提交

## repo 边界

| 场景 | 建议检查 | 不应做的假设 |
|---|---|---|
| 判断项目列表 | `repo list` | 根目录是单 Git 仓 |
| 判断各项目状态 | `repo status` | 子项目都在普通分支上 |
| 解析实际 revision | `repo manifest -r` | manifest 文本就是实际 SHA |
| 定位 Git 根 | 各路径执行 `git rev-parse --show-toplevel` | 目录名等于仓库边界 |

## 提交前清单

1. 读取当前源码工作区的 Git/repo 状态。
2. 确认精确仓库和精确文件。
3. 检查 detached HEAD、hook、未跟踪噪音和分支跟踪关系。
4. 输出完整 commit message 和待暂存文件。
5. 等待用户确认后才执行暂存、commit 或 push。

## 禁止默认执行

```text
repo sync -d
repo sync --force-sync
git reset --hard
git clean -fdx
git add .
git push --force
```

## 重新验证条件

repo manifest、当前分支、远端跟踪关系或 hook 改变后，重新检查提交流程；过去成功的分支命令不等于当前源码工作区仍适用。

## 2026-08-03 VAB 修复记录与拆分边界

状态：已确认历史证据与当前工作树状态，适用源码工作区 `/home/new_ssd1/caoyixi/workspace/android/ef930_2`。

| 修复组 | 文件集合 | 当前状态 |
|---|---|---|
| Recovery stale `Initiated` 清理 | `target/system/core/fs_mgr/libfiemap/image_manager.cpp`、`image_manager.h`、`libsnapshot/snapshot.cpp`、`snapshot.h`、`snapshot_test.cpp` | 2026-08-03 已恢复为当前工作树的 5 个未暂存改动；尚未编译、暂存、提交或对本工作树重新做设备验证。 |
| Update.apk ZIP payload 进度 | `qssi14/system/update_engine/download_action.cc`、`download_action_android_unittest.cc` | 当前工作树的另 2 个未暂存改动；它属于 QSSI system 侧进度修复，不解决 Recovery stale snapshot/COW。 |

当前分支为 `cyx-ef930-fix-update-error`，直接指向 `QCOM6225/EF930-dev` 的 `40e1f656b02`；该远端基线到 `HEAD` 的本地提交数为 0。原 `cyx-ef930-update-error` 已删除，先前的 `/private/config` 保护提交没有被 rebase 或 replay 到本分支历史。当前精确源码差异为上述 7 个文件，均未暂存、未提交，也没有 MR。

后续提交时，可在本分支按精确路径把 Recovery 五文件与 QSSI 两文件分别暂存为两个独立提交；不要把两类改动放进同一提交。提交、暂存、切换分支、cherry-pick 或 rebase 后，使用精确路径重新执行 `git diff`、`git diff --cached` 和对应测试检查。

# N6P Git 与提交

建档状态：部分确认  
适用工作区输入：V:\new_ssd1\workspace\android\n6p

## 仓库结构

| 项目 | 当前记录 | 状态 | 如何验证 |
|---|---|---|---|
| 源码管理方式 |  | 待验证 | `.repo/`、`.git/`、manifest 或仓库工具 |
| manifest 或远端 |  | 待验证 | `repo manifest -r`、仓库配置或远端列表 |
| 根目录与子项目关系 |  | 待验证 | `repo list`、`.git` 指向或项目清单 |
| 当前分支策略 |  | 待验证 | `git branch -vv`、远端跟踪关系和项目约定 |

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
- 切换分支前先检查 `git status --short --branch`。若有未提交修改，先创建并核验临时提交；不要把 `stash` 当作默认流程。

## 已确认的嵌套仓库与 rebase 经验

最后验证：2026-08-08，适用当前 N6P 工作区。

`A13/vendor/nexgo/build` 与其下 `xgd_tools/xgdprop_md` 是独立 Git 仓库；同名 `cyx-n6p-protect-config` 分支只在各自仓库内有意义。父仓库的 `git push` 不会推送 `xgdprop_md` 的属性登记提交，必须进入子仓库单独检查远端、rebase 和推送。

对属性文档子仓库的安全顺序是：

```bash
cd A13/vendor/nexgo/build/xgd_tools/xgdprop_md
git fetch modules --prune
git status --short --branch
# 若有修改，先在本地分支创建临时提交
git rebase modules/xgd
git log --oneline modules/xgd..HEAD
git push -u modules cyx-n6p-protect-config
```

不要在 detached `HEAD` 且工作区脏时直接 rebase。先将修改落在本地特性分支，再把该分支重放到已 fetch 的远端基线；rebase 后重新检查属性条目、工作区和 `git diff --check`。

该工作区的提交 hook 依赖 `ANDROID_BUILD_TOP`，提交前可能需要在 A13 根目录执行：

```bash
source build/envsetup.sh
lunch sys_n6pro_mssi_64_cn-userdebug
```

hook 会后台启动 AI 检查与邮件通知；Git 提交完成后仍可能遗留无终端的邮件客户端进程。确认 `git log -1` 和 `git status` 后再继续 rebase/push，并检查最终提交信息未被模板改写为不符合实际内容的标题。

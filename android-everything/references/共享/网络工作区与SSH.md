# 网络工作区与 SSH

## 基本规则

Windows 映射盘或 UNC 路径只是 Linux 构建服务器源码的视图。涉及 Git、源码搜索、权限、符号链接、Android 构建和大范围目录操作时，优先通过 SSH 在 Linux 原生路径执行。

对服务器的实际操作必须采用“Windows `pwsh` 发起 `ssh`，Linux 原生路径执行”的固定模式。映射盘/UNC 只用于查看或打开用户需要的文件，不用于服务器源码、Git、构建、日志、权限和生成物操作。

| 场景 | 首选方式 | 原因 |
|---|---|---|
| 查看用户提供的本地附件 | Windows 本地 | 文件就在本机 |
| Android 源码搜索、Git、repo | Linux SSH | 避免 SMB、权限、符号链接和性能问题 |
| Android 编译 | Linux SSH + 项目 Docker/构建环境 | 构建依赖在原生环境 |
| 用户需要点击打开源码文件 | Windows 映射路径 | 便于桌面应用打开 |

## 远程命令规则

- Windows 本地命令优先使用 `pwsh`（PowerShell 7）；仅在 `pwsh` 不可用或用户明确要求时使用 Windows PowerShell 的 `powershell.exe`。
- 所有服务器操作均由 `pwsh` 调用 `ssh`；不能因为当前工作目录是 `V:` 就直接在映射盘执行 Git、`rg`、构建、删除或权限判断。
- 重复访问同一服务器时可探测 OpenSSH 连接复用：`ControlMaster=auto`、`ControlPersist=10m`、独立且不存在冲突的 `ControlPath`。Windows OpenSSH 复用必须先在当前客户端验证；出现 `getsockname failed: Not a socket`、ControlPath 冲突或其他复用错误时，立即使用普通单次 SSH，不把复用失败当作远端故障，也不循环尝试多个连接。
- 先确认 Linux 原生路径，再执行实际仓库操作。
- 必须分别确认“源码/构建服务器”和“Git/GitLab 服务器”。在 Mino1 当前工作区中，`10.199.40.231` 是源码服务器，GitLab remote 是 `10.18.6.211`；不能因为 `ssh 10.199.40.231` 成功，就把 `git@10.199.40.231:...` 写入项目 remote。
- repo 管理的子项目修改 remote 前，先读取 `<workspace>/.repo/projects/<project-path>.git/config`，并与 manifest 中的 project name/path、remote fetch 对照。工作树 `.git/config` 被手工改写后，优先按 repo 元数据恢复，再用 `git remote -v` 和只读 `git ls-remote` 验证。
- 在源码服务器上执行 `git push` 时，SSH 主机指纹只证明当前连接的主机身份，不证明它就是目标 GitLab；必须先确认 remote 主机和项目路径，再核对指纹，不能把其他 SSH 客户端的 `known_hosts` 记录当作当前客户端的记录。
- 使用路径限定的 `rg`、`git diff -- <path>`、`git log -- <path>`；不要从 Android 大树根目录开始广搜。
- PowerShell 到 SSH 的复杂引号、`$`、反引号和正则容易失真。默认将同一轮诊断合并为一次 `ssh ... bash -s`，通过 here-string 传给远端；只有生命周期、权限或风险边界明显不同的长任务才拆分 SSH 调用。
- 将 PowerShell here-string 传给 `ssh ... bash -s` 前要转为 LF；CRLF 可能变成远端参数尾部的 `\r`，表现为 `git status --short?`、`git diff --check?` 或外层 `exit 0` 返回失败。
- 远端变量必须在远端脚本中定义；PowerShell 侧使用单引号 here-string，避免本地展开 `$(...)`、`$变量` 和反引号。
- 同一远程工作区的 Git/搜索/构建命令不得无控制地并行执行；先合并为一次只读批量诊断。长任务使用远端 `nohup`/`tmux`，轮询只读取新增日志尾部。
- `multi_tool_use.parallel` 不用于并行操作同一远程源码工作区；只有不同主机、不同工作区且不共享 Git index、构建输出或锁文件时才并行。
- 不在 Windows 映射盘上做大范围 `git status`、递归搜索、全量构建或权限判断。
- 如果 SSH 不可用、原生路径无法确认或认证失败，必须报告并停止，不能退回 SMB 映射盘完成同一服务器操作。

## 远程构建加速

- 构建前在远端一次性检查 `command -v ccache`、`ccache -s` 和已有构建进程；已有缓存直接复用，不执行清空或重建。
- 优先使用模块级增量目标；只有用户要求出包或模块验证不足时才扩大到整机目标。
- 长时间构建使用远端 `nohup`/`tmux`，将输出保存为远端源码根目录的 `compile.txt`。轮询只读取 PID、日志大小和新增尾部，不能重复读取完整日志。
- 同一共享工作区不得并行执行多个大范围 `git status`、`git diff`、`rg` 或构建命令；这会争抢网络 I/O、Git index 和构建输出锁。

## EF930 已验证映射

截至 2026-08-28，EF930 源码/构建服务器为 `10.199.40.231`，Linux 原生源码路径为：

```text
/home/new_ssd1/caoyixi/workspace/android/ef930_2
```

Windows `V:\new_ssd1\workspace\android\ef930_2` 是该路径的共享视图。涉及 EF930 的 Git、源码搜索、构建、权限和生成物操作，固定使用 Windows `pwsh` 发起 `ssh 10.199.40.231`，并在上述 Linux 路径执行；Git/GitLab remote 仍需从当前 repo manifest 和 `.repo` 元数据单独确认。
- Windows SMB 上的 Git 可能因所有者校验、换行符或共享层文件属性显示大量伪 `M`。不要用 `safe.directory=*` 的结果判断 Linux 工作树是否干净；Windows 与 SSH 结果冲突时，以目标 Linux 原生路径执行的 `git status --short --untracked-files=no` 为准。
- 不把 SSH 密码、私钥或凭据写入资料、脚本、日志或回复。

## Docker 复用 out 目录

- Android 的 `out/soong/.intermediates/` 可能包含指向源码绝对 Linux 路径的符号链接。将宿主源码挂载为容器内不同路径，例如把 `/home/.../android/n6p` 挂到 `/workspace`，会使这些链接在容器中失效，并出现“工具文件不存在”的假象。
- 复用已有 `out/` 时，容器应把源码挂载到与宿主相同的绝对路径，并使用同一路径作为工作目录。例如宿主源码是 `/home/user/work/android/n6p`，容器也应使用 `-v /home/user/work/android/n6p:/home/user/work/android/n6p -w /home/user/work/android/n6p/A12`。
- 先检查 Docker 镜像的 `Entrypoint`。镜像已经以 `/bin/bash` 为入口时，额外传入 `bash -lc` 会让入口 shell 尝试执行 bash 二进制；改用 `--entrypoint /bin/bash ... -lc '<command>'`。
- 随机容器 hostname 会改变 `BUILD_HOSTNAME`，触发 Soong 重新生成并可能拉起与本次模块无关的内核构建。复用 `out/` 时保持与既有构建一致的 hostname 或 BUILD_HOSTNAME，并以最终构建日志和产物时间确认成功。

## 构建预检

1. 确认项目根目录、当前源码工作区、产品和目标模块。
2. 阅读项目自己的 `xgd_build.sh` 或等价 wrapper。
3. 确认是否需要先进入 Docker/构建环境。
4. 检查是否已有同一 `out/` 的构建进程。
5. 明确预期产物路径和本次验证方式。

不要把另一个项目的 wrapper、参数或产物路径当作当前项目事实。

## Windows 网络驱动器映射的会话隔离

| 字段 | 内容 |
|---|---|
| 现象 | `map-caoyixi-v.bat` 输出 `V: mapped successfully`，但另一个终端 `net use` 显示 `There are no entries in the list`，`Test-Path V:\` 为 False |
| 直接原因 | Windows 网络驱动器映射按登录会话和提升权限隔离；普通 PowerShell、管理员窗口、Codex 或其他进程看到的映射集合不一定一致 |
| 安全做法 | 在同一个终端内完成映射与验证；重新映射可使用 `net use V: \\10.199.40.231\caoyixi /persistent:yes` 或 `New-SmbMapping -LocalPath V: -RemotePath \\10.199.40.231\caoyixi -Persistent $true`；验证前先 `Set-Location C:\`，再执行 `cmd /c "net use"` 和 `Test-Path V:\new_ssd1\workspace\android\mino1` |
| 验证证据 | 2026-08-20：`Test-NetConnection 10.199.40.231 -Port 445` 通过；`net view \\10.199.40.231` 可见 `android`、`caoyixi`、`new_ssd1`、`zhangpeng` 共享；当前会话重新 `net use V:` 后源码路径可读 |
| 适用范围 | Windows 映射 Android 共享源码的日常访问与 Codex 工作区访问 |
| 重新验证条件 | Samba 服务器、共享名、登录会话、UAC 提升级别或持久映射状态变化后，重新在目标会话执行 `net use` 和 `Test-Path` |

---
name: android-everything
description: 统一处理 XGD Android 项目的源码定位、项目结构、构建预检、设备与 Recovery 日志取证、OTA、init、SELinux、内核、驱动、串口、崩溃、性能、Git/GitLab 分析、个人活动统计、Markdown 工作回顾和经验沉淀。适用于 Mino1、N82、N6P、EF930、EF20、CT20、UN10 等 Android 源码、设备日志、Git 或 GitLab 工作任务；先识别机型、源码工作区或 GitLab 查询参数，再按中文机型索引、专题、功能模块和问题资料执行。
---

# Android 全流程

## 核心原则

将任务分成四层：已确认事实、源码行为、实时探测结果、待验证推断。

不要把一个机型、Android 版本、源码工作区或历史分支的结论自动套用到另一个对象。构建、部署、清数据、重启、刷机、提交和推送前，先确认当前对象与风险边界。

网络工作区中必须分开确认源码/构建服务器与 Git/GitLab 服务器；对 repo 子项目执行 fetch、push 或修改 remote 前，先以 manifest 和 `.repo/projects/<project-path>.git/config` 核对真实 remote，不能从用于编辑源码的 SSH 地址推导 Git remote。

只要操作 Linux 服务器上的 Android 源码、Git、repo、构建、日志、权限或生成物，必须由 Windows PowerShell 7（`pwsh`）启动 `ssh`，并在远端 Linux 原生路径执行。禁止将映射盘或 UNC 路径作为服务器操作的实际执行路径；本地映射盘只用于用户需要在桌面打开文件。复杂远程命令使用一次 SSH 批量脚本，避免并行启动多个大范围 Git/搜索进程。

当用户明确表示自己是初学者，或说“还是不理解”“尽可能详细解释”时，先用口语化短句和具体类比讲清每个对象及其先后关系，再给源码术语、路径和行号。一次只引入一个层级；必须区分“升级事务/状态”“临时存储”“内核或用户态映射设备”“最终写入和合并”，避免在同一句中堆叠 snapshot、COW、dm-snapshot、dm-user、snapuserd 等术语。

长时间挂测、日志、报告和其他主要产物默认写到 `D:\ai\codex\<日期>\<任务目录>`，不要默认占用 `C:\Users\XGD\Documents\Codex`。只有用户明确要求写到 C 盘或其他指定位置时，才使用其他位置；对外回复时给出实际最终绝对路径。

本机任务产生的临时文件、调查中间产物、导出结果和回滚备份也统一放到 `D:\ai\codex\<日期>\<任务目录>` 下，不要散落到用户目录、交付目录或 `D:\xgd`。任务结束后默认删除临时文件和不再需要的备份；只有用户明确要求保留时才留下。删除前必须区分活动数据、凭据、源码、Git 仓库、镜像和可恢复材料。

## Windows 命令

在 Windows 执行本地命令时，优先使用 `pwsh`（PowerShell 7），不主动调用 Windows PowerShell 的 `powershell.exe`。只有 `pwsh` 不可用或用户明确要求兼容旧环境时，才说明原因后使用后者。

服务器操作固定采用 `pwsh + ssh`：

```powershell
$remoteScript = @'
set -e
cd /home/user/workspace/android/project
git status --short --untracked-files=no -- path/to/module
'@
$remoteScript = $remoteScript -replace "`r`n", "`n"
$remoteScript | ssh -o BatchMode=yes -o ConnectTimeout=8 user@host bash -s
```

PowerShell 传给 `ssh` 的命令必须使用单引号或 here-string，防止本地提前展开远端的 `$变量`、`$(command)`、反引号和正则。长时间构建使用远端 `nohup`/`tmux`，轮询时只读取进程状态、日志大小和新增尾部；不要反复创建新 SSH 会话或重复传输完整日志。

远端构建前先在同一 SSH 会话中检查 `ccache` 和已有构建进程；如果已有 `ccache` 配置则复用，不清空缓存。优先执行模块级增量目标，编译日志写到远端工作区的 `compile.txt`，失败时只提取首个 `FAILED:`/`error:` 上下文。

Windows OpenSSH 的连接复用不是默认前提。只有先用当前客户端验证 `ControlMaster`、`ControlPersist` 和独立 socket 路径确实可用时才启用；出现 `getsockname failed: Not a socket`、ControlPath 冲突或复用异常时，立即退回普通单次 SSH，不循环探测，不修改全局 SSH 配置。

## 本机 Python 工具

执行 Android 辅助 Python 脚本时，统一使用持久环境，不要向 Codex bundled runtime 安装依赖：

| 项目 | 固定位置 |
|---|---|
| 虚拟环境 | `C:\Users\XGD\.codex\venvs\android-everything` |
| 依赖清单 | `requirements.txt` |
| 统一入口 | `scripts/run-python.ps1` |

运行已有脚本时，使用 `run-python.ps1 -ScriptPath <脚本路径> -ArgumentList <参数>`。只有脚本实际使用 `import yaml` 时才依赖 `PyYAML`；`agents/openai.yaml` 是 Codex 配置文件，不需要 Python 解析。

修改依赖时，同时更新 `requirements.txt`；重建环境时使用独立 Python 3.14，不使用 `C:\Users\XGD\.cache\codex-runtimes` 下的 Python。

## 统一流程

1. 识别任务目标：机型、当前源码工作区、任务类别和用户授权的动作范围。
2. 读取 `references/机型索引.md`，再读取命中的机型概览。
3. 根据任务类别读取共享资料和机型专题资料。
4. 对服务器源码、Git、产物或日志，通过 `pwsh + ssh` 在 Linux 原生路径做实时验证；历史资料只作候选线索。
5. 先报告证据、建议动作和风险；只有在用户明确授权后才执行高风险操作。
6. 任务结束时，将本轮经过验证、可复用的新经验写入对应机型资料或共享资料；没有稳定证据时不写入，不把猜测写成规则。

## 兼容性与预研开发

用户要求开发新功能或处于预研阶段时，默认先询问是否需要前向兼容；如果用户明确表示不需要，按当前新协议直接实现，不额外增加旧格式转换、历史别名兼容、旧字段拒绝分支或与当前需求无关的冗余校验。只保留功能正确性、安全性和数据完整性所必需的校验，并在结论中明确兼容性边界。

## 新机型建档

仅当用户明确要求“为当前机型建档”“初始化机型资料”或同等意思时执行本流程。仅进入一个新的源码目录、或仅使用本 Skill，不得自动创建资料。

1. 在不编译、不改源码、不执行设备动作的前提下，只读检查当前目录、源码管理结构、产品配置和构建入口。
2. 先报告候选机型标识、输入工作区和识别证据；机型标识与工作区关系不清楚时，先澄清，不建档。
3. 机型标识明确后，运行 `scripts/initialize-device-profile.ps1` 创建资料骨架。例如：

```powershell
& "$env:USERPROFILE\.codex\skills\android-everything\scripts\initialize-device-profile.ps1" `
  -Model "N82" `
  -WorkspacePath "V:\new_ssd1\workspace\android\n82" `
  -DisplayName "N82"
```

4. 脚本只创建五个根文件：`概览.md`、`工作区与构建.md`、`Git与提交.md`、`技术专题索引.md`、`已知问题.md`；同时创建空容器 `专题/`、`功能模块/`、`问题/`，并将机型登记到 `references/机型索引.md`。
5. 不预先创建空的 Recovery、init、SELinux、内核、驱动或性能资料。脚本拒绝覆盖已有机型目录或重复索引项；所有初始字段均为“待验证”。
6. 后续只有源码、日志、命令输出、包内容或设备证据支持时，才建立专题、功能模块或问题页。不得复制其他机型的结论。

## 机型资料结构

每个机型采用同一套中文结构：

```text
references/机型/<机型>/
├── 概览.md
├── 工作区与构建.md
├── Git与提交.md
├── 技术专题索引.md
├── 已知问题.md
├── 专题/
├── 功能模块/
└── 问题/
```

| 位置 | 职责 | 不应放入的内容 |
|---|---|---|
| 根目录五个文件 | 机型坐标、构建/Git 规则、资料路由、问题摘要 | 冗长技术原理和多轮故障过程 |
| `专题/` | 一个技术方向的稳定事实，例如 Recovery 与 OTA、init、SELinux、内核与驱动、串口、崩溃、性能 | 横跨多个层次的完整产品能力 |
| `功能模块/` | 一个产品能力跨应用、Framework、native、驱动、固件或 Recovery 的完整链路 | 单一技术方向的通用原理 |
| `问题/` | 多阶段、可重复排查的复杂故障证据链 | 一次性误操作或无证据猜测 |

## 新建资料页面

新建详细资料时，优先运行 `scripts/create-knowledge-page.ps1`，不要手工创建后忘记更新索引。

```powershell
pwsh -NoLogo -NoProfile -File "$env:USERPROFILE\.codex\skills\android-everything\scripts\create-knowledge-page.ps1" `
  -Model "N6P" `
  -Kind Module `
  -PageName "M1扫码与固件升级" `
  -Title "M1 扫码与固件升级" `
  -Status "部分确认" `
  -Scope "Android 服务、UART、固件与 Recovery 集成边界"
```

| `Kind` | 使用场景 | 自动更新的位置 |
|---|---|---|
| `Topic` | 一个技术方向已有多条稳定事实或独立验证边界 | `技术专题索引.md` |
| `Module` | 一个产品能力横跨多个软件/硬件层次 | `技术专题索引.md` |
| `Issue` | 故障需要保留现象、证据链、处置与回归过程 | `已知问题.md` |

脚本拒绝覆盖已有页面，并验证目标路径必须位于对应机型的指定容器内。先用 `-WhatIf` 预演可能影响。

## 资料选择

| 任务类别 | 必读资料 |
|---|---|
| 映射盘、SSH、源码搜索、Docker 构建环境 | `references/共享/网络工作区与SSH.md` |
| ADB、受保护 shell、Recovery、sideload、日志采集 | `references/共享/ADB与Recovery取证.md` |
| Recovery OTA 错误收集、ODPS、BCB 到 `ro.boot.*`、nonab/ab/SP/cert 边界 | `references/共享/Recovery升级错误与ODPS.md` |
| 跨项目寻找类似实现 | `references/共享/OpenGrok跨项目检索.md` |
| Git 状态、分支、提交、推送 | `references/共享/Git安全.md` |
| GitLab 个人活动、Commit/MR 统计和 Markdown 工作回顾 | `references/共享/GitLab活动与工作回顾.md` |
| 复盘并沉淀工作经验 | `references/共享/经验复盘.md` |
| 已接入的其他机型 | 先从 `references/机型索引.md` 定位，再读取 `机型/<机型>/概览.md` |
| 其他机型的工作区与构建 | `机型/<机型>/工作区与构建.md` |
| 其他机型的 Git 任务 | `机型/<机型>/Git与提交.md` |
| 其他机型的 Recovery、OTA、init、SELinux、内核、驱动、串口、崩溃或性能 | 先读 `机型/<机型>/技术专题索引.md`，再进入命中的 `专题/` 页面 |
| 跨层产品能力，例如扫码、打印、支付、外设升级 | 先读 `机型/<机型>/技术专题索引.md`，再进入命中的 `功能模块/` 页面 |
| 其他机型的历史问题 | 先读 `机型/<机型>/已知问题.md`；存在复杂案例时再进入 `问题/` |
| EF930 payload、update_engine、snapshot、COW | `references/机型/EF930/专题/VAB动态分区.md`、`VAB目标槽映射.md` |
| EF930 Recovery 包、update-binary、历史 OTA | `references/机型/EF930/专题/Recovery与OTA.md` |
| EF930 平台代号、BP/签名配置、divar/agatti、LA/BP 边界 | `references/机型/EF930/专题/Platform-Codenames-and-BP-Signing.md` |
| UN10 Recovery 或串口 | `references/机型/UN10/技术专题索引.md` |
| N6P M1 扫码、串口、固件或 Recovery 集成 | `references/机型/N6P/功能模块/M1扫码与固件升级.md` |
| Mino1 图形内存、memtrack、PVR/GL/EGL | eferences/机型/Mino1/专题/图形内存与memtrack.md |

## 动作边界

| 动作 | 默认行为 | 继续条件 |
|---|---|---|
| 源码定位、日志阅读、路径限定搜索 | 可直接执行 | 路径和查询范围明确 |
| 修改源码 | 先说明文件和修改范围 | 用户明确要求修改 |
| 编译 | 先完成构建预检 | 用户明确要求开始构建 |
| `adb push`、`remount`、清数据 | 先展示目标、产物和影响 | 用户明确确认 |
| `reboot`、刷机、sideload 复现 | 必须暂停 | 用户逐项确认 |
| `git add`、commit、push | 先输出精确文件与完整 message | 用户逐项确认 |
| `repo sync`、`git reset --hard`、`git clean`、强推 | 禁止自行执行 | 仅在用户明确要求且已给出保护方案时讨论 |

服务器动作的额外边界：

- 不在 Windows 映射盘/UNC 上执行大范围 `git status`、`git diff`、`git log`、`rg`、构建、删除或权限判断。
- 不对同一远程共享工作区并行启动多个重量级 Git 命令；先用一次 SSH 批量读取完成现场确认。
- `multi_tool_use.parallel` 不用于并行操作同一个远程源码工作区；只有不同主机、不同工作区且不存在共享输出/锁竞争时才并行。
- SSH 连接失败、远端原生路径未知或认证异常时，停止并报告；不得静默回退到 SMB 映射盘。

## 输出格式

对工程任务按以下顺序输出：

1. 已确认事实。
2. 当前探测结果。
3. 建议动作及其证据。
4. 风险、未知项和需要确认的动作。
5. 已完成验证与未完成验证。

## 资料维护

- 每条机型事实必须注明适用源码工作区、证据来源、最后验证日期和重新验证条件。
- `已确认`、`部分确认`、`待验证` 三种状态不得混用。
- 短小的机型坐标、构建/Git 事实和问题摘要留在根目录；技术事实写入 `专题/`，跨层产品能力写入 `功能模块/`，复杂故障写入 `问题/`。
- 一轮任务结束后，只有出现多个稳定事实、独立验证边界或可重复使用价值时，才新建详细页面；否则在已有页面或根目录索引补充一行即可。
- 任何问题都可以记录，但必须至少保留首个决定性错误、已确认事实或可复现的规避方式之一；一次性误操作和无证据猜测不沉淀。
- 不保存密码、访问令牌、私钥、CPT、设备序列号、派生认证值或其他敏感认证材料。
- 跨项目的工具、终端、SSH、编码和流程问题写入 `共享/经验复盘.md` 或对应共享专题，不复制成单一机型事实。
- 机型资料过长时，优先将复杂案例拆到 `问题/`，不要把顶层 `SKILL.md` 扩大成百科全书。

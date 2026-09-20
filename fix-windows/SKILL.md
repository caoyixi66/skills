---
name: fix-windows
description: "排查和修复 Windows 文件关联、打开方式列表、残留应用项、快捷访问和相关 Shell 缓存问题；适用于用户界面仍显示旧程序、默认打开程序异常或修改软件路径后快捷访问失效的场景。"
---

# Windows 修复

## 适用范围

处理以下问题时使用本 skill：

- 双击文件后无法用预期程序打开。
- “打开方式 -> 选择其他应用”仍显示已经移动、卸载或不希望出现的程序。
- 修改 exe、软件目录或快捷方式位置后，快捷访问、开始菜单或打开方式出现残留。
- 注册表看起来已经修改，但用户界面没有变化。

不要把“注册表查询成功”当作修复完成。最终结果必须以用户可见的实际窗口、重新执行的打开动作或用户提供的新截图为准。

## 首轮确认

先询问或从上下文确定：

- Windows 版本和当前登录用户。
- 具体文件路径、扩展名，以及用户操作的完整入口。
- 异常是默认打开失败，还是仅“选择其他应用”列表错误。
- 需要保留哪些程序，哪些程序只是希望从列表中隐藏。
- 是否允许修改当前用户注册表；默认只修改 `HKCU`，不主动改 `HKLM`。

## 排障顺序

按层次收集证据，不要在没有区分层次的情况下反复删除注册表：

1. 检查文件本身和默认关联：
   - `HKCU\Software\Classes\.ext`
   - `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.ext`
   - `OpenWithList`、`OpenWithProgids`、`UserChoice`
   - 目标 ProgID 下的 `shell\open\command`
2. 检查候选应用注册：
   - `HKCU\Software\Classes\Applications\<app>.exe`
   - `HKLM\Software\Classes\Applications\<app>.exe`
   - `SupportedTypes`、`FriendlyAppName`、`NoOpenWith`
   - 相关 ProgID 类，如 `Typora.md`、`Cursor.properties`
3. 检查系统或打包应用来源：
   - `RegisteredApplications`
   - `Capabilities\FileAssociations`
   - `App Paths`
   - `AppX`、`PackageRepository` 和程序自己的文件类型注册
4. 检查 Shell 生命周期：
   - `OpenWith.exe` 是否仍是旧实例
   - `explorer.exe`、`SearchHost.exe`、`StartMenuExperienceHost.exe` 是否在修改前启动
   - 必要时只重启相关 Shell 进程，不重启整机作为第一选择
5. 重新打开同一个文件的实际对话框，使用截图、OCR、UI Automation 或用户确认核对列表。

## 修复原则

- 先对命中的注册表键执行 `reg export` 备份，备份路径写入结果。
- 注册表导出、快捷方式备份和其他回滚材料默认放在 `D:\ai\codex\<日期>\<任务目录>\backup`，不要写入 `D:\xgd` 或用户交付目录；完成实际打开验证后，默认清理不再需要的备份。
- 优先使用当前用户覆盖项，避免为了隐藏一个候选应用而改动系统级注册。
- 对“只是不想显示”的程序，优先使用 `NoOpenWith`，而不是删除程序、卸载项或整棵文件类型树。
- 只处理用户明确指出的候选应用；不要清理所有文件关联、所有缓存或整个 `HKCU\Software\Classes`。
- 删除或移动前先确认绝对路径和影响范围。默认不删除用户数据和软件目录。
- 如果需要管理员权限修改 `HKLM`，先说明权限边界；没有权限时不要假装已经修改成功。
- 每次修改后都重新启动实际使用的 `OpenWith.exe`，并重新验证窗口，不要只查看 PowerShell 输出。

## 重要判断

当目标扩展名自己的 `OpenWithList` 已经只剩正确程序，但窗口仍显示旧程序时，问题通常已经不在默认关联层。此时应停止继续改 `.ext` 的默认值，转而查候选应用注册和 `NoOpenWith`。

`OpenWith.exe` 可能是长生命周期的 COM/系统进程。终止旧实例有助于刷新，但仅终止进程不保证能解决问题；如果候选应用仍被应用注册数据库枚举出来，还需要针对应用或 ProgID 增加当前用户级 `NoOpenWith` 覆盖。

详细的失败分析、案例证据和 PowerShell 模板见 [references/openwith-troubleshooting.md](references/openwith-troubleshooting.md)。

# Windows “选择其他应用”排障记录

## 一、问题模型

Windows 的“打开方式”不是只读取一个注册表位置。至少要区分四层：

1. **默认关联层**

   决定双击文件时使用谁，例如：

   - `HKCU\Software\Classes\.prop`
   - `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.prop\UserChoice`
   - `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.prop\OpenWithList`
   - `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.prop\OpenWithProgids`

2. **应用候选枚举层**

   决定“选择其他应用”可以列出谁，例如：

   - `HKCU\Software\Classes\Applications\<app>.exe`
   - `HKLM\Software\Classes\Applications\<app>.exe`
   - `SupportedTypes`
   - ProgID 的 `shell\open\command`
   - `FriendlyAppName`
   - `NoOpenWith`

3. **打包应用和程序安装层**

   一些应用不是普通的 `Applications\<app>.exe`，还可能通过以下位置被发现：

   - `RegisteredApplications`
   - `Capabilities\FileAssociations`
   - `App Paths`
   - `AppX`/`PackageRepository`
   - 软件自己的 ProgID、扩展名和 shell 注册

4. **Shell 进程和缓存层**

   `Explorer.exe`、`OpenWith.exe` 以及部分 Shell 组件可能在修改注册表前就已经读取了旧数据。重启 Explorer 或终止旧的 `OpenWith.exe` 有助于刷新，但不能代替候选应用注册层的修复。

因此：

```text
双击能否打开
不等于
“选择其他应用”列出的所有候选是否正确
```

## 二、这次为什么前面多轮没有效果

本次目标文件是 `D:\tmp\build.prop`，默认打开已经可以使用 Notepad++。之前多轮主要做了以下事情：

- 修改 `.prop` 默认 ProgID 和 `OpenWithList`。
- 清理部分 association-toast、MuiCache 和图标缓存。
- 移动开始菜单快捷方式。
- 重启 Explorer 和 Shell 组件。
- 终止过旧的 `OpenWith.exe`。

这些动作并非完全无效，但它们分别只覆盖了默认关联、显示缓存或 Shell 生命周期。实际检查结果显示：

- `.prop\OpenWithList` 只有记事本和 `notepad++.exe`。
- `shell:AppsFolder` 中只剩 Notepad++ 相关桌面应用。
- 新启动的 `OpenWith.exe` 仍显示 `7-Zip Console`、百度网盘、Cursor、Typora。

这组证据说明：旧项不是 `.prop` 自己的专属 `OpenWithList`，也不只是图标缓存，而是“打开方式”在枚举其他应用候选时仍把这些程序视为可用候选。

其中还发现了多个残留来源：

- 系统级 `Typora.exe` 注册仍指向已经不存在的 `D:\Typora\Typora.exe`。
- 系统级 `App Paths` 中仍有旧的 Typora 和 7-Zip 路径。
- Cursor 在当前用户下注册了大量 `Cursor.<extension>` ProgID，例如 `Cursor.properties`、`Cursor.txt`。
- 百度网盘保留了图像查看器 ProgID、打包应用和文件类型相关注册。

所以，前面继续修改 `.prop` 默认关联不会改变“更多选项”列表。即使杀掉旧的 `OpenWith.exe`，新实例仍会从这些注册项重新枚举旧程序。

## 三、最后为什么有效

最后一次处理做了两件关键事情：

1. 在当前用户注册表中给命中的候选应用和 ProgID 增加 `NoOpenWith`。
2. 终止 `OpenWith.exe`，重启 `explorer.exe`，再启动一个新的打开方式窗口验证。

示例覆盖项包括：

```text
HKCU\Software\Classes\Applications\7z.exe\NoOpenWith
HKCU\Software\Classes\Applications\BaiduNetdisk.exe\NoOpenWith
HKCU\Software\Classes\Applications\Cursor.exe\NoOpenWith
HKCU\Software\Classes\Applications\Typora.exe\NoOpenWith
HKCU\Software\Classes\CursorSourceFile\NoOpenWith
HKCU\Software\Classes\Cursor.properties\NoOpenWith
HKCU\Software\Classes\Typora.md\NoOpenWith
HKCU\Software\Classes\Typora.text\NoOpenWith
```

这不是把软件卸载，也不是删除所有关联；它是在当前用户层告诉 Shell：这些候选不要加入“打开方式”列表。当前用户层通常可以覆盖系统级同名应用注册，也不要求把系统注册表改成不可逆状态。

最终重新打开窗口后实际只剩：

- 默认应用：Notepad++
- 建议应用：记事本
- 旧的 7-Zip、百度网盘、Cursor、Typora：不再显示

这才是完成验证。仅看到 `Get-ItemProperty` 返回 `NoOpenWith`，不能单独证明 UI 已改变。

## 四、可复用的诊断模板

将 `<ext>` 替换成实际扩展名，例如 `.prop`。将候选名称替换成用户看到的项目：

```powershell
$ext = '.prop'

reg.exe query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext" /s
reg.exe query "HKCR\$ext" /s

$roots = @(
  'HKCU:\Software\Classes\Applications',
  'HKLM:\Software\Classes\Applications',
  'HKCU:\Software\Classes'
)

foreach ($root in $roots) {
  Get-ChildItem -LiteralPath $root -Recurse -ErrorAction SilentlyContinue |
    ForEach-Object {
      $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
      foreach ($v in $p.PSObject.Properties) {
        $text = "$($v.Name)=$($v.Value)"
        if ($text -match '(?i)候选程序名|目标路径|FriendlyAppName|NoOpenWith|SupportedTypes') {
          "$($_.PSPath) :: $text"
        }
      }
    }
}

Get-Process OpenWith,explorer,SearchHost,StartMenuExperienceHost `
  -ErrorAction SilentlyContinue |
  Select-Object Name,Id,StartTime,Path
```

不要对整个注册表做无界递归输出；实际执行时应先限定到候选应用、目标扩展名和相关 `Applications`/ProgID 路径。

## 五、可复用的安全修复模板

先备份，再只写当前用户级覆盖：

```powershell
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $env:TEMP "openwith-targeted-backup-$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null

$keys = @(
  'HKCU\Software\Classes\Applications\<app>.exe',
  'HKCU\Software\Classes\<ProgID>'
)

foreach ($key in $keys) {
  $file = Join-Path $backup (($key -replace '[\\:]','_') + '.reg')
  reg.exe export $key $file /y 2>$null | Out-Null
}

$apps = @('<app>.exe')
foreach ($app in $apps) {
  $key = "HKCU:\Software\Classes\Applications\$app"
  New-Item -Path $key -Force | Out-Null
  New-ItemProperty -Path $key -Name NoOpenWith `
    -PropertyType String -Value '' -Force | Out-Null
}

$progIds = @('<ProgID>')
foreach ($progId in $progIds) {
  $key = "HKCU:\Software\Classes\$progId"
  New-Item -Path $key -Force | Out-Null
  New-ItemProperty -Path $key -Name NoOpenWith `
    -PropertyType String -Value '' -Force | Out-Null
}
```

刷新和验证：

```powershell
Stop-Process -Name OpenWith -Force -ErrorAction SilentlyContinue
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 1000
Start-Process explorer.exe
```

然后重新打开同一个文件的“选择其他应用”窗口。应使用新截图或 UI Automation 树确认实际列表，不要只根据注册表输出宣布完成。

## 六、失败时的继续方向

如果增加当前用户级 `NoOpenWith` 并刷新后仍显示旧项：

1. 再次确认新 `OpenWith.exe` 的 `StartTime` 晚于刷新时间。
2. 用 `shell:AppsFolder` 枚举打包应用和桌面应用。
3. 精确检查候选显示名对应的 `FriendlyAppName`、`DefaultIcon`、`shell\open\command` 和 ProgID。
4. 检查 32 位视图：
   - `HKLM\Software\WOW6432Node\Classes`
   - `HKLM\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths`
5. 检查是否有第三方文件管理器、系统增强工具或应用安装器重新写回注册表。
6. 只有在证据明确指向某个系统级注册项时，才考虑管理员权限下的 `HKLM` 修改；先备份并说明会影响所有用户。

不要在没有新证据时继续清空图标缓存、删除整个 `FileExts`、删除整个 `Classes` 或修改无关的文件关联。

## 七、卸载后 OpenWithView 仍显示旧 exe 的补充案例

百度网盘卸载后，先前已删除常见的 `Applications`、ProgID、`FileExts`、MuiCache、托盘缓存及用户配置，OpenWithView 中仍显示指向 `D:\applications\BaiduNetdisk\BaiduNetdisk.exe` 的行。移动 OpenWithView 自身不会改变枚举结果；重新启动工具后仍显示旧行，不能再归因于旧窗口快照。

精确查询 `reg.exe query HKCU /f BaiduNetdisk.exe /s` 找到了：

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Start\TileProperties\W~D:\applications\BaiduNetdisk\BaiduNetdisk.exe
HKCU\Software\Microsoft\Windows\CurrentVersion\Start\TileProperties\W~D:\BaiduNetdisk\BaiduNetdisk.exe
HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store
    D:\applications\BaiduNetdisk\BaiduNetdisk.exe
```

兼容性助手中还记录了安装包和下载目录中的 exe 历史。先导出 `TileProperties` 与 `Store` 对应分支，随后只删除百度网盘路径的两个 `TileProperties` 父键及相关历史值。重新启动 OpenWithView 后，用户确认旧行不再显示。**这个先后验证了清理结果，但未做工具的注册表访问跟踪，不能断言 OpenWithView 直接读取这些历史键，也不能把所有 `TileProperties` 项当作打开方式注册。** 首先核对常见注册和窗口，再将这些位置作为扩展排查线索。

含 `D:` 的 `TileProperties` 子键在 PowerShell Registry provider 中用 `Test-Path`/`Remove-Item` 曾错误显示不存在。对这种含冒号的精确键名，备份后用原生 `reg.exe query "<完整键名>" /s` 和 `reg.exe delete "<完整键名>" /f`，再重复查询验证；不要删除整棵 `TileProperties` 或 `Store`。下载目录中的文件是用户数据，即使曾出现在兼容性历史中也不能一起删除。备份只保证注册表可回滚，不包含被删用户配置目录的内容；若需要恢复配置，应在删除前另行备份。

## 八、已安装程序目录移动前的检查

“D 盘到 D 盘”只是盘符不变；从 `D:\applications\<app>` 剪切到 `D:\<app>` 仍会令所有绝对路径失效。重建快捷方式只修复那个入口，不能修改其他注册或服务配置。

1. 区分便携版和安装版：有卸载项、MSI、服务、驱动、Shell 扩展、更新器或任务计划的程序，优先卸载后在目标路径重装；不要先剪切再尝试修补所有路径。
2. 逐项只读检查 `Uninstall` 的 `InstallLocation`/`DisplayIcon`/`UninstallString`，`App Paths`、`Run`、服务 `PathName`、任务 `Actions`、快捷方式目标、文件关联命令，以及程序自己的配置和升级机制。旧路径可能造成图标空白、打开方式失效、开机启动失败、卸载/升级回原位置；某个旧 `DisplayIcon` 不证明主程序已经损坏。
3. 对明确便携的工具，移动前仍应记录旧目录与快捷方式；移动后验证主程序、右键打开方式、图标、更新、卸载或启动入口。路径相关注册要逐项备份和处理，不批量替换整个注册表。
4. 用实际启动、相关文件打开、升级/卸载入口以及用户可见界面验证。注册表搜索“0 命中”只证明查过的范围没有该字符串，不能证明整个系统无残留。

一次只读盘点中，`D:\applications` 内 7-Zip、Clash Verge、Notepad++ 的卸载或图标注册指向旧路径；Notepad++、Typora、Wireshark 有固定 `App Paths`；`autotool` 的开机启动指向 `D:\applications\autotool\1.7.2\NativeNetServer.exe`；QPST 是 MSI 安装项。此清单只是当时的路径风险证据，不是永久的软件类型判定；移动前重新查询当前状态，且不要因目录名称猜测驱动是否已安装。

## 九、两个已验证的补充经验：Notepad++ 与百度网盘

### Notepad++ 重复项和空白图标

重装 Notepad++ 只会重新写入安装注册，不会自动清理当前用户的 `FileExts` 历史。例如 `.log` 曾同时存在：

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.log\OpenWithList
    c = notepad++.exe
```

同时默认 `UserChoice` 又指向 `log_auto_file`，其命令也指向 Notepad++。这会让同一个程序出现在不同区域或显示两次。精确备份后删除对应字母值并从 `MRUList` 删除同一字母，才能去重；不要删除整个 `.log` 关联或 `UserChoice`。

空白图标还可能来自移动后的快捷方式，而不是 `Applications\notepad++.exe`。必须检查：

```text
C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Notepad++.lnk
```

本案例中该快捷方式曾指向已不存在的 `D:\applications\Notepad++\notepad++.exe` 且 `IconLocation` 为空；修为 `D:\Notepad++\notepad++.exe,0` 后才消除这条残留。应用 EXE 本身可以成功提取图标，不等于 Shell 当前缓存或快捷方式使用了它。

### 百度网盘：现代窗口与 OpenWithView 的证据边界

百度网盘从现代 Windows“选择应用”窗口消失后，旧版 OpenWithView 仍显示一行：

```text
Application: BaiduNetdisk...
Disabled: Yes
Command Line: D:\applications\BaiduNetdisk\...
```

这不矛盾。OpenWithView v1.11 的随附文档只声明 Windows XP/2003/Vista 支持，并且明确显示/管理“已禁用项目”；在 Windows 11 上它可能保留历史候选。`Disabled=Yes` 只能说明该工具认为它已禁用，不能证明现代 OpenWith 窗口仍可用，也不能证明程序仍在运行。最终验证应以全新现代“选择应用”窗口、实际命令可执行性和注册表功能性来源为准。

本案例中真正的百度卸载残留还包括机器级 Shell/COM 类型库：

```text
HKLM\Software\Classes\AppID\YunShellExt.DLL
HKLM\Software\Classes\AppID\{B9480AFD-C7B1-4452-BE14-BB8A9540A05D}
HKLM\Software\Classes\Interface\{1434B2F5-5B9C-44C2-938D-2A11E03CEED9}
HKLM\Software\Classes\TypeLib\{75711486-6BB1-4C76-853A-F3B7763FACF4}
HKLM\Software\Classes\TypeLib\{8D20829A-1E9A-47CE-B851-08E204DDC970}
```

以及 32 位视图中的对应 `WOW6432Node` 键，路径指向已不存在的 `D:\BaiduNetdisk\YunShellExtV1.dll` 和 `npYunWebDetect.dll`。清理这些键前必须导出备份，并同时删除对应 32 位 Interface/TypeLib；只删 `BaiduNetdisk.exe`、普通 ProgID 或 HKCU 历史项可能仍留下 Shell/COM 残留。清理后应分别执行：

```text
reg query HKCU /f BaiduNetdisk /s
reg query HKLM /f BaiduNetdisk /s
reg query HKLM /f YunShellExt /s
reg query HKLM /f YunWebDetect /s
```

但 Windows AppX StateRepository、Setup/Upgrade 历史数据库仍可能保留包名或卸载历史；这些不是打开方式注册，不应为了追求字符串 0 命中而手工删除整个 StateRepository。

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

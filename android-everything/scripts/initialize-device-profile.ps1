[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$')]
    [string]$Model,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$WorkspacePath,

    [string]$DisplayName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-TableCell {
    param([Parameter(Mandatory)][string]$Value)

    return (($Value -replace '[\r\n|]', ' ').Trim())
}

$skillRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$modelsRoot = (Resolve-Path -LiteralPath (Join-Path $skillRoot 'references\机型')).Path
$templatesRoot = Join-Path $skillRoot 'assets\机型建档'
$indexPath = Join-Path $skillRoot 'references\机型索引.md'
$modelDirectory = [System.IO.Path]::GetFullPath((Join-Path $modelsRoot $Model))
$modelsRootPrefix = $modelsRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

if (-not $modelDirectory.StartsWith($modelsRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "机型目录不在预期资料根目录内：$modelDirectory"
}

if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
    throw "未找到机型索引：$indexPath"
}

if (Test-Path -LiteralPath $modelDirectory) {
    throw "机型目录已存在，拒绝覆盖：$modelDirectory"
}

$model = ConvertTo-TableCell $Model
$displayName = if ([string]::IsNullOrWhiteSpace($DisplayName)) {
    $model
} else {
    ConvertTo-TableCell $DisplayName
}
$workspace = ConvertTo-TableCell $WorkspacePath
$workspaceAccess = if (Test-Path -LiteralPath $WorkspacePath) {
    '本机路径可访问'
} else {
    '本机未解析，保留为输入路径'
}
$createdDate = (Get-Date).ToString('yyyy-MM-dd')
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$templates = [ordered]@{
    '概览.md' = '概览.md.tpl'
    '工作区与构建.md' = '工作区与构建.md.tpl'
    'Git与提交.md' = 'Git与提交.md.tpl'
    '技术专题索引.md' = '技术专题索引.md.tpl'
    '已知问题.md' = '已知问题.md.tpl'
}

$indexContent = [System.IO.File]::ReadAllText($indexPath, $utf8NoBom)
$duplicatePattern = '(?m)^\|\s*' + [regex]::Escape($model) + '\s*\|'
if ([regex]::IsMatch($indexContent, $duplicatePattern)) {
    throw "机型索引已包含 $model，拒绝重复登记。"
}

$statusHeadingPattern = '(?m)^## 资料状态\s*$'
$statusHeadingMatch = [regex]::Match($indexContent, $statusHeadingPattern)
if (-not $statusHeadingMatch.Success) {
    throw "机型索引缺少“## 资料状态”标题，拒绝进行不确定的自动修改。"
}

foreach ($templateFile in $templates.Values) {
    $templatePath = Join-Path $templatesRoot $templateFile
    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
        throw "缺少建档模板：$templatePath"
    }
}

if (-not $PSCmdlet.ShouldProcess($modelDirectory, "创建 $model 的待验证资料骨架并登记机型索引")) {
    return
}

New-Item -ItemType Directory -Path $modelDirectory -ErrorAction Stop | Out-Null

try {
    foreach ($containerName in @('专题', '功能模块', '问题')) {
        New-Item -ItemType Directory -Path (Join-Path $modelDirectory $containerName) -ErrorAction Stop | Out-Null
    }

    foreach ($item in $templates.GetEnumerator()) {
        $templatePath = Join-Path $templatesRoot $item.Value
        $content = [System.IO.File]::ReadAllText($templatePath, $utf8NoBom)
        $content = $content.Replace('{MODEL}', $model)
        $content = $content.Replace('{DISPLAY_NAME}', $displayName)
        $content = $content.Replace('{WORKSPACE}', $workspace)
        $content = $content.Replace('{WORKSPACE_ACCESS}', $workspaceAccess)
        $content = $content.Replace('{CREATED_DATE}', $createdDate)

        $destination = Join-Path $modelDirectory $item.Key
        [System.IO.File]::WriteAllText($destination, $content.TrimEnd() + [Environment]::NewLine, $utf8NoBom)
    }

    $indexRow = '| ' + $model + ' | ' + $workspace + ' | `机型/' + $model + '/` | 初始资料待核验 | 待验证 |'
    $indexBeforeStatus = $indexContent.Substring(0, $statusHeadingMatch.Index).TrimEnd()
    $indexFromStatus = $indexContent.Substring($statusHeadingMatch.Index)
    $updatedIndex = $indexBeforeStatus + [Environment]::NewLine +
        $indexRow + [Environment]::NewLine + [Environment]::NewLine +
        $indexFromStatus
    [System.IO.File]::WriteAllText($indexPath, $updatedIndex.TrimEnd() + [Environment]::NewLine, $utf8NoBom)
} catch {
    if (Test-Path -LiteralPath $modelDirectory) {
        Remove-Item -LiteralPath $modelDirectory -Recurse -Force
    }
    throw
}

Write-Host "已创建机型资料：$modelDirectory"
Write-Host "已登记机型索引：$indexPath"
Write-Host '已创建五个根文件和 专题/、功能模块/、问题/ 三个容器。'
Write-Host '所有新字段均为“待验证”；未写入构建、平台、OTA 或 Git 结论。'

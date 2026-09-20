[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$')]
    [string]$Model,

    [Parameter(Mandatory)]
    [ValidateSet('Topic', 'Module', 'Issue')]
    [string]$Kind,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PageName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Title,

    [ValidateSet('已确认', '部分确认', '待验证')]
    [string]$Status = '待验证',

    [string]$Scope = '待补充'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-TableCell {
    param([Parameter(Mandatory)][string]$Value)

    return (($Value -replace '[\r\n|]', ' ').Trim())
}

function Add-RowBeforeRule {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Row,
        [Parameter(Mandatory)][System.Text.Encoding]$Encoding
    )

    $content = [System.IO.File]::ReadAllText($Path, $Encoding)
    $headingMatch = [regex]::Match($content, '(?m)^## 新增规则\s*$')
    if (-not $headingMatch.Success) {
        throw "索引缺少“## 新增规则”标题，拒绝进行不确定的自动修改：$Path"
    }

    $beforeHeading = $content.Substring(0, $headingMatch.Index).TrimEnd()
    $fromHeading = $content.Substring($headingMatch.Index)
    $updated = $beforeHeading + [Environment]::NewLine +
        $Row + [Environment]::NewLine + [Environment]::NewLine +
        $fromHeading
    [System.IO.File]::WriteAllText($Path, $updated.TrimEnd() + [Environment]::NewLine, $Encoding)
}

$pageName = $PageName.Trim()
if ($pageName -in @('.', '..') -or
    $pageName.EndsWith('.md', [System.StringComparison]::OrdinalIgnoreCase) -or
    $pageName -match '[\\/:*?"<>|]') {
    throw 'PageName 必须是不含路径分隔符和 .md 后缀的安全文件名。'
}

$skillRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$modelsRoot = (Resolve-Path -LiteralPath (Join-Path $skillRoot 'references\机型')).Path
$templatesRoot = Join-Path $skillRoot 'assets\机型建档'
$modelDirectory = [System.IO.Path]::GetFullPath((Join-Path $modelsRoot $Model))
$modelsRootPrefix = $modelsRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

if (-not $modelDirectory.StartsWith($modelsRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "机型目录不在资料根目录内：$modelDirectory"
}

if (-not (Test-Path -LiteralPath $modelDirectory -PathType Container)) {
    throw "未找到机型资料，请先建档：$modelDirectory"
}

$configuration = switch ($Kind) {
    'Topic' {
        @{
            Directory = '专题'
            Template = '专题模板.md.tpl'
            Index = '技术专题索引.md'
            IndexRow = '| {TITLE} | 专题 | `专题/{PAGE}.md` | {SCOPE} | {STATUS} |'
        }
    }
    'Module' {
        @{
            Directory = '功能模块'
            Template = '功能模块模板.md.tpl'
            Index = '技术专题索引.md'
            IndexRow = '| {TITLE} | 功能模块 | `功能模块/{PAGE}.md` | {SCOPE} | {STATUS} |'
        }
    }
    'Issue' {
        @{
            Directory = '问题'
            Template = '复杂问题模板.md.tpl'
            Index = '已知问题.md'
            IndexRow = '| {PAGE} | {TITLE} | {STATUS} | 详见问题页 | `问题/{PAGE}.md` | {SCOPE} |'
        }
    }
}

$targetDirectory = Join-Path $modelDirectory $configuration.Directory
if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
    throw "机型资料缺少容器目录：$targetDirectory"
}

$pagePath = [System.IO.Path]::GetFullPath((Join-Path $targetDirectory ($pageName + '.md')))
$targetPrefix = $targetDirectory.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
if (-not $pagePath.StartsWith($targetPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "目标页面不在指定容器内：$pagePath"
}

if (Test-Path -LiteralPath $pagePath) {
    throw "资料页面已存在，拒绝覆盖：$pagePath"
}

$templatePath = Join-Path $templatesRoot $configuration.Template
$indexPath = Join-Path $modelDirectory $configuration.Index
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
    throw "缺少页面模板：$templatePath"
}
if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
    throw "缺少索引文件：$indexPath"
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$createdDate = (Get-Date).ToString('yyyy-MM-dd')
$safeTitle = ConvertTo-TableCell $Title
$safeScope = ConvertTo-TableCell $Scope
$templateContent = [System.IO.File]::ReadAllText($templatePath, $utf8NoBom)
$pageContent = $templateContent.Replace('{MODEL}', (ConvertTo-TableCell $Model))
$pageContent = $pageContent.Replace('{TITLE}', $safeTitle)
$pageContent = $pageContent.Replace('{STATUS}', $Status)
$pageContent = $pageContent.Replace('{SCOPE}', $safeScope)
$pageContent = $pageContent.Replace('{CREATED_DATE}', $createdDate)
$indexRow = $configuration.IndexRow.Replace('{PAGE}', (ConvertTo-TableCell $pageName))
$indexRow = $indexRow.Replace('{TITLE}', $safeTitle)
$indexRow = $indexRow.Replace('{STATUS}', $Status)
$indexRow = $indexRow.Replace('{SCOPE}', $safeScope)

if (-not $PSCmdlet.ShouldProcess($pagePath, "创建 $Kind 页面并更新 $($configuration.Index)")) {
    return
}

[System.IO.File]::WriteAllText($pagePath, $pageContent.TrimEnd() + [Environment]::NewLine, $utf8NoBom)
try {
    Add-RowBeforeRule -Path $indexPath -Row $indexRow -Encoding $utf8NoBom
} catch {
    Remove-Item -LiteralPath $pagePath -Force -ErrorAction SilentlyContinue
    throw
}

Write-Host "已创建资料页面：$pagePath"
Write-Host "已更新索引：$indexPath"

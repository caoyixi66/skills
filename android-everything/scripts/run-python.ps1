[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$ScriptPath,

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$ArgumentList
)

$ErrorActionPreference = 'Stop'
$python = Join-Path $env:USERPROFILE '.codex\venvs\android-everything\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $python)) {
    throw "Missing persistent Python environment: $python"
}

if ($ScriptPath) {
    & $python $ScriptPath @ArgumentList
} else {
    & $python
}

exit $LASTEXITCODE

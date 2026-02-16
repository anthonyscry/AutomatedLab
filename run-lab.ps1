param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$AppArguments
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$launcher = Join-Path $scriptDir 'Scripts\Run-OpenCodeLab.ps1'

& $launcher @AppArguments

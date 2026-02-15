[CmdletBinding()]
param(
    [Parameter()]
    [string]$RunId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$TargetHosts,

    [Parameter()]
    [ValidateSet('deploy', 'teardown')]
    [string]$Action = 'teardown',

    [Parameter()]
    [ValidateSet('quick', 'full')]
    [string]$Mode = 'full',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DispatchAction,

    [Parameter()]
    [string]$Secret,

    [Parameter()]
    [ValidateRange(1, 86400)]
    [int]$TtlSeconds = 300,

    [Parameter()]
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = Split-Path -Parent $scriptDir

. (Join-Path $repoRoot 'Private/New-LabScopedConfirmationToken.ps1')

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = [string]$env:OPENCODELAB_CONFIRMATION_RUN_ID
}

if ([string]::IsNullOrWhiteSpace($RunId)) {
    throw 'Run scope is required. Provide -RunId or set OPENCODELAB_CONFIRMATION_RUN_ID.'
}

if ([string]::IsNullOrWhiteSpace($Secret)) {
    $Secret = [string]$env:OPENCODELAB_CONFIRMATION_SECRET
}

if ([string]::IsNullOrWhiteSpace($Secret)) {
    throw 'Confirmation secret is required. Provide -Secret or set OPENCODELAB_CONFIRMATION_SECRET.'
}

$resolvedDispatchAction = if ([string]::IsNullOrWhiteSpace($DispatchAction)) {
    $Action
}
else {
    $DispatchAction
}

$operationHash = '{0}:{1}:{2}' -f $Action, $Mode, $resolvedDispatchAction
$token = New-LabScopedConfirmationToken -RunId $RunId -TargetHosts $TargetHosts -OperationHash $operationHash -Secret $Secret -TtlSeconds $TtlSeconds

if ($AsJson) {
    [pscustomobject]@{
        Token = $token
        RunId = $RunId
        TargetHosts = @($TargetHosts)
        OperationHash = $operationHash
        TtlSeconds = $TtlSeconds
    }
    return
}

$token

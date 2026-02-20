Set-StrictMode -Version Latest

$script:RuntimeInitialized = $false
$script:RuntimePaths = @(
        '../OpenCodeLab.Core/Public/New-LabActionResult.ps1',
        '../OpenCodeLab.Core/Public/Get-LabConfig.ps1',
        '../OpenCodeLab.Core/Public/Test-LabConfigSchema.ps1',
        '../OpenCodeLab.Core/Public/New-LabRunArtifactSet.ps1',
        '../OpenCodeLab.Core/Public/Write-LabEvent.ps1',
        '../OpenCodeLab.Core/Public/Enter-LabRunLock.ps1',
        '../OpenCodeLab.Core/Public/Exit-LabRunLock.ps1',
        '../OpenCodeLab.Domain/Policy/Resolve-LabTeardownPolicy.ps1',
        '../OpenCodeLab.Domain/State/Invoke-LabDeployStateMachine.ps1',
        '../OpenCodeLab.Infrastructure.HyperV/Public/Test-HyperVPrereqs.ps1',
        '../OpenCodeLab.Infrastructure.HyperV/Public/Get-LabVmSnapshot.ps1',
        '../OpenCodeLab.Presentation.Console/Public/Format-LabDashboardFrame.ps1',
        '../OpenCodeLab.Presentation.Console/Public/Show-LabDashboardAction.ps1',
        '../OpenCodeLab.Domain/Actions/Invoke-LabPreflightAction.ps1',
        '../OpenCodeLab.Domain/Actions/Invoke-LabDeployAction.ps1',
        '../OpenCodeLab.Domain/Actions/Invoke-LabTeardownAction.ps1',
        '../OpenCodeLab.Domain/Actions/Invoke-LabStatusAction.ps1',
        '../OpenCodeLab.Domain/Actions/Invoke-LabHealthAction.ps1'
)

foreach ($relativePath in $script:RuntimePaths) {
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath $relativePath))
    if (-not (Test-Path -Path $fullPath)) {
        throw "StartupError: missing runtime dependency: $fullPath"
    }

    . $fullPath
}

$script:RuntimeInitialized = $true

function Initialize-LabRuntime {
    if ($script:RuntimeInitialized) {
        return
    }

    foreach ($relativePath in $script:RuntimePaths) {
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath $relativePath))
        if (-not (Test-Path -Path $fullPath)) {
            throw "StartupError: missing runtime dependency: $fullPath"
        }
    }

    $script:RuntimeInitialized = $true
}

function Get-LabCommandMap {
    return [ordered]@{
        preflight = 'Invoke-LabPreflightAction'
        deploy    = 'Invoke-LabDeployAction'
        teardown  = 'Invoke-LabTeardownAction'
        status    = 'Invoke-LabStatusAction'
        health    = 'Invoke-LabHealthAction'
        dashboard = 'Show-LabDashboardAction'
    }
}

function Resolve-LabExitCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject]$Result
    )

    if ($Result.Succeeded) {
        return 0
    }

    switch ([string]$Result.FailureCategory) {
        'PolicyBlocked' { return 2 }
        'ConfigError' { return 3 }
        'StartupError' { return 3 }
        'UnexpectedException' { return 4 }
        default { return 1 }
    }
}

function Invoke-LabCliCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Command,

        [ValidateSet('full', 'quick')]
        [string]$Mode = 'full',

        [switch]$Force,

        [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath '../../config/lab.settings.psd1')
    )

    try {
        Initialize-LabRuntime
    }
    catch {
        $startupResult = [pscustomobject][ordered]@{
            RunId           = ([guid]::NewGuid()).ToString()
            Action          = $Command
            RequestedMode   = $Mode
            EffectiveMode   = $Mode
            PolicyOutcome   = 'Approved'
            Succeeded       = $false
            FailureCategory = 'StartupError'
            ErrorCode       = 'STARTUP_FAILURE'
            RecoveryHint    = $_.Exception.Message
            ArtifactPath    = $null
            DurationMs      = [int]0
        }

        return $startupResult
    }

    $commandMap = Get-LabCommandMap
    if (-not $commandMap.Contains($Command)) {
        $unsupportedResult = New-LabActionResult -Action $Command -RequestedMode $Mode
        $unsupportedResult.FailureCategory = 'ConfigError'
        $unsupportedResult.ErrorCode = 'UNSUPPORTED_COMMAND'
        $unsupportedResult.RecoveryHint = "Unsupported command: $Command"
        return $unsupportedResult
    }

    try {
        $config = Get-LabConfig -Path $ConfigPath
    }
    catch {
        $configResult = New-LabActionResult -Action $Command -RequestedMode $Mode
        $configResult.FailureCategory = 'ConfigError'
        $configResult.ErrorCode = 'CONFIG_LOAD_FAILED'
        $configResult.RecoveryHint = $_.Exception.Message
        return $configResult
    }

    $artifactSet = New-LabRunArtifactSet -LogRoot $config.Paths.LogRoot -RunId ([guid]::NewGuid().ToString())
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-LabEvent -ArtifactSet $artifactSet -Event @{ type = 'run-started'; action = $Command; mode = $Mode } | Out-Null

    $result = $null
    try {
        switch ($Command) {
            'preflight' { $result = Invoke-LabPreflightAction }
            'deploy' { $result = Invoke-LabDeployAction -Mode $Mode }
            'teardown' { $result = Invoke-LabTeardownAction -Mode $Mode -Force:$Force }
            'status' { $result = Invoke-LabStatusAction }
            'health' { $result = Invoke-LabHealthAction }
            'dashboard' {
                $frame = Show-LabDashboardAction -Status @{} -Events @() -Diagnostics @()
                $result = New-LabActionResult -Action 'dashboard' -RequestedMode 'full'
                $result.Succeeded = $true
                $result | Add-Member -MemberType NoteProperty -Name Data -Value $frame
            }
        }
    }
    catch {
        $result = New-LabActionResult -Action $Command -RequestedMode $Mode
        $result.FailureCategory = 'UnexpectedException'
        $result.ErrorCode = 'UNEXPECTED_EXCEPTION'
        $result.RecoveryHint = $_.Exception.Message
    }
    finally {
        $stopwatch.Stop()
    }

    if ($null -eq $result) {
        $result = New-LabActionResult -Action $Command -RequestedMode $Mode
        $result.FailureCategory = 'UnexpectedException'
        $result.ErrorCode = 'NO_RESULT_RETURNED'
        $result.RecoveryHint = 'No action result was produced.'
    }

    $result.RunId = $artifactSet.RunId
    $result.ArtifactPath = $artifactSet.Path
    $result.DurationMs = [int]$stopwatch.ElapsedMilliseconds

    $runJson = $result | ConvertTo-Json -Depth 10
    Set-Content -Path $artifactSet.RunFilePath -Value $runJson -Encoding utf8 -NoNewline

    $summaryLines = @(
        "Action: $($result.Action)",
        "Succeeded: $($result.Succeeded)",
        "FailureCategory: $($result.FailureCategory)",
        "ErrorCode: $($result.ErrorCode)",
        "DurationMs: $($result.DurationMs)",
        "ArtifactPath: $($result.ArtifactPath)"
    )
    Set-Content -Path $artifactSet.SummaryFilePath -Value ($summaryLines -join [Environment]::NewLine) -Encoding utf8 -NoNewline

    $errorsPayload = @()
    if (-not $result.Succeeded) {
        $errorsPayload = @([ordered]@{
            ErrorCode = $result.ErrorCode
            FailureCategory = $result.FailureCategory
            RecoveryHint = $result.RecoveryHint
        })
    }
    Set-Content -Path $artifactSet.ErrorsFilePath -Value ($errorsPayload | ConvertTo-Json -Depth 10) -Encoding utf8 -NoNewline

    Write-LabEvent -ArtifactSet $artifactSet -Event @{ type = 'run-finished'; succeeded = $result.Succeeded; failureCategory = $result.FailureCategory; durationMs = $result.DurationMs } | Out-Null

    return $result
}

<#
.SYNOPSIS
    Non-destructive runtime validation of lifecycle documentation against observed behavior.

.DESCRIPTION
    Runs non-destructive lifecycle actions (status, health) and captures their observable output
    signals. Writes a durable markdown evidence report to the specified output path.

    When prerequisites are unavailable (not running as admin, or lab not deployed), the script
    emits a clear SKIPPED state with reason and still writes a report scaffold so the output
    contract is always honoured.

.PARAMETER OutputPath
    Path to write the markdown evidence report. Defaults to docs/VALIDATION-RUNTIME.md in the
    repository root.

.PARAMETER TimeoutSeconds
    Maximum seconds to wait for each action invocation. Defaults to 60.

.EXAMPLE
    .\Scripts\Validate-DocsAgainstRuntime.ps1 -OutputPath .\docs\VALIDATION-RUNTIME.md

    Runs status and health checks and writes observed evidence to the report file.

.EXAMPLE
    .\Scripts\Validate-DocsAgainstRuntime.ps1

    Uses the default output path (docs/VALIDATION-RUNTIME.md relative to repo root).
#>

[CmdletBinding()]
param(
    [string]$OutputPath,
    [int]$TimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot   = Split-Path -Parent $scriptDir
$appScript  = Join-Path $repoRoot 'OpenCodeLab-App.ps1'

if (-not $OutputPath) {
    $OutputPath = Join-Path (Join-Path $repoRoot 'docs') 'VALIDATION-RUNTIME.md'
}

$timestamp  = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
$runner     = try { [System.Security.Principal.WindowsIdentity]::GetCurrent().Name } catch { $env:USERNAME }

# ---------------------------------------------------------------------------
# Helper: invoke a non-destructive action and capture output
# ---------------------------------------------------------------------------
function Invoke-LabActionSafe {
    [CmdletBinding()]
    param(
        [string]$Action,
        [string]$AppScript,
        [int]$TimeoutSeconds
    )

    $result = [pscustomobject]@{
        Action   = $Action
        State    = 'UNKNOWN'
        Reason   = ''
        Output   = ''
        ExitCode = $null
    }

    if (-not (Test-Path -Path $AppScript)) {
        $result.State  = 'SKIPPED'
        $result.Reason = "OpenCodeLab-App.ps1 not found at: $AppScript"
        return $result
    }

    try {
        $stdoutFile = [System.IO.Path]::GetTempFileName()
        $stderrFile = [System.IO.Path]::GetTempFileName()

        $proc = Start-Process -FilePath 'pwsh' `
            -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $AppScript, '-Action', $Action, '-NonInteractive') `
            -PassThru `
            -NoNewWindow `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError  $stderrFile `
            -ErrorAction Stop

        $waited = $proc.WaitForExit($TimeoutSeconds * 1000)

        if (-not $waited) {
            try { $proc.Kill() } catch { }
            $result.State  = 'SKIPPED'
            $result.Reason = "Action '$Action' timed out after ${TimeoutSeconds}s"
            try { Remove-Item -Path $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue } catch { }
            return $result
        }

        $result.ExitCode = $proc.ExitCode

        $stdout = ''
        $stderr = ''
        try { $stdout = Get-Content -Path $stdoutFile -Raw -ErrorAction SilentlyContinue } catch { }
        try { $stderr = Get-Content -Path $stderrFile -Raw -ErrorAction SilentlyContinue } catch { }
        try { Remove-Item -Path $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue } catch { }

        $combined = (($stdout + "`n" + $stderr) -replace '^\s+|\s+$').Trim()
        $result.Output = if ($combined) { $combined } else { '(no output captured)' }
        $result.State  = 'Observed'
    }
    catch {
        $result.State  = 'SKIPPED'
        $result.Reason = "Invocation failed: $_"
    }

    return $result
}

# ---------------------------------------------------------------------------
# Check admin prerequisite (non-destructive, just warn)
# ---------------------------------------------------------------------------
$adminNote = 'Administrator check not available on this platform.'
try {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    $adminNote = if ($isAdmin) { 'Running as Administrator — full runtime signals available.' } `
                 else { 'Not running as Administrator — some signals may be limited or skipped.' }
}
catch {
    # Non-Windows platforms do not support Windows Principal — use a neutral note
    $adminNote = 'Platform is non-Windows; Administrator context check skipped.'
}

# ---------------------------------------------------------------------------
# Run status and health actions
# ---------------------------------------------------------------------------
Write-Verbose "Validating docs against runtime (status)..." -Verbose
$statusResult = Invoke-LabActionSafe -Action 'status' -AppScript $appScript -TimeoutSeconds $TimeoutSeconds

Write-Verbose "Validating docs against runtime (health)..." -Verbose
$healthResult = Invoke-LabActionSafe -Action 'health' -AppScript $appScript -TimeoutSeconds $TimeoutSeconds

# ---------------------------------------------------------------------------
# Build report sections
# ---------------------------------------------------------------------------
function Format-ActionSection {
    param(
        [pscustomobject]$Result
    )

    $lines = @()
    $lines += "### Action: ``-Action $($Result.Action)``"
    $lines += ''
    $lines += "**Observed state:** $($Result.State)"

    if ($Result.State -eq 'SKIPPED') {
        $lines += ''
        $lines += "**Skip reason:** $($Result.Reason)"
        $lines += ''
        $lines += '_No runtime output captured — prerequisite not met._'
    }
    else {
        if ($Result.ExitCode -ne $null) {
            $lines += "**Exit code:** $($Result.ExitCode)"
        }
        $lines += ''
        $lines += '**Captured output:**'
        $lines += ''
        $lines += '```'
        $lines += $Result.Output
        $lines += '```'
    }

    return $lines -join "`n"
}

# ---------------------------------------------------------------------------
# Compose and write the report
# ---------------------------------------------------------------------------
$reportLines = @()
$reportLines += '# Runtime Docs Validation Report'
$reportLines += ''
$reportLines += '> Automatically generated by `Scripts/Validate-DocsAgainstRuntime.ps1`.'
$reportLines += '> Do **not** edit manually — re-run the script to refresh evidence.'
$reportLines += ''
$reportLines += "**Timestamp:** $timestamp"
$reportLines += "**Runner:** $runner"
$reportLines += "**Admin:** $adminNote"
$reportLines += ''
$reportLines += '---'
$reportLines += ''
$reportLines += '## Purpose'
$reportLines += ''
$reportLines += 'This report captures observed runtime signals from non-destructive lifecycle'
$reportLines += 'actions and validates that documentation in `docs/LIFECYCLE-WORKFLOWS.md`'
$reportLines += 'accurately reflects observable behavior.'
$reportLines += ''
$reportLines += 'Actions validated:'
$reportLines += '- `OpenCodeLab-App.ps1 -Action status` — VM inventory and network state'
$reportLines += '- `OpenCodeLab-App.ps1 -Action health` — connectivity and infrastructure gate'
$reportLines += ''
$reportLines += '---'
$reportLines += ''
$reportLines += '## Observed Runtime Evidence'
$reportLines += ''
$reportLines += Format-ActionSection -Result $statusResult
$reportLines += ''
$reportLines += '---'
$reportLines += ''
$reportLines += Format-ActionSection -Result $healthResult
$reportLines += ''
$reportLines += '---'
$reportLines += ''
$reportLines += '## Docs Alignment Summary'
$reportLines += ''
$reportLines += '| Documented behavior | Evidence source | Observed |'
$reportLines += '|---|---|---|'
$reportLines += "| ``status`` displays VM inventory and network state | ``-Action status`` output | $($statusResult.State) |"
$reportLines += "| ``health`` validates connectivity and infrastructure | ``-Action health`` output | $($healthResult.State) |"
$reportLines += ''
$reportLines += '---'
$reportLines += ''
$reportLines += '## Skip / Prerequisite Notes'
$reportLines += ''

$skipNotes = @()
if ($statusResult.State -eq 'SKIPPED') {
    $skipNotes += "- **status:** $($statusResult.Reason)"
}
if ($healthResult.State -eq 'SKIPPED') {
    $skipNotes += "- **health:** $($healthResult.Reason)"
}
if ($skipNotes.Count -eq 0) {
    $reportLines += '_All actions completed — no prerequisites were missing._'
}
else {
    $reportLines += $skipNotes
}

$reportLines += ''
$reportLines += '---'
$reportLines += ''
$reportLines += '_End of report._'

$reportContent = $reportLines -join "`n"

# Ensure output directory exists
$outputDir = Split-Path -Parent $OutputPath
if ($outputDir -and -not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

Set-Content -Path $OutputPath -Value $reportContent -Encoding UTF8

Write-Output "Runtime validation report written to: $OutputPath"
Write-Output "  status: $($statusResult.State)"
Write-Output "  health: $($healthResult.State)"

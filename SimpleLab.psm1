# SimpleLab.psm1
# SimpleLab Module - Streamlined Windows domain lab automation

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ModuleRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }

# Dot-source functions deterministically to keep import order stable.
$privateFiles = @(Get-ChildItem -Path "$ModuleRoot\Private\*.ps1" -ErrorAction SilentlyContinue | Sort-Object Name)
foreach ($file in $privateFiles) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error "Failed to import private function '$($file.BaseName)': $_"
        throw
    }
}

$publicFiles = @(Get-ChildItem -Path "$ModuleRoot\Public\*.ps1" -ErrorAction SilentlyContinue | Sort-Object Name)
foreach ($file in $publicFiles) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error "Failed to import public function '$($file.BaseName)': $_"
        throw
    }
}

# Export public functions explicitly
Export-ModuleMember -Function @(
    # VM management
    'Connect-LabVM', 'Get-LabCheckpoint', 'Get-LabStatus',
    'Initialize-LabDNS', 'Initialize-LabDomain', 'Initialize-LabNetwork', 'Initialize-LabVMs',
    'Join-LabDomain', 'New-LabSwitch', 'New-LabVM', 'New-LabNAT',
    'Remove-LabSwitch', 'Remove-LabVM', 'Remove-LabVMs', 'Reset-Lab',
    'Restart-LabVM', 'Restart-LabVMs', 'Restore-LabCheckpoint', 'Resume-LabVM',
    'Save-LabCheckpoint', 'Save-LabReadyCheckpoint', 'Show-LabStatus',
    'Start-LabVMs', 'Stop-LabVMs', 'Suspend-LabVM', 'Suspend-LabVMs',
    'Test-HyperVEnabled', 'Test-LabIso', 'Test-LabNetwork', 'Test-LabNetworkHealth',
    'Test-LabCleanup', 'Test-LabDomainHealth', 'Test-LabPrereqs',
    'Wait-LabVMReady', 'Write-RunArtifact', 'Write-ValidationReport', 'New-LabSSHKey',
    # Linux VM helpers (Lab-Common.ps1)
    'Invoke-BashOnLinuxVM', 'New-LinuxVM', 'New-CidataVhdx',
    'Get-Sha512PasswordHash', 'Get-LinuxVMIPv4', 'Finalize-LinuxInstallMedia',
    'Wait-LinuxVMReady', 'Get-LinuxSSHConnectionInfo',
    'Add-LinuxDhcpReservation', 'Join-LinuxToDomain',
    'New-LinuxGoldenVhdx', 'Remove-HyperVVMStale',
    # UX helpers
    'Write-LabStatus'
)

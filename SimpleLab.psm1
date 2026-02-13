# SimpleLab.psm1
# SimpleLab Module - Streamlined Windows domain lab automation

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Dot-source private functions
$PrivateFunctions = Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue
foreach ($file in $PrivateFunctions) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error "Failed to import function $($file.BaseName): $_"
        throw
    }
}

# Dot-source public functions
$PublicFunctions = Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue
foreach ($file in $PublicFunctions) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error "Failed to import function $($file.BaseName): $_"
        throw
    }
}

# Dot-source Lab-Common.ps1 for shared Linux helpers
$labCommonPath = Join-Path $PSScriptRoot 'Lab-Common.ps1'
if (Test-Path $labCommonPath) {
    try { . $labCommonPath }
    catch { Write-Warning "Failed to import Lab-Common.ps1: $_" }
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

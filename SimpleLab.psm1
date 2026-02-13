# SimpleLab.psm1
# SimpleLab Module - Streamlined Windows domain lab automation

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ModuleRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $PSScriptRoot }

$importHelperPath = Join-Path -Path $ModuleRoot -ChildPath 'Private\Import-LabScriptTree.ps1'
if (-not (Test-Path -Path $importHelperPath -PathType Leaf)) {
    throw "Required import helper not found: $importHelperPath"
}

. $importHelperPath

$privateFiles = Get-LabScriptFiles -RootPath $ModuleRoot -RelativePaths @('Private') -ExcludeFileNames @('Import-LabScriptTree.ps1')
foreach ($file in $privateFiles) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to import private function '$($file.FullName)': $($_.Exception.Message)"
    }
}

$publicFiles = Get-LabScriptFiles -RootPath $ModuleRoot -RelativePaths @('Public')
foreach ($file in $publicFiles) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to import public function '$($file.FullName)': $($_.Exception.Message)"
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
    # Linux VM helpers (Public/Linux)
    'Invoke-BashOnLinuxVM', 'New-LinuxVM', 'New-CidataVhdx',
    'Get-Sha512PasswordHash', 'Get-LinuxVMIPv4', 'Finalize-LinuxInstallMedia',
    'Wait-LinuxVMReady', 'Get-LinuxSSHConnectionInfo',
    'Add-LinuxDhcpReservation', 'Join-LinuxToDomain',
    'New-LinuxGoldenVhdx', 'Remove-HyperVVMStale',
    # UX helpers
    'Write-LabStatus'
)

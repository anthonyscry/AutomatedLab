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
    'Join-LabDomain', 'New-LabNAT', 'New-LabSSHKey', 'New-LabSwitch', 'New-LabVM',
    'Remove-LabSwitch', 'Remove-LabVM', 'Remove-LabVMs', 'Reset-Lab',
    'Restart-LabVM', 'Restart-LabVMs', 'Restore-LabCheckpoint', 'Resume-LabVM',
    'Save-LabCheckpoint', 'Save-LabReadyCheckpoint', 'Show-LabStatus',
    'Start-LabVMs', 'Stop-LabVMs', 'Suspend-LabVM', 'Suspend-LabVMs',
    'Test-HyperVEnabled', 'Test-LabDomainHealth', 'Test-LabIso', 'Test-LabNetwork', 'Test-LabNetworkHealth',
    'Wait-LabVMReady', 'Write-LabStatus', 'Write-RunArtifact',
    # Linux VM helpers (Public/Linux)
    'Add-LinuxDhcpReservation', 'Finalize-LinuxInstallMedia', 'Get-LinuxSSHConnectionInfo',
    'Get-LinuxVMIPv4', 'Get-Sha512PasswordHash', 'Invoke-BashOnLinuxVM',
    'Join-LinuxToDomain', 'New-CidataVhdx', 'New-LinuxGoldenVhdx', 'New-LinuxVM',
    'Remove-HyperVVMStale', 'Wait-LinuxVMReady'
)

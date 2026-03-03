param(
    [Parameter(Mandatory=$true)]
    [string]$LabName,
    [Parameter(Mandatory=$true)]
    [string]$LabPath,
    [Parameter(Mandatory=$false)]
    [string]$SwitchName = "LabSwitch",
    [Parameter(Mandatory=$false)]
    [string]$SwitchType = "Internal",
    [Parameter(Mandatory=$false)]
    [bool]$EnableExternalInternetSwitch = $false,
    [Parameter(Mandatory=$false)]
    [string]$ExternalSwitchName = 'DefaultExternal',
    [Parameter(Mandatory=$false)]
    [string]$DomainName = "lab.com",
    [Parameter(Mandatory=$true)]
    [string]$VMsJsonFile,
    [Parameter(Mandatory=$false)]
    [string]$AdminPassword,
    [Parameter(Mandatory=$false)]
    [string]$VMPath = "C:\LabSources\VMs",
    [Parameter(Mandatory=$false)]
    [switch]$Incremental,
    [Parameter(Mandatory=$false)]
    [switch]$UpdateExisting,
    [Parameter(Mandatory=$false)]
    [ValidateSet('abort','shutdown','skip')]
    [string]$OnRunningVMs = 'abort',
    [Parameter(Mandatory=$false)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$ParallelJobTimeoutSeconds = 180,
    [Parameter(Mandatory=$false)]
    [string]$SubnetsJsonFile
)

$ErrorActionPreference = 'Continue'

$subnets = @()
if ($SubnetsJsonFile -and (Test-Path $SubnetsJsonFile)) {
    $subnets = @(Get-Content -Raw $SubnetsJsonFile | ConvertFrom-Json)
    Write-Host "Loaded $($subnets.Count) subnet definition(s) from $SubnetsJsonFile" -ForegroundColor Cyan
}
if ($subnets.Count -eq 0) {
    $subnets = @([pscustomobject]@{
        Name          = 'Default'
        SwitchName    = $LabName
        SwitchType    = 'Internal'
        AddressPrefix = '192.168.10.0/24'
        Gateway       = '192.168.10.1'
        SubnetMask    = '255.255.255.0'
        VLANID        = 0
        EnableNAT     = $true
        NATName       = $null
        DnsServer     = $null
    })
}

$eventsDir = if ($VMsJsonFile) { Split-Path -Parent $VMsJsonFile } else { $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($eventsDir)) { $eventsDir = $PSScriptRoot }
$script:DeployEventsPath = Join-Path -Path $eventsDir -ChildPath 'deployment-events.jsonl'
$deployStart = Get-Date

. "$PSScriptRoot\Deploy-Lab.00-Utilities.ps1"
. "$PSScriptRoot\Deploy-Lab.01-Preflight.ps1"
. "$PSScriptRoot\Deploy-Lab.02-Cleanup.ps1"
. "$PSScriptRoot\Deploy-Lab.03-LabDefinition.ps1"
. "$PSScriptRoot\Deploy-Lab.04-BaseImageEFI.ps1"
. "$PSScriptRoot\Deploy-Lab.05-Installation.ps1"
. "$PSScriptRoot\Deploy-Lab.06-ValidationAndInternet.ps1"

Write-DeployProgress -Percent 0 -Status "Starting deployment: $LabName"

Write-Host "=== OpenCodeLab Deployment (AutomatedLab) ===" -ForegroundColor Cyan
Write-Host "Lab: $LabName"
Write-Host "Domain: $DomainName"
Write-DeployEvent -Type 'deploy.start' -Status 'info' -Message "Deployment started for lab '$LabName'" -Properties @{ labName = $LabName; incremental = [bool]$Incremental; updateExisting = [bool]$UpdateExisting }

$preflightResult = Invoke-DeployPreflight -LabName $LabName -VMsJsonFile $VMsJsonFile -Subnets $subnets -EnableExternalInternetSwitch $EnableExternalInternetSwitch -ExternalSwitchName $ExternalSwitchName
$vms = @($preflightResult.VMs)

$cleanupResult = Invoke-DeployCleanup -LabName $LabName -VMPath $VMPath -VMs $vms -SwitchName $SwitchName -Incremental:$Incremental -UpdateExisting:$UpdateExisting -OnRunningVMs $OnRunningVMs -AdminPassword $AdminPassword -DeployStart $deployStart

if ($cleanupResult.ShouldExit) {
    $exitCode = [int]$cleanupResult.ExitCode
    Write-DeployEvent -Type 'deploy.complete' -Status $(if ($exitCode -eq 0) { 'ok' } else { 'error' }) -Message "Deployment finished with exit code $exitCode" -Properties @{ exitCode = $exitCode; totalMinutes = [math]::Round(((Get-Date) - $deployStart).TotalMinutes, 1) }
    exit $exitCode
}

$labDefResult = Invoke-DeployLabDefinition -LabName $LabName -DomainName $DomainName -AdminPassword $AdminPassword -SwitchName $SwitchName -SwitchType $SwitchType -VMPath $VMPath -VMs $vms -Subnets $subnets -CleanupResult $cleanupResult -EnableExternalInternetSwitch $EnableExternalInternetSwitch -ExternalSwitchName $ExternalSwitchName -Incremental:$Incremental

$skipProvisioning = -not [bool]$labDefResult.InstallLabNeeded
$installError = $null
$vhdxWarnings = @()
$internetPolicyFailures = @()

if ($skipProvisioning) {
    Write-Host 'Skipping AutomatedLab provisioning (update-existing with no new VMs)' -ForegroundColor Yellow
    Write-DeployProgress -Percent 30 -Status 'Provisioning skipped (update-existing, no new VMs)'
}
else {
    Invoke-DeployBaseImageValidation -VMPath $VMPath
    $installResult = Invoke-DeployInstallation -LabName $LabName -AdminPassword $AdminPassword -DomainName $DomainName -VMPath $VMPath -VMs $vms
    $installError = $installResult.InstallError
}

$validationResult = Invoke-DeployValidationAndInternet -LabName $LabName -VMPath $VMPath -VMs $vms -Subnets $subnets -SwitchName $SwitchName -EnableExternalInternetSwitch $EnableExternalInternetSwitch -ExternalSwitchName $ExternalSwitchName -ParallelJobTimeoutSeconds $ParallelJobTimeoutSeconds -SkipVhdxValidation:$skipProvisioning
$vhdxWarnings = @($validationResult.vhdxWarnings)
$internetPolicyFailures = @($validationResult.internetPolicyFailures)

if ($installError -and $vhdxWarnings.Count -gt 0) {
    Write-DeployProgress -Percent 100 -Status 'Deployment finished with errors - check warnings above'
    Write-Host ''
    Write-Host '=== Deployment Finished With Errors ===' -ForegroundColor Red
    Write-Host "Install-Lab error: $($installError.Exception.Message)" -ForegroundColor Red
    Write-Host "VHDX warnings: $($vhdxWarnings.Count)" -ForegroundColor Red
    $exitCode = 1
    Write-DeployEvent -Type 'deploy.complete' -Status $(if ($exitCode -eq 0) { 'ok' } else { 'error' }) -Message "Deployment finished with exit code $exitCode" -Properties @{ exitCode = $exitCode; totalMinutes = [math]::Round(((Get-Date) - $deployStart).TotalMinutes, 1) }
    exit 1
}
elseif ($internetPolicyFailures.Count -gt 0) {
    if ($skipProvisioning) {
        Write-DeployProgress -Percent 100 -Status 'Deployment completed with internet policy warnings'
        Write-Host ''
        Write-Host '=== Deployment Complete (with internet policy warnings) ===' -ForegroundColor Yellow
        Write-Host 'Internet policy warnings (non-fatal in update-existing fast path):' -ForegroundColor Yellow
        foreach ($policyFailure in $internetPolicyFailures) {
            Write-Host "  - $($policyFailure.Name): [$($policyFailure.FailureCategory)] $($policyFailure.ErrorMessage)" -ForegroundColor Yellow
        }
        $exitCode = 0
        Write-DeployEvent -Type 'deploy.complete' -Status $(if ($exitCode -eq 0) { 'ok' } else { 'error' }) -Message "Deployment finished with exit code $exitCode" -Properties @{ exitCode = $exitCode; totalMinutes = [math]::Round(((Get-Date) - $deployStart).TotalMinutes, 1) }
        exit 0
    }

    Write-DeployProgress -Percent 100 -Status 'Deployment finished with internet policy failures'
    Write-Host ''
    Write-Host '=== Deployment Finished With Internet Policy Failures ===' -ForegroundColor Red
    foreach ($policyFailure in $internetPolicyFailures) {
        Write-Host "  - $($policyFailure.Name): [$($policyFailure.FailureCategory)] $($policyFailure.ErrorMessage)" -ForegroundColor Red
    }
    $exitCode = 1
    Write-DeployEvent -Type 'deploy.complete' -Status $(if ($exitCode -eq 0) { 'ok' } else { 'error' }) -Message "Deployment finished with exit code $exitCode" -Properties @{ exitCode = $exitCode; totalMinutes = [math]::Round(((Get-Date) - $deployStart).TotalMinutes, 1) }
    exit 1
}
elseif ($vhdxWarnings.Count -gt 0) {
    Write-DeployProgress -Percent 100 -Status 'Deployment finished with VHDX warnings'
    Write-Host ''
    Write-Host '=== Deployment Complete (with warnings) ===' -ForegroundColor Yellow
    $exitCode = 0
    Write-DeployEvent -Type 'deploy.complete' -Status $(if ($exitCode -eq 0) { 'ok' } else { 'error' }) -Message "Deployment finished with exit code $exitCode" -Properties @{ exitCode = $exitCode; totalMinutes = [math]::Round(((Get-Date) - $deployStart).TotalMinutes, 1) }
    exit 0
}
else {
    Write-DeployProgress -Percent 100 -Status 'Deployment completed successfully!'
    Write-Host ''
    Write-Host '=== Deployment Complete ===' -ForegroundColor Green
    Write-Host 'All VMs are installed, domain-joined, and roles configured.'
    $exitCode = 0
    Write-DeployEvent -Type 'deploy.complete' -Status $(if ($exitCode -eq 0) { 'ok' } else { 'error' }) -Message "Deployment finished with exit code $exitCode" -Properties @{ exitCode = $exitCode; totalMinutes = [math]::Round(((Get-Date) - $deployStart).TotalMinutes, 1) }
    exit 0
}

<#
.SYNOPSIS
    Captures VM state for checkpoint comparison and drift detection.
.DESCRIPTION
    Connects to Hyper-V VMs via PowerShell Direct and captures running services,
    installed software, open ports, local users, scheduled tasks, registry keys,
    and firewall profile state. Output is structured JSON.
.PARAMETER LabName
    Name of the lab whose VMs to scan.
.PARAMETER VMNameFilter
    Optional. Specific VM name to capture (default: all lab VMs).
.PARAMETER OutputPath
    Optional. File path to write JSON output. If omitted, writes to stdout.
.PARAMETER Credential
    PSCredential for VM access.
.EXAMPLE
    .\Invoke-VMStateCapture.ps1 -LabName "MyLab" -Credential $cred -OutputPath "C:\temp\state.json"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$LabName,

    [Parameter(Mandatory = $false)]
    [string]$VMNameFilter,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $true)]
    [PSCredential]$Credential
)

$ErrorActionPreference = 'Stop'

Write-Verbose "Discovering VMs for lab '$LabName'."
$vms = @(Get-VM | Where-Object { $_.Name -like "$LabName*" })

if ($VMNameFilter) {
    Write-Verbose "Applying VM name filter '$VMNameFilter'."
    $vms = @($vms | Where-Object { $_.Name -like $VMNameFilter })
}

if ($vms.Count -eq 0) {
    Write-Warning "No VMs found for LabName '$LabName'."
}

$vmStates = [System.Collections.Generic.List[object]]::new()

foreach ($vm in $vms) {
    if ($vm.State -ne 'Running') {
        $msg = "VM '$($vm.Name)' is not running (State: $($vm.State))."
        Write-Warning $msg
        $vmStates.Add([ordered]@{
                VMName       = $vm.Name
                Reachable    = $false
                CapturedAt   = (Get-Date).ToUniversalTime().ToString('o')
                ErrorMessage = $msg
            })
        continue
    }

    Write-Verbose "Capturing state from VM '$($vm.Name)'."
    try {
        $vmState = Invoke-Command -VMName $vm.Name -Credential $Credential -ScriptBlock {
            param(
                [string]$VmName
            )

            $state = [ordered]@{
                VMName             = $VmName
                Reachable          = $true
                CapturedAt         = (Get-Date).ToUniversalTime().ToString('o')
                RunningServices    = @(Get-Service | Where-Object Status -eq 'Running' | Select-Object -ExpandProperty Name | Sort-Object)
                InstalledSoftware  = @(
                    Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName } |
                    ForEach-Object {
                        [ordered]@{
                            Name        = $_.DisplayName
                            Version     = $_.DisplayVersion
                            Publisher   = $_.Publisher
                            InstallDate = $_.InstallDate
                        }
                    } | Sort-Object { $_.Name }
                )
                OpenPorts          = @(
                    Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty LocalPort -Unique | Sort-Object
                )
                LocalUsers         = @(
                    Get-LocalUser -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty Name | Sort-Object
                )
                ScheduledTasks     = @(
                    Get-ScheduledTask -ErrorAction SilentlyContinue |
                    Where-Object { $_.State -eq 'Ready' -and $_.TaskPath -notlike '\Microsoft\*' } |
                    Select-Object -ExpandProperty TaskName | Sort-Object
                )
                RegistryKeys       = @{}
                FirewallProfile    = (
                    Get-NetFirewallProfile -ErrorAction SilentlyContinue |
                    Where-Object { $_.Enabled -eq $true } |
                    Select-Object -First 1 -ExpandProperty Name
                )
            }

            $regPaths = @(
                @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName'; Name = 'ComputerName' }
                @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'; Name = 'ProductName' }
                @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'; Name = 'CurrentBuild' }
            )

            foreach ($reg in $regPaths) {
                $val = Get-ItemProperty -Path $reg.Path -Name $reg.Name -ErrorAction SilentlyContinue
                if ($val) {
                    $state.RegistryKeys["$($reg.Path)\$($reg.Name)"] = $val.$($reg.Name)
                }
            }

            [pscustomobject]$state
        } -ArgumentList $vm.Name

        $vmStates.Add($vmState)
    }
    catch {
        $msg = "Failed to capture VM '$($vm.Name)': $($_.Exception.Message)"
        Write-Warning $msg
        $vmStates.Add([ordered]@{
                VMName       = $vm.Name
                Reachable    = $false
                CapturedAt   = (Get-Date).ToUniversalTime().ToString('o')
                ErrorMessage = $_.Exception.Message
            })
    }
}

$result = [ordered]@{
    LabName    = $LabName
    CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
    VMStates   = @($vmStates)
}

$json = $result | ConvertTo-Json -Depth 10

if ($OutputPath) {
    $parent = Split-Path -Path $OutputPath -Parent
    if ($parent -and -not (Test-Path -Path $parent)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }

    Set-Content -Path $OutputPath -Value $json -Encoding utf8
    Write-Verbose "VM state written to '$OutputPath'."
}
else {
    Write-Output $json
}

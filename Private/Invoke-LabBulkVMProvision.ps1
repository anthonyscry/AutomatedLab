# Invoke-LabBulkVMProvision.ps1
# Provisions multiple additional server and workstation VMs in bulk.
# VM names are auto-generated sequentially (SVR2, SVR3, ... / WS2, WS3, ...).

function Invoke-LabBulkVMProvision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(0, 100)]
        [int]$ServerCount,

        [Parameter(Mandatory)]
        [ValidateRange(0, 100)]
        [int]$WorkstationCount,

        [string]$ServerIsoPath,
        [string]$WorkstationIsoPath,

        [Parameter(Mandatory)]
        [hashtable]$LabConfig,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$RunEvents
    )

    $total = $ServerCount + $WorkstationCount
    if ($total -eq 0) { return }

    $serverMemoryGB = [int]([math]::Ceiling($LabConfig.VMSizing.Server.Memory / 1GB))
    $workstationMemoryGB = [int]([math]::Ceiling($LabConfig.VMSizing.Client.Memory / 1GB))
    $serverCpu = [int]$LabConfig.VMSizing.Server.Processors
    $workstationCpu = [int]$LabConfig.VMSizing.Client.Processors

    $diskRoot = Join-Path (Join-Path $LabConfig.Paths.LabRoot $LabConfig.Lab.Name) 'Disks'
    if (-not (Test-Path $diskRoot)) {
        New-Item -Path $diskRoot -ItemType Directory -Force | Out-Null
    }

    $existingNames = @()
    try {
        $existingNames = @(Hyper-V\Get-VM -ErrorAction Stop | Select-Object -ExpandProperty Name)
    } catch {
        $existingNames = @()
    }

    $newVmCmd = Get-Command New-LabVM -ErrorAction SilentlyContinue
    if (-not $newVmCmd) {
        throw 'New-LabVM function is not available in this session.'
    }

    for ($i = 0; $i -lt $ServerCount; $i++) {
        $suffix = 2
        while ($existingNames -contains ("SVR{0}" -f $suffix)) { $suffix++ }
        $vmName = "SVR{0}" -f $suffix
        $existingNames += $vmName
        $vhdPath = Join-Path $diskRoot ("{0}.vhdx" -f $vmName)

        if ([string]::IsNullOrWhiteSpace($ServerIsoPath)) {
            $result = New-LabVM -VMName $vmName -MemoryGB $serverMemoryGB -VHDPath $vhdPath -SwitchName $LabConfig.Network.SwitchName -ProcessorCount $serverCpu
        } else {
            $result = New-LabVM -VMName $vmName -MemoryGB $serverMemoryGB -VHDPath $vhdPath -SwitchName $LabConfig.Network.SwitchName -ProcessorCount $serverCpu -IsoPath $ServerIsoPath
        }

        if ($result.Status -eq 'OK' -or $result.Status -eq 'AlreadyExists') {
            Add-LabRunEvent -Step 'setup-add-server-vm' -Status 'ok' -Message ("{0}: {1}" -f $vmName, $result.Status) -RunEvents $RunEvents
            Write-LabStatus -Status OK -Message ("Provisioned server VM {0}: {1}" -f $vmName, $result.Status)
        } else {
            Add-LabRunEvent -Step 'setup-add-server-vm' -Status 'fail' -Message ("{0}: {1} {2}" -f $vmName, $result.Status, $result.Message) -RunEvents $RunEvents
            Write-LabStatus -Status FAIL -Message ("Failed to provision server VM {0}: {1}" -f $vmName, $result.Message)
        }
    }

    for ($i = 0; $i -lt $WorkstationCount; $i++) {
        $suffix = 2
        while ($existingNames -contains ("WS{0}" -f $suffix)) { $suffix++ }
        $vmName = "WS{0}" -f $suffix
        $existingNames += $vmName
        $vhdPath = Join-Path $diskRoot ("{0}.vhdx" -f $vmName)

        if ([string]::IsNullOrWhiteSpace($WorkstationIsoPath)) {
            $result = New-LabVM -VMName $vmName -MemoryGB $workstationMemoryGB -VHDPath $vhdPath -SwitchName $LabConfig.Network.SwitchName -ProcessorCount $workstationCpu
        } else {
            $result = New-LabVM -VMName $vmName -MemoryGB $workstationMemoryGB -VHDPath $vhdPath -SwitchName $LabConfig.Network.SwitchName -ProcessorCount $workstationCpu -IsoPath $WorkstationIsoPath
        }

        if ($result.Status -eq 'OK' -or $result.Status -eq 'AlreadyExists') {
            Add-LabRunEvent -Step 'setup-add-workstation-vm' -Status 'ok' -Message ("{0}: {1}" -f $vmName, $result.Status) -RunEvents $RunEvents
            Write-LabStatus -Status OK -Message ("Provisioned workstation VM {0}: {1}" -f $vmName, $result.Status)
        } else {
            Add-LabRunEvent -Step 'setup-add-workstation-vm' -Status 'fail' -Message ("{0}: {1} {2}" -f $vmName, $result.Status, $result.Message) -RunEvents $RunEvents
            Write-LabStatus -Status FAIL -Message ("Failed to provision workstation VM {0}: {1}" -f $vmName, $result.Message)
        }
    }
}

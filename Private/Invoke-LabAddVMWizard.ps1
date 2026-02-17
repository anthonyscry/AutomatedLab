function Invoke-LabAddVMWizard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Server', 'Workstation')][string]$VMType,
        [Parameter(Mandatory)][hashtable]$LabConfig,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$RunEvents
    )

    $defaultName = if ($VMType -eq 'Server') { 'SVR2' } else { 'WS2' }
    $defaultMemory = if ($VMType -eq 'Server') { 4 } else { 6 }
    $defaultCpu = 2

    $vmNameInput = (Read-Host ("  VM name [{0}]" -f $defaultName)).Trim()
    $vmName = if ([string]::IsNullOrWhiteSpace($vmNameInput)) { $defaultName } else { $vmNameInput }

    $memoryInput = (Read-Host ("  Memory GB [{0}]" -f $defaultMemory)).Trim()
    $memoryGB = $defaultMemory
    if (-not [string]::IsNullOrWhiteSpace($memoryInput)) {
        $parsedMemory = 0
        if ([int]::TryParse($memoryInput, [ref]$parsedMemory) -and $parsedMemory -ge 1) {
            $memoryGB = $parsedMemory
        }
    }

    $cpuInput = (Read-Host ("  CPU count [{0}]" -f $defaultCpu)).Trim()
    $cpuCount = $defaultCpu
    if (-not [string]::IsNullOrWhiteSpace($cpuInput)) {
        $parsedCpu = 0
        if ([int]::TryParse($cpuInput, [ref]$parsedCpu) -and $parsedCpu -ge 1) {
            $cpuCount = $parsedCpu
        }
    }

    $isoPath = (Read-Host '  ISO path (optional, leave blank for none)').Trim()

    $diskRoot = Join-Path (Join-Path $LabConfig.Paths.LabRoot $LabConfig.Lab.Name) 'Disks'
    if (-not (Test-Path $diskRoot)) {
        New-Item -Path $diskRoot -ItemType Directory -Force | Out-Null
    }
    $vhdPath = Join-Path $diskRoot ("{0}.vhdx" -f $vmName)

    Write-Host ''
    Write-Host '  VM plan:' -ForegroundColor Cyan
    Write-Host ("    Type: {0}" -f $VMType) -ForegroundColor Gray
    Write-Host ("    Name: {0}" -f $vmName) -ForegroundColor Gray
    Write-Host ("    MemoryGB: {0}" -f $memoryGB) -ForegroundColor Gray
    Write-Host ("    CPU: {0}" -f $cpuCount) -ForegroundColor Gray
    Write-Host ("    Switch: {0}" -f $LabConfig.Network.SwitchName) -ForegroundColor Gray
    Write-Host ("    VHD: {0}" -f $vhdPath) -ForegroundColor Gray
    if (-not [string]::IsNullOrWhiteSpace($isoPath)) {
        Write-Host ("    ISO: {0}" -f $isoPath) -ForegroundColor Gray
    }

    $confirm = (Read-Host '  Create VM now? (y/n)').Trim().ToLowerInvariant()
    if ($confirm -ne 'y') {
        Write-Host '  VM creation cancelled.' -ForegroundColor Yellow
        return
    }

    $newVmCmd = Get-Command New-LabVM -ErrorAction SilentlyContinue
    if (-not $newVmCmd) {
        Write-Host '  New-LabVM function is not available in this session.' -ForegroundColor Red
        return
    }

    $vmResult = $null
    if ([string]::IsNullOrWhiteSpace($isoPath)) {
        $vmResult = New-LabVM -VMName $vmName -MemoryGB $memoryGB -VHDPath $vhdPath -SwitchName $LabConfig.Network.SwitchName -ProcessorCount $cpuCount
    } else {
        $vmResult = New-LabVM -VMName $vmName -MemoryGB $memoryGB -VHDPath $vhdPath -SwitchName $LabConfig.Network.SwitchName -ProcessorCount $cpuCount -IsoPath $isoPath
    }

    if ($vmResult.Status -eq 'OK' -or $vmResult.Status -eq 'AlreadyExists') {
        Add-LabRunEvent -Step 'add-vm' -Status 'ok' -Message ("Type={0}; VM={1}; Status={2}" -f $VMType, $vmName, $vmResult.Status) -RunEvents $RunEvents
        Write-LabStatus -Status OK -Message $vmResult.Message
    } else {
        Add-LabRunEvent -Step 'add-vm' -Status 'fail' -Message ("Type={0}; VM={1}; Status={2}; Msg={3}" -f $VMType, $vmName, $vmResult.Status, $vmResult.Message) -RunEvents $RunEvents
        Write-LabStatus -Status FAIL -Message $vmResult.Message
    }
}

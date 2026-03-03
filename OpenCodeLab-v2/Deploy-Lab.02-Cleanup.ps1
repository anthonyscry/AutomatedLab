function Invoke-DeployCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LabName,
        [Parameter(Mandatory = $true)]
        [string]$VMPath,
        [Parameter(Mandatory = $true)]
        [array]$VMs,
        [Parameter(Mandatory = $false)]
        [string]$SwitchName,
        [Parameter(Mandatory = $false)]
        [switch]$Incremental,
        [Parameter(Mandatory = $false)]
        [switch]$UpdateExisting,
        [Parameter(Mandatory = $false)]
        [ValidateSet('abort', 'shutdown', 'skip')]
        [string]$OnRunningVMs = 'abort',
        [Parameter(Mandatory = $false)]
        [string]$AdminPassword,
        [Parameter(Mandatory = $false)]
        [datetime]$DeployStart
    )

    $existingVMNames = @()
    foreach ($vm in $VMs) {
        if ([string]::IsNullOrWhiteSpace($vm.Name)) { continue }
        $hvVM = Get-VM -Name $vm.Name -ErrorAction SilentlyContinue
        if ($hvVM) { $existingVMNames += $vm.Name }
    }

    $newVMs = @($VMs | Where-Object { $_.Name -notin $existingVMNames })
    $keepVMs = @($VMs | Where-Object { $_.Name -in $existingVMNames })

    if (-not $UpdateExisting -and -not $Incremental -and $newVMs.Count -eq 0 -and $existingVMNames.Count -gt 0) {
        Write-Host '  [SAFE] All requested VMs already exist. Switching to update-existing mode to preserve existing VMs and disks.' -ForegroundColor Yellow
        $UpdateExisting = $true
        if ($OnRunningVMs -eq 'abort') {
            $OnRunningVMs = 'skip'
        }
    }

    $skipProvisioning = $UpdateExisting -and $newVMs.Count -eq 0
    $requiresAdminPassword = -not $skipProvisioning

    if ($requiresAdminPassword -and [string]::IsNullOrWhiteSpace($AdminPassword)) {
        throw 'AdminPassword is required for domain creation. Set OPENCODELAB_ADMIN_PASSWORD or pass -AdminPassword.'
    }

    $runningExistingVMs = @()
    foreach ($name in $existingVMNames) {
        $hvVM = Get-VM -Name $name -ErrorAction SilentlyContinue
        if ($hvVM -and $hvVM.State -eq 'Running') {
            $runningExistingVMs += $hvVM
        }
    }

    $runningSkipNames = @()
    if ($UpdateExisting -and $runningExistingVMs.Count -gt 0) {
        switch ($OnRunningVMs) {
            'abort' {
                $runningNames = $runningExistingVMs | Select-Object -ExpandProperty Name
                throw "Running VMs detected in update-existing mode (${runningNames -join ', '}). Stop them or rerun with -OnRunningVMs skip/shutdown."
            }
            'shutdown' {
                foreach ($running in $runningExistingVMs) {
                    Write-Host "  [STOP] Turning off running VM: $($running.Name)" -ForegroundColor Yellow
                    Stop-VM -Name $running.Name -TurnOff -Force -ErrorAction SilentlyContinue
                }
                Start-Sleep -Seconds 5
            }
            'skip' {
                if ($newVMs.Count -gt 0) {
                    throw 'OnRunningVMs=skip is not allowed when new VMs must be created. Stop running VMs or use -OnRunningVMs shutdown.'
                }
                $runningSkipNames += $runningExistingVMs | Select-Object -ExpandProperty Name
                Write-Host "  [SKIP] Keeping running VMs as-is (OnRunningVMs=skip): $($runningSkipNames -join ', ')" -ForegroundColor Yellow
            }
        }
    }

    $WillUpdateInPlace = @()
    $WillCreate = @()
    $RequiresRecreate = @()
    $Skipped = @()

    if ($UpdateExisting) {
        Write-DeployProgress -Percent 6 -Status 'Update-existing mode: reconciling existing VM(s)...'
        Write-Host ''
        Write-Host '=== UPDATE EXISTING DEPLOYMENT ===' -ForegroundColor Green
        foreach ($name in $existingVMNames) {
            $hvVM = Get-VM -Name $name -ErrorAction SilentlyContinue
            Write-Host "  [KEEP] $name (State: $($hvVM.State))" -ForegroundColor Green
        }
        if ($newVMs.Count -gt 0) {
            foreach ($vm in $newVMs) {
                Write-Host "  [NEW]  $($vm.Name) ($($vm.Role))" -ForegroundColor Yellow
            }
        }

        foreach ($vm in $newVMs) {
            $vhdDir = "$VMPath\$($vm.Name)"
            if (Test-Path $vhdDir) {
                Write-Host "  Removing stale disk for new VM: $($vm.Name)" -ForegroundColor Yellow
                Remove-Item $vhdDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    elseif ($Incremental -and $existingVMNames.Count -gt 0) {
        Write-DeployProgress -Percent 6 -Status "Incremental mode: keeping $($existingVMNames.Count) existing VM(s)..."
        Write-Host ''
        Write-Host '=== INCREMENTAL DEPLOYMENT ===' -ForegroundColor Green
        foreach ($name in $existingVMNames) {
            $hvVM = Get-VM -Name $name -ErrorAction SilentlyContinue
            Write-Host "  [KEEP] $name (State: $($hvVM.State))" -ForegroundColor Green
        }
        if ($newVMs.Count -gt 0) {
            foreach ($vm in $newVMs) {
                Write-Host "  [NEW]  $($vm.Name) ($($vm.Role))" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host '  No new VMs to create - all VMs already exist' -ForegroundColor Cyan
            Write-DeployProgress -Percent 100 -Status 'All VMs already deployed'
            Write-Host ''
            Write-Host '=== Lab Already Up To Date ===' -ForegroundColor Green

            return @{
                WillCreate                = @($WillCreate)
                WillUpdateInPlace         = @($WillUpdateInPlace)
                RequiresRecreate          = @($RequiresRecreate)
                Skipped                   = @($Skipped)
                IsUpdateExistingFastPath  = $false
                EffectiveUpdateExisting   = [bool]$UpdateExisting
                SkipProvisioning          = [bool]$skipProvisioning
                RequiresAdminPassword     = [bool]$requiresAdminPassword
                ExistingVMNames           = @($existingVMNames)
                NewVMs                    = @($newVMs)
                KeepVMs                   = @($keepVMs)
                RunningSkipNames          = @($runningSkipNames)
                OnRunningVMs              = $OnRunningVMs
                ShouldExit                = $true
                ExitCode                  = 0
                ExitReason                = 'All VMs already deployed'
            }
        }

        foreach ($vm in $newVMs) {
            $vhdDir = "$VMPath\$($vm.Name)"
            if (Test-Path $vhdDir) {
                Write-Host "  Removing stale disk for new VM: $($vm.Name)" -ForegroundColor Yellow
                Remove-Item $vhdDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        Write-DeployProgress -Percent 6 -Status 'Cleaning up previous deployment...'

        try {
            $existingLab = Get-Lab -List -ErrorAction SilentlyContinue | Where-Object { $_ -eq $LabName }
            if ($existingLab) {
                Write-Host "  Removing existing lab: $LabName" -ForegroundColor Yellow
                Remove-Lab -Name $LabName -Confirm:$false -ErrorAction SilentlyContinue
            }
        }
        catch { }

        Write-DeployProgress -Percent 10 -Status 'Removing stale VMs...'

        foreach ($vm in $VMs) {
            $vmName = $vm.Name
            if ([string]::IsNullOrWhiteSpace($vmName)) { continue }
            $existing = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($existing) {
                Write-Host "  Removing VM: $vmName" -ForegroundColor Yellow
                Stop-VM -Name $vmName -TurnOff -Force -ErrorAction SilentlyContinue
                Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
            }
            $vhdDir = "$VMPath\$vmName"
            if (Test-Path $vhdDir) {
                Write-Host "  Removing disk: $vhdDir" -ForegroundColor Yellow
                Remove-Item $vhdDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        Write-DeployProgress -Percent 12 -Status 'Cleaning up stale switches and NAT...'

        $staleSwitch = Get-VMSwitch -Name $LabName -ErrorAction SilentlyContinue
        if ($staleSwitch) {
            Write-Host "  Removing stale virtual switch: $LabName" -ForegroundColor Yellow
            Remove-VMSwitch -Name $LabName -Force -ErrorAction SilentlyContinue
        }

        $staleExtSwitch = Get-VMSwitch -Name "${LabName}External" -ErrorAction SilentlyContinue
        if ($staleExtSwitch) {
            Write-Host "  Removing stale external switch: ${LabName}External" -ForegroundColor Yellow
            Remove-VMSwitch -Name "${LabName}External" -Force -ErrorAction SilentlyContinue
        }

        Get-VMSwitch -Name 'DefaultExternal' -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host '  Removing stale external switch: DefaultExternal' -ForegroundColor Yellow
            Remove-VMSwitch -Name 'DefaultExternal' -Force -ErrorAction SilentlyContinue
        }

        $defaultSwitch = Get-VMSwitch -Name 'Default' -ErrorAction SilentlyContinue
        if ($defaultSwitch -and $defaultSwitch.SwitchType -eq 'Internal') {
            Write-Host "  Removing stale 'Default' switch" -ForegroundColor Yellow
            Remove-VMSwitch -Name 'Default' -Force -ErrorAction SilentlyContinue
        }

        Get-NetNat -ErrorAction SilentlyContinue | Where-Object { $_.InternalIPInterfaceAddressPrefix -like '192.168.10.*' } | ForEach-Object {
            Write-Host "  Removing stale NAT: $($_.Name)" -ForegroundColor Yellow
            Remove-NetNat -Name $_.Name -Confirm:$false -ErrorAction SilentlyContinue
        }

        $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
        $hostsContent = Get-Content $hostsPath
        $vmNameList = @($VMs | ForEach-Object { $_.Name.ToLower() })
        $filtered = $hostsContent | Where-Object {
            $line = $_.Trim().ToLower()
            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { return $true }
            $parts = $line -split '\s+'
            foreach ($part in $parts[1..($parts.Length - 1)]) {
                $hostname = $part.Split('.')[0]
                if ($vmNameList -contains $hostname) { return $false }
            }
            return $true
        }
        Set-Content -Path $hostsPath -Value $filtered -Force
    }

    Write-DeployProgress -Percent 8 -Status 'Checking base images...'

    $existingBases = Get-ChildItem $VMPath -Filter 'BASE_*' -ErrorAction SilentlyContinue
    if ($existingBases) {
        Write-Host "  Keeping $($existingBases.Count) existing base image(s) (reuse speeds deployment)" -ForegroundColor Green
        foreach ($b in $existingBases) {
            Write-Host "    $($b.Name) ($([math]::Round($b.Length/1GB,1))GB)" -ForegroundColor Gray
        }
    }

    $lockFile = 'C:\ProgramData\AutomatedLab\LabDiskDeploymentInProgress.txt'
    if (Test-Path $lockFile) {
        $alRunning = Get-Process -Name 'integratedlab*', 'autolab*' -ErrorAction SilentlyContinue
        if (-not $alRunning) {
            Write-Host '  Removing stale deployment lock file' -ForegroundColor Yellow
            Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        }
    }

    Write-DeployProgress -Percent 15 -Status 'Cleanup complete'
    Write-DeployEvent -Type 'cleanup.complete' -Status 'ok' -Message 'Cleanup phase complete'

    return @{
        WillCreate                = @($WillCreate)
        WillUpdateInPlace         = @($WillUpdateInPlace)
        RequiresRecreate          = @($RequiresRecreate)
        Skipped                   = @($Skipped)
        IsUpdateExistingFastPath  = [bool]$skipProvisioning
        EffectiveUpdateExisting   = [bool]$UpdateExisting
        SkipProvisioning          = [bool]$skipProvisioning
        RequiresAdminPassword     = [bool]$requiresAdminPassword
        ExistingVMNames           = @($existingVMNames)
        NewVMs                    = @($newVMs)
        KeepVMs                   = @($keepVMs)
        RunningSkipNames          = @($runningSkipNames)
        OnRunningVMs              = $OnRunningVMs
        ShouldExit                = $false
        ExitCode                  = 0
        ExitReason                = ''
    }
}

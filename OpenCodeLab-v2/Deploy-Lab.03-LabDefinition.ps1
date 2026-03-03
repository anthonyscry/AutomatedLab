function Update-ExistingVMSettings {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VmName,
        [Parameter(Mandatory = $true)]
        [int]$Processors,
        [Parameter(Mandatory = $true)]
        [int64]$StartupMemoryBytes,
        [Parameter(Mandatory = $true)]
        [string]$SwitchName
    )

    $result = [pscustomobject]@{
        VMName           = $VmName
        UpdatedFields    = @()
        RequiresRecreate = $false
        Reason           = ''
    }

    $vm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
    if (-not $vm) {
        $result.Reason = 'VM not found'
        return $result
    }

    if ($vm.Generation -ne 2) {
        $result.RequiresRecreate = $true
        $result.Reason = 'Generation mismatch requires recreate for safe reconciliation'
        return $result
    }

    try {
        if ($vm.ProcessorCount -ne $Processors) {
            Set-VMProcessor -VMName $VmName -Count $Processors -ErrorAction Stop
            $result.UpdatedFields += 'Processors'
        }

        if ($vm.MemoryStartup -ne $StartupMemoryBytes) {
            $minBytes = [int64][Math]::Max(536870912, [int64]($StartupMemoryBytes / 2))
            $maxBytes = [int64]($StartupMemoryBytes * 2)
            Set-VMMemory -VMName $VmName -StartupBytes $StartupMemoryBytes -DynamicMemoryEnabled $true -MinimumBytes $minBytes -MaximumBytes $maxBytes -ErrorAction Stop
            $result.UpdatedFields += 'Memory'
        }

        $adapter = Get-VMNetworkAdapter -VMName $VmName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($adapter -and $adapter.SwitchName -ne $SwitchName) {
            Connect-VMNetworkAdapter -VMName $VmName -SwitchName $SwitchName -ErrorAction Stop
            $result.UpdatedFields += 'NetworkSwitch'
        }
    }
    catch {
        $result.RequiresRecreate = $true
        $result.Reason = "In-place update failed: $($_.Exception.Message)"
    }

    return $result
}

function Invoke-DeployLabDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LabName,
        [Parameter(Mandatory = $true)]
        [string]$DomainName,
        [Parameter(Mandatory = $false)]
        [string]$AdminPassword,
        [Parameter(Mandatory = $false)]
        [string]$SwitchName,
        [Parameter(Mandatory = $false)]
        [string]$SwitchType,
        [Parameter(Mandatory = $true)]
        [string]$VMPath,
        [Parameter(Mandatory = $true)]
        [array]$VMs,
        [Parameter(Mandatory = $true)]
        [array]$Subnets,
        [Parameter(Mandatory = $true)]
        [hashtable]$CleanupResult,
        [Parameter(Mandatory = $true)]
        [bool]$EnableExternalInternetSwitch,
        [Parameter(Mandatory = $true)]
        [string]$ExternalSwitchName,
        [Parameter(Mandatory = $false)]
        [switch]$Incremental
    )

    $skipProvisioning = [bool]$CleanupResult.SkipProvisioning
    $updateExisting = [bool]$CleanupResult.EffectiveUpdateExisting
    $existingVMNames = @($CleanupResult.ExistingVMNames)
    $newVMs = @($CleanupResult.NewVMs)
    $keepVMs = @($CleanupResult.KeepVMs)
    $runningSkipNames = @($CleanupResult.RunningSkipNames)
    $requiresAdminPassword = [bool]$CleanupResult.RequiresAdminPassword

    $WillUpdateInPlace = @($CleanupResult.WillUpdateInPlace)
    $WillCreate = @($CleanupResult.WillCreate)
    $RequiresRecreate = @($CleanupResult.RequiresRecreate)
    $Skipped = @($CleanupResult.Skipped)

    if ($skipProvisioning) {
        Write-DeployProgress -Percent 16 -Status 'Update-existing fast path (no new VMs)...'

        if ($existingVMNames.Count -gt 0) {
            Import-Lab -Name $LabName -NoValidation -ErrorAction SilentlyContinue
        }

        Write-DeployProgress -Percent 18 -Status 'Reconciling existing VM settings...'

        foreach ($vm in $keepVMs) {
            $vmName = [string]$vm.Name
            if ([string]::IsNullOrWhiteSpace($vmName)) {
                continue
            }

            $hvVM = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            Write-Host "  [EXISTING] $vmName (State: $($hvVM.State))" -ForegroundColor DarkGray

            if ($runningSkipNames -contains $vmName) {
                $Skipped += "${vmName}: running VM kept as-is (OnRunningVMs=skip)"
                Write-Host "    [SKIP] $vmName is running; updates skipped by OnRunningVMs=skip" -ForegroundColor Yellow
                continue
            }

            $memoryBytes = [int64]$vm.MemoryGB * 1GB
            $procCount = 2
            if ($vm.PSObject.Properties['Processors'] -and $vm.Processors -gt 0) {
                $procCount = [int]$vm.Processors
            }

            $reconcile = Update-ExistingVMSettings -VmName $vmName -Processors $procCount -StartupMemoryBytes $memoryBytes -SwitchName $LabName
            Write-DeployEvent -Type 'vm.update' -Status 'info' -Message "Updating existing VM: $vmName"
            if ($reconcile.RequiresRecreate) {
                $RequiresRecreate += "${vmName}: $($reconcile.Reason)"
                Write-Warning "Skipping destructive recreate in update-existing mode for ${vmName}: $($reconcile.Reason)"
            }
            elseif ($reconcile.UpdatedFields.Count -gt 0) {
                $WillUpdateInPlace += "$vmName => $($reconcile.UpdatedFields -join ', ')"
                Write-Host "    [UPDATE] ${vmName}: $($reconcile.UpdatedFields -join ', ')" -ForegroundColor Cyan
            }
            else {
                $Skipped += "${vmName}: already compliant"
            }
        }

        Write-DeployProgress -Percent 20 -Status 'Machine reconciliation complete'

        Write-Host ''
        Write-Host 'Update-existing summary:' -ForegroundColor Cyan
        Write-Host "  WillUpdateInPlace: $($WillUpdateInPlace.Count)" -ForegroundColor Cyan
        Write-Host "  WillCreate: $($WillCreate.Count)" -ForegroundColor Cyan
        Write-Host "  RequiresRecreate: $($RequiresRecreate.Count)" -ForegroundColor Cyan
        Write-Host "  Skipped: $($Skipped.Count)" -ForegroundColor Cyan
        if ($runningSkipNames.Count -gt 0) {
            Write-Host "  Running VMs skipped per OnRunningVMs=skip: $($runningSkipNames -join ', ')" -ForegroundColor Yellow
        }

        Write-Host 'No new VMs detected in update-existing mode. Skipping AutomatedLab provisioning phases.' -ForegroundColor Yellow
    }
    else {
        Write-DeployProgress -Percent 16 -Status 'Creating lab definition...'

        if (($Incremental -or $updateExisting) -and $existingVMNames.Count -gt 0) {
            Import-Lab -Name $LabName -NoValidation -ErrorAction SilentlyContinue
        }
        if (-not (Test-Path $VMPath)) { New-Item -Path $VMPath -ItemType Directory -Force | Out-Null }
        New-LabDefinition -Name $LabName -DefaultVirtualizationEngine HyperV -VmPath $VMPath

        Write-DeployProgress -Percent 17 -Status 'Configuring network...'

        foreach ($subnet in $Subnets) {
            $switchProps = @{ SwitchType = $subnet.SwitchType }
            Add-LabVirtualNetworkDefinition -Name $subnet.SwitchName -AddressSpace $subnet.AddressPrefix -HyperVProperties $switchProps
            Write-Host "  Network: $($subnet.SwitchName) ($($subnet.SwitchType), $($subnet.AddressPrefix))" -ForegroundColor Cyan
        }
        if ($EnableExternalInternetSwitch) {
            Write-Host "  Secondary external adapter mode: enabled (switch: $ExternalSwitchName)" -ForegroundColor Cyan
        }

        if ($requiresAdminPassword) {
            Write-Host "Configuring domain: $DomainName" -ForegroundColor Yellow
            Add-LabDomainDefinition -Name $DomainName -AdminUser dod_admin -AdminPassword $AdminPassword
            Set-LabInstallationCredential -Username dod_admin -Password $AdminPassword
        }
        else {
            Write-Host 'Skipping domain configuration (no new VMs to provision)' -ForegroundColor Yellow
        }

        $PSDefaultParameterValues = @{
            'Add-LabMachineDefinition:Network'         = $Subnets[0].SwitchName
            'Add-LabMachineDefinition:DomainName'      = $DomainName
            'Add-LabMachineDefinition:OperatingSystem' = 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)'
        }

        Write-DeployProgress -Percent 18 -Status 'Adding virtual machine definitions...'

        $serverIP = 10
        $clientIP = 50

        foreach ($vm in $VMs) {
            $vmName = $vm.Name
            if ([string]::IsNullOrWhiteSpace($vmName)) {
                Write-Host '  WARNING: Skipping VM with empty name' -ForegroundColor Yellow
                continue
            }

            $vmAlreadyExists = ($Incremental -or $updateExisting) -and $vmName -in $existingVMNames

            $memoryBytes = [int64]$vm.MemoryGB * 1GB
            $procCount = 2
            if ($vm.PSObject.Properties['Processors'] -and $vm.Processors -gt 0) {
                $procCount = [int]$vm.Processors
            }

            $vmRole = [string]$vm.Role
            if ([string]::IsNullOrWhiteSpace($vmRole)) {
                $vmRole = 'MemberServer'
            }
            else {
                switch ($vmRole.Trim()) {
                    'MS' { $vmRole = 'MemberServer'; break }
                    'Member' { $vmRole = 'MemberServer'; break }
                    'Server' { $vmRole = 'MemberServer'; break }
                    default { $vmRole = $vmRole.Trim() }
                }
            }

            $alRole = $null
            $isClient = $false
            $os = 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)'

            switch -Regex ($vmRole) {
                '^DC$' {
                    $firstDC = @($VMs | Where-Object { $_.Role -eq 'DC' })[0]
                    if ($vm.Name -eq $firstDC.Name) {
                        $alRole = Get-LabMachineRoleDefinition -Role RootDC
                    }
                    else {
                        $alRole = Get-LabMachineRoleDefinition -Role DC
                    }
                }
                'FileServer' { $alRole = Get-LabMachineRoleDefinition -Role FileServer }
                'WebServer' { $alRole = Get-LabMachineRoleDefinition -Role WebServer }
                'SQL' { $alRole = Get-LabMachineRoleDefinition -Role SQLServer2019 }
                'DHCP' { $alRole = Get-LabMachineRoleDefinition -Role DHCP }
                'CA' { $alRole = Get-LabMachineRoleDefinition -Role CaRoot }
                'Client' {
                    $isClient = $true
                    $os = 'Windows 11 Enterprise Evaluation'
                }
                'Router' {
                    $alRole = Get-LabMachineRoleDefinition -Role Routing
                }
                'Firewall' {
                    $alRole = Get-LabMachineRoleDefinition -Role Routing
                }
                'Linux' {
                    $isClient = $false
                    $os = 'Ubuntu 24.04 LTS'
                }
            }

            $vmSubnetName = $null
            if ($vm.PSObject.Properties.Name -contains 'SubnetName' -and $vm.SubnetName) {
                $vmSubnetName = $vm.SubnetName
            }
            $vmSubnet = if ($vmSubnetName) {
                $Subnets | Where-Object { $_.Name -eq $vmSubnetName } | Select-Object -First 1
            }
            else {
                $Subnets | Select-Object -First 1
            }
            if (-not $vmSubnet) { $vmSubnet = $Subnets[0] }

            $subnetBase = ($vmSubnet.AddressPrefix -split '/')[0]
            $subnetBase = $subnetBase -replace '\.\d+$', ''

            if ($isClient) { $ip = "$subnetBase.$clientIP"; $clientIP++ }
            else { $ip = "$subnetBase.$serverIP"; $serverIP++ }

            $additionalSubnets = @()
            if ($vm.PSObject.Properties.Name -contains 'AdditionalSubnets') {
                $additionalSubnets = @($vm.AdditionalSubnets)
            }

            $networkAdapters = $null
            if ($additionalSubnets.Count -gt 0) {
                $adapters = @()
                $adapters += New-LabNetworkAdapterDefinition -VirtualSwitch $vmSubnet.SwitchName -Ipv4Address $ip
                foreach ($addSubnetName in $additionalSubnets) {
                    $addSubnet = $Subnets | Where-Object { $_.Name -eq $addSubnetName } | Select-Object -First 1
                    if ($addSubnet) {
                        $addBase = ($addSubnet.AddressPrefix -split '/')[0] -replace '\.\d+$', ''
                        $addIp = "$addBase.1"
                        $adapters += New-LabNetworkAdapterDefinition -VirtualSwitch $addSubnet.SwitchName -Ipv4Address $addIp
                        Write-Host "    + Additional NIC: $($addSubnet.SwitchName) ($addIp)" -ForegroundColor DarkCyan
                    }
                }
                $networkAdapters = $adapters
            }

            $params = @{
                Name            = $vmName
                Memory          = $memoryBytes
                Processors      = $procCount
                IpAddress       = $ip
                OperatingSystem = $os
            }
            if ($networkAdapters) {
                $params['NetworkAdapter'] = $networkAdapters
                $params.Remove('IpAddress')
            }
            if ($alRole) { $params['Roles'] = $alRole }

            if ($vmAlreadyExists) {
                Write-Host "  [EXISTING] $vmName ($vmRole) - $os, IP: $ip (will be kept)" -ForegroundColor DarkGray
                if ($updateExisting) {
                    if ($runningSkipNames -contains $vmName) {
                        $Skipped += "${vmName}: running VM kept as-is (OnRunningVMs=skip)"
                        Write-Host "    [SKIP] $vmName is running; updates skipped by OnRunningVMs=skip" -ForegroundColor Yellow
                    }
                    else {
                        $reconcile = Update-ExistingVMSettings -VmName $vmName -Processors $procCount -StartupMemoryBytes $memoryBytes -SwitchName $LabName
                        Write-DeployEvent -Type 'vm.update' -Status 'info' -Message "Updating existing VM: $vmName"
                        if ($reconcile.RequiresRecreate) {
                            $RequiresRecreate += "${vmName}: $($reconcile.Reason)"
                            Write-Warning "Skipping destructive recreate in update-existing mode for ${vmName}: $($reconcile.Reason)"
                        }
                        elseif ($reconcile.UpdatedFields.Count -gt 0) {
                            $WillUpdateInPlace += "$vmName => $($reconcile.UpdatedFields -join ', ')"
                            Write-Host "    [UPDATE] ${vmName}: $($reconcile.UpdatedFields -join ', ')" -ForegroundColor Cyan
                        }
                        else {
                            $Skipped += "${vmName}: already compliant"
                        }
                    }
                }
            }
            else {
                Write-Host "  $vmName ($vmRole) - $os, ${procCount}CPU, $($vm.MemoryGB)GB RAM, IP: $ip" -ForegroundColor Cyan
                $WillCreate += $vmName
            }

            Write-DeployEvent -Type 'vm.define' -Status 'info' -Message "Defining VM: $vmName" -Properties @{ vmName = $vmName; role = $vmRole; ip = $ip }
            Add-LabMachineDefinition @params
        }

        Write-DeployProgress -Percent 20 -Status 'Machine definitions complete'

        if ($updateExisting) {
            Write-Host ''
            Write-Host 'Update-existing summary:' -ForegroundColor Cyan
            Write-Host "  WillUpdateInPlace: $($WillUpdateInPlace.Count)" -ForegroundColor Cyan
            Write-Host "  WillCreate: $($WillCreate.Count)" -ForegroundColor Cyan
            Write-Host "  RequiresRecreate: $($RequiresRecreate.Count)" -ForegroundColor Cyan
            Write-Host "  Skipped: $($Skipped.Count)" -ForegroundColor Cyan
        }
        if ($updateExisting -and $runningSkipNames.Count -gt 0) {
            Write-Host "  Running VMs skipped per OnRunningVMs=skip: $($runningSkipNames -join ', ')" -ForegroundColor Yellow
        }
    }

    Write-DeployEvent -Type 'labdef.complete' -Status 'ok' -Message 'Lab definition created'

    return @{
        InstallLabNeeded    = (-not $skipProvisioning)
        WillCreate          = @($WillCreate)
        WillUpdateInPlace   = @($WillUpdateInPlace)
        RequiresRecreate    = @($RequiresRecreate)
        Skipped             = @($Skipped)
    }
}

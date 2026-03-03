function Set-VMInternetPolicy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VmName,
        [Parameter(Mandatory = $true)]
        [bool]$EnableHostInternet,
        [Parameter(Mandatory = $false)]
        [string]$Gateway = '192.168.10.1'
    )

    $modeLabel = if ($EnableHostInternet) { 'enabled' } else { 'disabled' }
    Write-Host "  [NET] Applying host internet policy to ${VmName}: $modeLabel" -ForegroundColor Cyan

    try {
        $hvVm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
        if (-not $hvVm) {
            $msg = 'VM not found'
            Write-Warning "Could not apply internet policy for ${VmName}: $msg"
            return [pscustomobject]@{
                VMName       = $VmName
                Succeeded    = $false
                ErrorMessage = $msg
                Details      = @()
            }
        }

        if ($hvVm.State -ne 'Running') {
            Start-VM -Name $VmName -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Seconds 20
        }

        $vmReadyTimeoutMinutes = 5
        $vmReadyPostDelaySeconds = 15
        try {
            Wait-LabVM -ComputerName $VmName -TimeoutInMinutes $vmReadyTimeoutMinutes -PostDelaySeconds $vmReadyPostDelaySeconds -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Warning "Wait-LabVM readiness check failed for ${VmName}: $($_.Exception.Message)"
        }

        $commandRetries = 4
        $retryDelaySeconds = 10
        $commandOutput = @()
        for ($attempt = 1; $attempt -le $commandRetries; $attempt++) {
            try {
                $commandOutput = @(Invoke-LabCommand -ComputerName $VmName -ActivityName 'Apply host internet policy' -ScriptBlock {
                    param($AllowInternet, $NatGateway)

                    $defaultRoutes = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                        Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' })

                    foreach ($route in $defaultRoutes) {
                        Remove-NetRoute -AddressFamily IPv4 -DestinationPrefix $route.DestinationPrefix -InterfaceIndex $route.InterfaceIndex -NextHop $route.NextHop -Confirm:$false -ErrorAction SilentlyContinue
                    }

                    if ($AllowInternet) {
                        $nic = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
                            Where-Object {
                                $_.IPv4Address -and
                                $_.IPv4Address.IPAddress -like '192.168.10.*' -and
                                $_.NetAdapter -and
                                $_.NetAdapter.Status -eq 'Up'
                            } |
                            Select-Object -First 1

                        if (-not $nic) {
                            $nic = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
                                Where-Object { $_.IPv4Address -and $_.IPv4Address.IPAddress -like '192.168.10.*' } |
                                Select-Object -First 1
                        }

                        if (-not $nic) {
                            throw 'No adapter found in 192.168.10.0/24 for NAT default route enforcement.'
                        }

                        $routeApplyRetries = 3
                        $routeSet = $false

                        for ($attempt = 1; $attempt -le $routeApplyRetries; $attempt++) {
                            New-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -InterfaceIndex $nic.InterfaceIndex -NextHop $NatGateway -RouteMetric 25 -ErrorAction SilentlyContinue | Out-Null
                            Start-Sleep -Seconds 2

                            $hasExpectedRoute = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -PolicyStore ActiveStore -ErrorAction SilentlyContinue |
                                Where-Object { $_.InterfaceIndex -eq $nic.InterfaceIndex -and $_.NextHop -eq $NatGateway }

                            if ($hasExpectedRoute) {
                                $routeSet = $true
                                break
                            }
                        }

                        if (-not $routeSet) {
                            $observedRoutes = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -PolicyStore ActiveStore -ErrorAction SilentlyContinue |
                                Where-Object { $_.InterfaceIndex -eq $nic.InterfaceIndex } |
                                Select-Object -First 5)

                            $routeSummary = if ($observedRoutes.Count -gt 0) {
                                ($observedRoutes | ForEach-Object { "$($_.DestinationPrefix) via $($_.NextHop) (metric $($_.RouteMetric))" }) -join '; '
                            }
                            else {
                                'none'
                            }

                            throw "Failed to set default route via $NatGateway on interface $($nic.InterfaceAlias) index $($nic.InterfaceIndex). Active routes: $routeSummary"
                        }

                        "Host internet enabled via $NatGateway"
                    }
                    else {
                        'Host internet disabled (default routes removed)'
                    }
                } -ArgumentList $EnableHostInternet, $Gateway -ErrorAction Stop)
                break
            }
            catch {
                $errorMessage = [string]$_.Exception.Message
                $isTransientRemotingError =
                    $errorMessage -match 'port is closed' -or
                    $errorMessage -match 'Connecting to remote server' -or
                    $errorMessage -match 'WinRM' -or
                    $errorMessage -match 'Access is denied'

                if ($attempt -lt $commandRetries -and $isTransientRemotingError) {
                    Write-Warning "Transient remoting error for ${VmName} (attempt $attempt/$commandRetries): $errorMessage"
                    Start-Sleep -Seconds $retryDelaySeconds
                    continue
                }

                throw
            }
        }

        $commandOutput | ForEach-Object {
            Write-Host "    $_" -ForegroundColor Gray
        }

        return [pscustomobject]@{
            VMName       = $VmName
            Succeeded    = $true
            ErrorMessage = ''
            Details      = @($commandOutput)
        }
    }
    catch {
        $msg = $_.Exception.Message
        Write-Warning "Could not apply internet policy for ${VmName}: $msg"
        return [pscustomobject]@{
            VMName       = $VmName
            Succeeded    = $false
            ErrorMessage = $msg
            Details      = @()
        }
    }
}

function Initialize-VMExternalInternetAdapter {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VmName,
        [Parameter(Mandatory = $true)]
        [string]$ExternalSwitchName
    )

    try {
        $switch = Get-VMSwitch -Name $ExternalSwitchName -ErrorAction SilentlyContinue
        if (-not $switch) {
            return [pscustomobject]@{
                Succeeded = $false
                Message   = "External switch '$ExternalSwitchName' not found"
            }
        }

        if ($switch.SwitchType -ne 'External') {
            return [pscustomobject]@{
                Succeeded = $false
                Message   = "Switch '$ExternalSwitchName' is '$($switch.SwitchType)', expected External"
            }
        }

        $vm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
        if (-not $vm) {
            return [pscustomobject]@{
                Succeeded = $false
                Message   = 'VM not found'
            }
        }

        $existing = Get-VMNetworkAdapter -VMName $VmName -ErrorAction SilentlyContinue |
            Where-Object { $_.SwitchName -eq $ExternalSwitchName } |
            Select-Object -First 1

        if ($existing) {
            return [pscustomobject]@{
                Succeeded = $true
                Message   = 'External adapter already present'
            }
        }

        Add-VMNetworkAdapter -VMName $VmName -SwitchName $ExternalSwitchName -Name 'Internet' -ErrorAction Stop | Out-Null

        $attached = Get-VMNetworkAdapter -VMName $VmName -ErrorAction SilentlyContinue |
            Where-Object { $_.SwitchName -eq $ExternalSwitchName } |
            Select-Object -First 1

        if (-not $attached) {
            return [pscustomobject]@{
                Succeeded = $false
                Message   = 'External adapter attach verification failed'
            }
        }

        return [pscustomobject]@{
            Succeeded = $true
            Message   = "Attached external adapter on '$ExternalSwitchName'"
        }
    }
    catch {
        return [pscustomobject]@{
            Succeeded = $false
            Message   = $_.Exception.Message
        }
    }
}

function Initialize-HostNatForLabNetwork {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LabName,
        [Parameter(Mandatory = $false)]
        [string]$AddressPrefix = '192.168.10.0/24'
    )

    try {
        $existingByPrefix = Get-NetNat -ErrorAction SilentlyContinue |
            Where-Object { $_.InternalIPInterfaceAddressPrefix -eq $AddressPrefix } |
            Select-Object -First 1

        if ($existingByPrefix) {
            Write-Host "  [NET] Host NAT already available: $($existingByPrefix.Name) ($AddressPrefix)" -ForegroundColor DarkGray
            return [pscustomobject]@{
                Succeeded = $true
                Message   = 'Existing NAT found'
            }
        }

        $natName = "${LabName}NAT"
        $existingByName = Get-NetNat -Name $natName -ErrorAction SilentlyContinue
        if ($existingByName -and $existingByName.InternalIPInterfaceAddressPrefix -ne $AddressPrefix) {
            $natName = "${natName}-19216810"
        }

        Write-Host "  [NET] Creating host NAT '$natName' for $AddressPrefix" -ForegroundColor Cyan
        New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix $AddressPrefix -ErrorAction Stop | Out-Null

        return [pscustomobject]@{
            Succeeded = $true
            Message   = "Created NAT '$natName'"
        }
    }
    catch {
        return [pscustomobject]@{
            Succeeded = $false
            Message   = $_.Exception.Message
        }
    }
}

function Invoke-DeployValidationAndInternet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LabName,
        [Parameter(Mandatory = $true)]
        [string]$VMPath,
        [Parameter(Mandatory = $true)]
        [array]$VMs,
        [Parameter(Mandatory = $true)]
        [array]$Subnets,
        [Parameter(Mandatory = $false)]
        [string]$SwitchName,
        [Parameter(Mandatory = $true)]
        [bool]$EnableExternalInternetSwitch,
        [Parameter(Mandatory = $true)]
        [string]$ExternalSwitchName,
        [Parameter(Mandatory = $false)]
        [int]$ParallelJobTimeoutSeconds = 180,
        [Parameter(Mandatory = $false)]
        [switch]$SkipVhdxValidation
    )

    $vhdxWarnings = @()
    if (-not $SkipVhdxValidation) {
        Write-DeployProgress -Percent 81 -Status 'Validating VM disk images...'

        $vhdxRoot = $VMPath

        foreach ($vm in $VMs) {
            $vmName = $vm.Name
            $vmDir = Join-Path $vhdxRoot $vmName

            $hvVM = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if (-not $hvVM) {
                $vhdxWarnings += "VM '$vmName' was NOT created by Install-Lab"
                Write-Host "  [FAIL] VM '$vmName' not found" -ForegroundColor Red
                continue
            }
            Write-Host "  [OK] VM '$vmName' exists (State: $($hvVM.State))" -ForegroundColor Green

            if (Test-Path $vmDir) {
                $vhdxFiles = Get-ChildItem $vmDir -Filter '*.vhdx' -ErrorAction SilentlyContinue
                foreach ($vhdxFile in $vhdxFiles) {
                    $sizeMB = [math]::Round($vhdxFile.Length / 1MB)
                    if ($sizeMB -lt 500) {
                        $msg = "VM '$vmName' disk '$($vhdxFile.Name)' is only ${sizeMB}MB - OS installation likely failed!"
                        $vhdxWarnings += $msg
                        Write-Host "  [WARN] $msg" -ForegroundColor Red

                        try {
                            $vhdInfo = Get-VHD -Path $vhdxFile.FullName -ErrorAction Stop
                            if ($vhdInfo.ParentPath) {
                                $parentExists = Test-Path $vhdInfo.ParentPath
                                Write-Host "    Type: $($vhdInfo.VhdType), Parent: $($vhdInfo.ParentPath) (exists: $parentExists)" -ForegroundColor Yellow
                                if (-not $parentExists) {
                                    $vhdxWarnings += "Parent VHDX missing for '$vmName': $($vhdInfo.ParentPath)"
                                    Write-Host '    ERROR: Parent VHDX is missing! Differencing disk chain is broken.' -ForegroundColor Red
                                }
                            }
                        }
                        catch {
                            Write-Host "    Could not inspect VHDX: $_" -ForegroundColor Yellow
                        }
                    }
                    else {
                        $sizeGB = [math]::Round($sizeMB / 1024, 1)
                        Write-Host "  [OK] '$vmName' disk: ${sizeGB}GB ($($vhdxFile.Name))" -ForegroundColor Green
                    }
                }
            }

            if ($hvVM.Generation -eq 2) {
                $firmware = Get-VMFirmware -VMName $vmName -ErrorAction SilentlyContinue
                if ($firmware -and $firmware.BootOrder.Count -gt 0) {
                    $firstBoot = $firmware.BootOrder[0].BootType
                    Write-Host "    Boot order[0]: $firstBoot" -ForegroundColor Gray
                }
                $dvd = Get-VMDvdDrive -VMName $vmName -ErrorAction SilentlyContinue
                if ($dvd -and $dvd.Path) {
                    Write-Host "    DVD: $($dvd.Path)" -ForegroundColor Gray
                }
            }
        }

        if ($vhdxWarnings.Count -gt 0) {
            Write-Host ''
            Write-Host '=== VHDX VALIDATION WARNINGS ===' -ForegroundColor Red
            foreach ($w in $vhdxWarnings) {
                Write-Host "  - $w" -ForegroundColor Red
            }
            Write-Host ''
            Write-Host 'Troubleshooting:' -ForegroundColor Yellow
            Write-Host "  1. Run: Get-LabAvailableOperatingSystem -Path 'C:\LabSources\ISOs'" -ForegroundColor Yellow
            Write-Host '  2. Verify OS names match exactly (case-sensitive)' -ForegroundColor Yellow
            Write-Host "  3. Check $VMPath for BASE_*.vhdx files" -ForegroundColor Yellow
            Write-Host '  4. Re-run deployment to recreate from scratch' -ForegroundColor Yellow
        }

        Write-DeployProgress -Percent 85 -Status 'VHDX validation complete'
        Write-DeployEvent -Type 'vhdx.validation' -Status $(if ($vhdxWarnings.Count -gt 0) { 'warning' } else { 'ok' }) -Message 'VHDX validation complete' -Properties @{ warningCount = $vhdxWarnings.Count }
    }

    Write-DeployProgress -Percent 86 -Status 'Applying per-VM internet policy...'

    $internetPolicyTargets = @()
    foreach ($vm in $VMs) {
        if ([string]::IsNullOrWhiteSpace($vm.Name)) {
            continue
        }

        $internetEnabled = $false
        if ($vm.PSObject.Properties.Name -contains 'EnableHostInternet') {
            $internetEnabled = [bool]$vm.EnableHostInternet
        }

        $vmRole = if ($vm.PSObject.Properties.Name -contains 'Role') {
            [string]$vm.Role
        }
        else {
            ''
        }

        $normalizedRole = if ([string]::IsNullOrWhiteSpace($vmRole)) {
            ''
        }
        else {
            $vmRole.Trim().ToUpperInvariant()
        }

        $isDomainController = $normalizedRole -eq 'DC' -or $normalizedRole -eq 'ROOTDC'

        $internetPolicyTargets += [pscustomobject]@{
            VMName                   = [string]$vm.Name
            LabName                  = [string]$LabName
            IsDomainController       = $isDomainController
            EnableHostInternet       = $internetEnabled
            UseExternalInternetSwitch = $EnableExternalInternetSwitch -and $internetEnabled
            Gateway                  = if ($vm.PSObject.Properties.Name -contains 'SubnetName' -and $vm.SubnetName) {
                $matchSub = $Subnets | Where-Object { $_.Name -eq $vm.SubnetName } | Select-Object -First 1
                if ($matchSub) { $matchSub.Gateway } else { '192.168.10.1' }
            }
            else { '192.168.10.1' }
        }
    }

    if (-not $EnableExternalInternetSwitch) {
        $internetEnabledNonDcTargets = @($internetPolicyTargets | Where-Object { $_.EnableHostInternet -and -not $_.IsDomainController })
        $dcTargetsNeedingDnsEgress = @($internetPolicyTargets | Where-Object { $_.IsDomainController -and -not $_.EnableHostInternet -and -not $_.UseExternalInternetSwitch })

        if ($internetEnabledNonDcTargets.Count -gt 0 -and $dcTargetsNeedingDnsEgress.Count -gt 0) {
            foreach ($dcTarget in $dcTargetsNeedingDnsEgress) {
                Write-Warning "Auto-enabling host internet on domain controller '$($dcTarget.VMName)' so domain DNS can resolve external names for internet-enabled member VMs."
                $dcTarget.EnableHostInternet = $true
            }
        }
    }

    $internetPolicyFailures = @()

    $requiresHostInternet = $internetPolicyTargets | Where-Object { $_.EnableHostInternet -and -not $_.UseExternalInternetSwitch }
    $hostNatReady = $true
    if (@($requiresHostInternet).Count -gt 0) {
        $natResult = @{ Succeeded = $true }
        foreach ($subnet in ($Subnets | Where-Object { $_.EnableNAT -eq $true })) {
            $subNatResult = Initialize-HostNatForLabNetwork -LabName $subnet.SwitchName -AddressPrefix $subnet.AddressPrefix
            if (-not $subNatResult.Succeeded) {
                $natResult = $subNatResult
                break
            }
            Write-Host "  [NET][OK] Host NAT ready for $($subnet.AddressPrefix)" -ForegroundColor Green
        }
        if (-not $natResult.Succeeded) {
            $hostNatReady = $false
            Write-Warning "Host NAT setup failed [ExecutionError]: $($natResult.Message)"
        }
        else {
            $hostNatReady = $true
        }
    }

    foreach ($item in $internetPolicyTargets) {
        if ($item.UseExternalInternetSwitch) {
            Write-Host "  [NET] External internet mode for $($item.VMName): switch '$ExternalSwitchName'" -ForegroundColor Cyan

            $clearPolicyResult = Set-VMInternetPolicy -VmName $item.VMName -EnableHostInternet $false -Gateway $item.Gateway
            if (-not ($clearPolicyResult -and $clearPolicyResult.Succeeded)) {
                $clearError = if ($clearPolicyResult -and $clearPolicyResult.ErrorMessage) {
                    [string]$clearPolicyResult.ErrorMessage
                }
                else {
                    'Failed to clear host NAT route before external adapter attach.'
                }

                $failure = [pscustomobject]@{
                    Name            = "internet-policy-$($item.VMName)"
                    FailureCategory = 'ExecutionError'
                    ErrorMessage    = $clearError
                }
                $internetPolicyFailures += $failure
                Write-Warning "Internet policy failed for $($failure.Name) [$($failure.FailureCategory)]: $($failure.ErrorMessage)"
                Write-DeployEvent -Type 'internet.policy.fail' -Status 'error' -Message 'Internet policy failed for VM' -Properties @{ vmName = $item.VMName }
                continue
            }

            $externalAdapterResult = Initialize-VMExternalInternetAdapter -VmName $item.VMName -ExternalSwitchName $ExternalSwitchName
            if ($externalAdapterResult.Succeeded) {
                Write-Host "  [NET][OK] $($item.VMName) external adapter ($ExternalSwitchName)" -ForegroundColor Green
                continue
            }

            $failure = [pscustomobject]@{
                Name            = "external-nic-$($item.VMName)"
                FailureCategory = 'ExecutionError'
                ErrorMessage    = [string]$externalAdapterResult.Message
            }
            $internetPolicyFailures += $failure
            Write-Warning "Internet policy failed for $($failure.Name) [$($failure.FailureCategory)]: $($failure.ErrorMessage)"
            Write-DeployEvent -Type 'internet.policy.fail' -Status 'error' -Message 'Internet policy failed for VM' -Properties @{ vmName = $item.VMName }
            continue
        }

        if (-not $hostNatReady -and $item.EnableHostInternet -and -not $item.UseExternalInternetSwitch) {
            $failure = [pscustomobject]@{
                Name            = "internet-policy-$($item.VMName)"
                FailureCategory = 'ExecutionError'
                ErrorMessage    = 'Skipped because host NAT setup for 192.168.10.0/24 failed.'
            }
            $internetPolicyFailures += $failure
            Write-Warning "Internet policy failed for $($failure.Name) [$($failure.FailureCategory)]: $($failure.ErrorMessage)"
            Write-DeployEvent -Type 'internet.policy.fail' -Status 'error' -Message 'Internet policy failed for VM' -Properties @{ vmName = $item.VMName }
            continue
        }

        $policyResult = Set-VMInternetPolicy -VmName $item.VMName -EnableHostInternet $item.EnableHostInternet -Gateway $item.Gateway

        if ($policyResult -and $policyResult.Succeeded) {
            Write-Host "  [NET][OK] $($policyResult.VMName)" -ForegroundColor Green
            continue
        }

        $errorMessage = if ($policyResult -and $policyResult.ErrorMessage) {
            [string]$policyResult.ErrorMessage
        }
        else {
            'Unknown error'
        }

        $failure = [pscustomobject]@{
            Name            = "internet-policy-$($item.VMName)"
            FailureCategory = 'ExecutionError'
            ErrorMessage    = $errorMessage
        }

        $internetPolicyFailures += $failure
        Write-Warning "Internet policy failed for $($failure.Name) [$($failure.FailureCategory)]: $($failure.ErrorMessage)"
        Write-DeployEvent -Type 'internet.policy.fail' -Status 'error' -Message 'Internet policy failed for VM' -Properties @{ vmName = $item.VMName }
    }

    if ($internetPolicyFailures.Count -gt 0) {
        Write-Host "  [NET] Failed internet policy jobs: $($internetPolicyFailures.Count)" -ForegroundColor Yellow
    }
    Write-DeployEvent -Type 'internet.policy' -Status $(if ($internetPolicyFailures.Count -gt 0) { 'warning' } else { 'ok' }) -Message 'Internet policy enforcement complete' -Properties @{ failureCount = $internetPolicyFailures.Count }

    Write-DeployProgress -Percent 88 -Status 'Generating deployment summary...'

    Write-Host ''
    try {
        Show-LabDeploymentSummary
    }
    catch {
        Write-Host "  Could not generate AutomatedLab summary: $_" -ForegroundColor Yellow
    }

    Write-DeployProgress -Percent 95 -Status 'Deployment summary complete'

    return @{
        vhdxWarnings          = @($vhdxWarnings)
        internetPolicyFailures = @($internetPolicyFailures)
    }
}

function Test-DCPromotionPrereqs {
    <#
    .SYNOPSIS
        Tests prerequisites for domain controller promotion.

    .DESCRIPTION
        Validates that the VM is running, has the ADDSDeployment module,
        and has network connectivity. Uses PowerShell Direct for in-VM checks.

    .PARAMETER VMName
        Name of the VM to test (default: "dc1").

    .OUTPUTS
        PSCustomObject with VMName, CanPromote (bool), Status, Message, and Checks array.

    .EXAMPLE
        $prereqs = Test-DCPromotionPrereqs -VMName "dc1"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$VMName = "dc1"
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        VMName = $VMName
        CanPromote = $false
        Status = "Failed"
        Message = ""
        Checks = @()
        Duration = $null
    }

    try {
        # Check 1: Hyper-V module available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            $result.Status = "NoHyperV"
            $result.Message = "Hyper-V module is not available"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Check 2: VM exists and is running
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if ($null -eq $vm) {
            $result.Status = "NotFound"
            $result.Message = "VM '$VMName' does not exist"
            $result.Checks += [PSCustomObject]@{
                Name = "VMExists"
                Status = "Fail"
                Message = "VM '$VMName' not found"
            }
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        if ($vm.State -ne "Running") {
            $result.Status = "NotRunning"
            $result.Message = "VM '$VMName' is not running (State: $($vm.State))"
            $result.Checks += [PSCustomObject]@{
                Name = "VMState"
                Status = "Fail"
                Message = "VM state is '$($vm.State)', expected 'Running'"
            }
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        $result.Checks += [PSCustomObject]@{
            Name = "VMState"
            Status = "Pass"
            Message = "VM is running"
        }

        # Check 3: VM Heartbeat (responsive)
        if ($vm.Heartbeat -ne "Ok") {
            $result.Status = "NoHeartbeat"
            $result.Message = "VM '$VMName' is not responsive (Heartbeat: $($vm.Heartbeat))"
            $result.Checks += [PSCustomObject]@{
                Name = "Heartbeat"
                Status = "Fail"
                Message = "VM heartbeat is '$($vm.Heartbeat)', expected 'Ok'"
            }
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        $result.Checks += [PSCustomObject]@{
            Name = "Heartbeat"
            Status = "Pass"
            Message = "VM is responsive"
        }

        # Check 4: ADDSDeployment module available inside VM
        try {
            $moduleCheck = Invoke-Command -VMName $VMName -ScriptBlock {
                Get-Module -ListAvailable -Name ADDSDeployment -ErrorAction SilentlyContinue
            } -ErrorAction Stop

            if ($null -eq $moduleCheck) {
                $result.Status = "MissingModule"
                $result.Message = "ADDSDeployment module not available in VM '$VMName'"
                $result.Checks += [PSCustomObject]@{
                    Name = "ADDSDeploymentModule"
                    Status = "Fail"
                    Message = "Install RSAT-AD-Tools or AD-Domain-Services feature"
                }
                $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
                return $result
            }

            $result.Checks += [PSCustomObject]@{
                Name = "ADDSDeploymentModule"
                Status = "Pass"
                Message = "ADDSDeployment module is available"
            }
        }
        catch {
            $result.Status = "PowerShellDirectFailed"
            $result.Message = "PowerShell Direct connection failed: $($_.Exception.Message)"
            $result.Checks += [PSCustomObject]@{
                Name = "PowerShellDirect"
                Status = "Fail"
                Message = "Cannot connect to VM via PowerShell Direct"
            }
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Check 5: Network connectivity (basic check - can ping localhost)
        try {
            $networkCheck = Invoke-Command -VMName $VMName -ScriptBlock {
                Test-Connection -ComputerName localhost -Count 1 -Quiet -ErrorAction SilentlyContinue
            } -ErrorAction Stop

            if (-not $networkCheck) {
                $result.Status = "NoNetwork"
                $result.Message = "VM '$VMName' has no network connectivity"
                $result.Checks += [PSCustomObject]@{
                    Name = "NetworkConnectivity"
                    Status = "Fail"
                    Message = "Basic network test failed"
                }
                $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
                return $result
            }

            $result.Checks += [PSCustomObject]@{
                Name = "NetworkConnectivity"
                Status = "Pass"
                Message = "Network connectivity OK"
            }
        }
        catch {
            $result.Status = "NetworkCheckFailed"
            $result.Message = "Network connectivity check failed: $($_.Exception.Message)"
            $result.Checks += [PSCustomObject]@{
                Name = "NetworkConnectivity"
                Status = "Warning"
                Message = "Could not verify network connectivity"
            }
            # Don't fail on network check warning - promotion may still work
        }

        # All checks passed
        $result.CanPromote = $true
        $result.Status = "Ready"
        $result.Message = "VM '$VMName' is ready for domain controller promotion"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
    catch {
        $result.Status = "Error"
        $result.Message = "Unexpected error: $($_.Exception.Message)"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
}

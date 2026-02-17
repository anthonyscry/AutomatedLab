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
        # Flag to track whether in-VM checks can be performed
        $canProceedToVMChecks = $true

        # Check 1: Hyper-V module available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            $result.Checks += [PSCustomObject]@{
                Name = "HyperVModule"
                Status = "Fail"
                Message = "Hyper-V module is not available"
            }
            $canProceedToVMChecks = $false
        }
        else {
            $result.Checks += [PSCustomObject]@{
                Name = "HyperVModule"
                Status = "Pass"
                Message = "Hyper-V module is available"
            }
        }

        # Check 2: VM exists and is running
        if ($canProceedToVMChecks) {
            $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
            if ($null -eq $vm) {
                $result.Checks += [PSCustomObject]@{
                    Name = "VMExists"
                    Status = "Fail"
                    Message = "VM '$VMName' not found"
                }
                $canProceedToVMChecks = $false
            }
            elseif ($vm.State -ne "Running") {
                $result.Checks += [PSCustomObject]@{
                    Name = "VMState"
                    Status = "Fail"
                    Message = "VM state is '$($vm.State)', expected 'Running'"
                }
                $canProceedToVMChecks = $false
            }
            else {
                $result.Checks += [PSCustomObject]@{
                    Name = "VMState"
                    Status = "Pass"
                    Message = "VM is running"
                }
            }
        }
        else {
            $result.Checks += [PSCustomObject]@{
                Name = "VMState"
                Status = "Skipped"
                Message = "Cannot check VM state (prerequisite check failed)"
            }
        }

        # Check 3: VM Heartbeat (responsive)
        if ($canProceedToVMChecks) {
            if ($vm.Heartbeat -ne "Ok") {
                $result.Checks += [PSCustomObject]@{
                    Name = "Heartbeat"
                    Status = "Fail"
                    Message = "VM heartbeat is '$($vm.Heartbeat)', expected 'Ok'"
                }
            }
            else {
                $result.Checks += [PSCustomObject]@{
                    Name = "Heartbeat"
                    Status = "Pass"
                    Message = "VM is responsive"
                }
            }
        }
        else {
            $result.Checks += [PSCustomObject]@{
                Name = "Heartbeat"
                Status = "Skipped"
                Message = "Cannot check heartbeat (VM not running)"
            }
        }

        # Check 4: ADDSDeployment module available inside VM
        if ($canProceedToVMChecks) {
            try {
                $moduleCheck = Invoke-Command -VMName $VMName -ScriptBlock {
                    Get-Module -ListAvailable -Name ADDSDeployment -ErrorAction SilentlyContinue
                } -ErrorAction Stop

                if ($null -eq $moduleCheck) {
                    $result.Checks += [PSCustomObject]@{
                        Name = "ADDSDeploymentModule"
                        Status = "Fail"
                        Message = "Install RSAT-AD-Tools or AD-Domain-Services feature"
                    }
                }
                else {
                    $result.Checks += [PSCustomObject]@{
                        Name = "ADDSDeploymentModule"
                        Status = "Pass"
                        Message = "ADDSDeployment module is available"
                    }
                }
            }
            catch {
                $result.Checks += [PSCustomObject]@{
                    Name = "PowerShellDirect"
                    Status = "Fail"
                    Message = "Cannot connect to VM via PowerShell Direct"
                }
            }
        }
        else {
            $result.Checks += [PSCustomObject]@{
                Name = "ADDSDeploymentModule"
                Status = "Skipped"
                Message = "Cannot check ADDS module (VM not running)"
            }
        }

        # Check 5: Network connectivity (basic check - can ping localhost)
        # This check ALWAYS runs if VM is available, regardless of earlier failures
        if ($canProceedToVMChecks) {
            try {
                $networkCheck = Invoke-Command -VMName $VMName -ScriptBlock {
                    Test-Connection -ComputerName localhost -Count 1 -Quiet -ErrorAction SilentlyContinue
                } -ErrorAction Stop

                if (-not $networkCheck) {
                    $result.Checks += [PSCustomObject]@{
                        Name = "NetworkConnectivity"
                        Status = "Fail"
                        Message = "Basic network test failed"
                    }
                }
                else {
                    $result.Checks += [PSCustomObject]@{
                        Name = "NetworkConnectivity"
                        Status = "Pass"
                        Message = "Network connectivity OK"
                    }
                }
            }
            catch {
                $result.Checks += [PSCustomObject]@{
                    Name = "NetworkConnectivity"
                    Status = "Warning"
                    Message = "Could not verify network connectivity"
                }
                # Don't fail on network check warning - promotion may still work
            }
        }
        else {
            $result.Checks += [PSCustomObject]@{
                Name = "NetworkConnectivity"
                Status = "Skipped"
                Message = "Cannot check network connectivity (VM not running)"
            }
        }

        # Determine final status based on accumulated check results
        $failCount = ($result.Checks | Where-Object Status -eq 'Fail').Count
        $warningCount = ($result.Checks | Where-Object Status -eq 'Warning').Count

        $result.CanPromote = ($failCount -eq 0)

        if ($result.CanPromote) {
            $result.Status = if ($warningCount -gt 0) { "Warning" } else { "Ready" }
            $result.Message = "VM '$VMName' is ready for domain controller promotion"
        }
        else {
            $result.Status = "Failed"
            $failedChecks = ($result.Checks | Where-Object Status -eq 'Fail').Name -join ', '
            $result.Message = "VM '$VMName' failed prerequisite checks: $failedChecks"
        }

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

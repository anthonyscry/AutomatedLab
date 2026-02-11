function Test-LabDomainJoin {
    <#
    .SYNOPSIS
        Tests domain membership status for a VM.

    .DESCRIPTION
        Validates that a VM is joined to the specified domain and that
        the domain trust channel is established. Uses PowerShell Direct for
        in-VM validation.

    .PARAMETER VMName
        Name of the VM to test (required).

    .PARAMETER DomainName
        Domain name to check membership for (default: from config or "simplelab.local").

    .PARAMETER Credential
        Domain administrator credential (default: creates from config or prompts).

    .OUTPUTS
        PSCustomObject with domain membership status and diagnostic information.

    .EXAMPLE
        Test-LabDomainJoin -VMName "svr1"

    .EXAMPLE
        Test-LabDomainJoin -VMName "ws1" -DomainName "simplelab.local"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMName,

        [Parameter()]
        [string]$DomainName,

        [Parameter()]
        [pscredential]$Credential
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        VMName = $VMName
        IsJoined = $false
        DomainName = ""
        TrustStatus = "Failed"
        Status = "NotJoined"
        Message = ""
        Checks = @()
        Duration = $null
    }

    try {
        # Get domain configuration
        $domainConfig = Get-LabDomainConfig
        $targetDomain = if ($PSBoundParameters.ContainsKey('DomainName')) {
            $DomainName
        }
        else {
            $domainConfig.DomainName
        }

        # Set up credential if not provided
        $targetCredential = $Credential
        if ($null -eq $targetCredential) {
            # Create credential from config password
            $password = ConvertTo-SecureString -String $domainConfig.SafeModePassword -AsPlainText -Force
            $targetCredential = New-Object System.Management.Automation.PSCredential ("$($targetDomain)\Administrator", $password)
        }

        # Check 1: Hyper-V module available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            $result.Status = "Failed"
            $result.Message = "Hyper-V module is not available"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Check 2: VM exists and is running
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if ($null -eq $vm) {
            $result.Status = "NotFound"
            $result.Message = "VM '$VMName' does not exist"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        if ($vm.State -ne "Running") {
            $result.Status = "NotRunning"
            $result.Message = "VM '$VMName' is not running (State: $($vm.State))"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        $result.Checks += [PSCustomObject]@{
            Name = "VMState"
            Status = "Pass"
            Message = "VM is running"
        }

        # Run domain join checks inside the VM via PowerShell Direct
        try {
            $joinChecks = Invoke-Command -VMName $VMName -ScriptBlock {
                param($domainName, $credential)

                $checks = @()
                $isJoined = $false
                $actualDomain = ""
                $trustStatus = "Failed"

                # Check 3: Get computer domain information
                try {
                    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
                    $actualDomain = $cs.Domain
                    $workgroup = $cs.Workgroup

                    if ($actualDomain -and $actualDomain -ne "") {
                        # Check if joined to the target domain
                        if ($actualDomain -eq $domainName) {
                            $isJoined = $true
                            $checks += [PSCustomObject]@{
                                Name = "DomainMembership"
                                Status = "Pass"
                                Message = "Joined to domain: $actualDomain"
                            }
                        }
                        else {
                            $checks += [PSCustomObject]@{
                                Name = "DomainMembership"
                                Status = "Fail"
                                Message = "Joined to different domain: $actualDomain (expected: $domainName)"
                            }
                        }
                    }
                    elseif ($workgroup) {
                        $checks += [PSCustomObject]@{
                            Name = "DomainMembership"
                            Status = "Fail"
                            Message = "VM is in workgroup: $workgroup"
                        }
                    }
                    else {
                        $checks += [PSCustomObject]@{
                            Name = "DomainMembership"
                            Status = "Warning"
                            Message = "Could not determine domain/workgroup status"
                        }
                    }
                }
                catch {
                    $checks += [PSCustomObject]@{
                        Name = "DomainMembership"
                        Status = "Error"
                        Message = "Failed to query domain status: $($_.Exception.Message)"
                    }
                }

                # Check 4: Test domain trust channel if joined
                if ($isJoined) {
                    try {
                        $trustTest = Test-ComputerSecureChannel -Credential $credential -ErrorAction Stop
                        if ($trustTest) {
                            $trustStatus = "OK"
                            $checks += [PSCustomObject]@{
                                Name = "DomainTrust"
                                Status = "Pass"
                                Message = "Domain trust channel is OK"
                            }
                        }
                        else {
                            $trustStatus = "Failed"
                            $checks += [PSCustomObject]@{
                                Name = "DomainTrust"
                                Status = "Fail"
                                Message = "Domain trust channel test failed"
                            }
                        }
                    }
                    catch {
                        $trustStatus = "Error"
                        $checks += [PSCustomObject]@{
                            Name = "DomainTrust"
                            Status = "Error"
                            Message = "Trust test error: $($_.Exception.Message)"
                        }
                    }
                }

                # Check 5: Verify DC is reachable from VM
                try {
                    $dcTest = Test-Connection -ComputerName "$($domainName -split '\.')[0]DC" -Count 1 -Quiet -ErrorAction SilentlyContinue
                    if ($dcTest) {
                        $checks += [PSCustomObject]@{
                            Name = "DCReachability"
                            Status = "Pass"
                            Message = "Domain controller is reachable"
                        }
                    }
                    else {
                        $checks += [PSCustomObject]@{
                            Name = "DCReachability"
                            Status = "Warning"
                            Message = "Could not verify DC reachability"
                        }
                    }
                }
                catch {
                    $checks += [PSCustomObject]@{
                        Name = "DCReachability"
                        Status = "Warning"
                        Message = "DC reachability check skipped: $($_.Exception.Message)"
                    }
                }

                # Return results
                return @{
                    IsJoined = $isJoined
                    DomainName = $actualDomain
                    TrustStatus = $trustStatus
                    Checks = $checks
                }
            } -ArgumentList $targetDomain, $targetCredential -ErrorAction Stop

            # Map results from VM
            $result.IsJoined = $joinChecks.IsJoined
            $result.DomainName = $joinChecks.DomainName
            $result.TrustStatus = $joinChecks.TrustStatus
            $result.Checks += $joinChecks.Checks

            # Determine overall status
            if ($result.IsJoined -and $result.TrustStatus -eq "OK") {
                $result.Status = "Joined"
                $result.Message = "VM '$VMName' is joined to domain '$($result.DomainName)' with valid trust"
            }
            elseif ($result.IsJoined) {
                $result.Status = "NoTrust"
                $result.Message = "VM '$VMName' is joined to domain '$($result.DomainName)' but trust is failing"
            }
            else {
                $result.Status = "NotJoined"
                $result.Message = "VM '$VMName' is not joined to domain '$targetDomain'"
            }
        }
        catch {
            $result.Status = "Error"
            $result.Message = "PowerShell Direct connection failed: $($_.Exception.Message)"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
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

function Join-LabDomain {
    <#
    .SYNOPSIS
        Joins member VMs to the SimpleLab domain.

    .DESCRIPTION
        Orchestrates domain join for multiple VMs using PowerShell Direct.
        Handles credentials, reboots, and verification of domain membership.

    .PARAMETER VMNames
        Array of VM names to join to the domain (default: svr1, ws1).

    .PARAMETER DomainName
        Domain name to join (default: from config or "simplelab.local").

    .PARAMETER Credential
        Domain administrator credential. Prompts if not provided.

    .PARAMETER OUPath
        Organizational Unit DistinguishedName for computer accounts.

    .PARAMETER Force
        Rejoin VMs that are already domain members.

    .PARAMETER WaitTimeoutMinutes
        Maximum minutes to wait for VMs to return from reboot (default: 10).

    .OUTPUTS
        PSCustomObject with join results for all VMs.

    .EXAMPLE
        Join-LabDomain

    .EXAMPLE
        Join-LabDomain -VMNames @("svr1") -Force
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string[]]$VMNames = @("svr1", "ws1"),

        [Parameter()]
        [string]$DomainName,

        [Parameter()]
        [pscredential]$Credential,

        [Parameter()]
        [string]$OUPath,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$WaitTimeoutMinutes = 10
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        VMsJoined = @{}
        FailedVMs = @()
        SkippedVMs = @()
        OverallStatus = "Failed"
        Message = ""
        Duration = $null
    }

    try {
        Write-Verbose "Starting domain join for VMs: $($VMNames -join ', ')..."

        # Step 1: Get domain configuration
        $domainConfig = Get-LabDomainConfig
        $targetDomain = if ($PSBoundParameters.ContainsKey('DomainName')) {
            $GlobalLabConfig.Lab.DomainName
        }
        else {
            $domainConfig.DomainName
        }

        # Step 2: Set up credential if not provided
        $targetCredential = $Credential
        if ($null -eq $targetCredential) {
            Write-Verbose "Prompting for domain administrator credentials..."
            $targetCredential = Get-Credential -Message "Enter credentials for $targetDomain domain administrator"
            if ($null -eq $targetCredential) {
                $result.OverallStatus = "Failed"
                $result.Message = "Domain administrator credentials not provided"
                $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
                return $result
            }
        }

        # Track success and failure counts
        $successCount = 0
        $failureCount = 0
        $skippedCount = 0

        # Step 3: Process each VM in order (servers before clients already sorted)
        foreach ($vmName in $VMNames) {
            Write-Verbose "Processing VM '$vmName'..."

            # Check if VM exists
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($null -eq $vm) {
                $result.FailedVMs += $vmName
                $result.VMsJoined[$vmName] = [PSCustomObject]@{
                    VMName = $vmName
                    Joined = $false
                    Status = "NotFound"
                    Message = "VM '$vmName' does not exist"
                }
                $failureCount++
                continue
            }

            # Check if VM is running
            if ($vm.State -ne "Running") {
                $result.FailedVMs += $vmName
                $result.VMsJoined[$vmName] = [PSCustomObject]@{
                    VMName = $vmName
                    Joined = $false
                    Status = "NotRunning"
                    Message = "VM '$vmName' is not running (State: $($vm.State))"
                }
                $failureCount++
                continue
            }

            # Step 4: Check if already joined to domain
            $joinTest = Test-LabDomainJoin -VMName $vmName -DomainName $targetDomain -Credential $targetCredential

            if ($joinTest.IsJoined -and -not $Force) {
                # Already joined and not forcing - skip
                $result.SkippedVMs += $vmName
                $result.VMsJoined[$vmName] = [PSCustomObject]@{
                    VMName = $vmName
                    Joined = $false
                    Status = "AlreadyJoined"
                    Message = "VM '$vmName' is already joined to domain '$($joinTest.DomainName)'"
                }
                $skippedCount++
                continue
            }

            # Step 5: Execute domain join
            try {
                Write-Verbose "Joining '$vmName' to domain '$targetDomain'..."

                $joinParams = @{
                    DomainName = $targetDomain
                    Credential = $targetCredential
                    Restart = $true
                    Force = $true
                }

                # Add OUPath if specified
                if ($PSBoundParameters.ContainsKey('OUPath')) {
                    $joinParams.OUPath = $OUPath
                }

                # Execute domain join via PowerShell Direct
                Invoke-Command -VMName $vmName -ScriptBlock {
                    param($domainName, $credential, $ouPath, $force)

                    $joinParams = @{
                        DomainName = $domainName
                        Credential = $credential
                        Restart = $true
                        Force = $force
                    }

                    if ($ouPath) {
                        $joinParams.OUPath = $ouPath
                    }

                    Add-Computer @joinParams -ErrorAction Stop

                    return $true
                } -ArgumentList $targetDomain, $targetCredential, $OUPath, $true -ErrorAction Stop | Out-Null

                Write-Verbose "Domain join command executed for '$vmName', waiting for reboot..."

                # Step 6: Wait for reboot to start
                $rebootStarted = $false
                $rebootWaitStart = Get-Date
                $maxRebootWait = [TimeSpan]::FromMinutes(5)

                while (-not $rebootStarted -and ((Get-Date) - $rebootWaitStart) -lt $maxRebootWait) {
                    $vmCheck = Get-VM -Name $vmName -ErrorAction SilentlyContinue
                    if ($vmCheck.State -eq "Off" -or $vmCheck.Heartbeat -eq "LostCommunication") {
                        $rebootStarted = $true
                        Write-Verbose "VM '$vmName' reboot started"
                    }
                    Start-Sleep -Seconds 2
                }

                if (-not $rebootStarted) {
                    # VM didn't reboot, might already be in domain
                    Write-Warning "VM '$vmName' did not start reboot within expected time, verifying status..."
                }

                # Step 7: Wait for VM to return online
                Write-Verbose "Waiting for '$vmName' to return online..."
                $vmBackOnline = $false
                $onlineWaitStart = Get-Date
                $maxWait = [TimeSpan]::FromMinutes($WaitTimeoutMinutes)

                while (-not $vmBackOnline -and ((Get-Date) - $onlineWaitStart) -lt $maxWait) {
                    $vmCheck = Get-VM -Name $vmName -ErrorAction SilentlyContinue

                    if ($vmCheck.State -eq "Running" -and $vmCheck.Heartbeat -eq "Ok") {
                        # Give VM extra time to fully start
                        Start-Sleep -Seconds 30

                        # Verify domain membership
                        $verifyJoin = Test-LabDomainJoin -VMName $vmName -DomainName $targetDomain -Credential $targetCredential

                        if ($verifyJoin.IsJoined) {
                            $vmBackOnline = $true
                            Write-Verbose "VM '$vmName' is back online and joined to domain"
                        }
                    }

                    if (-not $vmBackOnline) {
                        Start-Sleep -Seconds 10
                    }
                }

                if (-not $vmBackOnline) {
                    Write-Warning "VM '$vmName' did not return online within timeout, but join command was executed"
                }

                # Step 8: Verify domain membership
                $finalVerify = Test-LabDomainJoin -VMName $vmName -DomainName $targetDomain -Credential $targetCredential

                if ($finalVerify.IsJoined) {
                    $result.VMsJoined[$vmName] = [PSCustomObject]@{
                        VMName = $vmName
                        Joined = $true
                        Status = "OK"
                        Message = "Successfully joined to domain '$targetDomain'"
                    }
                    $successCount++
                }
                elseif ($finalVerify.Status -eq "NoTrust") {
                    # Joined but trust not established yet
                    $result.VMsJoined[$vmName] = [PSCustomObject]@{
                        VMName = $vmName
                        Joined = $true
                        Status = "Warning"
                        Message = "Joined to domain but trust not yet established"
                    }
                    $successCount++
                }
                else {
                    $result.FailedVMs += $vmName
                    $result.VMsJoined[$vmName] = [PSCustomObject]@{
                        VMName = $vmName
                        Joined = $false
                        Status = "Failed"
                        Message = "Failed to join domain: $($finalVerify.Message)"
                    }
                    $failureCount++
                }
            }
            catch {
                $result.FailedVMs += $vmName
                $result.VMsJoined[$vmName] = [PSCustomObject]@{
                    VMName = $vmName
                    Joined = $false
                    Status = "Error"
                    Message = "Domain join error: $($_.Exception.Message)"
                }
                $failureCount++
            }
        }

        # Step 9: Determine overall status
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))

        if ($failureCount -eq 0) {
            $result.OverallStatus = "OK"
            $result.Message = "Successfully joined $successCount VM(s) to domain '$targetDomain'"
        }
        elseif ($successCount -eq 0) {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to join all VMs to domain"
        }
        else {
            $result.OverallStatus = "Partial"
            $result.Message = "Joined $successCount VM(s), failed $failureCount VM(s), skipped $skippedCount VM(s)"
        }

        Write-Verbose "Domain join completed: $($result.OverallStatus)"

        return $result
    }
    catch {
        $result.OverallStatus = "Failed"
        $result.Message = "Domain join operation failed: $($_.Exception.Message)"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
}

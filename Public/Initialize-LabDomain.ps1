function Initialize-LabDomain {
    <#
    .SYNOPSIS
        Promotes a VM to be an Active Directory domain controller.

    .DESCRIPTION
        Orchestrates complete DC promotion workflow including prerequisite
        validation, domain promotion execution, reboot handling, and
        post-promotion verification. Uses PowerShell Direct for in-VM operations.

    .PARAMETER VMName
        Name of the VM to promote (default: "dc1").

    .PARAMETER SafeModePassword
        Safe Mode administrator password for the domain controller.
        If not specified, uses value from config.json or default.

    .PARAMETER DomainName
        FQDN for the new domain (default: from config or "simplelab.local").

    .PARAMETER Force
        Suppress confirmation prompts during promotion.

    .PARAMETER WaitTimeoutMinutes
        Maximum minutes to wait for VM to return from reboot (default: 15).

    .OUTPUTS
        PSCustomObject with VMName, Promoted (bool), Status, Message, and Duration.

    .EXAMPLE
        Initialize-LabDomain

    .EXAMPLE
        Initialize-LabDomain -VMName "dc1" -Force -WaitTimeoutMinutes 20
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$VMName = "dc1",

        [Parameter()]
        [securestring]$SafeModePassword,

        [Parameter()]
        [string]$DomainName,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$WaitTimeoutMinutes = 15
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        VMName = $VMName
        Promoted = $false
        Status = "Failed"
        Message = ""
        Duration = $null
    }

    try {
        Write-Verbose "Starting domain controller promotion for '$VMName'..."

        # Step 1: Get domain configuration
        $domainConfig = Get-LabDomainConfig

        # Override with parameters if provided
        $targetDomainName = if ($PSBoundParameters.ContainsKey('DomainName')) {
            $DomainName
        }
        else {
            $domainConfig.DomainName
        }

        $targetPassword = if ($PSBoundParameters.ContainsKey('SafeModePassword')) {
            $SafeModePassword
        }
        else {
            ConvertTo-SecureString -String $domainConfig.SafeModePassword -AsPlainText -Force
        }

        # Step 2: Test prerequisites
        Write-Verbose "Testing DC promotion prerequisites..."
        $prereqResult = Test-DCPromotionPrereqs -VMName $VMName

        if (-not $prereqResult.CanPromote) {
            $result.Status = $prereqResult.Status
            $result.Message = "Prerequisites not met: $($prereqResult.Message)"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        Write-Verbose "Prerequisites validated successfully"

        # Step 3: Check if already a domain controller
        Write-Verbose "Checking if '$VMName' is already a domain controller..."
        try {
            $alreadyDC = Invoke-Command -VMName $VMName -ScriptBlock {
                Get-Service -Name NTDS -ErrorAction SilentlyContinue |
                    Where-Object { $_.Status -eq 'Running' }
            } -ErrorAction SilentlyContinue

            if ($alreadyDC) {
                $result.Status = "AlreadyDC"
                $result.Promoted = $false
                $result.Message = "VM '$VMName' is already a domain controller"
                $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
                Write-Verbose "Already a domain controller, skipping promotion"
                return $result
            }
        }
        catch {
            # Service check failed - continue with promotion attempt
        }

        # Step 4: Execute domain promotion
        Write-Verbose "Promoting '$VMName' to domain controller for '$targetDomainName'..."

        $promotionScriptBlock = {
            param($domainName, $safeModePassword, $force)

            # Install AD DS and promote to DC
            Install-ADDSForest -DomainName $domainName `
                -InstallDns:$true `
                -SafeModeAdministratorPassword $safeModePassword `
                -Force:$true `
                -NoRebootOnCompletion:$false `
                -ErrorAction Stop
        }

        try {
            Invoke-Command -VMName $VMName -ScriptBlock $promotionScriptBlock `
                -ArgumentList $targetDomainName, $targetPassword, $Force `
                -ErrorAction Stop

            Write-Verbose "Domain promotion command executed successfully"
        }
        catch {
            # Check for "already a DC" error
            if ($_.Exception.Message -match "already.*domain controller|already promoted") {
                $result.Status = "AlreadyDC"
                $result.Promoted = $false
                $result.Message = "VM '$VMName' is already a domain controller"
                $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
                return $result
            }

            throw
        }

        # Step 5: Wait for reboot to start
        Write-Verbose "Waiting for VM reboot to start..."
        $rebootStarted = $false
        $rebootWaitStart = Get-Date

        while (-not $rebootStarted -and ((Get-Date) - $rebootWaitStart).TotalMinutes -lt 5) {
            $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
            if ($vm.State -eq "Off" -or $vm.Heartbeat -eq "LostCommunication") {
                $rebootStarted = $true
                Write-Verbose "VM reboot started"
            }
            Start-Sleep -Seconds 2
        }

        if (-not $rebootStarted) {
            $result.Status = "RebootTimeout"
            $result.Message = "VM did not start reboot within expected time"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Step 6: Wait for VM to return online
        Write-Verbose "Waiting for VM to return online (timeout: $WaitTimeoutMinutes minutes)..."

        $vmBackOnline = $false
        $onlineWaitStart = Get-Date
        $maxWait = [TimeSpan]::FromMinutes($WaitTimeoutMinutes)

        while (-not $vmBackOnline -and ((Get-Date) - $onlineWaitStart) -lt $maxWait) {
            $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue

            if ($vm.State -eq "Running" -and $vm.Heartbeat -eq "Ok") {
                # Give VM extra time to fully start AD services
                Start-Sleep -Seconds 30

                # Verify AD services are running
                try {
                    $adServices = Invoke-Command -VMName $VMName -ScriptBlock {
                        Get-Service -Name NTDS, DNS -ErrorAction SilentlyContinue |
                            Where-Object { $_.Status -eq 'Running' }
                    } -ErrorAction SilentlyContinue

                    if ($adServices -and $adServices.Count -ge 1) {
                        $vmBackOnline = $true
                        Write-Verbose "VM is back online with AD services running"
                    }
                }
                catch {
                    # Services not ready yet, continue waiting
                }
            }

            if (-not $vmBackOnline) {
                Start-Sleep -Seconds 10
            }
        }

        if (-not $vmBackOnline) {
            $result.Status = "Timeout"
            $result.Message = "VM did not return online within $WaitTimeoutMinutes minutes"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Step 7: Verify domain controller functionality
        Write-Verbose "Verifying domain controller functionality..."

        try {
            # Test that we can query the domain
            $domainTest = Invoke-Command -VMName $VMName -ScriptBlock {
                Get-ADDomain -ErrorAction Stop
            } -ErrorAction Stop

            if ($domainTest) {
                Write-Verbose "Domain '$($domainTest.DNSRoot)' is functional"
            }
        }
        catch {
            $result.Status = "VerificationFailed"
            $result.Message = "Domain controller promotion completed but verification failed: $($_.Exception.Message)"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Success!
        $result.Promoted = $true
        $result.Status = "OK"
        $result.Message = "Successfully promoted '$VMName' to domain controller for '$targetDomainName'"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        Write-Verbose "Domain controller promotion completed successfully"

        return $result
    }
    catch {
        $result.Status = "Failed"
        $result.Message = "Domain controller promotion failed: $($_.Exception.Message)"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
}

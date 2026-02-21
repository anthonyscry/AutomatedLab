function Test-LabBulkOperationCore {
    <#
    .SYNOPSIS
        Validates pre-flight conditions for bulk VM operations.

    .DESCRIPTION
        Test-LabBulkOperationCore performs validation checks before bulk
        operations execute, including VM existence, Hyper-V module
        availability, and resource constraints. Returns structured
        results with Pass/Warn/Fail statuses and remediation guidance.

    .PARAMETER VMName
        Array of VM names to validate.

    .PARAMETER Operation
        Operation type to validate: 'Start', 'Stop', 'Suspend', 'Restart', 'Checkpoint'.

    .PARAMETER CheckResourceAvailability
        Include resource availability checks (RAM/CPU) for Start operations.

    .OUTPUTS
        [pscustomobject] with OverallStatus (OK/Warning/Fail), Checks array,
        FailedChecks array, and remediation suggestions.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string[]]$VMName,

        [Parameter(Mandatory)]
        [ValidateSet('Start', 'Stop', 'Suspend', 'Restart', 'Checkpoint')]
        [string]$Operation,

        [switch]$CheckResourceAvailability
    )

    $checks = [System.Collections.Generic.List[pscustomobject]]::new()
    $failCount = 0
    $warnCount = 0

    # Check 1: Hyper-V module availability
    $hvCheck = [ordered]@{
        Name    = 'Hyper-V Module'
        Status  = 'Pass'
        Message = 'Hyper-V module is available'
        Remediation = $null
    }

    try {
        $null = Get-Module -ListAvailable -Name Hyper-V -ErrorAction Stop
    }
    catch {
        $hvCheck.Status = 'Fail'
        $hvCheck.Message = 'Hyper-V module not found'
        $hvCheck.Remediation = 'Install Hyper-V module: Install-Module -Name Hyper-V -Force'
        $failCount++
    }

    $checks.Add([pscustomobject]$hvCheck)

    # Check 2: VM existence
    $vmCheck = [ordered]@{
        Name    = 'VM Existence'
        Status  = 'Pass'
        Message = "All $($VMName.Count) VMs exist"
        Remediation = $null
    }

    try {
        $missingVMs = [System.Collections.Generic.List[string]]::new()
        $foundVMs = [System.Collections.Generic.List[string]]::new()

        foreach ($vmName in $VMName) {
            try {
                $vm = Get-VM -Name $vmName -ErrorAction Stop
                $foundVMs.Add($vmName)
            }
            catch {
                $missingVMs.Add($vmName)
            }
        }

        if ($missingVMs.Count -gt 0) {
            $vmCheck.Status = 'Fail'
            $vmCheck.Message = "$($missingVMs.Count) of $($VMName.Count) VMs not found: $($missingVMs -join ', ')"
            $vmCheck.Remediation = "Verify VM names or create missing VMs: $($missingVMs -join ', ')"
            $failCount++
        }
        else {
            $vmCheck.Message = "All $($VMName.Count) VMs found: $($foundVMs -join ', ')"
        }
    }
    catch {
        $vmCheck.Status = 'Fail'
        $vmCheck.Message = "Failed to query VMs: $($_.Exception.Message)"
        $vmCheck.Remediation = 'Ensure Hyper-V service is running and you have administrative permissions'
        $failCount++
    }

    $checks.Add([pscustomobject]$vmCheck)

    # Check 3: Operation-specific validation
    $opCheck = [ordered]@{
        Name    = 'Operation Validation'
        Status  = 'Pass'
        Message = "Operation '$Operation' is valid for target VMs"
        Remediation = $null
    }

    try {
        if ($foundVMs.Count -gt 0) {
            $invalidVMs = [System.Collections.Generic.List[string]]::new()

            foreach ($vmName in $foundVMs) {
                try {
                    $vm = Get-VM -Name $vmName -ErrorAction Stop

                    switch ($Operation) {
                        'Start' {
                            if ($vm.State -eq 'Running') {
                                $invalidVMs.Add("$vmName (already running)")
                            }
                        }
                        'Stop' {
                            if ($vm.State -eq 'Off') {
                                $invalidVMs.Add("$vmName (already off)")
                            }
                        }
                        'Suspend' {
                            if ($vm.State -ne 'Running') {
                                $invalidVMs.Add("$vmName (state: $($vm.State))")
                            }
                        }
                        'Restart' {
                            if ($vm.State -eq 'Off') {
                                $invalidVMs.Add("$vmName (VM is off)")
                            }
                        }
                        'Checkpoint' {
                            if ($vm.State -eq 'Off') {
                                $invalidVMs.Add("$vmName (VM is off)")
                            }
                        }
                    }
                }
                catch {
                    $invalidVMs.Add("$vmName (query failed)")
                }
            }

            if ($invalidVMs.Count -gt 0) {
                $opCheck.Status = 'Warn'
                $opCheck.Message = "$($invalidVMs.Count) VMs may not behave as expected: $($invalidVMs -join ', ')"
                $opCheck.Remediation = 'Review VM states before proceeding or use Force parameter if applicable'
                $warnCount++
            }
        }
    }
    catch {
        $opCheck.Status = 'Warn'
        $opCheck.Message = "Could not validate operation-specific conditions: $($_.Exception.Message)"
        $opCheck.Remediation = 'Proceed with caution; operation will validate at execution time'
        $warnCount++
    }

    $checks.Add([pscustomobject]$opCheck)

    # Check 4: Resource availability (for Start operations only)
    if ($Operation -eq 'Start' -and $CheckResourceAvailability) {
        $resourceCheck = [ordered]@{
            Name    = 'Resource Availability'
            Status  = 'Pass'
            Message = 'Sufficient resources available'
            Remediation = $null
        }

        try {
            $resourceInfo = Get-LabHostResourceInfo

            $requiredRAM = 0
            foreach ($vmName in $foundVMs) {
                try {
                    $vm = Get-VM -Name $vmName -ErrorAction Stop
                    $requiredRAM += [math]::Ceiling($vm.MemoryGB / 1GB)
                }
                catch {
                    # Assume 4GB default if VM can't be queried
                    $requiredRAM += 4
                }
            }

            if ($requiredRAM -gt $resourceInfo.FreeRAMGB) {
                $resourceCheck.Status = 'Warn'
                $resourceCheck.Message = "May require ~$requiredRAM GB RAM but only $($resourceInfo.FreeRAMGB) GB free"
                $resourceCheck.Remediation = 'Stop other VMs or add more RAM to host before proceeding'
                $warnCount++
            }
            else {
                $resourceCheck.Message = "Sufficient RAM: ~$requiredRAM GB required, $($resourceInfo.FreeRAMGB) GB free"
            }
        }
        catch {
            $resourceCheck.Status = 'Warn'
            $resourceCheck.Message = "Could not verify resource availability: $($_.Exception.Message)"
            $resourceCheck.Remediation = 'Manually verify host has sufficient RAM and CPU before starting VMs'
            $warnCount++
        }

        $checks.Add([pscustomobject]$resourceCheck)
    }

    # Determine overall status
    $overallStatus = switch ($failCount) {
        { $_ -gt 0 } { 'Fail' }
        { $warnCount -gt 0 } { 'Warning' }
        default { 'OK' }
    }

    $failedChecks = @($checks | Where-Object { $_.Status -eq 'Fail' })

    return [pscustomobject]@{
        OverallStatus = $overallStatus
        Checks        = @($checks)
        FailedChecks  = $failedChecks
        Operation     = $Operation
        VMCount       = $VMName.Count
        Timestamp     = (Get-Date -Format 'o')
    }
}

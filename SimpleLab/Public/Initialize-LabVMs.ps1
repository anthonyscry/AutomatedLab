function Initialize-LabVMs {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$SwitchName = "SimpleLab",

        [Parameter()]
        [string]$VHDBasePath = "C:\Lab\VMs",

        [Parameter()]
        [switch]$Force
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        VMsCreated = @{}
        FailedVMs = @()
        OverallStatus = "Failed"
        Duration = $null
        Message = ""
    }

    # Get VM configurations
    $vmConfigs = Get-LabVMConfig

    if ($null -eq $vmConfigs) {
        $result.Message = "Failed to retrieve VM configurations"
        $result.OverallStatus = "Failed"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }

    # Get ISO paths from config
    $labConfig = Get-LabConfig

    if ($null -eq $labConfig -or -not ($labConfig.PSObject.Properties.Name -contains 'IsoPaths')) {
        $result.Message = "Failed to retrieve ISO paths from configuration"
        $result.OverallStatus = "Failed"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }

    $isoPaths = $labConfig.IsoPaths

    # Ensure VHDBasePath exists
    if (-not (Test-Path $VHDBasePath)) {
        try {
            New-Item -Path $VHDBasePath -ItemType Directory -Force | Out-Null
        }
        catch {
            $result.Message = "Failed to create VHD base path '$VHDBasePath': $($_.Exception.Message)"
            $result.OverallStatus = "Failed"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }
    }

    # Track success and failure counts
    $successCount = 0
    $failureCount = 0

    # VM creation order: DC, Server, Win11
    $vmOrder = @("SimpleDC", "SimpleServer", "SimpleWin11")

    # Create each VM
    foreach ($vmName in $vmOrder) {
        # Get VM config for this specific VM
        $vmConfig = Get-LabVMConfig -VMName $vmName

        if ($null -eq $vmConfig) {
            # No configuration for this VM
            $result.FailedVMs += $vmName
            $result.VMsCreated[$vmName] = [PSCustomObject]@{
                VMName = $vmName
                Created = $false
                Status = "Failed"
                Message = "No configuration found for VM '$vmName'"
            }
            $failureCount++
            continue
        }

        # Build VHD path
        $vhdPath = Join-Path $VHDBasePath "$vmName.vhdx"

        # Get ISO path from config
        $isoPath = $null
        if ($vmConfig.PSObject.Properties.Name -contains 'ISO' -and $isoPaths.PSObject.Properties.Name -contains $vmConfig.ISO) {
            $isoPath = $isoPaths.($vmConfig.ISO)
        }

        # Build parameters for New-LabVM
        $newVMParams = @{
            VMName = $vmName
            MemoryGB = $vmConfig.MemoryGB
            VHDPath = $vhdPath
            SwitchName = $SwitchName
            ProcessorCount = $vmConfig.ProcessorCount
            Generation = $vmConfig.Generation
        }

        # Add ISO path if available
        if (-not [string]::IsNullOrEmpty($isoPath)) {
            $newVMParams.IsoPath = $isoPath
        }

        # Add Force parameter if specified
        if ($Force) {
            $newVMParams.Force = $true
        }

        # Create the VM
        $vmResult = New-LabVM @newVMParams

        # Store result
        $result.VMsCreated[$vmName] = $vmResult

        if ($vmResult.Status -eq "OK") {
            $successCount++
        }
        elseif ($vmResult.Status -eq "AlreadyExists" -and -not $Force) {
            # Count already existing as success in non-force mode
            $successCount++
        }
        else {
            $failureCount++
            $result.FailedVMs += $vmName
        }
    }

    # Calculate duration
    $result.Duration = New-TimeSpan -Start $startTime -End (Get-Date)

    # Determine overall status
    if ($failureCount -eq 0) {
        $result.OverallStatus = "OK"
        $result.Message = "Successfully created $successCount VM(s)"
    }
    elseif ($successCount -eq 0) {
        $result.OverallStatus = "Failed"
        $result.Message = "Failed to create all VMs"
    }
    else {
        $result.OverallStatus = "Partial"
        $result.Message = "Created $successCount VM(s), failed $failureCount VM(s)"
    }

    return $result
}

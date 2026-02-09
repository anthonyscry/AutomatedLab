function Test-LabPrereqs {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # Initialize
    $checks = @()
    $startTime = Get-Date

    try {
        # Check 1: Hyper-V
        $hypervResult = Test-HyperVEnabled
        $checks += [PSCustomObject]@{
            Name = "HyperV"
            Status = if ($hypervResult) { "Pass" } else { "Fail" }
            Message = if ($hypervResult) { "Hyper-V is enabled" } else { "Hyper-V is not enabled" }
        }

        # Check 2: Configuration
        $config = Get-LabConfig
        if ($null -eq $config) {
            $checks += [PSCustomObject]@{
                Name = "Configuration"
                Status = "Fail"
                Message = "Configuration file not found. Run Initialize-LabConfig"
            }
        }
        else {
            $checks += [PSCustomObject]@{
                Name = "Configuration"
                Status = "Pass"
                Message = "Configuration loaded"
            }
        }

        # Check 3: Disk Space (only if config loaded)
        if ($null -ne $config) {
            $minDiskSpace = $config.Requirements.MinDiskSpaceGB
            if ($minDiskSpace) {
                $diskResult = Test-DiskSpace -MinSpaceGB $minDiskSpace
                $checks += [PSCustomObject]@{
                    Name = "DiskSpace"
                    Status = $diskResult.Status
                    Message = $diskResult.Message
                }
            }
            else {
                $checks += [PSCustomObject]@{
                    Name = "DiskSpace"
                    Status = "Warning"
                    Message = "MinDiskSpaceGB not specified in configuration"
                }
            }
        }

        # Check 4: ISOs (only if config loaded)
        if ($null -ne $config) {
            foreach ($isoEntry in $config.IsoPaths.PSObject.Properties) {
                $isoName = $isoEntry.Name
                $isoPath = $isoEntry.Value

                $isoResult = Test-LabIso -IsoName $isoName -IsoPath $isoPath
                $checks += [PSCustomObject]@{
                    Name = "ISO_$isoName"
                    Status = $isoResult.Status
                    Message = "Path: $isoPath"
                }

                # If ISO not found, try to find it
                if ($isoResult.Status -eq "Fail") {
                    $searchPaths = $config.IsoSearchPaths
                    if ($searchPaths -and $searchPaths.Count -gt 0) {
                        $findResult = Find-LabIso -IsoName $isoName -SearchPaths $searchPaths
                        if ($findResult.Found) {
                            $checks += [PSCustomObject]@{
                                Name = "ISO_${isoName}_Search"
                                Status = "Info"
                                Message = "ISO found at: $($findResult.FoundPath)"
                            }
                        }
                        else {
                            $checks += [PSCustomObject]@{
                                Name = "ISO_${isoName}_Search"
                                Status = "Fail"
                                Message = "ISO not found in any search path"
                            }
                        }
                    }
                }
            }
        }

        # Final assembly
        $overallStatus = if ($checks.Status -contains "Fail") { "Fail" } else { "Pass" }
        $failedChecks = $checks | Where-Object { $_.Status -eq "Fail" } | Select-Object -ExpandProperty Name
        $duration = (New-TimeSpan -Start $startTime -End (Get-Date)).TotalSeconds
        $timestamp = (Get-Date).ToString("o")

        return [PSCustomObject]@{
            Timestamp = $timestamp
            OverallStatus = $overallStatus
            Checks = $checks
            FailedChecks = $failedChecks
            Duration = $duration
        }
    }
    catch {
        # Handle any unexpected errors - don't use Write-Error as it may terminate
        # when parent scope has ErrorActionPreference = 'Stop'
        $duration = (New-TimeSpan -Start $startTime -End (Get-Date)).TotalSeconds
        $timestamp = (Get-Date).ToString("o")

        return [PSCustomObject]@{
            Timestamp = $timestamp
            OverallStatus = "Error"
            Checks = $checks
            FailedChecks = @("Error")
            Duration = $duration
            Error = $_.Exception.Message
        }
    }
}

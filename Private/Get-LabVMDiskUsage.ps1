function Get-LabVMDiskUsage {
    <#
    .SYNOPSIS
        Returns disk usage information for a VM.

    .DESCRIPTION
        Queries Get-VMHardDiskDrive and Get-VHD to retrieve disk usage information
        including file size, logical size, and usage percentage. Handles multi-disk VMs
        by summing all disk sizes. Returns null on error.

    .PARAMETER VMName
        Name of the virtual machine to query.

    .OUTPUTS
        [pscustomobject] with FileSizeGB, SizeGB, UsagePercent properties, or $null on error.

    .EXAMPLE
        Get-LabVMDiskUsage -VMName 'dc1'
        Returns disk usage information for dc1.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$VMName
    )

    begin {
        $totalFileSize = 0
        $totalSize = 0
        $vmCount = 0
    }

    process {
        try {
            # Get all hard disk drives for the VM
            $hardDrives = Get-VMHardDiskDrive -VMName $VMName -ErrorAction SilentlyContinue

            if (-not $hardDrives -or @($hardDrives).Count -eq 0) {
                Write-Verbose "[Get-LabVMDiskUsage] No hard disks found for $VMName"
                return
            }

            foreach ($drive in $hardDrives) {
                $vhdInfo = Get-VHD -Path $drive.Path -ErrorAction SilentlyContinue
                if ($vhdInfo) {
                    $totalFileSize += $vhdInfo.FileSize
                    $totalSize += $vhdInfo.Size
                }
            }

            $vmCount++
        }
        catch {
            Write-Verbose "[Get-LabVMDiskUsage] Failed to query disk usage for $VMName`: $($_.Exception.Message)"
        }
    }

    end {
        if ($vmCount -eq 0 -or $totalSize -eq 0) {
            return $null
        }

        $fileSizeGB = [math]::Round($totalFileSize / 1GB, 2)
        $sizeGB = [math]::Round($totalSize / 1GB, 2)
        $usagePercent = [math]::Round(($totalFileSize / $totalSize) * 100, 0)

        return [pscustomobject]@{
            FileSizeGB    = $fileSizeGB
            SizeGB        = $sizeGB
            UsagePercent  = $usagePercent
        }
    }
}

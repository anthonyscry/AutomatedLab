function Test-DiskSpace {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$Path = "C:\",

        [Parameter()]
        [int]$MinSpaceGB = 100
    )

    try {
        # Extract drive letter from path (handles "C:", "C:\", "C:\Folder", etc.)
        $driveLetter = ($Path -split ':')[0]

        # Get the drive using Get-PSDrive
        $drive = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue

        # Initialize result object
        $result = [PSCustomObject]@{
            Path = $Path
            FreeSpaceGB = 0
            RequiredSpaceGB = $MinSpaceGB
            Status = "Fail"
            Message = ""
        }

        # Check if drive exists
        if (-not $drive) {
            $result.Status = "Fail"
            $result.Message = "Drive '$driveLetter' not found"
            return $result
        }

        # Calculate free space in GB
        $freeSpaceGB = $drive.Free / 1GB
        $result.FreeSpaceGB = [math]::Round($freeSpaceGB, 2)

        # Compare free space with required space
        if ($freeSpaceGB -ge $MinSpaceGB) {
            $result.Status = "Pass"
        }

        # Format message
        $result.Message = "$($result.FreeSpaceGB) GB free, $MinSpaceGB GB required"

        return $result
    }
    catch {
        Write-Error "Failed to check disk space for path '$Path': $($_.Exception.Message)"
        return [PSCustomObject]@{
            Path = $Path
            FreeSpaceGB = 0
            RequiredSpaceGB = $MinSpaceGB
            Status = "Error"
            Message = "Error: $($_.Exception.Message)"
        }
    }
}

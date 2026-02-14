function Test-DiskSpace {
    <#
    .SYNOPSIS
        Checks available disk space on the system.

    .DESCRIPTION
        Tests disk space availability for Windows or Linux/macOS systems.
        On Windows, checks drive letters. On Linux/macOS, checks filesystem mount points.

    .PARAMETER Path
        The path to check. On Windows: "C:\" or "C:" (default: "C:\")
        On Linux/macOS: "/" or any mount point (default: "/")

    .PARAMETER MinSpaceGB
        Minimum required disk space in GB (default: 100)

    .EXAMPLE
        Test-DiskSpace -Path "C:\" -MinSpaceGB 100

    .EXAMPLE
        Test-DiskSpace -Path "/" -MinSpaceGB 50
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$Path,

        [Parameter()]
        [int]$MinSpaceGB = 100
    )

    # Initialize result object
    $result = [PSCustomObject]@{
        Path = $Path
        FreeSpaceGB = 0
        RequiredSpaceGB = $MinSpaceGB
        Status = "Fail"
        Message = ""
    }

    try {
        # Detect platform and set default path if not specified
        # Use Get-Variable for PowerShell 5.1 compatibility
        $isWindowsVar = Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue
        $platformIsWindows = if ($null -eq $isWindowsVar) { $env:OS -eq 'Windows_NT' } else { $isWindowsVar.Value }

        if ([string]::IsNullOrEmpty($Path)) {
            $Path = if ($platformIsWindows) { "C:\" } else { "/" }
        }

        $result.Path = $Path

        # Platform-specific disk space check
        if ($platformIsWindows) {
            # Windows: Use Get-PSDrive for drive letter
            $driveLetter = ($Path -split ':')[0]
            $drive = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue

            if (-not $drive) {
                $result.Message = "Drive '$driveLetter' not found"
                return $result
            }

            $freeSpaceGB = $drive.Free / 1GB
        }
        else {
            # Linux/macOS: Use df command
            # df outputs in 1K blocks by default; extract available space
            $dfOutput = df -k "$Path" 2>/dev/null | tail -n 1

            if (-not $dfOutput) {
                $result.Message = "Cannot check disk space for path '$Path'"
                return $result
            }

            # Parse df output: typically "Filesystem 1K-blocks Used Available Capacity Mounted"
            # The 4th column is available space in KB
            $availableKB = ($dfOutput -split '\s+')[3]
            $freeSpaceGB = [int]$availableKB / 1MB / 1KB  # Convert KB to GB
        }

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
        $result.Status = "Error"
        $result.Message = "Error: $($_.Exception.Message)"
        return $result
    }
}

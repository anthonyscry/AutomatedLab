function Get-LabHostResourceInfo {
    <#
    .SYNOPSIS
        Returns host resource availability (RAM, disk, CPU).
    .DESCRIPTION
        Probes the host machine for free RAM in GB, free disk space in GB,
        and logical processor count. Works on Windows and Linux/macOS.
    .PARAMETER DiskPath
        Path to check for free disk space. Default: "C:\" on Windows, "/" on Linux/macOS.
    .EXAMPLE
        Get-LabHostResourceInfo
        Returns PSCustomObject with FreeRAMGB, FreeDiskGB, LogicalProcessors, DiskPath.
    .EXAMPLE
        Get-LabHostResourceInfo -DiskPath 'D:\'
        Checks free disk space on D: drive.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Object with FreeRAMGB (decimal), FreeDiskGB (decimal), LogicalProcessors (int), DiskPath (string).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$DiskPath
    )

    try {
        # Platform detection (PowerShell 5.1 compatible)
        $isWindowsVar = Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue
        $platformIsWindows = if ($null -eq $isWindowsVar) { $env:OS -eq 'Windows_NT' } else { $isWindowsVar.Value }

        # Default disk path based on platform
        if ([string]::IsNullOrEmpty($DiskPath)) {
            $DiskPath = if ($platformIsWindows) { 'C:\' } else { '/' }
        }

        # --- RAM ---
        $freeRAMGB = 0
        if ($platformIsWindows) {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            # FreePhysicalMemory is in KB
            $freeRAMGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        }
        else {
            # Linux/macOS: try /proc/meminfo first, fall back to free -b
            $memInfoPath = '/proc/meminfo'
            if (Test-Path $memInfoPath) {
                $memAvailLine = Get-Content $memInfoPath | Where-Object { $_ -match '^MemAvailable:\s+(\d+)\s+kB' }
                if ($memAvailLine -and $Matches[1]) {
                    $freeRAMGB = [math]::Round([long]$Matches[1] / 1MB, 2)
                }
                else {
                    # Fallback: MemFree + Buffers + Cached
                    $memFreeLine = Get-Content $memInfoPath | Where-Object { $_ -match '^MemFree:\s+(\d+)\s+kB' }
                    $freeKB = if ($memFreeLine -and $Matches[1]) { [long]$Matches[1] } else { 0 }
                    $freeRAMGB = [math]::Round($freeKB / 1MB, 2)
                }
            }
            else {
                # macOS or fallback: use free -b if available
                $freeOutput = & free -b 2>$null
                if ($freeOutput) {
                    $memLine = ($freeOutput | Where-Object { $_ -match '^Mem:' }) -split '\s+'
                    if ($memLine.Count -ge 4) {
                        $freeRAMGB = [math]::Round([long]$memLine[3] / 1GB, 2)
                    }
                }
            }
        }

        # --- Disk ---
        $freeDiskGB = 0
        if ($platformIsWindows) {
            $driveLetter = ($DiskPath -split ':')[0]
            $drive = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue
            if (-not $drive) {
                throw "Get-LabHostResourceInfo: Drive '$driveLetter' not found for path '$DiskPath'"
            }
            $freeDiskGB = [math]::Round($drive.Free / 1GB, 2)
        }
        else {
            $dfOutput = & df -k $DiskPath 2>$null | Select-Object -Last 1
            if (-not $dfOutput) {
                throw "Get-LabHostResourceInfo: Cannot check disk space for path '$DiskPath'"
            }
            $availableKB = ($dfOutput -split '\s+')[3]
            $freeDiskGB = [math]::Round([long]$availableKB / 1MB, 2)
        }

        # --- CPU ---
        $logicalProcessors = [Environment]::ProcessorCount

        return [pscustomobject]@{
            FreeRAMGB         = $freeRAMGB
            FreeDiskGB        = $freeDiskGB
            LogicalProcessors = $logicalProcessors
            DiskPath          = $DiskPath
        }
    }
    catch {
        if ($_.Exception.Message -like 'Get-LabHostResourceInfo:*') {
            throw
        }
        throw "Get-LabHostResourceInfo: $($_.Exception.Message)"
    }
}

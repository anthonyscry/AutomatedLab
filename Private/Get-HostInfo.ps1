function Get-HostInfo {
    <#
    .SYNOPSIS
        Gets host system information for run artifacts.

    .DESCRIPTION
        Collects host system information including computer name, username,
        PowerShell version, OS platform, and OS details. Works on Windows,
        Linux, and macOS.

    .OUTPUTS
        Ordered hashtable with host information keys.

    .EXAMPLE
        $info = Get-HostInfo
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    # Detect platform (works in both PowerShell 5.1 and PowerShell 6+/Core)
    # Use Get-Variable to safely check for automatic variables that don't exist in 5.1
    $isWindowsVar = Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue
    $isWindows = if ($null -eq $isWindowsVar) { $env:OS -eq 'Windows_NT' } else { $isWindowsVar.Value }

    $isLinuxVar = Get-Variable -Name 'IsLinux' -ErrorAction SilentlyContinue
    $isLinux = if ($null -eq $isLinuxVar) { $false } else { $isLinuxVar.Value }

    $isMacOSVar = Get-Variable -Name 'IsMacOS' -ErrorAction SilentlyContinue
    $isMacOS = if ($null -eq $isMacOSVar) { $false } else { $isMacOSVar.Value }

    # Determine platform string
    $platform = if ($isWindows) { "Windows" }
                elseif ($isLinux) { "Linux" }
                elseif ($isMacOS) { "macOS" }
                else { "Unknown" }

    return [ordered]@{
        ComputerName = if ($isWindows) { $env:COMPUTERNAME } else { $env:HOSTNAME }
        Username = if ($isWindows) { $env:USERNAME } else { $env:USER }
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        OS = $env:OS
        Platform = $platform
        IsWindows = $isWindows
        IsLinux = $isLinux
        IsMacOS = $isMacOS
    }
}

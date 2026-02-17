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

    try {
        # Detect platform (works in both PowerShell 5.1 and PowerShell 6+/Core)
        # Use Get-Variable to safely check for automatic variables that don't exist in 5.1
        $isWindowsVar = Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue
        $platformIsWindows = if ($null -eq $isWindowsVar) { $env:OS -eq 'Windows_NT' } else { $isWindowsVar.Value }

        $isLinuxVar = Get-Variable -Name 'IsLinux' -ErrorAction SilentlyContinue
        $platformIsLinux = if ($null -eq $isLinuxVar) { $false } else { $isLinuxVar.Value }

        $isMacOSVar = Get-Variable -Name 'IsMacOS' -ErrorAction SilentlyContinue
        $platformIsMacOS = if ($null -eq $isMacOSVar) { $false } else { $isMacOSVar.Value }

        # Determine platform string
        $platform = if ($platformIsWindows) { "Windows" }
                    elseif ($platformIsLinux) { "Linux" }
                    elseif ($platformIsMacOS) { "macOS" }
                    else { "Unknown" }

        return [ordered]@{
            ComputerName = if ($platformIsWindows) { $env:COMPUTERNAME } else { $env:HOSTNAME }
            Username = if ($platformIsWindows) { $env:USERNAME } else { $env:USER }
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            OS = $env:OS
            Platform = $platform
            IsWindows = $platformIsWindows
            IsLinux = $platformIsLinux
            IsMacOS = $platformIsMacOS
        }
    }
    catch {
        $PSCmdlet.WriteError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Get-HostInfo: failed to gather host information - $_", $_.Exception),
                'Get-HostInfo.Failure',
                [System.Management.Automation.ErrorCategory]::NotSpecified,
                $null
            )
        )
    }
}

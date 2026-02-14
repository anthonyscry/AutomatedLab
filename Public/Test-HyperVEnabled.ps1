function Test-HyperVEnabled {
    <#
    .SYNOPSIS
        Tests if Hyper-V is available and enabled on Windows.

    .DESCRIPTION
        Checks Hyper-V availability on Windows systems. Returns false on
        non-Windows platforms (Linux, macOS) without errors since Hyper-V
        is Windows-specific. Use -Verbose to see platform detection details.

    .OUTPUTS
        System.Boolean. True if Hyper-V is available and enabled, false otherwise.

    .EXAMPLE
        $enabled = Test-HyperVEnabled

    .EXAMPLE
        Test-HyperVEnabled -Verbose
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Detect platform (use Get-Variable for PowerShell 5.1 compatibility)
    $isWindowsVar = Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue
    $platformIsWindows = if ($null -eq $isWindowsVar) { $env:OS -eq 'Windows_NT' } else { $isWindowsVar.Value }

    try {
        # Non-Windows platforms: Hyper-V is not available, but this isn't an error
        if (-not $platformIsWindows) {
            Write-Verbose "Running on non-Windows platform ($($PSVersionTable.Platform)) - Hyper-V not available"
            return $false
        }

        Write-Verbose "Running on Windows - checking Hyper-V status"

        # Windows: Check HypervisorPresent using Get-CimInstance
        # Source: Microsoft Scripting Blog per RESEARCH.md
        $cimResult = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $hypervisorPresent = $cimResult.HypervisorPresent

        if (-not $hypervisorPresent) {
            Write-Verbose "Hyper-V is not enabled on this system"
            Write-Error "Hyper-V is not enabled. Run: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All"
            return $false
        }

        Write-Verbose "Hyper-V is enabled and available"
        return $true
    }
    catch {
        Write-Verbose "Failed to detect Hyper-V status: $($_.Exception.Message)"
        Write-Error "Failed to detect Hyper-V status: $($_.Exception.Message)"
        return $false
    }
}

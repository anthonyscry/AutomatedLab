function Test-HyperVEnabled {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        # Check platform - Get-ComputerInfo is Windows-only
        if ($IsWindows -eq $false -and $env:OS -ne 'Windows_NT') {
            # Not an error - just return false as Hyper-V is not available
            return $false
        }

        # Method 1: Check HypervisorPresent using Get-CimInstance (more direct)
        # Source: Microsoft Scripting Blog per RESEARCH.md
        $hypervisorPresent = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).HypervisorPresent

        if (-not $hypervisorPresent) {
            # User decision: Offer to enable with full command syntax
            $errorMsg = "Hyper-V is not enabled. Run: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All"
            Write-Error $errorMsg
            return $false
        }

        return $true
    }
    catch {
        # Surface the error with proper context
        Write-Error "Failed to detect Hyper-V status: $($_.Exception.Message)"
        return $false
    }
}

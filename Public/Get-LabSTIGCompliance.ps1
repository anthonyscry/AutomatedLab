function Get-LabSTIGCompliance {
    <#
    .SYNOPSIS
        Returns STIG compliance status for lab VMs.

    .DESCRIPTION
        Reads the STIG compliance cache file and returns per-VM
        compliance breakdown as PSCustomObject array. The cache is
        written by Invoke-LabSTIGBaseline after each DSC push.

        Returns empty array when the cache file does not exist,
        is empty, or is malformed.

    .PARAMETER CachePath
        Override path to stig-compliance.json. Defaults to the
        ComplianceCachePath value from Get-LabSTIGConfig.

    .EXAMPLE
        Get-LabSTIGCompliance
        Returns compliance status for all VMs in the cache.

    .EXAMPLE
        Get-LabSTIGCompliance | Where-Object Status -eq 'NonCompliant'
        Returns only non-compliant VMs.

    .EXAMPLE
        Get-LabSTIGCompliance | Format-Table VMName, Role, Status, ExceptionsApplied
        Displays a compliance summary table.

    .OUTPUTS
        [PSCustomObject[]] Per-VM compliance entries with fields:
        VMName, Role, STIGVersion, Status, ExceptionsApplied, LastChecked, ErrorMessage.
        Returns empty array @() when cache is missing, empty, or unreadable.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [string]$CachePath
    )

    if (-not $CachePath) {
        $config = Get-LabSTIGConfig
        $CachePath = $config.ComplianceCachePath
    }

    if (-not (Test-Path $CachePath)) {
        return @()
    }

    try {
        $cache = Get-Content -Path $CachePath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning "[STIG] Failed to read compliance cache: $($_.Exception.Message)"
        return @()
    }

    if (-not $cache.VMs -or $cache.VMs.Count -eq 0) {
        return @()
    }

    return @($cache.VMs | ForEach-Object {
        [pscustomobject]@{
            VMName            = $_.VMName
            Role              = $_.Role
            STIGVersion       = $_.STIGVersion
            Status            = $_.Status
            ExceptionsApplied = $_.ExceptionsApplied
            LastChecked       = $_.LastChecked
            ErrorMessage      = $_.ErrorMessage
        }
    })
}

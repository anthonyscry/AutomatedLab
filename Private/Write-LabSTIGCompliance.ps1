function Write-LabSTIGCompliance {
    <#
    .SYNOPSIS
        Writes or updates per-VM STIG compliance status to the JSON cache file.

    .DESCRIPTION
        Reads existing compliance cache (if present), updates or appends the VM entry
        matching VMName, then writes back to disk. Follows cache-on-write pattern so
        the dashboard (Phase 29) can read without live DSC queries.

        Schema:
          {
            "LastUpdated": "<ISO 8601>",
            "VMs": [
              {
                "VMName": "...",
                "Role": "DC|MS",
                "STIGVersion": "2019|2022",
                "Status": "Compliant|NonCompliant|Failed|Pending",
                "ExceptionsApplied": <int>,
                "LastChecked": "<ISO 8601>",
                "ErrorMessage": "<string or null>"
              }
            ]
          }

    .PARAMETER CachePath
        Full path to the compliance JSON cache file.

    .PARAMETER VMName
        Name of the VM being updated.

    .PARAMETER Role
        STIG role: DC or MS.

    .PARAMETER STIGVersion
        PowerSTIG OS year string: 2019 or 2022.

    .PARAMETER Status
        Compliance result: Compliant, NonCompliant, Failed, or Pending.

    .PARAMETER ExceptionsApplied
        Number of V-number exceptions applied at MOF compile time. Defaults to 0.

    .PARAMETER ErrorMessage
        Error text on failure; null/empty on success.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CachePath,

        [Parameter(Mandatory)]
        [string]$VMName,

        [Parameter(Mandatory)]
        [string]$Role,

        [Parameter(Mandatory)]
        [string]$STIGVersion,

        [Parameter(Mandatory)]
        [ValidateSet('Compliant', 'NonCompliant', 'Failed', 'Pending')]
        [string]$Status,

        [int]$ExceptionsApplied = 0,

        [string]$ErrorMessage = $null
    )

    # Read existing cache or start fresh
    $cache = $null
    if (Test-Path $CachePath) {
        try {
            $raw = Get-Content -Path $CachePath -Raw
            if ($raw) {
                $cache = $raw | ConvertFrom-Json
            }
        }
        catch {
            Write-Warning "[STIGCompliance] Could not parse existing cache at '$CachePath': $($_.Exception.Message). Starting fresh."
            $cache = $null
        }
    }

    if (-not $cache) {
        $cache = [pscustomobject]@{
            LastUpdated = (Get-Date).ToString('o')
            VMs         = @()
        }
    }

    # Build new VM entry
    $vmEntry = [pscustomobject]@{
        VMName            = $VMName
        Role              = $Role
        STIGVersion       = $STIGVersion
        Status            = $Status
        ExceptionsApplied = $ExceptionsApplied
        LastChecked       = (Get-Date).ToString('o')
        ErrorMessage      = $ErrorMessage
    }

    # Find existing index by VMName
    $existingIndex = -1
    for ($i = 0; $i -lt $cache.VMs.Count; $i++) {
        if ($cache.VMs[$i].VMName -eq $VMName) {
            $existingIndex = $i
            break
        }
    }

    if ($existingIndex -ge 0) {
        # Update in-place
        $vmList = [System.Collections.ArrayList]@($cache.VMs)
        $vmList[$existingIndex] = $vmEntry
        $cache.VMs = $vmList.ToArray()
    }
    else {
        # Append new entry
        $cache.VMs = @($cache.VMs) + @($vmEntry)
    }

    $cache.LastUpdated = (Get-Date).ToString('o')

    # Ensure the parent directory exists
    $dir = Split-Path -Parent $CachePath
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }

    $cache | ConvertTo-Json -Depth 5 | Set-Content -Path $CachePath -Encoding UTF8
}

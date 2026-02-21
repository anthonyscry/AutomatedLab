function Write-LabAnalyticsEvent {
    <#
    .SYNOPSIS
        Writes an analytics event to the lab analytics log.

    .DESCRIPTION
        Write-LabAnalyticsEvent appends a new event record to the analytics log,
        creating the file if it doesn't exist. Events include timestamp, event
        type, lab name, VM names, and optional metadata. Non-blocking operation
        that logs errors but doesn't throw.

    .PARAMETER EventType
        Type of event: 'LabCreated', 'LabDeployed', 'LabTeardown', 'LabExported',
        'LabImported', 'ProfileSaved', 'ProfileLoaded', etc.

    .PARAMETER LabName
        Name of the lab this event relates to.

    .PARAMETER VMNames
        Array of VM names affected by this event (optional).

    .PARAMETER Metadata
        Additional event metadata as hashtable (optional).

    .EXAMPLE
        Write-LabAnalyticsEvent -EventType 'LabDeployed' -LabName 'AutomatedLab' -VMNames @('dc1', 'svr1')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EventType,

        [Parameter(Mandatory)]
        [string]$LabName,

        [string[]]$VMNames = @(),

        [hashtable]$Metadata = @{}
    )

    try {
        $analyticsConfig = Get-LabAnalyticsConfig

        if (-not $analyticsConfig.Enabled) {
            return
        }

        $storagePath = $analyticsConfig.StoragePath
        $parentDir = Split-Path -Parent $storagePath

        if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path $parentDir)) {
            $null = New-Item -Path $parentDir -ItemType Directory -Force
            Write-Verbose "Created directory: $parentDir"
        }

        $event = [pscustomobject]@{
            Timestamp = Get-Date -Format 'o'
            EventType = $EventType
            LabName   = $LabName
            VMNames   = @($VMNames)
            Metadata  = if ($Metadata.Count -gt 0) { $Metadata } else { $null }
            Host      = $env:COMPUTERNAME
            User      = "$env:USERDOMAIN\$env:USERNAME"
        }

        if ((Test-Path $storagePath)) {
            $existing = Get-Content -Raw -Path $storagePath | ConvertFrom-Json
            if ($existing.events) {
                $existing.events += @($event)
            } else {
                $existing = [pscustomobject]@{ events = @($event) }
            }
        } else {
            $existing = [pscustomobject]@{ events = @($event) }
        }

        $existing | ConvertTo-Json -Depth 8 | Set-Content -Path $storagePath -Encoding UTF8
    }
    catch {
        Write-Warning "Write-LabAnalyticsEvent: failed to write analytics event to '$storagePath' - $_"
    }
}

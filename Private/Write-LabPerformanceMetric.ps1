function Write-LabPerformanceMetric {
    <#
    .SYNOPSIS
        Writes a performance metric to the lab performance log.

    .DESCRIPTION
        Write-LabPerformanceMetric appends a new metric record to the performance log,
        creating the file if it doesn't exist. Metrics include timestamp, operation
        type, VM name, duration, success status, and optional metadata. Non-blocking
        operation that logs errors but doesn't throw.

    .PARAMETER Operation
        Type of operation: 'VMStart', 'VMStop', 'VMSuspend', 'VMCheckpoint',
        'VMRestore', 'LabDeploy', 'LabTeardown', etc.

    .PARAMETER VMName
        Name of the VM this metric relates to (optional for lab-wide operations).

    .PARAMETER Duration
        Duration of the operation in milliseconds.

    .PARAMETER Success
        Whether the operation completed successfully.

    .PARAMETER Metadata
        Additional metric metadata as hashtable (optional).

    .EXAMPLE
        Write-LabPerformanceMetric -Operation 'VMStart' -VMName 'dc1' -Duration 15234 -Success $true
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Operation,

        [string]$VMName = '',

        [Parameter(Mandatory)]
        [long]$Duration,

        [Parameter(Mandatory)]
        [bool]$Success,

        [hashtable]$Metadata = @{}
    )

    try {
        $performanceConfig = Get-LabPerformanceConfig

        if (-not $performanceConfig.Enabled) {
            return
        }

        $storagePath = $performanceConfig.StoragePath
        $parentDir = Split-Path -Parent $storagePath

        if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path $parentDir)) {
            $null = New-Item -Path $parentDir -ItemType Directory -Force
            Write-Verbose "Created directory: $parentDir"
        }

        $metric = [pscustomobject]@{
            Timestamp = Get-Date -Format 'o'
            Operation = $Operation
            VMName    = $VMName
            Duration  = $Duration
            Success   = $Success
            Metadata  = if ($Metadata.Count -gt 0) { $Metadata } else { $null }
            Host      = $env:COMPUTERNAME
        }

        if ((Test-Path $storagePath)) {
            $existing = Get-Content -Raw -Path $storagePath | ConvertFrom-Json
            if ($existing.metrics) {
                $existing.metrics += @($metric)
            } else {
                $existing = [pscustomobject]@{ metrics = @($metric) }
            }
        } else {
            $existing = [pscustomobject]@{ metrics = @($metric) }
        }

        $existing | ConvertTo-Json -Depth 8 | Set-Content -Path $storagePath -Encoding UTF8

        Invoke-LabPerformanceRetention -StoragePath $storagePath -RetentionDays $performanceConfig.RetentionDays
    }
    catch {
        Write-Warning "Write-LabPerformanceMetric: failed to write metric to '$storagePath' - $_"
    }
}

function Invoke-LabPerformanceRetention {
    <#
    .SYNOPSIS
        Removes old performance metrics based on retention policy.

    .DESCRIPTION
        Internal helper that removes metrics older than the retention period.
        Only processes retention if the retention period is greater than 0.
    #>
    [CmdletBinding()]
    param(
        [string]$StoragePath,
        [int]$RetentionDays
    )

    if ($RetentionDays -le 0) {
        return
    }

    try {
        if (-not (Test-Path $StoragePath)) {
            return
        }

        $data = Get-Content -Raw -Path $StoragePath | ConvertFrom-Json
        $cutoffDate = (Get-Date).AddDays(-$RetentionDays)

        if ($data.metrics) {
            $filteredMetrics = @($data.metrics | Where-Object {
                try {
                    [DateTime]::Parse($_.Timestamp) -gt $cutoffDate
                }
                catch {
                    $true
                }
            })

            if ($filteredMetrics.Count -lt $data.metrics.Count) {
                $result = [pscustomobject]@{ metrics = $filteredMetrics }
                $result | ConvertTo-Json -Depth 8 | Set-Content -Path $StoragePath -Encoding UTF8
                Write-Verbose "Removed $($data.metrics.Count - $filteredMetrics.Count) old performance metrics"
            }
        }
    }
    catch {
        Write-Warning "Invoke-LabPerformanceRetention: failed to apply retention - $_"
    }
}

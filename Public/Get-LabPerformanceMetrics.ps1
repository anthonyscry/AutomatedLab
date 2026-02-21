function Get-LabPerformanceMetrics {
    <#
    .SYNOPSIS
        Retrieves and aggregates performance metrics for lab operations.

    .DESCRIPTION
        Get-LabPerformanceMetrics reads metrics from the performance log and
        returns either raw metrics or aggregated statistics. Supports filtering
        by operation type, VM name, date range, and success status.

    .PARAMETER Operation
        Filter to specific operation type: 'VMStart', 'VMStop', 'VMSuspend',
        'VMCheckpoint', 'VMRestore', 'LabDeploy', 'LabTeardown', etc.

    .PARAMETER VMName
        Filter to specific VM name (optional).

    .PARAMETER Success
        Filter to successful ($true) or failed ($false) operations (optional).

    .PARAMETER After
        Only include metrics after this DateTime (optional).

    .PARAMETER Before
        Only include metrics before this DateTime (optional).

    .PARAMETER Aggregated
        Return aggregated statistics instead of raw metrics (default: $true).

    .PARAMETER Last
        Return only the last N raw metrics when Aggregated is $false (default: 100).

    .EXAMPLE
        Get-LabPerformanceMetrics -Operation 'VMStart'
        Returns aggregated statistics for VMStart operations.

    .EXAMPLE
        Get-LabPerformanceMetrics -VMName 'dc1' -Aggregated:$false -Last 50
        Returns last 50 raw metrics for dc1 VM.

    .EXAMPLE
        Get-LabPerformanceMetrics -Operation 'VMStart' -Success $true
        Returns aggregated statistics for successful VMStart operations.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Operation,

        [string]$VMName,

        [bool]$Success,

        [DateTime]$After,

        [DateTime]$Before,

        [switch]$Aggregated = $true,

        [int]$Last = 100
    )

    $performanceConfig = Get-LabPerformanceConfig
    $storagePath = $performanceConfig.StoragePath

    if (-not (Test-Path $storagePath)) {
        Write-Warning "Performance metrics file not found at '$storagePath'"
        if ($Aggregated) {
            return [pscustomobject]@{
                Operation          = $Operation
                VMName             = $VMName
                Min                = $null
                Max                = $null
                Avg                = $null
                Percentile50       = $null
                Percentile90       = $null
                Percentile95       = $null
                TotalCount         = 0
                SuccessCount       = 0
                FailureCount       = 0
                SuccessRatePercent = 0
            }
        }
        else {
            return @()
        }
    }

    try {
        $data = Get-Content -Raw -Path $storagePath | ConvertFrom-Json
        $metrics = if ($data.metrics) { @($data.metrics) } else { @() }
    }
    catch {
        Write-Warning "Failed to read performance metrics file '$storagePath': $($_.Exception.Message)"
        if ($Aggregated) {
            return [pscustomobject]@{
                Operation          = $Operation
                VMName             = $VMName
                Min                = $null
                Max                = $null
                Avg                = $null
                Percentile50       = $null
                Percentile90       = $null
                Percentile95       = $null
                TotalCount         = 0
                SuccessCount       = 0
                FailureCount       = 0
                SuccessRatePercent = 0
            }
        }
        else {
            return @()
        }
    }

    $filtered = $metrics

    if ($PSBoundParameters.ContainsKey('Operation')) {
        $filtered = @($filtered | Where-Object { $_.Operation -eq $Operation })
    }

    if ($PSBoundParameters.ContainsKey('VMName')) {
        $filtered = @($filtered | Where-Object { $_.VMName -eq $VMName })
    }

    if ($PSBoundParameters.ContainsKey('Success')) {
        $filtered = @($filtered | Where-Object { $_.Success -eq $Success })
    }

    if ($PSBoundParameters.ContainsKey('After')) {
        $filtered = @($filtered | Where-Object {
            try {
                [DateTime]::Parse($_.Timestamp) -gt $After
            }
            catch {
                $false
            }
        })
    }

    if ($PSBoundParameters.ContainsKey('Before')) {
        $filtered = @($filtered | Where-Object {
            try {
                [DateTime]::Parse($_.Timestamp) -lt $Before
            }
            catch {
                $false
            }
        })
    }

    if ($Aggregated) {
        $coreParams = @{
            Metrics = $filtered
        }

        if ($PSBoundParameters.ContainsKey('Operation')) {
            $coreParams['Operation'] = $Operation
        }

        if ($PSBoundParameters.ContainsKey('VMName')) {
            $coreParams['VMName'] = $VMName
        }

        if ($PSBoundParameters.ContainsKey('Success')) {
            $coreParams['Success'] = $Success
        }

        if ($PSBoundParameters.ContainsKey('After')) {
            $coreParams['After'] = $After
        }

        if ($PSBoundParameters.ContainsKey('Before')) {
            $coreParams['Before'] = $Before
        }

        return Get-LabPerformanceMetricsCore @coreParams
    }
    else {
        $sorted = @($filtered | Sort-Object -Property @{ Expression = { [DateTime]::Parse($_.Timestamp) }; Descending = $true })
        return @($sorted | Select-Object -First $Last)
    }
}


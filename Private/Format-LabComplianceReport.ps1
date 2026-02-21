function Format-LabComplianceReport {
    <#
    .SYNOPSIS
        Formats compliance data into console, HTML, CSV, or JSON output.

    .DESCRIPTION
        Format-LabComplianceReport takes processed compliance data and generates
        formatted output in the specified format. Supports console tables,
        HTML reports with styling, CSV exports, and JSON exports. Includes
        pass/fail summary statistics and compliance rate calculations.

    .PARAMETER ComplianceData
        Processed compliance data with VMName, Role, Status, STIGVersion fields.

    .PARAMETER Format
        Output format: 'Console', 'Html', 'Csv', 'Json'.

    .PARAMETER LabName
        Name of the lab for the report header.

    .PARAMETER ThresholdPercent
        Compliance threshold percentage for warnings.

    .PARAMETER OutputPath
        Path to save the report file (required for Html, Csv, Json formats).

    .PARAMETER IncludeDetails
        Include detailed rule-level information if available.

    .OUTPUTS
        For Console: Formatted string output
        For Html/Csv/Json: Path to saved file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [pscustomobject[]]$ComplianceData = @(),

        [Parameter(Mandatory)]
        [ValidateSet('Console', 'Html', 'Csv', 'Json')]
        [string]$Format,

        [string]$LabName = 'AutomatedLab',

        [int]$ThresholdPercent = 80,

        [string]$OutputPath,

        [switch]$IncludeDetails
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $totalVMs = $ComplianceData.Count
    $compliantVMs = @($ComplianceData | Where-Object { $_.Status -eq 'Compliant' }).Count
    $nonCompliantVMs = @($ComplianceData | Where-Object { $_.Status -eq 'NonCompliant' }).Count
    $failedVMs = @($ComplianceData | Where-Object { $_.Status -eq 'Failed' }).Count
    $pendingVMs = @($ComplianceData | Where-Object { $_.Status -eq 'Pending' }).Count

    $complianceRate = if ($totalVMs -gt 0) {
        [math]::Round(($compliantVMs / $totalVMs) * 100, 1)
    } else {
        0.0
    }

    $thresholdMet = $complianceRate -ge $ThresholdPercent

    switch ($Format) {
        'Console' {
            $output = [System.Text.StringBuilder]::new()
            [void]$output.AppendLine('')
            [void]$output.AppendLine('  +--------------------------------------------------------------+')
            [void]$output.AppendLine('  |                    COMPLIANCE REPORT                       |')
            [void]$output.AppendLine('  +--------------------------------------------------------------+')
            [void]$output.AppendLine("  Lab:           $LabName")
            [void]$output.AppendLine("  Generated:     $timestamp")
            [void]$output.AppendLine('')
            [void]$output.AppendLine('  SUMMARY')
            [void]$output.AppendLine('  -------')
            [void]$output.AppendLine("  Total VMs:         $totalVMs")
            [void]$output.AppendLine("  Compliant:         $compliantVMs")
            [void]$output.AppendLine("  Non-Compliant:     $nonCompliantVMs")
            [void]$output.AppendLine("  Failed:            $failedVMs")
            [void]$output.AppendLine("  Pending:           $pendingVMs")
            [void]$output.AppendLine("  Compliance Rate:   $complianceRate% (Threshold: $ThresholdPercent%)")

            if (-not $thresholdMet) {
                [void]$output.AppendLine('')
                [void]$output.AppendLine("  WARNING: Compliance rate below threshold of $ThresholdPercent%")
            }

            [void]$output.AppendLine('')
            [void]$output.AppendLine('  VM DETAILS')
            [void]$output.AppendLine('  -----------')
            [void]$output.AppendLine('  VM Name      Role      STIG Ver.   Status           Exceptions    Last Checked')
            [void]$output.AppendLine('  -------      ----      --------   ------           ----------    -----------')

            foreach ($vm in $ComplianceData) {
                $statusColor = switch ($vm.Status) {
                    'Compliant'     { 'OK' }
                    'NonCompliant'  { 'WARN' }
                    'Failed'        { 'FAIL' }
                    'Pending'       { 'PEND' }
                }

                [void]$output.AppendLine(("  {0,-12} {1,-8} {2,-10} {3,-16} {4,-12} {5}" -f
                    $vm.VMName,
                    $vm.Role,
                    $vm.STIGVersion,
                    $statusColor,
                    $vm.ExceptionsApplied,
                    $vm.LastChecked))
            }

            Write-Host $output.ToString()
        }

        'Html' {
            if (-not $OutputPath) {
                Write-Error "OutputPath is required for Html format"
                return
            }

            $statusColor = switch ($complianceRate) {
                { $_ -ge 90 } { '#a6e3a1' }
                { $_ -ge 80 } { '#f9e2af' }
                { $_ -ge 70 } { '#fab387' }
                default      { '#f38ba8' }
            }

            $vmRows = ($ComplianceData | ForEach-Object {
                $statusClass = switch ($_.Status) {
                    'Compliant'     { 'compliant' }
                    'NonCompliant'  { 'noncompliant' }
                    'Failed'        { 'failed' }
                    'Pending'       { 'pending' }
                }
                ("        <tr class=`"$statusClass`"><td>$($_.VMName)</td><td>$($_.Role)</td><td>$($_.STIGVersion)</td><td>$($_.Status)</td><td>$($_.ExceptionsApplied)</td><td>$($_.LastChecked)</td></tr>")
            }) -join "`n"

            $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Compliance Report - $LabName</title>
<style>
  body { font-family: 'Segoe UI', Tahoma, sans-serif; margin: 40px; background: #1e1e2e; color: #cdd6f4; }
  h1 { color: #cba6f7; border-bottom: 2px solid #45475a; padding-bottom: 10px; }
  .meta { color: #a6adc8; margin-bottom: 20px; }
  .meta span { display: inline-block; margin-right: 30px; }
  .summary { background: #313244; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
  .summary h2 { margin-top: 0; color: #89b4fa; }
  .stat-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; }
  .stat-box { background: #45475a; padding: 15px; border-radius: 6px; text-align: center; }
  .stat-value { font-size: 2em; font-weight: bold; color: #f38ba8; }
  .stat-label { color: #a6adc8; font-size: 0.9em; }
  .compliance-rate { text-align: center; padding: 20px; }
  .rate-value { font-size: 3em; font-weight: bold; color: $statusColor; }
  .rate-label { color: #a6adc8; }
  table { border-collapse: collapse; width: 100%; margin-top: 20px; }
  th { background: #313244; color: #cba6f7; padding: 10px 15px; text-align: left; }
  td { padding: 8px 15px; border-bottom: 1px solid #45475a; }
  tr.compliant td:last-child { color: #a6e3a1; font-weight: bold; }
  tr.noncompliant td:last-child { color: #f9e2af; font-weight: bold; }
  tr.failed td:last-child { color: #f38ba8; font-weight: bold; }
  tr.pending td:last-child { color: #94e2d5; font-weight: bold; }
  .footer { margin-top: 30px; color: #6c7086; font-size: 0.85em; }
</style>
</head>
<body>
  <h1>STIG Compliance Report</h1>
  <div class="meta">
    <span>Lab: <strong>$LabName</strong></span>
    <span>Generated: <strong>$timestamp</strong></span>
  </div>

  <div class="summary">
    <h2>Compliance Summary</h2>
    <div class="stat-grid">
      <div class="stat-box">
        <div class="stat-value">$totalVMs</div>
        <div class="stat-label">Total VMs</div>
      </div>
      <div class="stat-box">
        <div class="stat-value">$compliantVMs</div>
        <div class="stat-label">Compliant</div>
      </div>
      <div class="stat-box">
        <div class="stat-value">$nonCompliantVMs</div>
        <div class="stat-label">Non-Compliant</div>
      </div>
    </div>
  </div>

  <div class="compliance-rate">
    <div class="rate-value">$complianceRate%</div>
    <div class="rate-label">Compliance Rate (Threshold: $ThresholdPercent%)</div>
  </div>

  <table>
    <thead>
      <tr><th>VM Name</th><th>Role</th><th>STIG Version</th><th>Status</th><th>Exceptions</th><th>Last Checked</th></tr>
    </thead>
    <tbody>
$vmRows
    </tbody>
  </table>

  <div class="footer">Generated by AutomatedLab on $timestamp</div>
</body>
</html>
"@

            $parentDir = Split-Path -Parent $OutputPath
            if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path $parentDir)) {
                $null = New-Item -Path $parentDir -ItemType Directory -Force
            }

            [System.IO.File]::WriteAllText($OutputPath, $html, [System.Text.Encoding]::UTF8)
            $resolvedPath = (Resolve-Path $OutputPath).Path
            Write-Host "`n  Compliance report saved: $resolvedPath" -ForegroundColor Cyan
            return $resolvedPath
        }

        'Csv' {
            if (-not $OutputPath) {
                Write-Error "OutputPath is required for Csv format"
                return
            }

            $ComplianceData | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
            $resolvedPath = (Resolve-Path $OutputPath).Path
            Write-Host "`n  Compliance report saved: $resolvedPath" -ForegroundColor Cyan
            return $resolvedPath
        }

        'Json' {
            if (-not $OutputPath) {
                Write-Error "OutputPath is required for Json format"
                return
            }

            $reportData = [pscustomobject]@{
                LabName            = $LabName
                GeneratedAt        = $timestamp
                Summary            = [pscustomobject]@{
                    TotalVMs             = $totalVMs
                    CompliantVMs         = $compliantVMs
                    NonCompliantVMs      = $nonCompliantVMs
                    FailedVMs            = $failedVMs
                    PendingVMs           = $pendingVMs
                    ComplianceRate       = $complianceRate
                    ThresholdPercent     = $ThresholdPercent
                    ThresholdMet         = $thresholdMet
                }
                VMs                = $ComplianceData
            }

            $reportData | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding UTF8
            $resolvedPath = (Resolve-Path $OutputPath).Path
            Write-Host "`n  Compliance report saved: $resolvedPath" -ForegroundColor Cyan
            return $resolvedPath
        }
    }
}

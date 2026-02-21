function Format-LabResourceReport {
    <#
    .SYNOPSIS
        Formats resource utilization data into console, HTML, CSV, or JSON output.

    .DESCRIPTION
        Format-LabResourceReport takes processed resource data and generates
        formatted output in the specified format. Supports console tables,
        HTML reports with visual indicators, CSV exports, and JSON exports.
        Includes bottleneck identification and usage pattern analysis.

    .PARAMETER ResourceData
        Per-VM resource metrics with VMName, CPUPercent, MemoryGB, DiskGB fields.

    .PARAMETER TrendData
        Aggregated trend data with time-based averages and peaks (optional).

    .PARAMETER Format
        Output format: 'Console', 'Html', 'Csv', 'Json'.

    .PARAMETER LabName
        Name of the lab for the report header.

    .PARAMETER OutputPath
        Path to save the report file (required for Html, Csv, Json formats).

    .PARAMETER Thresholds
        Hashtable with warning thresholds for CPU, Memory, Disk (optional).

    .OUTPUTS
        For Console: Formatted string output
        For Html/Csv/Json: Path to saved file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [pscustomobject[]]$ResourceData = @(),

        [pscustomobject[]]$TrendData = @(),

        [Parameter(Mandatory = $false)]
        [ValidateSet('Console', 'Html', 'Csv', 'Json')]
        [string]$Format = 'Console',

        [string]$LabName = 'AutomatedLab',

        [string]$OutputPath,

        [hashtable]$Thresholds = @{}
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $defaultThresholds = @{
        CPUWarning    = 70
        CPUCritical   = 90
        MemoryWarning = 80
        MemoryCritical = 95
        DiskWarning   = 80
        DiskCritical  = 95
    }

    foreach ($key in $defaultThresholds.Keys) {
        if (-not $Thresholds.ContainsKey($key)) {
            $Thresholds[$key] = $defaultThresholds[$key]
        }
    }

    $totalVMs = $ResourceData.Count

    # Extract metrics from various possible property names
    $avgCPU = if ($totalVMs -gt 0) {
        $cpuValues = @($ResourceData | ForEach-Object {
            if ($_.CPUPercent -ge 0) { $_.CPUPercent }
            elseif ($_.CPU -ge 0) { $_.CPU }
            else { 0 }
        } | Where-Object { $_ -gt 0 })
        if ($cpuValues.Count -gt 0) { [math]::Round(($cpuValues | Measure-Object -Average).Average, 1) } else { 0.0 }
    } else { 0.0 }

    $avgMemory = if ($totalVMs -gt 0) {
        $memValues = @($ResourceData | ForEach-Object {
            if ($_.MemoryGB -ge 0) { $_.MemoryGB }
            elseif ($_.Memory -ge 0) { $_.Memory / 1024 }
            else { 0 }
        } | Where-Object { $_ -gt 0 })
        if ($memValues.Count -gt 0) { [math]::Round(($memValues | Measure-Object -Average).Average, 2) } else { 0.0 }
    } else { 0.0 }

    $avgDisk = if ($totalVMs -gt 0) {
        $diskValues = @($ResourceData | ForEach-Object {
            if ($_.DiskUsagePercent -ge 0) { $_.DiskUsagePercent }
            elseif ($_.DiskGB -ge 0) { $_.DiskGB }
            elseif ($_.DiskUsageGB -ge 0) { $_.DiskUsageGB }
            else { 0 }
        } | Where-Object { $_ -gt 0 })
        if ($diskValues.Count -gt 0) { [math]::Round(($diskValues | Measure-Object -Average).Average, 2) } else { 0.0 }
    } else { 0.0 }

    $highCPUVMs = @($ResourceData | Where-Object {
        $cpu = if ($_.CPUPercent -ge 0) { $_.CPUPercent } elseif ($_.CPU -ge 0) { $_.CPU } else { 0 }
        $cpu -ge $Thresholds.CPUWarning
    })
    $highMemoryVMs = @($ResourceData | Where-Object {
        $mem = if ($_.MemoryGB -ge 0) { $_.MemoryGB } elseif ($_.Memory -ge 0) { $_.Memory / 1024 } else { 0 }
        $mem -ge $Thresholds.MemoryWarning
    })
    $highDiskVMs = @($ResourceData | Where-Object {
        $disk = if ($_.DiskUsagePercent -ge 0) { $_.DiskUsagePercent }
                 elseif ($_.DiskGB -ge 0) { $_.DiskGB }
                 elseif ($_.DiskUsageGB -ge 0) { $_.DiskUsageGB }
                 else { 0 }
        $disk -ge $Thresholds.DiskWarning
    })

    switch ($Format) {
        'Console' {
            $output = [System.Text.StringBuilder]::new()
            [void]$output.AppendLine('')
            [void]$output.AppendLine('  +--------------------------------------------------------------+')
            [void]$output.AppendLine('  |                  RESOURCE UTILIZATION REPORT               |')
            [void]$output.AppendLine('  +--------------------------------------------------------------+')
            [void]$output.AppendLine("  Lab:           $LabName")
            [void]$output.AppendLine("  Generated:     $timestamp")
            [void]$output.AppendLine('')
            [void]$output.AppendLine('  SUMMARY')
            [void]$output.AppendLine('  -------')
            [void]$output.AppendLine("  Total VMs:         $totalVMs")
            [void]$output.AppendLine("  Avg CPU:           $avgCPU% (High: $($highCPUVMs.Count))")
            [void]$output.AppendLine("  Avg Memory:        $avgMemory GB (High: $($highMemoryVMs.Count))")
            [void]$output.AppendLine("  Avg Disk:          $avgDisk% (High: $($highDiskVMs.Count))")

            if ($highCPUVMs.Count -gt 0 -or $highMemoryVMs.Count -gt 0 -or $highDiskVMs.Count -gt 0) {
                [void]$output.AppendLine('')
                [void]$output.AppendLine('  BOTTLENECKS DETECTED')
                [void]$output.AppendLine('  --------------------')

                if ($highCPUVMs.Count -gt 0) {
                    [void]$output.AppendLine("  High CPU (> $($Thresholds.CPUWarning)%): $($highCPUVMs.VMName -join ', ')")
                }
                if ($highMemoryVMs.Count -gt 0) {
                    [void]$output.AppendLine("  High Memory (> $($Thresholds.MemoryWarning)GB): $($highMemoryVMs.VMName -join ', ')")
                }
                if ($highDiskVMs.Count -gt 0) {
                    [void]$output.AppendLine("  High Disk (> $($Thresholds.DiskWarning)%): $($highDiskVMs.VMName -join ', ')")
                }
            }

            [void]$output.AppendLine('')
            [void]$output.AppendLine('  VM DETAILS')
            [void]$output.AppendLine('  -----------')
            [void]$output.AppendLine('  VM Name      CPU %     Memory GB   Disk %     Status')
            [void]$output.AppendLine('  -------      ------    ----------   -------    ------')

            foreach ($vm in $ResourceData) {
                $cpu = if ($vm.CPUPercent -ge 0) { $vm.CPUPercent } elseif ($vm.CPU -ge 0) { $vm.CPU } else { 0 }
                $mem = if ($vm.MemoryGB -ge 0) { $vm.MemoryGB } elseif ($vm.Memory -ge 0) { $vm.Memory / 1024 } else { 0 }
                $disk = if ($vm.DiskUsagePercent -ge 0) { $vm.DiskUsagePercent }
                        elseif ($vm.DiskGB -ge 0) { $vm.DiskGB }
                        elseif ($vm.DiskUsageGB -ge 0) { $vm.DiskUsageGB }
                        else { 0 }

                $status = switch ($cpu) {
                    { $_ -ge $Thresholds.CPUCritical } { 'CRIT' }
                    { $_ -ge $Thresholds.CPUWarning } { 'WARN' }
                    default { 'OK' }
                }

                if ($disk -ge $Thresholds.DiskCritical) {
                    $status = 'CRIT'
                } elseif ($disk -ge $Thresholds.DiskWarning) {
                    $status = 'WARN'
                }

                [void]$output.AppendLine(("  {0,-12} {1,-8} {2,-10} {3,-8} {4}" -f
                    $vm.VMName,
                    "$cpu%",
                    "$mem",
                    "$disk%",
                    $status))
            }

            Write-Host $output.ToString()
        }

        'Html' {
            if (-not $OutputPath) {
                Write-Error "OutputPath is required for Html format"
                return
            }

            $vmRows = ($ResourceData | ForEach-Object {
                $cpu = if ($_.CPUPercent -ge 0) { $_.CPUPercent } elseif ($_.CPU -ge 0) { $_.CPU } else { 0 }
                $mem = if ($_.MemoryGB -ge 0) { $_.MemoryGB } elseif ($_.Memory -ge 0) { $_.Memory / 1024 } else { 0 }
                $disk = if ($_.DiskUsagePercent -ge 0) { $_.DiskUsagePercent }
                        elseif ($_.DiskGB -ge 0) { $_.DiskGB }
                        elseif ($_.DiskUsageGB -ge 0) { $_.DiskUsageGB }
                        else { 0 }

                $statusClass = switch ($cpu) {
                    { $_ -ge $Thresholds.CPUCritical } { 'critical' }
                    { $_ -ge $Thresholds.CPUWarning } { 'warning' }
                    default { 'ok' }
                }

                if ($disk -ge $Thresholds.DiskCritical) {
                    $statusClass = 'critical'
                } elseif ($disk -ge $Thresholds.DiskWarning) {
                    $statusClass = 'warning'
                }

                ("        <tr class=`"$statusClass`"><td>$($_.VMName)</td><td>$cpu%</td><td>$mem GB</td><td>$disk%</td><td>$statusClass.ToUpper()</td></tr>")
            }) -join "`n"

            $bottlenecks = @()
            if ($highCPUVMs.Count -gt 0) {
                $bottlenecks += "<li>High CPU: $($highCPUVMs.VMName -join ', ')</li>"
            }
            if ($highMemoryVMs.Count -gt 0) {
                $bottlenecks += "<li>High Memory: $($highMemoryVMs.VMName -join ', ')</li>"
            }
            if ($highDiskVMs.Count -gt 0) {
                $bottlenecks += "<li>High Disk: $($highDiskVMs.VMName -join ', ')</li>"
            }
            $bottleneckHtml = if ($bottlenecks.Count -gt 0) {
                "<ul>$($bottlenecks -join '')</ul>"
            } else {
                "<p>No bottlenecks detected</p>"
            }

            $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Resource Report - $LabName</title>
<style>
  body { font-family: 'Segoe UI', Tahoma, sans-serif; margin: 40px; background: #1e1e2e; color: #cdd6f4; }
  h1 { color: #89b4fa; border-bottom: 2px solid #45475a; padding-bottom: 10px; }
  .meta { color: #a6adc8; margin-bottom: 20px; }
  .meta span { display: inline-block; margin-right: 30px; }
  .summary { background: #313244; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
  .summary h2 { margin-top: 0; color: #89b4fa; }
  .stat-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; }
  .stat-box { background: #45475a; padding: 15px; border-radius: 6px; text-align: center; }
  .stat-value { font-size: 2em; font-weight: bold; color: #f38ba8; }
  .stat-label { color: #a6adc8; font-size: 0.9em; }
  .bottlenecks { background: #313244; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
  .bottlenecks h2 { margin-top: 0; color: #fab387; }
  .bottlenecks ul { list-style: none; padding: 0; }
  .bottlenecks li { padding: 5px 0; }
  table { border-collapse: collapse; width: 100%; margin-top: 20px; }
  th { background: #313244; color: #cba6f7; padding: 10px 15px; text-align: left; }
  td { padding: 8px 15px; border-bottom: 1px solid #45475a; }
  tr.ok td:last-child { color: #a6e3a1; font-weight: bold; }
  tr.warning td:last-child { color: #f9e2af; font-weight: bold; }
  tr.critical td:last-child { color: #f38ba8; font-weight: bold; }
  .footer { margin-top: 30px; color: #6c7086; font-size: 0.85em; }
</style>
</head>
<body>
  <h1>Resource Utilization Report</h1>
  <div class="meta">
    <span>Lab: <strong>$LabName</strong></span>
    <span>Generated: <strong>$timestamp</strong></span>
  </div>

  <div class="summary">
    <h2>Resource Summary</h2>
    <div class="stat-grid">
      <div class="stat-box">
        <div class="stat-value">$avgCPU%</div>
        <div class="stat-label">Avg CPU</div>
      </div>
      <div class="stat-box">
        <div class="stat-value">$avgMemory GB</div>
        <div class="stat-label">Avg Memory</div>
      </div>
      <div class="stat-box">
        <div class="stat-value">$avgDisk%</div>
        <div class="stat-label">Avg Disk</div>
      </div>
    </div>
  </div>

  <div class="bottlenecks">
    <h2>Bottlenecks</h2>
    $bottleneckHtml
  </div>

  <table>
    <thead>
      <tr><th>VM Name</th><th>CPU</th><th>Memory</th><th>Disk</th><th>Status</th></tr>
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
            Write-Host "`n  Resource report saved: $resolvedPath" -ForegroundColor Cyan
            return $resolvedPath
        }

        'Csv' {
            if (-not $OutputPath) {
                Write-Error "OutputPath is required for Csv format"
                return
            }

            $csvData = $ResourceData | ForEach-Object {
                $cpu = if ($_.CPUPercent -ge 0) { $_.CPUPercent } elseif ($_.CPU -ge 0) { $_.CPU } else { 0 }
                $mem = if ($_.MemoryGB -ge 0) { $_.MemoryGB } elseif ($_.Memory -ge 0) { $_.Memory / 1024 } else { 0 }
                $disk = if ($_.DiskUsagePercent -ge 0) { $_.DiskUsagePercent }
                        elseif ($_.DiskGB -ge 0) { $_.DiskGB }
                        elseif ($_.DiskUsageGB -ge 0) { $_.DiskUsageGB }
                        else { 0 }

                [pscustomobject]@{
                    VMName     = $_.VMName
                    CPUPercent = $cpu
                    MemoryGB   = $mem
                    DiskGB     = $disk
                }
            }

            $csvData | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
            $resolvedPath = (Resolve-Path $OutputPath).Path
            Write-Host "`n  Resource report saved: $resolvedPath" -ForegroundColor Cyan
            return $resolvedPath
        }

        'Json' {
            if (-not $OutputPath) {
                Write-Error "OutputPath is required for Json format"
                return
            }

            $vmData = $ResourceData | ForEach-Object {
                $cpu = if ($_.CPUPercent -ge 0) { $_.CPUPercent } elseif ($_.CPU -ge 0) { $_.CPU } else { 0 }
                $mem = if ($_.MemoryGB -ge 0) { $_.MemoryGB } elseif ($_.Memory -ge 0) { $_.Memory / 1024 } else { 0 }
                $disk = if ($_.DiskUsagePercent -ge 0) { $_.DiskUsagePercent }
                        elseif ($_.DiskGB -ge 0) { $_.DiskGB }
                        elseif ($_.DiskUsageGB -ge 0) { $_.DiskUsageGB }
                        else { 0 }

                [pscustomobject]@{
                    VMName     = $_.VMName
                    CPUPercent = $cpu
                    MemoryGB   = $mem
                    DiskGB     = $disk
                }
            }

            $reportData = [pscustomobject]@{
                LabName            = $LabName
                GeneratedAt        = $timestamp
                Summary            = [pscustomobject]@{
                    TotalVMs        = $totalVMs
                    AvgCPU          = $avgCPU
                    AvgMemoryGB     = $avgMemory
                    AvgDiskGB       = $avgDisk
                    HighCPUVMs      = $highCPUVMs.VMName
                    HighMemoryVMs   = $highMemoryVMs.VMName
                    HighDiskVMs     = $highDiskVMs.VMName
                }
                VMs                = $vmData
                Trends             = $TrendData
            }

            $reportData | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding UTF8
            $resolvedPath = (Resolve-Path $OutputPath).Path
            Write-Host "`n  Resource report saved: $resolvedPath" -ForegroundColor Cyan
            return $resolvedPath
        }
    }
}

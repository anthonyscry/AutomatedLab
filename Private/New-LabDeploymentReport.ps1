# New-LabDeploymentReport.ps1 -- Generate deployment recap report
function New-LabDeploymentReport {
    <#
    .SYNOPSIS
    Generates a deployment recap report in HTML and console format.
    .DESCRIPTION
    Creates a summary of all deployed VMs, their roles, IPs, and status.
    Outputs both an HTML file and console-formatted text.
    .PARAMETER Machines
    Array of hashtables with machine info (VMName, IP, OS tag, Roles, Status).
    .PARAMETER LabName
    Name of the lab deployment.
    .PARAMETER OutputPath
    Directory to save the HTML report.
    .PARAMETER StartTime
    When the deployment started.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$Machines,
        [string]$LabName = 'AutomatedLab',
        [string]$OutputPath = (Join-Path 'C:\AutomatedLab' 'AutomatedLab'),
        [datetime]$StartTime = [datetime]::Now
    )

    try {
        $endTime = [datetime]::Now
        $duration = $endTime - $StartTime
        $durationStr = '{0:D2}h {1:D2}m {2:D2}s' -f [int]$duration.TotalHours, $duration.Minutes, $duration.Seconds
        $timestamp = $endTime.ToString('yyyy-MM-dd HH:mm:ss')
        $dateStamp = $endTime.ToString('yyyyMMdd-HHmmss')

        Write-Host ""
        Write-Host '  +----------------------------------------------+' -ForegroundColor Cyan
        Write-Host '  |           DEPLOYMENT RECAP REPORT            |' -ForegroundColor Cyan
        Write-Host '  +----------------------------------------------+' -ForegroundColor Cyan
        Write-Host ('  Lab:       {0}' -f $LabName) -ForegroundColor White
        Write-Host ('  Completed: {0}' -f $timestamp) -ForegroundColor White
        Write-Host ('  Duration:  {0}' -f $durationStr) -ForegroundColor White
        Write-Host ('  Machines:  {0}' -f $Machines.Count) -ForegroundColor White
        Write-Host ''

        Write-Host '  VM Name      OS      IP                Role(s)               Status' -ForegroundColor Gray
        Write-Host '  -------      --      --                -------               ------' -ForegroundColor Gray
        foreach ($m in $Machines) {
            $rolesText = @($m.Roles) -join ', '
            if ($rolesText.Length -gt 20) { $rolesText = $rolesText.Substring(0, 17) + '...' }
            $status = [string]$m.Status
            $statusColor = if ($status -eq 'OK') { 'Green' } elseif ($status -eq 'WARN') { 'Yellow' } else { 'Red' }

            Write-Host ('  {0,-12} {1,-7} {2,-17} {3,-20} ' -f $m.VMName, $m.OSTag, $m.IP, $rolesText) -NoNewline -ForegroundColor Gray
            Write-Host $status -ForegroundColor $statusColor
        }

        Write-Host ''
        Write-Host '  CONNECTION INFO:' -ForegroundColor Yellow
        foreach ($m in $Machines) {
            if ($m.OSTag -eq '[LIN]') {
                Write-Host ('    {0}: ssh -i (Join-Path (Join-Path $GlobalLabConfig.Paths.LabSourcesRoot SSHKeys) id_ed25519) {1}@{2}' -f $m.VMName, $GlobalLabConfig.Credentials.LinuxUser, $m.IP) -ForegroundColor Gray
            }
            else {
                $rdpUser = '{0}\{1}' -f $GlobalLabConfig.Lab.DomainName, $GlobalLabConfig.Credentials.InstallUser
                Write-Host ('    {0}: RDP to {1} ({2})' -f $m.VMName, $m.IP, $rdpUser) -ForegroundColor Gray
            }
        }
        Write-Host ''

        if ($OutputPath) {
            $htmlDir = $OutputPath
            New-Item -ItemType Directory -Path $htmlDir -Force | Out-Null
            $htmlPath = Join-Path $htmlDir ("DeployReport-{0}.html" -f $dateStamp)

            $machineRows = ($Machines | ForEach-Object {
                $statusClass = switch ($_.Status) { 'OK' { 'ok' } 'WARN' { 'warn' } default { 'fail' } }
                ('        <tr class="{0}"><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td></tr>' -f $statusClass, $_.VMName, $_.OSTag, $_.IP, (($_.Roles) -join ', '), $_.Status)
            }) -join "`n"

            $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Lab Deployment Report - $LabName</title>
<style>
  body { font-family: 'Segoe UI', Tahoma, sans-serif; margin: 40px; background: #1e1e2e; color: #cdd6f4; }
  h1 { color: #89b4fa; border-bottom: 2px solid #45475a; padding-bottom: 10px; }
  .meta { color: #a6adc8; margin-bottom: 20px; }
  .meta span { display: inline-block; margin-right: 30px; }
  table { border-collapse: collapse; width: 100%; margin-top: 20px; }
  th { background: #313244; color: #cba6f7; padding: 10px 15px; text-align: left; }
  td { padding: 8px 15px; border-bottom: 1px solid #45475a; }
  tr.ok td:last-child { color: #a6e3a1; font-weight: bold; }
  tr.warn td:last-child { color: #f9e2af; font-weight: bold; }
  tr.fail td:last-child { color: #f38ba8; font-weight: bold; }
  .footer { margin-top: 30px; color: #6c7086; font-size: 0.85em; }
</style>
</head>
<body>
  <h1>Lab Deployment Report</h1>
  <div class="meta">
    <span>Lab: <strong>$LabName</strong></span>
    <span>Date: <strong>$timestamp</strong></span>
    <span>Duration: <strong>$durationStr</strong></span>
    <span>Machines: <strong>$($Machines.Count)</strong></span>
  </div>
  <table>
    <thead>
      <tr><th>VM Name</th><th>OS</th><th>IP</th><th>Role(s)</th><th>Status</th></tr>
    </thead>
    <tbody>
$machineRows
    </tbody>
  </table>
  <div class="footer">Generated by LabBuilder on $timestamp</div>
</body>
</html>
"@

            [IO.File]::WriteAllText($htmlPath, $html, [System.Text.UTF8Encoding]::new($false))
            Write-Host ("  Report saved: {0}" -f $htmlPath) -ForegroundColor Green
            return $htmlPath
        }

        return $null
    }
    catch {
        $PSCmdlet.WriteError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("New-LabDeploymentReport: failed to generate deployment report - $_", $_.Exception),
                'New-LabDeploymentReport.Failure',
                [System.Management.Automation.ErrorCategory]::NotSpecified,
                $null
            )
        )
    }
}

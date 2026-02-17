# Lab-Status.ps1 -- Detailed status dashboard for OpenCode Dev Lab
# Shows VM states, resource usage, network info, share health,
# recent snapshots, and service status for the Windows lab topology.

#Requires -RunAsAdministrator

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = Split-Path -Parent $ScriptDir
$ConfigPath = Join-Path $RepoRoot 'Lab-Config.ps1'
$CommonPath = Join-Path $RepoRoot 'Lab-Common.ps1'
if (Test-Path $ConfigPath) { . $ConfigPath }
if (Test-Path $CommonPath) { . $CommonPath }

if (-not (Get-Variable -Name LabVMs -ErrorAction SilentlyContinue)) { @($GlobalLabConfig.Lab.CoreVMNames) = @('dc1','svr1','dsc','ws1') }

# Include Linux VMs if present
$lin1Exists = Hyper-V\Get-VM -Name 'LIN1' -ErrorAction SilentlyContinue
$allLabVMs = if ($lin1Exists) { @(@($GlobalLabConfig.Lab.CoreVMNames)) + @('LIN1') | Select-Object -Unique } else { @(@($GlobalLabConfig.Lab.CoreVMNames)) }



Write-Host "`n=== OPENCODE LAB STATUS ===" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# -- VM States + Resources --
Write-Host "`n  VM STATUS:" -ForegroundColor Yellow
$labVMObjects = Get-VM | Where-Object { $_.Name -in $allLabVMs }
foreach ($vm in $labVMObjects) {
    $osTag = if ($vm.Name -eq 'LIN1') { '[LIN]' } else { '[WIN]' }
    $color = if ($vm.State -eq 'Running') { 'Green' } else { 'Red' }
    $mem = if ($vm.MemoryAssigned -gt 0) { "$([math]::Round($vm.MemoryAssigned / 1GB, 1)) GB" } else { '--' }
    $cpu = "$($vm.ProcessorCount) vCPU"
    $uptime = if ($vm.Uptime.TotalMinutes -gt 0) { "$([math]::Round($vm.Uptime.TotalHours, 1))h" } else { '--' }
    Write-Host "    $osTag $($vm.Name.PadRight(6)) $($vm.State.ToString().PadRight(10)) RAM: $($mem.PadRight(8)) $cpu   Up: $uptime" -ForegroundColor $color
}

# -- Network --
Write-Host "`n  NETWORK:" -ForegroundColor Yellow
foreach ($vm in $labVMObjects) {
    $osTag = if ($vm.Name -eq 'LIN1') { '[LIN]' } else { '[WIN]' }
    $adapters = Get-VMNetworkAdapter -VMName $vm.Name -ErrorAction SilentlyContinue
    foreach ($a in $adapters) {
        $ips = $a.IPAddresses -join ', '
        if (-not $ips) { $ips = '(no IP yet)' }
        Write-Host "    $osTag $($vm.Name.PadRight(6)) $($a.SwitchName.PadRight(16)) $ips" -ForegroundColor Gray
    }
}

# -- Snapshots --
Write-Host "`n  SNAPSHOTS:" -ForegroundColor Yellow
$snaps = Get-VM | Where-Object { $_.Name -in $allLabVMs } | Get-VMSnapshot -ErrorAction SilentlyContinue
if ($snaps) {
    $snaps | Sort-Object CreationTime -Descending | Select-Object -First 5 | ForEach-Object {
        Write-Host "    $($_.VMName.PadRight(6)) $($_.Name.PadRight(25)) $(($_.CreationTime).ToString('MM/dd HH:mm'))" -ForegroundColor Gray
    }
    Write-Host "    ($($snaps.Count) total snapshots)" -ForegroundColor DarkGray
} else {
    Write-Host "    (none)" -ForegroundColor DarkGray
}

# -- Disk Usage --
Write-Host "`n  DISK:" -ForegroundColor Yellow
$labPath = (Join-Path $GlobalLabConfig.Paths.LabRoot $GlobalLabConfig.Lab.Name)
if (Test-Path $labPath) {
    $vhdxFiles = Get-ChildItem $labPath -Filter '*.vhdx' -Recurse -ErrorAction SilentlyContinue
    foreach ($vhd in $vhdxFiles) {
        $sizeGB = [math]::Round($vhd.Length / 1GB, 1)
        Write-Host "    $($vhd.Name.PadRight(30)) $sizeGB GB" -ForegroundColor Gray
    }
    $totalGB = [math]::Round(($vhdxFiles | Measure-Object -Property Length -Sum).Sum / 1GB, 1)
    Write-Host "    Total: $totalGB GB" -ForegroundColor Gray
}

# Try to import lab for Invoke-LabCommand (non-fatal)
$labImported = Import-OpenCodeLab -Name $GlobalLabConfig.Lab.Name

# -- Live checks (only if VMs are running) --
$running = $labVMObjects | Where-Object { $_.State -eq 'Running' }
if ($labImported -and ($running.Name -contains 'DC1')) {
    try {
        Import-Lab -Name $GlobalLabConfig.Lab.Name -ErrorAction Stop 2>$null

        Write-Host "`n  SERVICES (DC1):" -ForegroundColor Yellow
        $svcCheck = Invoke-LabCommand -ComputerName 'DC1' -ScriptBlock {
            $results = @()
            $results += "AD DS:    $((Get-Service NTDS -ErrorAction SilentlyContinue).Status)"
            $results += "DNS:      $((Get-Service DNS -ErrorAction SilentlyContinue).Status)"
            $results += "SMB:      $((Get-SmbShare -Name 'LabShare' -ErrorAction SilentlyContinue).Name)"
            $results += "SSH:      $((Get-Service sshd -ErrorAction SilentlyContinue).Status)"
            $results += "WinRM:    $((Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains 'Transport=HTTPS' }).Count) HTTPS listener(s)"
            $results
        } -PassThru -ErrorAction SilentlyContinue
        $svcCheck | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    } catch {
        Write-Verbose "DC1 live status check failed: $($_.Exception.Message)"
    }
}

if ($labImported -and ($running.Name -contains 'WS1')) {
    try {
        Write-Host "`n  SERVICES (WS1):" -ForegroundColor Yellow
        $ws1Check = Invoke-LabCommand -ComputerName 'WS1' -ScriptBlock {
            $results = @()
            $results += "AppIDSvc: $((Get-Service AppIDSvc -ErrorAction SilentlyContinue).Status)"
            $results += "L: drive: $(if (Test-Path 'L:\') { 'Mapped' } else { 'NOT MAPPED' })"
            $results
        } -PassThru -ErrorAction SilentlyContinue
        $ws1Check | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    } catch {
        Write-Verbose "WS1 live status check failed: $($_.Exception.Message)"
    }
}

if ($labImported -and ($running.Name -contains 'WSUS1')) {
    try {
        Write-Host "`n  SERVICES (WSUS1):" -ForegroundColor Yellow
        $wsusCheck = Invoke-LabCommand -ComputerName 'WSUS1' -ScriptBlock {
            $results = @()
            $cs = Get-CimInstance Win32_ComputerSystem
            $results += "Domain:   $($cs.Domain)"
            $results += "WinRM:    $((Get-Service WinRM -ErrorAction SilentlyContinue).Status)"
            $results += "Server:   $((Get-Service LanmanServer -ErrorAction SilentlyContinue).Status)"
            $results += "W32Time:  $((Get-Service W32Time -ErrorAction SilentlyContinue).Status)"
            $results
        } -PassThru -ErrorAction SilentlyContinue
        $wsusCheck | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    } catch {
        Write-Verbose "WSUS1 live status check failed: $($_.Exception.Message)"
    }
}

if ($labImported -and ($running.Name -contains 'LIN1')) {
    try {
        # Launch git and mount checks in parallel
        $bashCmd = 'for d in ' + $GlobalLabConfig.Paths.LinuxProjectsRoot + '/*/; do if [ -d "$d/.git" ]; then name=$(basename "$d"); cd "$d"; branch=$(git branch --show-current 2>/dev/null); changes=$(git status --porcelain 2>/dev/null | wc -l); remote=$(git remote get-url origin 2>/dev/null || echo "(no remote)"); echo "  $name [$branch] $changes uncommitted | $remote"; fi; done'
        $mountCmd = 'if mountpoint -q "' + $GlobalLabConfig.Paths.LinuxLabShareMount + '" 2>/dev/null; then echo "  ' + $GlobalLabConfig.Paths.LinuxLabShareMount + ': MOUNTED"; else echo "  ' + $GlobalLabConfig.Paths.LinuxLabShareMount + ': NOT MOUNTED"; fi'

        $gitJob = Start-Job -ScriptBlock {
            param($GlobalLabConfig.Lab.Name, $Cmd)
            Import-Lab -Name $GlobalLabConfig.Lab.Name -ErrorAction Stop 2>$null
            Invoke-LabCommand -ComputerName 'LIN1' -ScriptBlock {
                param($C); bash -lc $C
            } -ArgumentList $Cmd -PassThru -ErrorAction SilentlyContinue
        } -ArgumentList $GlobalLabConfig.Lab.Name, $bashCmd

        $mountJob = Start-Job -ScriptBlock {
            param($GlobalLabConfig.Lab.Name, $Cmd)
            Import-Lab -Name $GlobalLabConfig.Lab.Name -ErrorAction Stop 2>$null
            Invoke-LabCommand -ComputerName 'LIN1' -ScriptBlock {
                param($C); bash -lc $C
            } -ArgumentList $Cmd -PassThru -ErrorAction SilentlyContinue
        } -ArgumentList $GlobalLabConfig.Lab.Name, $mountCmd

        # Wait with 30s timeout
        $null = Wait-Job -Job $gitJob, $mountJob -Timeout 30

        Write-Host "`n  GIT PROJECTS (LIN1):" -ForegroundColor Yellow
        if ($gitJob.State -eq 'Completed') {
            $gitStatus = Receive-Job -Job $gitJob -ErrorAction SilentlyContinue
            if ($gitStatus) {
                $gitStatus | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
            } else {
                Write-Host "    (no projects)" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "    (timed out)" -ForegroundColor DarkGray
            Stop-Job -Job $gitJob -ErrorAction SilentlyContinue
        }

        Write-Host "`n  MOUNT (LIN1):" -ForegroundColor Yellow
        if ($mountJob.State -eq 'Completed') {
            $mountCheck = Receive-Job -Job $mountJob -ErrorAction SilentlyContinue
            $mountCheck | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
        } else {
            Write-Host "    (timed out)" -ForegroundColor DarkGray
            Stop-Job -Job $mountJob -ErrorAction SilentlyContinue
        }

        Remove-Job -Job $gitJob, $mountJob -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Verbose "LIN1 live status check failed: $($_.Exception.Message)"
    }
}

if ($lin1Exists -and ($running.Name -contains 'LIN1')) {
    $sshInfo = Get-LinuxSSHConnectionInfo -VMName 'LIN1'
    if ($sshInfo) {
        Write-Host "`n  SSH CONNECTION (LIN1):" -ForegroundColor Yellow
        Write-Host "    $($sshInfo.Command)" -ForegroundColor Gray
    }
}

Write-Host "`n=== END STATUS ===" -ForegroundColor Cyan
Write-Host ""

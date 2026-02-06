# Lab-Status.ps1 -- Detailed status dashboard for OpenCode Dev Lab
# Shows VM states, resource usage, network info, share health,
# recent snapshots, and Git status on LIN1.

#Requires -RunAsAdministrator

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ConfigPath = Join-Path $ScriptDir 'Lab-Config.ps1'
$CommonPath = Join-Path $ScriptDir 'Lab-Common.ps1'
if (Test-Path $ConfigPath) { . $ConfigPath }
if (Test-Path $CommonPath) { . $CommonPath }



Write-Host "`n=== OPENCODE LAB STATUS ===" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

# -- VM States + Resources --
Write-Host "`n  VM STATUS:" -ForegroundColor Yellow
$labVMs = Get-VM | Where-Object { $_.Name -in 'DC1','WS1','LIN1' }
foreach ($vm in $labVMs) {
    $color = if ($vm.State -eq 'Running') { 'Green' } else { 'Red' }
    $mem = if ($vm.MemoryAssigned -gt 0) { "$([math]::Round($vm.MemoryAssigned / 1GB, 1)) GB" } else { '--' }
    $cpu = "$($vm.ProcessorCount) vCPU"
    $uptime = if ($vm.Uptime.TotalMinutes -gt 0) { "$([math]::Round($vm.Uptime.TotalHours, 1))h" } else { '--' }
    Write-Host "    $($vm.Name.PadRight(6)) $($vm.State.ToString().PadRight(10)) RAM: $($mem.PadRight(8)) $cpu   Up: $uptime" -ForegroundColor $color
}

# -- Network --
Write-Host "`n  NETWORK:" -ForegroundColor Yellow
foreach ($vm in $labVMs) {
    $adapters = Get-VMNetworkAdapter -VMName $vm.Name -ErrorAction SilentlyContinue
    foreach ($a in $adapters) {
        $ips = $a.IPAddresses -join ', '
        if (-not $ips) { $ips = '(no IP yet)' }
        Write-Host "    $($vm.Name.PadRight(6)) $($a.SwitchName.PadRight(16)) $ips" -ForegroundColor Gray
    }
}

# -- Snapshots --
Write-Host "`n  SNAPSHOTS:" -ForegroundColor Yellow
$snaps = Get-VM | Where-Object { $_.Name -in 'DC1','WS1','LIN1' } | Get-VMSnapshot -ErrorAction SilentlyContinue
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
$labPath = 'C:\AutomatedLab\OpenCodeLab'
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
$labImported = Import-OpenCodeLab -Name $LabName

# -- Live checks (only if VMs are running) --
$running = $labVMs | Where-Object { $_.State -eq 'Running' }
if ($running.Name -contains 'DC1') {
    try {
        Import-Lab -Name $LabName -ErrorAction Stop 2>$null

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
    } catch {}
}

if ($running.Name -contains 'WS1') {
    try {
        Write-Host "`n  SERVICES (WS1):" -ForegroundColor Yellow
        $ws1Check = Invoke-LabCommand -ComputerName 'WS1' -ScriptBlock {
            $results = @()
            $results += "AppIDSvc: $((Get-Service AppIDSvc -ErrorAction SilentlyContinue).Status)"
            $results += "L: drive: $(if (Test-Path 'L:\') { 'Mapped' } else { 'NOT MAPPED' })"
            $results
        } -PassThru -ErrorAction SilentlyContinue
        $ws1Check | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    } catch {}
}

if ($running.Name -contains 'LIN1') {
    try {
        Write-Host "`n  GIT PROJECTS (LIN1):" -ForegroundColor Yellow
        $bashCmd = 'for d in ' + $LinuxProjectsRoot + '/*/; do if [ -d "$d/.git" ]; then name=$(basename "$d"); cd "$d"; branch=$(git branch --show-current 2>/dev/null); changes=$(git status --porcelain 2>/dev/null | wc -l); remote=$(git remote get-url origin 2>/dev/null || echo "(no remote)"); echo "  $name [$branch] $changes uncommitted | $remote"; fi; done'
        $gitStatus = Invoke-LabCommand -ComputerName 'LIN1' -ScriptBlock {
            param($Cmd)
            bash -lc $Cmd
        } -ArgumentList $bashCmd -PassThru -ErrorAction SilentlyContinue
        if ($gitStatus) {
            $gitStatus | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
        } else {
            Write-Host "    (no projects)" -ForegroundColor DarkGray
        }

        Write-Host "`n  MOUNT (LIN1):" -ForegroundColor Yellow
        $mountCmd = 'if mountpoint -q "' + $LinuxLabShareMount + '" 2>/dev/null; then echo "  ' + $LinuxLabShareMount + ': MOUNTED"; else echo "  ' + $LinuxLabShareMount + ': NOT MOUNTED"; fi'
        $mountCheck = Invoke-LabCommand -ComputerName 'LIN1' -ScriptBlock {
            param($Cmd)
            bash -lc $Cmd
        } -ArgumentList $mountCmd -PassThru -ErrorAction SilentlyContinue
        $mountCheck | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
    } catch {}
}

Write-Host "`n=== END STATUS ===" -ForegroundColor Cyan
Write-Host ""
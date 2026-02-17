# Invoke-LabBlowAway.ps1
# Performs full lab teardown: stops VMs, removes AutomatedLab definition,
# removes Hyper-V VMs, deletes lab files, optionally removes network.

function Invoke-LabBlowAway {
    [CmdletBinding()]
    param(
        [switch]$BypassPrompt,
        [switch]$DropNetwork,
        [switch]$Simulate,
        [Parameter(Mandatory)][hashtable]$LabConfig,
        [Parameter(Mandatory)][string]$SwitchName,
        [Parameter(Mandatory)][System.Collections.Generic.List[object]]$RunEvents
    )

    if ($Simulate) {
        Write-Host "`n=== DRY RUN: BLOW AWAY LAB ===" -ForegroundColor Yellow
        Write-Host "  Would stop lab VMs: $(@($LabConfig.Lab.CoreVMNames) -join ', ')" -ForegroundColor DarkGray
        Write-Host "  Would remove lab definition: $($LabConfig.Lab.Name)" -ForegroundColor DarkGray
        Write-Host "  Would remove lab files: $(Join-Path $LabConfig.Paths.LabRoot $LabConfig.Lab.Name)" -ForegroundColor DarkGray
        Write-Host "  Would clear SSH known_hosts entries" -ForegroundColor DarkGray
        if ($DropNetwork) {
            Write-Host "  Would remove network: $SwitchName / $($LabConfig.Network.NatName)" -ForegroundColor DarkGray
        }
        Add-LabRunEvent -Step 'blow-away' -Status 'dry-run' -Message 'No changes made' -RunEvents $RunEvents
        return
    }

    Write-Host "`n=== BLOW AWAY LAB ===" -ForegroundColor Red
    Write-Host "  This will stop VMs, remove lab definition, and delete local lab files." -ForegroundColor Yellow
    if ($DropNetwork) {
        Write-Host "  Network objects ($SwitchName / $($LabConfig.Network.NatName)) will also be removed." -ForegroundColor Yellow
    }

    if (-not $BypassPrompt) {
        $confirm = Read-Host "  Type BLOW-IT-AWAY to continue"
        if ($confirm -ne 'BLOW-IT-AWAY') {
            Write-Host "  [ABORT] Cancelled" -ForegroundColor Yellow
            return
        }
    }

    Write-Host "`n  [1/5] Stopping lab VMs..." -ForegroundColor Cyan
    Stop-LabVMsSafe -LabName $LabConfig.Lab.Name -CoreVMNames @($LabConfig.Lab.CoreVMNames)

    Write-Host "  [2/5] Removing AutomatedLab definition..." -ForegroundColor Cyan
    try {
        Import-Module AutomatedLab -ErrorAction SilentlyContinue | Out-Null

        # Remove-Lab can emit noisy non-terminating errors for already-missing
        # metadata files (for example Network_<switch>.xml). Those are benign
        # during blow-away, so suppress raw error stream and continue cleanup.
        Remove-Lab -Name $LabConfig.Lab.Name -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 2>$null
    }
    catch {
        Write-LabStatus -Status WARN -Message "Remove-Lab returned: $($_.Exception.Message)"
    }

    Write-Host "  [3/5] Removing Hyper-V VMs/checkpoints if present..." -ForegroundColor Cyan
    $allLabVMs = @(@($LabConfig.Lab.CoreVMNames)) + @('LIN1')
    foreach ($vmName in $allLabVMs) {
        if (Remove-VMHardSafe -VMName $vmName) {
            Write-Host "    removed VM $vmName" -ForegroundColor Gray
        }
        elseif (Hyper-V\Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
            Write-LabStatus -Status WARN -Message "Could not fully remove VM $vmName. Reboot host, then run blow-away again." -Indent 2
        }
    }

    $remainingLabVms = foreach ($vmName in $allLabVMs) {
        Hyper-V\Get-VM -Name $vmName -ErrorAction SilentlyContinue
    }
    if (-not $remainingLabVms) {
        Write-LabStatus -Status OK -Message "No lab VMs remain in Hyper-V inventory." -Indent 2

        # Hyper-V Manager can still show phantom entries until management services/UI refresh.
        try {
            Get-Process vmconnect -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Get-Process mmc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

            Stop-Service vmcompute -Force -ErrorAction SilentlyContinue
            Stop-Service vmms -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            Start-Service vmms -ErrorAction Stop
            Start-Service vmcompute -ErrorAction SilentlyContinue

            Write-LabStatus -Status OK -Message "Refreshed Hyper-V management services and closed stale UI sessions." -Indent 2
        }
        catch {
            Write-LabStatus -Status WARN -Message "Could not fully refresh Hyper-V services automatically: $($_.Exception.Message)" -Indent 2
        }

        $ghostCheck = Hyper-V\Get-VM -Name 'LIN1' -ErrorAction SilentlyContinue
        if (-not $ghostCheck) {
            Write-LabStatus -Status OK -Message "PowerShell confirms LIN1 is not present." -Indent 2
        }

        Write-LabStatus -Status NOTE -Message "If Hyper-V Manager still shows LIN1 now, reboot the host to clear VMMS cache." -Indent 2
        Write-Host "           Then open Hyper-V Manager and refresh the server node." -ForegroundColor DarkGray
    }

    Write-Host "  [4/5] Removing lab files..." -ForegroundColor Cyan
    if (Test-Path (Join-Path $LabConfig.Paths.LabRoot $LabConfig.Lab.Name)) {
        Remove-Item -Path (Join-Path $LabConfig.Paths.LabRoot $LabConfig.Lab.Name) -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    removed $(Join-Path $LabConfig.Paths.LabRoot $LabConfig.Lab.Name)" -ForegroundColor Gray
    }

    Write-Host "  [4b/5] Clearing SSH known hosts..." -ForegroundColor Cyan
    if (Get-Command Clear-LabSSHKnownHosts -ErrorAction SilentlyContinue) {
        try {
            Clear-LabSSHKnownHosts
            Write-Host "    SSH known_hosts cleared" -ForegroundColor Gray
        }
        catch {
            Write-LabStatus -Status WARN -Message "SSH known_hosts cleanup failed: $($_.Exception.Message)"
        }
    }

    Write-Host "  [5/5] Cleaning network artifacts (optional)..." -ForegroundColor Cyan
    if ($DropNetwork) {
        $nat = Get-NetNat -Name $LabConfig.Network.NatName -ErrorAction SilentlyContinue
        if ($nat) {
            Remove-NetNat -Name $LabConfig.Network.NatName -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "    removed NAT $($LabConfig.Network.NatName)" -ForegroundColor Gray

            # Verify NAT removal
            $natCheck = Get-NetNat -Name $LabConfig.Network.NatName -ErrorAction SilentlyContinue
            if ($natCheck) {
                Write-LabStatus -Status WARN -Message "NAT '$($LabConfig.Network.NatName)' still present after removal attempt"
            }
        }

        $sw = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
        if ($sw) {
            Remove-VMSwitch -Name $SwitchName -Force -ErrorAction SilentlyContinue
            Write-Host "    removed switch $SwitchName" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "    skipped (use -RemoveNetwork to include)" -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-LabStatus -Status OK -Message 'Lab teardown complete.'
    Write-Host "  Run '.\OpenCodeLab-App.ps1 -Action setup' to rebuild." -ForegroundColor Gray
}

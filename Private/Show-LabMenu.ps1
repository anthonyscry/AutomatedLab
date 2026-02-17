function Show-LabMenu {
    [CmdletBinding()]
    param()

    Clear-Host
    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host "   OPENCODE LAB APP" -ForegroundColor Cyan
    Write-Host ("   {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm')) -ForegroundColor Gray
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  SETUP" -ForegroundColor DarkCyan
    Write-Host "   [S] Setup Lab      Bootstrap + Deploy + optional extra VMs"
    Write-Host "   [R] Reset Lab      Blow away + Rebuild"
    Write-Host ""
    Write-Host "  MANAGE" -ForegroundColor DarkCyan
    Write-Host "   [1] Start    [4] Rollback    [7] Terminal"
    Write-Host "   [2] Stop     [5] Health      [8] New Project"
    Write-Host "   [3] Status   [6] Push/Save   [9] Test"
    Write-Host "   [A] Asset Report"
    Write-Host "   [F] Offline AL Bundle"
    Write-Host "   [O] Configure Role"
    Write-Host "   [V] Add VM"
    Write-Host ""
    Write-Host "  LINUX" -ForegroundColor DarkCyan
    Write-Host "   [L] Add LIN1 (Ubuntu)"
    Write-Host "   [C] Configure LIN1"
    Write-Host "   [N] Install Ansible"
    Write-Host ""
    Write-Host "  [X] Exit" -ForegroundColor DarkGray
    Write-Host ""
}

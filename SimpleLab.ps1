# SimpleLab.ps1
# SimpleLab v3.1.1 - Enhanced Windows Domain Lab Automation
# Main entry point with interactive menu and CLI support
# Now with optional NAT networking and Linux VM support

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('Build', 'Start', 'Stop', 'Restart', 'Suspend', 'Status', 'Checkpoint', 'Reset', 'NAT', 'SSHKey', 'Preflight', 'Menu', 'Help')]
    [string]$Operation = 'Menu'
)

# Exit codes
$EXIT_SUCCESS = 0
$EXIT_ERROR = 1
$EXIT_VALIDATION = 2
$EXIT_CANCELLED = 3

$ErrorActionPreference = 'Stop'
$script:exitCode = $EXIT_SUCCESS

function Import-SimpleLabModule {
    try {
        $modulePath = Join-Path $PSScriptRoot 'SimpleLab.psd1'
        Import-Module $modulePath -Force -ErrorAction Stop
        return $true
    }
    catch {
        Write-Error "Failed to import SimpleLab module: $($_.Exception.Message)"
        return $false
    }
}

function Show-Banner {
    Write-Host ""
    Write-Host "SimpleLab v3.1.1 - Enhanced Windows Domain Lab Automation" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Gray
    Write-Host ""
}

function Show-LabStatusHeader {
    $status = Get-LabStatus -ErrorAction SilentlyContinue

    Write-Host "Current Lab Status:" -ForegroundColor White

    if ($null -eq $status -or $status.Count -eq 0) {
        Write-Host "  No lab VMs found" -ForegroundColor Gray
    }
    else {
        foreach ($vm in $status) {
            $statusColor = switch ($vm.State) {
                "Running"   { "Green" }
                "Off"       { "Gray" }
                "Saved"     { "Yellow" }
                default     { "Yellow" }
            }

            $heartbeat = if ($vm.Heartbeat -eq "Healthy") { "[$($vm.Heartbeat)]" } else { "" }

            Write-Host "  $($vm.VMName.PadRight(15)) " -NoNewline -ForegroundColor Cyan
            Write-Host ($vm.State.PadRight(12)) -NoNewline -ForegroundColor $statusColor
            Write-Host $heartbeat -ForegroundColor $(if ($vm.Heartbeat -eq "Healthy") { "Green" } else { "Red" })
        }
    }
    Write-Host ""
}

function Show-Menu {
    Show-Banner
    Show-LabStatusHeader

    Write-Host "Main Menu:" -ForegroundColor White
    Write-Host "  1. Build Lab        - Create VMs, configure domain, create LabReady checkpoint"
    Write-Host "  2. Start Lab        - Start all lab VMs"
    Write-Host "  3. Stop Lab         - Stop all lab VMs"
    Write-Host "  4. Restart Lab      - Restart all lab VMs"
    Write-Host "  5. Suspend Lab      - Suspend all lab VMs (save state)"
    Write-Host "  6. Show Status      - Display detailed lab status"
    Write-Host "  7. LabReady Checkpoint - Create baseline checkpoint"
    Write-Host "  8. Restore Checkpoint - Restore from a previous checkpoint"
    Write-Host "  9. Setup NAT        - Create NAT network (for Internet access)"
    Write-Host "  A. Generate SSH Key - Generate SSH key pair for Linux VMs"
    Write-Host "  P. Preflight Check  - Show prerequisites dashboard (check what's blocking)"
    Write-Host "  R. Reset Lab        - Complete lab teardown (remove VMs, checkpoints, vSwitch)"
    Write-Host "  0. Exit             - Exit SimpleLab"
    Write-Host ""

    $selection = Read-Host "Select option"
    return $selection
}

function Invoke-MenuOperation {
    param([string]$Selection)

    switch ($Selection) {
        "1" { Invoke-BuildLab }
        "2" { Invoke-StartLab }
        "3" { Invoke-StopLab }
        "4" { Invoke-RestartLab }
        "5" { Invoke-SuspendLab }
        "6" { Invoke-ShowStatus }
        "7" { Invoke-CreateCheckpoint }
        "8" { Invoke-RestoreCheckpointMenu }
        "9" { Invoke-SetupNAT }
        "A" { Invoke-GenerateSSHKey }
        "a" { Invoke-GenerateSSHKey }
        "P" { Invoke-PreflightCheck }
        "p" { Invoke-PreflightCheck }
        "R" { Invoke-ResetLab }
        "r" { Invoke-ResetLab }
        "0" { return $false }
        default {
            Write-Host "Invalid option. Please select 0-9, A, P, or R." -ForegroundColor Red
            return $true
        }
    }
    return $true
}

function Invoke-BuildLab {
    Write-Host ""
    Write-Host "=== Building Lab ===" -ForegroundColor Cyan

    # Check prerequisites
    Write-Host "Checking prerequisites..." -ForegroundColor Yellow
    $prereqResult = Test-LabPrereqs

    # Show detailed report - DON'T use Quiet mode so user sees what's wrong
    $reportResult = Write-ValidationReport -Results $prereqResult

    if ($reportResult.ExitCode -ne 0) {
        $script:exitCode = $EXIT_VALIDATION
        Write-Host ""
        Write-Host "=== BUILD BLOCKED ===" -ForegroundColor Red
        Write-Host "Prerequisites check failed. Resolve the issues above and try again." -ForegroundColor Red
        Write-Host "Tip: Use 'Preflight Check' from the main menu to re-check anytime." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to continue"
        return
    }

    # Create vSwitch
    Write-Host "Creating virtual switch..." -ForegroundColor Yellow
    New-LabSwitch | Out-Null

    # Create VMs
    Write-Host "Creating VMs..." -ForegroundColor Yellow
    Initialize-LabVMs | Out-Null

    # Start VMs
    Write-Host "Starting VMs..." -ForegroundColor Yellow
    Start-LabVMs -Wait | Out-Null

    # Wait for Windows installation to complete
    Write-Host ""
    $waitResult = Wait-LabVMReady

    if ($waitResult.OverallStatus -eq "Failed") {
        Write-Host "ERROR: VMs did not become ready. Check Hyper-V Manager for installation progress." -ForegroundColor Red
        Read-Host "Press Enter to continue"
        return
    }

    # Configure network
    Write-Host "Configuring network..." -ForegroundColor Yellow
    Initialize-LabNetwork | Out-Null

    # Promote DC
    Write-Host "Configuring domain controller..." -ForegroundColor Yellow
    Initialize-LabDomain | Out-Null

    # Configure DNS
    Write-Host "Configuring DNS..." -ForegroundColor Yellow
    Initialize-LabDNS | Out-Null

    # Join member servers
    Write-Host "Joining member servers to domain..." -ForegroundColor Yellow
    Join-LabDomain | Out-Null

    # Create LabReady checkpoint
    Write-Host "Creating LabReady checkpoint..." -ForegroundColor Yellow
    Save-LabReadyCheckpoint | Out-Null

    Write-Host ""
    Write-Host "Lab build complete!" -ForegroundColor Green
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Invoke-StartLab {
    Write-Host ""
    Write-Host "=== Starting Lab ===" -ForegroundColor Cyan
    $result = Start-LabVMs -Wait
    Write-Host $result.Message -ForegroundColor $(if ($result.OverallStatus -eq "OK") { "Green" } else { "Red" })
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Invoke-StopLab {
    Write-Host ""
    Write-Host "=== Stopping Lab ===" -ForegroundColor Cyan
    $result = Stop-LabVMs -Wait
    Write-Host $result.Message -ForegroundColor $(if ($result.OverallStatus -eq "OK") { "Green" } else { "Red" })
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Invoke-RestartLab {
    Write-Host ""
    Write-Host "=== Restarting Lab ===" -ForegroundColor Cyan
    $result = Restart-LabVMs -Wait
    Write-Host $result.Message -ForegroundColor $(if ($result.OverallStatus -eq "OK") { "Green" } else { "Red" })
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Invoke-SuspendLab {
    Write-Host ""
    Write-Host "=== Suspending Lab ===" -ForegroundColor Cyan
    $result = Suspend-LabVMs -Wait
    Write-Host $result.Message -ForegroundColor $(if ($result.OverallStatus -eq "OK") { "Green" } else { "Red" })
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Invoke-ShowStatus {
    Write-Host ""
    Write-Host "=== Lab Status ===" -ForegroundColor Cyan
    Show-LabStatus
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Invoke-CreateCheckpoint {
    Write-Host ""
    Write-Host "=== Creating LabReady Checkpoint ===" -ForegroundColor Cyan
    $result = Save-LabReadyCheckpoint
    Write-Host $result.Message -ForegroundColor $(if ($result.OverallStatus -eq "OK") { "Green" } else { "Red" })
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Invoke-RestoreCheckpointMenu {
    Write-Host ""
    Write-Host "=== Available Checkpoints ===" -ForegroundColor Cyan

    $checkpoints = Get-LabCheckpoint

    if ($null -eq $checkpoints -or $checkpoints.Count -eq 0) {
        Write-Host "No checkpoints found." -ForegroundColor Yellow
        Read-Host "Press Enter to continue"
        return
    }

    $checkpointNames = $checkpoints | Select-Object -ExpandProperty Name -Unique
    for ($i = 0; $i -lt $checkpointNames.Count; $i++) {
        Write-Host "  $($i + 1). $($checkpointNames[$i])" -ForegroundColor Cyan
    }

    Write-Host ""
    $selection = Read-Host "Select checkpoint to restore (0 to cancel)"

    if ($selection -eq "0") {
        return
    }

    $index = [int]$selection - 1
    if ($index -ge 0 -and $index -lt $checkpointNames.Count) {
        $checkpointName = $checkpointNames[$index]
        Write-Host "Restoring checkpoint: $checkpointName" -ForegroundColor Yellow
        $result = Restore-LabCheckpoint -CheckpointName $checkpointName
        Write-Host $result.Message -ForegroundColor $(if ($result.OverallStatus -eq "OK") { "Green" } else { "Red" })
    }
    else {
        Write-Host "Invalid selection." -ForegroundColor Red
    }

    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Invoke-ResetLab {
    Write-Host ""
    Write-Host "=== Reset Lab ===" -ForegroundColor Cyan
    Write-Host "This will remove all VMs, checkpoints, and the virtual switch." -ForegroundColor Yellow
    $confirm = Read-Host "Are you sure? (yes/NO)"

    if ($confirm -eq "yes") {
        $result = Reset-Lab
        Write-Host $result.Message -ForegroundColor $(if ($result.OverallStatus -eq "OK") { "Green" } else { "Red" })
    }
    else {
        Write-Host "Reset cancelled." -ForegroundColor Yellow
    }

    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Invoke-SetupNAT {
    Write-Host ""
    Write-Host "=== Setup NAT Network ===" -ForegroundColor Cyan
    Write-Host "This creates a NAT network for lab Internet access." -ForegroundColor Yellow
    Write-Host ""
    $result = New-LabNAT

    Write-Host ""
    Write-Host "Switch: $($result.SwitchName)" -ForegroundColor Cyan
    Write-Host "Gateway: $($result.GatewayIP)" -ForegroundColor Cyan
    Write-Host "NAT: $($result.NatName)" -ForegroundColor Cyan
    Write-Host "Address Space: $($result.AddressSpace)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host $result.Message -ForegroundColor $(if ($result.OverallStatus -eq "OK") { "Green" } else { "Yellow" })
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Invoke-GenerateSSHKey {
    Write-Host ""
    Write-Host "=== Generate SSH Key Pair ===" -ForegroundColor Cyan
    Write-Host "This generates an ed25519 SSH key pair for Linux VMs." -ForegroundColor Yellow
    Write-Host ""

    $result = New-LabSSHKey

    Write-Host ""
    if ($result.OverallStatus -eq "OK") {
        Write-Host "Private Key: $($result.PrivateKeyPath)" -ForegroundColor Cyan
        Write-Host "Public Key:  $($result.PublicKeyPath)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Public Key Content:" -ForegroundColor White
        Write-Host $result.PublicKeyContent -ForegroundColor Green
        Write-Host ""
    }
    Write-Host $result.Message -ForegroundColor $(if ($result.OverallStatus -eq "OK") { "Green" } else { "Yellow" })
    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Invoke-PreflightCheck {
    Write-Host ""
    Write-Host "=== Preflight Check Dashboard ===" -ForegroundColor Cyan

    $prereqResult = Test-LabPrereqs
    $reportResult = Write-ValidationReport -Results $prereqResult

    Write-Host ""
    if ($reportResult.OverallStatus -eq "Pass") {
        Write-Host "[SYSTEM READY]" -ForegroundColor Green
        Write-Host "All prerequisites met. You can proceed with Build Lab." -ForegroundColor Green
    }
    elseif ($reportResult.OverallStatus -eq "Fail") {
        Write-Host "[BLOCKERS DETECTED]" -ForegroundColor Red
        Write-Host "Resolve the issues above before building the lab." -ForegroundColor Yellow
    }
    else {
        Write-Host "[WARNINGS]" -ForegroundColor Yellow
        Write-Host "Some checks have warnings. Review above." -ForegroundColor Yellow
    }

    Write-Host ""
    Read-Host "Press Enter to continue"
}

function Show-Help {
    Write-Host ""
    Write-Host "SimpleLab v3.1.1 - Enhanced Windows Domain Lab Automation" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor White
    Write-Host "  .\SimpleLab.ps1 [Operation]"
    Write-Host ""
    Write-Host "Operations:" -ForegroundColor White
    Write-Host "  Build       - Complete lab build (VMs, domain, checkpoint)"
    Write-Host "  Start       - Start all lab VMs"
    Write-Host "  Stop        - Stop all lab VMs"
    Write-Host "  Restart     - Restart all lab VMs"
    Write-Host "  Suspend     - Suspend all lab VMs (save state)"
    Write-Host "  Status      - Display detailed lab status"
    Write-Host "  Checkpoint  - Create LabReady checkpoint"
    Write-Host "  NAT         - Setup NAT network for Internet access"
    Write-Host "  SSHKey      - Generate SSH key pair for Linux VMs"
    Write-Host "  Preflight   - Show prerequisites dashboard (check blockers)"
    Write-Host "  Reset       - Complete lab teardown"
    Write-Host "  Menu        - Show interactive menu (default)"
    Write-Host "  Help        - Show this help message"
    Write-Host ""
    Write-Host "New in v3.1.1:" -ForegroundColor Green
    Write-Host "  - NAT network support for lab Internet access"
    Write-Host "  - SSH key generation for Linux VMs"
    Write-Host "  - Dynamic memory configuration (Min/Max)"
    Write-Host "  - Enhanced configuration with Deploy.ps1 compatibility"
    Write-Host "  - Preflight dashboard to check what's blocking your build"
    Write-Host ""
    Write-Host "Exit Codes:" -ForegroundColor White
    Write-Host "  0 = Success"
    Write-Host "  1 = General error"
    Write-Host "  2 = Validation failure"
    Write-Host "  3 = Operation cancelled"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor White
    Write-Host "  .\SimpleLab.ps1           # Interactive menu"
    Write-Host "  .\SimpleLab.ps1 -Build    # Build lab"
    Write-Host "  .\SimpleLab.ps1 -Status   # Show status"
    Write-Host "  .\SimpleLab.ps1 -Preflight # Check prerequisites"
    Write-Host "  .\SimpleLab.ps1 -NAT      # Setup NAT network"
    Write-Host ""
}

function Invoke-Operation {
    param([string]$Op)

    if (-not (Import-SimpleLabModule)) {
        exit $EXIT_ERROR
    }

    switch ($Op) {
        "Build" {
            Write-Host "SimpleLab v3.1.1 - Building Lab..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-BuildLab
        }
        "Start" {
            Write-Host "SimpleLab v3.1.1 - Starting Lab..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-StartLab
        }
        "Stop" {
            Write-Host "SimpleLab v3.1.1 - Stopping Lab..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-StopLab
        }
        "Restart" {
            Write-Host "SimpleLab v3.1.1 - Restarting Lab..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-RestartLab
        }
        "Suspend" {
            Write-Host "SimpleLab v3.1.1 - Suspending Lab..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-SuspendLab
        }
        "Status" {
            Write-Host "SimpleLab v3.1.1 - Lab Status" -ForegroundColor Cyan
            Write-Host ""
            Invoke-ShowStatus
        }
        "Checkpoint" {
            Write-Host "SimpleLab v3.1.1 - Creating LabReady Checkpoint..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-CreateCheckpoint
        }
        "NAT" {
            Write-Host "SimpleLab v3.1.1 - Setting up NAT Network..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-SetupNAT
        }
        "SSHKey" {
            Write-Host "SimpleLab v3.1.1 - Generating SSH Key Pair..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-GenerateSSHKey
        }
        "Preflight" {
            Write-Host "SimpleLab v3.1.1 - Preflight Check..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-PreflightCheck
        }
        "Reset" {
            Write-Host "SimpleLab v3.1.1 - Resetting Lab..." -ForegroundColor Cyan
            Write-Host ""
            Invoke-ResetLab
        }
        "Menu" {
            if (-not (Import-SimpleLabModule)) {
                exit $EXIT_ERROR
            }

            $continue = $true
            while ($continue) {
                Clear-Host
                $selection = Show-Menu
                $continue = Invoke-MenuOperation -Selection $selection
            }
        }
        "Help" {
            Show-Help
        }
        default {
            Write-Host "Unknown operation: $Op" -ForegroundColor Red
            Write-Host "Run '.\SimpleLab.ps1 -Help' for usage information." -ForegroundColor Yellow
            $script:exitCode = $EXIT_ERROR
        }
    }
}

# Main execution
try {
    Invoke-Operation -Op $Operation
}
catch {
    Write-Error "Error: $($_.Exception.Message)"
    $script:exitCode = $EXIT_ERROR
}

exit $script:exitCode

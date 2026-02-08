# AutomatedLab

Lightweight PowerShell automation for building and operating the OpenCode 3-VM lab
(DC1, WS1, LIN1) on Hyper-V with AutomatedLab.

## New Single-Entry App

Use `OpenCodeLab-App.ps1` as the main entry point.

```powershell
# interactive menu
.\OpenCodeLab-App.ps1

# one-command build path (bootstrap + deploy)
.\OpenCodeLab-App.ps1 -Action setup

# preflight checks only
.\OpenCodeLab-App.ps1 -Action preflight

# post-deploy health gate only
.\OpenCodeLab-App.ps1 -Action health

# lint scripts (PSScriptAnalyzer)
.\OpenCodeLab-App.ps1 -Action lint

# full lint audit (includes advisory/style rules)
.\Test-OpenCodeLabLint.ps1 -Full

# one-button full setup (bootstrap + deploy + start + status)
.\OpenCodeLab-App.ps1 -Action one-button-setup

# one-button core-only setup (DC1 + WS1 only)
.\OpenCodeLab-App.ps1 -Action one-button-setup -CoreOnly

# noninteractive mode (for task scheduler / automation)
.\OpenCodeLab-App.ps1 -Action one-button-setup -NonInteractive

# noninteractive core-only mode
.\OpenCodeLab-App.ps1 -Action one-button-setup -NonInteractive -CoreOnly

# one-button setup now enforces health gate and auto-rolls back to LabReady on failure

# install desktop one-click shortcuts
.\OpenCodeLab-App.ps1 -Action install-shortcuts

# daily operations
.\OpenCodeLab-App.ps1 -Action start
.\OpenCodeLab-App.ps1 -Action status
.\OpenCodeLab-App.ps1 -Action new-project
.\OpenCodeLab-App.ps1 -Action push
.\OpenCodeLab-App.ps1 -Action test
.\OpenCodeLab-App.ps1 -Action save

# direct script automation examples
.\New-LabProject.ps1 -NonInteractive -ProjectName demo-app -Visibility private -Force -AutoStart
.\Push-ToWS1.ps1 -NonInteractive -ProjectName demo-app -AutoStart -Force
.\Test-OnWS1.ps1 -NonInteractive -ProjectName demo-app -ScriptName run-tests.ps1 -AutoStart -CheckLogs
.\Save-LabWork.ps1 -NonInteractive -ProjectName all -AutoStart -TakeSnapshot

# stop and rollback
.\OpenCodeLab-App.ps1 -Action stop
.\OpenCodeLab-App.ps1 -Action rollback

# full teardown ("blow it away")
.\OpenCodeLab-App.ps1 -Action blow-away

# non-interactive full teardown including switch/NAT removal
.\OpenCodeLab-App.ps1 -Action blow-away -Force -RemoveNetwork

# one-button full reset and rebuild (teardown + setup)
.\OpenCodeLab-App.ps1 -Action one-button-reset
.\OpenCodeLab-App.ps1 -Action one-button-reset -RemoveNetwork

# dry run for destructive action planning
.\OpenCodeLab-App.ps1 -Action blow-away -DryRun -RemoveNetwork

# load defaults from JSON
.\OpenCodeLab-App.ps1 -Action one-button-reset -DefaultsFile .\opencodelab.defaults.json
```

## Noninteractive Defaults File

Example `opencodelab.defaults.json`:

```json
{
  "NonInteractive": true,
  "CoreOnly": false,
  "Force": true,
  "RemoveNetwork": false
}
```

When `NonInteractive` is true, orchestrator `new-project`, `push`, `test`, and `save`
actions pass noninteractive flags to their underlying scripts. Set `CoreOnly` to `true`
to keep setup/health flows in DC1+WS1 mode.

## Admin Password Override

`Deploy.ps1` supports an environment override:

```powershell
$env:OPENCODELAB_ADMIN_PASSWORD = "Server123!"
.\OpenCodeLab-App.ps1 -Action one-button-setup -NonInteractive
```

Configure LIN1 SSH after deploy:

```powershell
.\OpenCodeLab-App.ps1 -Action lin1-config
```

`Deploy.ps1` now defaults to `Server123!`. You can still override with `OPENCODELAB_ADMIN_PASSWORD` or `-AdminPassword`. If an empty password is passed accidentally, deploy falls back to the default and continues.

## Run Artifacts (JSON + Text)

Every `OpenCodeLab-App.ps1` run now writes machine-readable artifacts to:

- `C:\LabSources\Logs\OpenCodeLab-Run-<timestamp>.json`
- `C:\LabSources\Logs\OpenCodeLab-Run-<timestamp>.txt`

The JSON report includes action, flags, timestamps, success/failure, error message,
and per-step event records.

Old log/report files are automatically pruned based on retention (default: 14 days).
Override with `-LogRetentionDays <n>` on `OpenCodeLab-App.ps1`.

`-Action menu` is interactive-only; in automation use explicit actions with `-NonInteractive`.

## Desktop One-Click Buttons

Run once from an elevated PowerShell prompt:

```powershell
.\OpenCodeLab-App.ps1 -Action install-shortcuts
```

This creates desktop shortcuts:
- `OpenCodeLab - Setup`
- `OpenCodeLab - Reset Rebuild`
- `OpenCodeLab - Reset Rebuild (Network Too)`
- `OpenCodeLab - Control Menu`

## SOP / Word Document

Primary workflow reference: `SOP-OpenCode-Dev-Lab-Slim-v3.1c.docx`.

The app maps to the SOP flow:
- setup: prerequisites + deploy
- daily: start/status/connect/develop/test/save
- recovery: rollback to `LabReady`
- destructive reset: stop/remove lab artifacts, optional network cleanup

## Release Docs

- `CHANGELOG.md`
- `SECRETS-BOOTSTRAP.md`
- `RUNBOOK-ROLLBACK.md`


## Troubleshooting: Phantom LIN1 in Hyper-V Manager

If Hyper-V Manager still shows `LIN1`, but PowerShell says `Remove-VM` / `Get-VM` cannot find it, the VM is usually already deleted and the UI is stale.

Run in elevated PowerShell:

```powershell
Hyper-V\Get-VM -ComputerName $env:COMPUTERNAME -Name LIN1 -ErrorAction SilentlyContinue
Get-Process vmconnect,mmc -ErrorAction SilentlyContinue | Stop-Process -Force
Stop-Service vmcompute -Force
Stop-Service vmms -Force
Start-Service vmms
Start-Service vmcompute
Hyper-V\Get-VM -ComputerName $env:COMPUTERNAME -Name LIN1 -ErrorAction SilentlyContinue
```

If `Get-VM` still returns nothing but Hyper-V Manager still shows LIN1, reboot the host (this clears VMMS cache), then reopen Hyper-V Manager and click **Refresh**.


### LIN1 Ubuntu 24.04 Deployment (v1.8.0+)

`Deploy.ps1` alone defaults to `DC1` + `WS1` (core lab). LIN1 is enabled with
`-IncludeLIN1`.

`OpenCodeLab-App.ps1` defaults to full mode (includes LIN1). Use `-CoreOnly` for
DC1/WS1-only runs.

**Why LIN1 is Optional**: AutomatedLab lacks Ubuntu 24.04 support. LIN1 is created manually using native Hyper-V cmdlets to work around this limitation.

**To Include LIN1**:

```powershell
.\Deploy.ps1 -IncludeLIN1
```

**What Happens**:
1. Creates LIN1 VM manually (bypasses AutomatedLab)
2. Generates CIDATA VHDX with Ubuntu 24.04 autoinstall configuration
3. Attaches Ubuntu ISO + CIDATA VHDX to Gen2 VM (Secure Boot disabled)
4. Starts VM - Ubuntu autoinstall proceeds unattended (10-15 minutes)
5. Waits up to 30 minutes for SSH to become reachable

**Requirements**:
- Ubuntu 24.04 ISO at: `C:\LabSources\ISOs\ubuntu-24.04.3.iso`
- Download from: https://releases.ubuntu.com/24.04.3/ubuntu-24.04.3-live-server-amd64.iso

**Note**: No ISO modifications needed! The implementation creates a CIDATA VHDX automatically with proper autoinstall configuration.


## Recommended Run Order (Numbered)

Use this exact order:

1. **Optional clean slate**
   ```powershell
   .\OpenCodeLab-App.ps1 -Action blow-away -RemoveNetwork
   ```
2. **Build lab (default full mode includes LIN1)**
   ```powershell
   .\OpenCodeLab-App.ps1 -Action one-button-setup
   ```
   **Core-only variant:**
   ```powershell
   .\OpenCodeLab-App.ps1 -Action one-button-setup -CoreOnly
   ```
3. **Start/verify health**
   ```powershell
   .\OpenCodeLab-App.ps1 -Action start
   .\OpenCodeLab-App.ps1 -Action health
   ```
4. **(Optional) Add/rebuild LIN1 after a core-only run**
   ```powershell
   .\OpenCodeLab-App.ps1 -Action add-lin1
   ```
5. **One-click LIN1 SSH config after LIN1 exists**
   ```powershell
   .\OpenCodeLab-App.ps1 -Action lin1-config
   ```

### Important
- Step 2 default now includes LIN1; use `-CoreOnly` for a faster core-only setup.
- Step 5 is the preferred after-the-fact LIN1 SSH bootstrap path.
- If Hyper-V still shows phantom LIN1 but `Get-VM` does not, follow the troubleshooting section below and reboot host if needed.

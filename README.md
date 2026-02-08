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

# one-button full setup (bootstrap + deploy + start + status)
.\OpenCodeLab-App.ps1 -Action one-button-setup

# noninteractive mode (for task scheduler / automation)
.\OpenCodeLab-App.ps1 -Action one-button-setup -NonInteractive

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
.\Push-ToWS1_POLISHED_FINAL.ps1 -NonInteractive -ProjectName demo-app -AutoStart -Force
.\Test-OnWS1.ps1 -NonInteractive -ProjectName demo-app -ScriptName run-tests.ps1 -AutoStart -CheckLogs
.\Save-LabWork_POLISHED_FINAL.ps1 -NonInteractive -ProjectName all -AutoStart -TakeSnapshot

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
  "Force": true,
  "RemoveNetwork": false
}
```

When `NonInteractive` is true, orchestrator `new-project`, `push`, `test`, and `save`
actions pass noninteractive flags to their underlying scripts.

## Admin Password Override

`Deploy.ps1` supports an environment override:

```powershell
$env:OPENCODELAB_ADMIN_PASSWORD = "Server123!"
.\OpenCodeLab-App.ps1 -Action one-button-setup -NonInteractive
```

One-click install LIN1 after core lab deploy:

```powershell
.\OpenCodeLab-App.ps1 -Action lin1-install
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


### Optional: Include LIN1 in Deploy

By default, `Deploy.ps1` now deploys only `DC1` + `WS1` to avoid AutomatedLab's Linux timeout on internal switches.

To include LIN1 in the same run:

```powershell
.\Deploy.ps1 -IncludeLIN1
```


## Recommended Run Order (Numbered)

### Menu quick order (keys)

1. `A` = One-Button Setup
2. `N` = Install LIN1 (post-deploy)
3. `L` = Configure LIN1 SSH (post-deploy)
4. `H` = Health Gate

Use this exact order:

1. **Optional clean slate**
   ```powershell
   .\OpenCodeLab-App.ps1 -Action blow-away -RemoveNetwork
   ```
2. **Build core lab (DC1 + WS1)**
   ```powershell
   .\OpenCodeLab-App.ps1 -Action one-button-setup
   ```
3. **Start/verify health**
   ```powershell
   .\OpenCodeLab-App.ps1 -Action start
   .\OpenCodeLab-App.ps1 -Action health
   ```
4. **One-click install LIN1 after core deploy**
   ```powershell
   .\OpenCodeLab-App.ps1 -Action lin1-install
   ```
5. **One-click LIN1 SSH config after LIN1 exists**
   ```powershell
   .\OpenCodeLab-App.ps1 -Action lin1-config
   ```
6. **(Optional advanced) include LIN1 during full deploy run**
   ```powershell
   .\Deploy.ps1 -IncludeLIN1
   ```

### Important
- Step 2 is the default reliable path (core Windows lab).
- Step 5 is the preferred after-the-fact LIN1 SSH bootstrap path.
- If Hyper-V still shows phantom LIN1 but `Get-VM` does not, follow the troubleshooting section below and reboot host if needed.

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
$env:OPENCODELAB_ADMIN_PASSWORD = "YourStrongPassword"
.\OpenCodeLab-App.ps1 -Action one-button-setup -NonInteractive
```

`OPENCODELAB_ADMIN_PASSWORD` (or `-AdminPassword` on deploy) is now required.

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

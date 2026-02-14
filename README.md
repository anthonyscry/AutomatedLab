# AutomatedLab / SimpleLab

PowerShell automation for building and operating a reusable Hyper-V lab with a Windows core topology (DC1, SVR1, WS1) and optional LIN1 Ubuntu node.

## What this repo contains

- A PowerShell module (`SimpleLab.psd1` / `SimpleLab.psm1`) with reusable public and private lab functions.
- End-to-end orchestration scripts (`OpenCodeLab-App.ps1`, `Bootstrap.ps1`, `Deploy.ps1`) for setup, daily operations, health checks, rollback, and rebuild.
- Role templates and lab builder helpers in `LabBuilder/`.
- Pester tests under `Tests/`.

## Requirements

- Windows 10/11 Pro, Enterprise, or Education (Hyper-V required)
- PowerShell 5.1+
- Hyper-V enabled
- Sufficient host resources for multiple VMs (16 GB+ RAM and fast SSD strongly recommended)

## Quick start

1) Set the deployment password for non-interactive runs:

```powershell
$env:OPENCODELAB_ADMIN_PASSWORD = "YourStrongPasswordHere"
```

2) Run preflight and bootstrap/deploy in one command:

```powershell
.\OpenCodeLab-App.ps1 -Action one-button-setup -NonInteractive
```

For mode-aware orchestration, use `deploy`/`teardown` with `-Mode quick|full`:

```powershell
# Fast reuse path when the core lab is already healthy
.\OpenCodeLab-App.ps1 -Action deploy -Mode quick -NonInteractive

# Fast stop + restore to LabReady when available
.\OpenCodeLab-App.ps1 -Action teardown -Mode quick -NonInteractive

# Full destructive teardown path
.\OpenCodeLab-App.ps1 -Action teardown -Mode full -Force -RemoveNetwork -NonInteractive
```

`quick` deploy automatically falls back to `full` when required state is missing (for example missing lab registration, missing VMs, missing LabReady snapshot, or network drift).

3) Check status:

```powershell
.\OpenCodeLab-App.ps1 -Action status
```

## Common operations

```powershell
# Start the lab day workflow
.\OpenCodeLab-App.ps1 -Action start

# Health gate
.\OpenCodeLab-App.ps1 -Action health

# Roll back to LabReady snapshot
.\OpenCodeLab-App.ps1 -Action rollback

# Add Ubuntu node to an existing core lab
.\OpenCodeLab-App.ps1 -Action add-lin1

# Destructive cleanup (preview first)
.\OpenCodeLab-App.ps1 -Action blow-away -DryRun -RemoveNetwork
```

## GUI wrapper

Use the WinForms wrapper when you want a guided launcher for app actions:

```powershell
.\OpenCodeLab-GUI.ps1
```

The GUI builds an `OpenCodeLab-App.ps1` command preview, starts each run in a separate PowerShell process, and reports the latest run artifact summary from `C:\LabSources\Logs`.

## Repository layout

```text
AutomatedLab/
├── Public/                    # Exported module functions
│   └── Linux/                 # Linux-focused public helpers
├── Private/                   # Internal helper functions
│   └── Linux/                 # Linux-focused private helpers
├── Scripts/                   # Day-2 operational scripts
├── LabBuilder/                # Role-driven builder workflows
├── Ansible/                   # Ansible templates/playbooks
├── Tests/                     # Pester tests and test runner
├── docs/                      # Architecture and structure notes
├── Bootstrap.ps1              # Prerequisite/bootstrap installer
├── Deploy.ps1                 # Full lab deployment flow
├── OpenCodeLab-App.ps1        # Primary app-style entry point
├── Lab-Config.ps1             # Lab defaults/config values
├── Lab-Common.ps1             # Shared loader shim for scripts
├── SimpleLab.psd1             # Module manifest
└── SimpleLab.psm1             # Module root
```

## Testing

Run all tests:

```powershell
Invoke-Pester -Path .\Tests\
```

Run the provided test runner:

```powershell
.\Tests\Run.Tests.ps1
```

## Documentation

- Rollback runbook: `RUNBOOK-ROLLBACK.md`
- Secret/bootstrap guide: `SECRETS-BOOTSTRAP.md`
- Architecture notes: `docs/ARCHITECTURE.md`
- Repository structure notes: `docs/REPOSITORY-STRUCTURE.md`
- Fast deploy/teardown design notes: `docs/plans/2026-02-14-fast-deploy-teardown-gui-design.md`
- Fast deploy/teardown implementation plan: `docs/plans/2026-02-14-fast-deploy-teardown-gui.md`

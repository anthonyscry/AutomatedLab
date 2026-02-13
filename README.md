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

## Repository layout

```text
AutomatedLab/
├── Public/                    # Exported module functions
├── Private/                   # Internal helper functions
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

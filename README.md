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

Dispatch execution is controlled separately with `-DispatchMode off|canary|enforced`:

```powershell
# Kill switch: disable all dispatch execution paths
.\OpenCodeLab-App.ps1 -Action deploy -Mode quick -DispatchMode off -NonInteractive

# Canary: dispatch exactly one eligible host and mark others not_dispatched
.\OpenCodeLab-App.ps1 -Action deploy -Mode quick -TargetHosts hv-a,hv-b -DispatchMode canary -NonInteractive

# Enforced: dispatch all eligible hosts
.\OpenCodeLab-App.ps1 -Action deploy -Mode quick -TargetHosts hv-a,hv-b -DispatchMode enforced -NonInteractive
```

Rollback note: if a rollout regresses, switch to `-DispatchMode off` immediately (or set `OPENCODELAB_DISPATCH_MODE=off`) to bypass dispatcher execution while preserving coordinator policy checks and run artifacts.

Precedence: explicit `-DispatchMode` takes precedence over `OPENCODELAB_DISPATCH_MODE` when both are provided.

For multi-host safety-first orchestration, operators can scope and approve destructive intent explicitly:

```powershell
# Scope orchestration to explicit hosts
.\OpenCodeLab-App.ps1 -Action deploy -Mode quick -TargetHosts hv-a,hv-b -InventoryPath .\Ansible\inventory.json -NonInteractive

# Full teardown requires a scoped confirmation token (fail-closed if missing/invalid)
.\OpenCodeLab-App.ps1 -Action teardown -Mode full -TargetHosts hv-a -InventoryPath .\Ansible\inventory.json -ConfirmationToken <token> -Force -NonInteractive
```

Inventory files use JSON with a top-level `hosts` array:

```json
{
  "hosts": [
    { "name": "hv-a", "role": "primary", "connection": "local" },
    { "name": "hv-b", "role": "secondary", "connection": "ssh" }
  ]
}
```

Mint scoped confirmation tokens from the public script surface before destructive runs:

```powershell
$env:OPENCODELAB_CONFIRMATION_RUN_ID = "run-20260214-01"
$env:OPENCODELAB_CONFIRMATION_SECRET = "<shared-secret>"

$token = .\Scripts\New-ScopedConfirmationToken.ps1 -TargetHosts hv-a -Action teardown -Mode full

.\OpenCodeLab-App.ps1 -Action teardown -Mode full -TargetHosts hv-a -InventoryPath .\Ansible\inventory.json -ConfirmationToken $token -Force -NonInteractive
```

Run-scope and secret contract for token issuance/validation:
- `OPENCODELAB_CONFIRMATION_RUN_ID`: required run scope; the same value must be used when minting and when executing `OpenCodeLab-App.ps1`.
- `OPENCODELAB_CONFIRMATION_SECRET`: required shared secret used to sign and validate scoped confirmation tokens.
- `Scripts/New-ScopedConfirmationToken.ps1` also accepts explicit `-RunId` and `-Secret` parameters when env vars are not used.

- `-TargetHosts`: explicit host blast radius for `deploy`/`teardown` routing.
- `-InventoryPath`: inventory source used to resolve/validate host targeting.
- `-ConfirmationToken`: scoped approval token required for destructive `teardown -Mode full` execution.
- `-DispatchMode`: dispatch execution control (`off|canary|enforced`), with `off` as kill switch during rollback.
- `EscalationRequired`: policy outcome emitted when `teardown -Mode quick` would require destructive escalation; the run does not silently switch behavior.
- Fail-closed policy outcomes: unresolved targets, missing scoped confirmation, or invalid scoped confirmation block execution (`PolicyBlocked`) until operators provide valid scope/approval.

3) Check status:

```powershell
.\OpenCodeLab-App.ps1 -Action status
```

## OpenCode `/run` alias

This repo includes a project command alias at `.opencode/commands/run.md`.

In OpenCode, run:

```text
/run
```

You can also pass app arguments through the alias:

```text
/run -Action status
```

The alias calls `Scripts/Run-OpenCodeLab.ps1`, which syntax-checks key app scripts before launch (unless you pass `-SkipBuild`).

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

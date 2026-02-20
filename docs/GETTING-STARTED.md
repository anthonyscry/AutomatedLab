# Getting Started with AutomatedLab

This guide walks a new operator through everything needed to run AutomatedLab on a clean Windows host for the first time.

See [README.md](../README.md) for a full command reference and feature overview.

---

## Preflight Checklist

Before running any commands, verify these requirements on your Hyper-V host:

### Host OS and Virtualization

- [ ] Windows 10/11 Pro, Enterprise, or Education (Home is **not** supported — Hyper-V unavailable)
- [ ] Hyper-V role enabled (`Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All`)
- [ ] At least 16 GB RAM available (8 GB minimum, 16 GB+ strongly recommended for three concurrent VMs)
- [ ] At least 80 GB free disk on an SSD (spinning disk will be very slow)

### PowerShell

- [ ] PowerShell 5.1 or later (`$PSVersionTable.PSVersion`)
- [ ] Running as Administrator (required for Hyper-V operations and network configuration)

### Secrets — Password Setup (Required Before First Run)

AutomatedLab uses a deployment password for non-interactive runs. Set it before any deploy action.

Refer to [SECRETS-BOOTSTRAP.md](../SECRETS-BOOTSTRAP.md) for the full secrets guide.

**Minimum required for first run:**

```powershell
$env:OPENCODELAB_ADMIN_PASSWORD = "YourStrongPasswordHere"
```

Verify it is set:

```powershell
if ([string]::IsNullOrWhiteSpace($env:OPENCODELAB_ADMIN_PASSWORD)) { "MISSING - set it before continuing" } else { "OK" }
```

---

## First Run: 10-Step Flow

Follow these steps in order for a clean first deployment.

### Step 1 — Clone the repository

```powershell
git clone https://github.com/your-org/AutomatedLab.git
Set-Location AutomatedLab
```

### Step 2 — Set the deployment password

```powershell
$env:OPENCODELAB_ADMIN_PASSWORD = "YourStrongPasswordHere"
```

This environment variable is required before any `one-button-setup` or `deploy` action.

### Step 3 — Run preflight checks

```powershell
.\OpenCodeLab-App.ps1 -Action health
```

Review any warnings before continuing. Missing Hyper-V features or insufficient RAM will be reported here.

### Step 4 — Run one-button setup

This command bootstraps prerequisites, creates the Hyper-V vSwitch and NAT, deploys all VMs, and takes a LabReady snapshot:

```powershell
.\OpenCodeLab-App.ps1 -Action one-button-setup -NonInteractive
```

Expected duration: 20–60 minutes depending on host speed and internet connection for downloads.

**What to expect after `one-button-setup`:**
- Hyper-V vSwitch (`LabSwitch`) and NAT (`LabNAT`) created
- DC1, SVR1, and WS1 VMs provisioned and domain-joined
- `LabReady` snapshot taken on all VMs
- Exit code 0 if successful

### Step 5 — Verify lab status

```powershell
.\OpenCodeLab-App.ps1 -Action status
```

All core VMs (DC1, SVR1, WS1) should appear as Running.

### Step 6 — Run a health check

```powershell
.\OpenCodeLab-App.ps1 -Action health
```

The health check validates VM state, network connectivity, snapshot availability, and NAT configuration.

### Step 7 — Try a quick deploy cycle

Quick deploy restores VMs to the `LabReady` snapshot without full reprovisioning:

```powershell
.\OpenCodeLab-App.ps1 -Action deploy -Mode quick -NonInteractive
```

If required state is missing (VMs gone, snapshot absent, or network drift), quick mode automatically falls back to full deploy with a logged reason.

### Step 8 — Run a quick teardown

Quick teardown stops all lab VMs cleanly and restores to LabReady snapshot if available:

```powershell
.\OpenCodeLab-App.ps1 -Action teardown -Mode quick -NonInteractive
```

### Step 9 — (Optional) Add the Ubuntu node

If your workflow needs a Linux VM:

```powershell
.\OpenCodeLab-App.ps1 -Action add-lin1 -NonInteractive
```

LIN1 is added to the existing core lab topology (DC1, SVR1, WS1 must be running).

### Step 10 — (Optional) Launch the GUI

For a guided launcher instead of CLI:

```powershell
.\OpenCodeLab-GUI.ps1
```

The GUI builds command previews, runs each action in a separate PowerShell process, and shows the latest run artifact summary.

---

## Quick Reference

| Action | Command | Notes |
|--------|---------|-------|
| Full setup (first run) | `.\OpenCodeLab-App.ps1 -Action one-button-setup -NonInteractive` | Bootstraps + deploys + snapshots |
| Deploy (quick) | `.\OpenCodeLab-App.ps1 -Action deploy -Mode quick -NonInteractive` | Restore from snapshot; falls back to full |
| Deploy (full) | `.\OpenCodeLab-App.ps1 -Action deploy -Mode full -NonInteractive` | Full reprovisioning |
| Teardown (quick) | `.\OpenCodeLab-App.ps1 -Action teardown -Mode quick -NonInteractive` | Stop + restore snapshot |
| Teardown (full) | `.\OpenCodeLab-App.ps1 -Action teardown -Mode full -Force -RemoveNetwork -NonInteractive` | Destructive cleanup |
| Status | `.\OpenCodeLab-App.ps1 -Action status` | VM state summary |
| Health check | `.\OpenCodeLab-App.ps1 -Action health` | Full infrastructure diagnostics |
| Rollback to LabReady | `.\OpenCodeLab-App.ps1 -Action rollback` | Restore all VMs to LabReady snapshot |
| Add Linux node | `.\OpenCodeLab-App.ps1 -Action add-lin1 -NonInteractive` | Add LIN1 to existing core lab |
| Destroy everything | `.\OpenCodeLab-App.ps1 -Action blow-away -DryRun -RemoveNetwork` | Preview first with -DryRun |

---

## Failure Recovery

If your first run fails partway through, follow this sequence:

### Step 1 — Check the run artifact

Run artifacts are written to `C:\LabSources\Logs\` as JSON. The most recent run directory shows the `ExecutionOutcome` and any error messages.

### Step 2 — Run health check for diagnostics

```powershell
.\OpenCodeLab-App.ps1 -Action health
```

Health output will indicate what infrastructure is missing or broken.

### Step 3 — If deploy fails mid-run: try rollback

```powershell
.\OpenCodeLab-App.ps1 -Action rollback
```

Rollback restores all VMs to the `LabReady` snapshot. This is safe to run without data loss if a snapshot exists.

### Step 4 — If no snapshot is available: full teardown then redeploy

```powershell
# Destroy current state cleanly
.\OpenCodeLab-App.ps1 -Action teardown -Mode full -Force -RemoveNetwork -NonInteractive

# Re-run full setup from scratch
.\OpenCodeLab-App.ps1 -Action one-button-setup -NonInteractive
```

### Step 5 — Dispatch rollback (multi-host environments only)

If dispatch execution caused a regression, switch to `-DispatchMode off` immediately:

```powershell
.\OpenCodeLab-App.ps1 -Action deploy -Mode quick -DispatchMode off -NonInteractive
```

`-DispatchMode off` is the kill switch. It bypasses dispatcher execution while preserving coordinator policy checks and run artifacts. Explicit `-DispatchMode` always takes precedence over the `OPENCODELAB_DISPATCH_MODE` environment variable.

---

## Next Steps

- **[README.md](../README.md)** — Full command reference including dispatch modes, multi-host inventory, and confirmation token usage
- **[SECRETS-BOOTSTRAP.md](../SECRETS-BOOTSTRAP.md)** — Secret management and credential setup
- **[RUNBOOK-ROLLBACK.md](../RUNBOOK-ROLLBACK.md)** — Detailed rollback procedures
- **[docs/ARCHITECTURE.md](ARCHITECTURE.md)** — Architecture overview and orchestration model
- **[docs/SMOKE-CHECKLIST.md](SMOKE-CHECKLIST.md)** — Manual smoke test checklist for validating a deployment

# Lifecycle Workflows: Operator Playbook

This guide covers end-to-end operator workflows for bootstrapping, deploying, and maintaining the OpenCodeLab Hyper-V environment. Each section includes the canonical command sequence, expected status fields in run artifacts, and artifacts to check afterward.

---

## Overview

The main entry point for all lifecycle operations is `OpenCodeLab-App.ps1`:

```powershell
.\OpenCodeLab-App.ps1 -Action <action> [options]
```

Run artifacts are written as JSON and text to `C:\LabSources\Logs\OpenCodeLab-Run-*.json` (and `.txt`) after every run.

---

## Bootstrap

The bootstrap workflow installs prerequisites and validates the host environment before a deploy can succeed.

### One-button setup (fully automatic)

Set the deployment password first, then run bootstrap and deploy together:

```powershell
$env:OPENCODELAB_ADMIN_PASSWORD = "YourStrongPasswordHere"
.\OpenCodeLab-App.ps1 -Action one-button-setup -NonInteractive
```

`-NonInteractive` suppresses all interactive prompts. The script calls `Bootstrap.ps1` (prerequisites) then `Deploy.ps1` (core topology) in sequence.

### Bootstrap only

If you need to install prerequisites without deploying:

```powershell
$env:OPENCODELAB_ADMIN_PASSWORD = "YourStrongPasswordHere"
.\OpenCodeLab-App.ps1 -Action bootstrap -NonInteractive
```

### Expected Outcomes

After a successful bootstrap:

| Artifact field | Expected value |
|---|---|
| `ExecutionOutcome` | `success` |
| `PolicyBlocked` | `false` |
| `EscalationRequired` | `false` |

### Artifacts to check

- `C:\LabSources\Logs\OpenCodeLab-Run-*.json` — check `ExecutionOutcome`
- `C:\LabSources\Logs\OpenCodeLab-Run-*.txt` — human-readable run log

---

## Deploy

The deploy workflow provisions or restores the core lab topology (DC1, SVR1, WS1 and optional LIN1).

### Quick-mode deploy (preferred for daily use)

Use quick mode when the lab has been deployed before and a `LabReady` snapshot is available:

```powershell
.\OpenCodeLab-App.ps1 -Action deploy -Mode quick -NonInteractive
```

Quick mode starts VMs and restores from the `LabReady` snapshot without reprovisioning.

### Full-mode deploy (initial or after teardown)

Use full mode for initial provisioning or after a destructive teardown:

```powershell
$env:OPENCODELAB_ADMIN_PASSWORD = "YourStrongPasswordHere"
.\OpenCodeLab-App.ps1 -Action deploy -Mode full -NonInteractive
```

Full mode runs the complete `Deploy.ps1` provisioning flow.

### Multi-host scoped deploy

For environments with multiple Hyper-V hosts:

```powershell
.\OpenCodeLab-App.ps1 -Action deploy -Mode quick -TargetHosts hv-a,hv-b -InventoryPath .\Ansible\inventory.json -NonInteractive
```

### Dispatch mode control

Dispatch mode controls which hosts receive the operation:

```powershell
# Kill switch: disable all dispatch (safe fallback during rollback)
.\OpenCodeLab-App.ps1 -Action deploy -Mode quick -DispatchMode off -NonInteractive

# Canary: dispatch exactly one host, mark others not_dispatched
.\OpenCodeLab-App.ps1 -Action deploy -Mode quick -TargetHosts hv-a,hv-b -DispatchMode canary -NonInteractive

# Enforced: dispatch all eligible hosts
.\OpenCodeLab-App.ps1 -Action deploy -Mode quick -TargetHosts hv-a,hv-b -DispatchMode enforced -NonInteractive
```

Precedence: explicit `-DispatchMode` takes precedence over the `OPENCODELAB_DISPATCH_MODE` environment variable.

### Expected Outcomes

| Artifact field | Expected value (success) |
|---|---|
| `ExecutionOutcome` | `success` |
| `PolicyBlocked` | `false` |
| `EscalationRequired` | `false` |

For dispatch runs, `host_outcomes` shows `dispatched`, `not_dispatched`, or `policy_blocked` per host.

### Artifacts to check

- `C:\LabSources\Logs\OpenCodeLab-Run-*.json` — check `ExecutionOutcome`, `host_outcomes`, `blast_radius`
- `C:\LabSources\Logs\OpenCodeLab-Run-*.txt` — step-by-step run log

---

## Quick Mode

Quick mode deploy and teardown are the fast paths for day-to-day operations. They rely on the `LabReady` snapshot for sub-minute restore/stop cycles.

### How quick mode works

On `deploy -Mode quick`:

1. `Get-LabStateProbe` checks lab registration, VM presence, `LabReady` snapshot, and network state.
2. `Resolve-LabModeDecision` decides whether quick mode is safe.
3. If all checks pass: start VMs and restore `LabReady` snapshot.
4. If any check fails: auto-fall-back to full deploy (see Quick Mode Auto-heal Fallback below).

On `teardown -Mode quick`:

1. Stop all lab VMs.
2. If `LabReady` snapshot exists: restore it (ready for next quick deploy).
3. If snapshot is missing: `EscalationRequired` is set — escalation to full teardown may be needed.

### Quick Mode Auto-heal Fallback

When quick mode detects a gap — missing lab registration, missing VMs, missing `LabReady` snapshot, or network drift — it falls back to full deploy automatically:

```powershell
# This may silently promote to full if quick state is missing
.\OpenCodeLab-App.ps1 -Action deploy -Mode quick -NonInteractive
```

The effective mode and fallback reason are recorded in the run artifact:

| Artifact field | Value when fallback occurs |
|---|---|
| `ExecutionOutcome` | `success` (if full deploy succeeds) |
| `effective_mode` | `full` |
| `fallback_reason` | Specific gap description (e.g., `missing_snapshot`) |

### Escalation conditions

Quick mode does NOT silently escalate destructive operations. For teardown, if quick mode cannot proceed safely, it surfaces `EscalationRequired` and stops:

| Condition | Artifact field | Value |
|---|---|---|
| Quick teardown blocked (snapshot missing) | `EscalationRequired` | `true` |
| Full teardown blocked (missing token) | `PolicyBlocked` | `true` |

When `EscalationRequired` is true: run teardown with `-Mode full` and a scoped confirmation token.

### Auto-heal behavior

`Invoke-LabQuickModeHeal` runs between state probe and mode decision to repair:

- Missing or misconfigured vSwitch
- Missing NAT rules
- `LabReady` snapshot gaps

Auto-heal is enabled by default (controlled by `AutoHeal` block in `Lab-Config.ps1`). To disable:

```powershell
# Disable auto-heal for this run (set in Lab-Config.ps1 or via config override)
# AutoHeal.Enabled = $false
```

---

## Teardown

The teardown workflow stops and optionally removes the lab environment.

### Quick teardown (stop and restore)

```powershell
.\OpenCodeLab-App.ps1 -Action teardown -Mode quick -NonInteractive
```

Stops VMs and restores `LabReady` snapshot (if available). Does not remove VMs or network infrastructure.

### Full teardown (destructive)

Full teardown removes VMs, checkpoints, vSwitch, and NAT. Requires a scoped confirmation token:

```powershell
# 1) Set run-scope and secret
$env:OPENCODELAB_CONFIRMATION_RUN_ID = "run-20260214-01"
$env:OPENCODELAB_CONFIRMATION_SECRET = "<shared-secret>"

# 2) Mint the scoped token
$token = .\Scripts\New-ScopedConfirmationToken.ps1 -TargetHosts hv-a -Action teardown -Mode full

# 3) Execute destructive teardown
.\OpenCodeLab-App.ps1 -Action teardown -Mode full -TargetHosts hv-a -InventoryPath .\Ansible\inventory.json -ConfirmationToken $token -Force -NonInteractive
```

### Preview before destructive teardown

Always preview first:

```powershell
.\OpenCodeLab-App.ps1 -Action blow-away -DryRun -RemoveNetwork
```

### Expected Outcomes

| Artifact field | Expected value (success) |
|---|---|
| `ExecutionOutcome` | `success` |
| `EscalationRequired` | `false` |
| `PolicyBlocked` | `false` |

### Artifacts to check

- `C:\LabSources\Logs\OpenCodeLab-Run-*.json` — check `ExecutionOutcome`, `policy_outcome`
- `C:\LabSources\Logs\OpenCodeLab-Run-*.txt` — human-readable teardown log

---

## Status and Health Verification

### Check current status

```powershell
.\OpenCodeLab-App.ps1 -Action status
```

Displays VM inventory, current state (running/stopped/missing), and network status.

### Run health gate

```powershell
.\OpenCodeLab-App.ps1 -Action health
```

Validates VM connectivity, network infrastructure (vSwitch, NAT, static IPs, DNS), and domain join. Reports actionable diagnostics for any failure.

### Day workflow start

```powershell
.\OpenCodeLab-App.ps1 -Action start
```

Starts all lab VMs in correct order.

### Expected Outcomes after health check

| Artifact field | Healthy value |
|---|---|
| `ExecutionOutcome` | `success` |
| `PolicyBlocked` | `false` |
| `EscalationRequired` | `false` |

If health fails, check the run artifact for step events that identify which component failed.

---

## Integration Verification

After any lifecycle operation, confirm readiness with the following sanity flow:

```powershell
# 1) Verify status reports expected VMs
.\OpenCodeLab-App.ps1 -Action status

# 2) Gate on health before using the lab
.\OpenCodeLab-App.ps1 -Action health

# 3) Confirm latest run artifact is clean
$latest = Get-Item "C:\LabSources\Logs\OpenCodeLab-Run-*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
(Get-Content $latest.FullName | ConvertFrom-Json).ExecutionOutcome
```

Expected output: `success`

---

## Rollback

If a deployment or health check fails:

```powershell
# Restore to LabReady snapshot
.\OpenCodeLab-App.ps1 -Action rollback
```

See `RUNBOOK-ROLLBACK.md` for full failure matrix and recovery procedures.

---

## Reference: Key Command Summary

| Goal | Command |
|---|---|
| Full setup from scratch | `.\OpenCodeLab-App.ps1 -Action one-button-setup -NonInteractive` |
| Quick daily deploy | `.\OpenCodeLab-App.ps1 -Action deploy -Mode quick -NonInteractive` |
| Full reprovisioning | `.\OpenCodeLab-App.ps1 -Action deploy -Mode full -NonInteractive` |
| Quick stop and restore | `.\OpenCodeLab-App.ps1 -Action teardown -Mode quick -NonInteractive` |
| Full destructive teardown | `.\OpenCodeLab-App.ps1 -Action teardown -Mode full -ConfirmationToken $token -Force -NonInteractive` |
| Check lab status | `.\OpenCodeLab-App.ps1 -Action status` |
| Run health gate | `.\OpenCodeLab-App.ps1 -Action health` |
| Rollback to snapshot | `.\OpenCodeLab-App.ps1 -Action rollback` |
| Disable dispatch (kill switch) | `.\OpenCodeLab-App.ps1 -Action deploy -DispatchMode off -NonInteractive` |
| Full destructive reset | `.\OpenCodeLab-App.ps1 -Action one-button-reset -NonInteractive -Force -RemoveNetwork` |

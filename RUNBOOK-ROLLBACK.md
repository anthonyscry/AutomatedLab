# Rollback and Troubleshooting Runbook

Use this runbook when deployment, health checks, or teardown fails. It covers immediate recovery steps and a detailed failure matrix for common production failure classes.

---

## Quick Recovery Reference

### Step 1: Check Current Health

```powershell
.\OpenCodeLab-App.ps1 -Action health
```

Review output for which component reported a failure. Check the latest run artifact:

```powershell
$latest = Get-Item "C:\LabSources\Logs\OpenCodeLab-Run-*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Get-Content $latest.FullName | ConvertFrom-Json | Select-Object ExecutionOutcome, PolicyBlocked, EscalationRequired
```

### Step 2: Roll Back to Baseline Snapshot

```powershell
.\OpenCodeLab-App.ps1 -Action rollback
```

If rollback fails, the `LabReady` snapshot is likely missing. Proceed to failure scenario 4 below.

### Step 3: Rebuild Baseline if Needed

```powershell
$env:OPENCODELAB_ADMIN_PASSWORD = "YourStrongPasswordHere"
.\OpenCodeLab-App.ps1 -Action one-button-setup -NonInteractive
```

### Step 4: Destructive Reset (Last Resort)

Preview first:

```powershell
.\OpenCodeLab-App.ps1 -Action blow-away -DryRun -RemoveNetwork
```

Then execute:

```powershell
.\OpenCodeLab-App.ps1 -Action one-button-reset -NonInteractive -Force -RemoveNetwork
```

### Step 5: Audit Run Artifacts

Review latest run reports:

- `C:\LabSources\Logs\OpenCodeLab-Run-*.json`
- `C:\LabSources\Logs\OpenCodeLab-Run-*.txt`

---

## Failure Matrix

The matrix below covers the most common failure classes encountered in production. Each entry includes symptom signatures, likely root cause, corrective steps, and recovery verification commands.

---

### Scenario: Deployment Fails During VM Provisioning

1) Deployment Fails During VM Provisioning

**Symptom / command failure signature:**

- `Deploy.ps1` exits with non-zero code or throws an exception.
- Run artifact `ExecutionOutcome` is not `success`.
- VM(s) remain in `Off` state or do not appear in `Get-VM`.
- Log contains phrases like `New-VM : A parameter cannot be found`, `insufficient disk`, or role-specific provisioning errors.

**Likely root cause:**

- Insufficient host resources (RAM, disk space, CPU).
- Hyper-V role not fully enabled or in a degraded state.
- `OPENCODELAB_ADMIN_PASSWORD` environment variable not set.
- ISO/VHDX image paths misconfigured in `Lab-Config.ps1`.

**Corrective steps:**

```powershell
# 1) Confirm password env var is set
[System.Environment]::GetEnvironmentVariable('OPENCODELAB_ADMIN_PASSWORD')

# 2) Check host resources
Get-VM | Select-Object Name, State, MemoryStartup, ProcessorCount

# 3) Verify Hyper-V is functional
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V | Select-Object State

# 4) Check available disk on the LabSources path
Get-PSDrive -Name C | Select-Object Used, Free

# 5) Re-run full deploy after correcting resources
$env:OPENCODELAB_ADMIN_PASSWORD = "YourStrongPasswordHere"
.\OpenCodeLab-App.ps1 -Action deploy -Mode full -NonInteractive
```

**Confirm recovery:**

```powershell
.\OpenCodeLab-App.ps1 -Action status
.\OpenCodeLab-App.ps1 -Action health
```

---

### Scenario: Quick Mode Policy Escalation

2) Quick Mode Policy Escalation

**Symptom / command failure signature:**

- `.\OpenCodeLab-App.ps1 -Action teardown -Mode quick` returns without performing teardown.
- Run artifact `EscalationRequired` is `true`.
- Log contains `quick teardown cannot be safely honored` or `LabReady snapshot missing`.

**Likely root cause:**

- `LabReady` snapshot does not exist on one or more lab VMs.
- State probe detected missing VMs or network drift that makes quick mode unsafe.
- Auto-heal ran but could not repair the gap (e.g., VM itself is missing).

**Corrective steps:**

```powershell
# 1) Confirm escalation is set in artifact
$latest = Get-Item "C:\LabSources\Logs\OpenCodeLab-Run-*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
(Get-Content $latest.FullName | ConvertFrom-Json).EscalationRequired

# 2) Check which VMs are missing the LabReady snapshot
Get-VMSnapshot -VMName DC1,SVR1,WS1 | Select-Object VMName, Name

# 3) If VMs exist but snapshot is missing, redeploy to restore baseline
$env:OPENCODELAB_ADMIN_PASSWORD = "YourStrongPasswordHere"
.\OpenCodeLab-App.ps1 -Action deploy -Mode full -NonInteractive

# 4) After full deploy succeeds, retry quick teardown
.\OpenCodeLab-App.ps1 -Action teardown -Mode quick -NonInteractive
```

**Confirm recovery:**

```powershell
.\OpenCodeLab-App.ps1 -Action status
Get-VMSnapshot -VMName DC1,SVR1,WS1 | Select-Object VMName, Name
```

---

### Scenario: Scoped Confirmation Token Failures

3) Scoped Confirmation Token Failures

**Symptom / command failure signature:**

- `teardown -Mode full` does not proceed and exits with `PolicyBlocked = true`.
- Log contains `ConfirmationToken is missing`, `invalid token`, or `token validation failed`.
- Run artifact `policy_outcome` is `PolicyBlocked`.

**Likely root cause:**

- `-ConfirmationToken` was not passed to the command.
- Token was minted with a different `OPENCODELAB_CONFIRMATION_RUN_ID` or `OPENCODELAB_CONFIRMATION_SECRET` than those set at execution time.
- Token was minted for different `-TargetHosts` or `-Action`/`-Mode` values.
- Token expired or was already consumed in a previous run.

**Corrective steps:**

```powershell
# 1) Confirm the env vars are set consistently for minting and execution
$env:OPENCODELAB_CONFIRMATION_RUN_ID = "run-20260214-01"
$env:OPENCODELAB_CONFIRMATION_SECRET = "<shared-secret>"

# 2) Mint a fresh token for the exact targets, action, and mode
$token = .\Scripts\New-ScopedConfirmationToken.ps1 -TargetHosts hv-a -Action teardown -Mode full

# 3) Execute teardown with the token
.\OpenCodeLab-App.ps1 -Action teardown -Mode full -TargetHosts hv-a -InventoryPath .\Ansible\inventory.json -ConfirmationToken $token -Force -NonInteractive
```

**Confirm recovery:**

```powershell
$latest = Get-Item "C:\LabSources\Logs\OpenCodeLab-Run-*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
(Get-Content $latest.FullName | ConvertFrom-Json) | Select-Object ExecutionOutcome, PolicyBlocked, policy_outcome
```

---

### Scenario: Missing Snapshot Restore Path

4) Missing Snapshot Restore Path

**Symptom / command failure signature:**

- `.\OpenCodeLab-App.ps1 -Action rollback` fails.
- Log contains `LabReady snapshot not found` or `Restore-VMSnapshot : No snapshots found`.
- `EscalationRequired` is `true` in the artifact after quick teardown.

**Likely root cause:**

- Lab was never fully deployed (full deploy creates the `LabReady` snapshot).
- Snapshot was manually deleted or was lost during a host failure/restart.
- Previous teardown removed VMs and their associated checkpoints.

**Corrective steps:**

```powershell
# 1) Confirm LabReady snapshots are missing
Get-VMSnapshot -VMName DC1,SVR1,WS1 | Where-Object { $_.Name -eq 'LabReady' }

# 2) If no results: run full deploy to recreate VMs and snapshot
$env:OPENCODELAB_ADMIN_PASSWORD = "YourStrongPasswordHere"
.\OpenCodeLab-App.ps1 -Action deploy -Mode full -NonInteractive

# 3) Confirm LabReady snapshot was created by full deploy
Get-VMSnapshot -VMName DC1,SVR1,WS1 | Where-Object { $_.Name -eq 'LabReady' } | Select-Object VMName, Name, CreationTime

# 4) Re-run rollback once snapshot is present
.\OpenCodeLab-App.ps1 -Action rollback
```

**Confirm recovery:**

```powershell
.\OpenCodeLab-App.ps1 -Action health
```

---

### Scenario: Network Route or Inventory Resolution Failures

5) Network Route or Inventory Resolution Failures

**Symptom / command failure signature:**

- `.\OpenCodeLab-App.ps1 -Action deploy -TargetHosts hv-a -InventoryPath .\Ansible\inventory.json` fails.
- Log contains `host not found in inventory`, `unresolved targets`, or `inventory validation failed`.
- Run artifact `PolicyBlocked` is `true` with `policy_reason` mentioning target resolution.
- Health check reports `vSwitch not found`, `NAT rule missing`, or `static IP unreachable`.

**Likely root cause:**

- Host name in `-TargetHosts` does not match any entry in the inventory JSON `hosts` array.
- Inventory file is malformed or missing the `hosts` top-level key.
- vSwitch or NAT rule was removed or renamed outside of the automation.
- Static IP routing is broken due to host network configuration changes.

**Corrective steps:**

```powershell
# 1) Validate inventory file content
$inv = Get-Content .\Ansible\inventory.json | ConvertFrom-Json
$inv.hosts | Select-Object name, role, connection

# 2) Confirm target host names match inventory
# -TargetHosts value must exactly match a .name entry in inventory hosts array

# 3) Check vSwitch exists
Get-VMSwitch | Select-Object Name, SwitchType

# 4) Check NAT rule
Get-NetNat | Select-Object Name, InternalIPInterfaceAddressPrefix

# 5) If vSwitch or NAT is missing, rebuild network infrastructure via full deploy
$env:OPENCODELAB_ADMIN_PASSWORD = "YourStrongPasswordHere"
.\OpenCodeLab-App.ps1 -Action deploy -Mode full -NonInteractive

# 6) Re-run with corrected inventory or targets
.\OpenCodeLab-App.ps1 -Action deploy -Mode quick -TargetHosts hv-a -InventoryPath .\Ansible\inventory.json -NonInteractive
```

**Confirm recovery:**

```powershell
.\OpenCodeLab-App.ps1 -Action health
.\OpenCodeLab-App.ps1 -Action status
```

---

### Scenario: Health Check and Rollback Loop Failures

6) Health Check and Rollback Loop Failures

**Symptom / command failure signature:**

- `.\OpenCodeLab-App.ps1 -Action health` fails repeatedly after rollback.
- `.\OpenCodeLab-App.ps1 -Action rollback` succeeds but health still fails.
- Log contains component-specific failures such as `domain controller unreachable`, `DNS resolution failed`, or `ADWS not running`.
- Run artifact `ExecutionOutcome` is not `success` even after multiple rollback attempts.

**Likely root cause:**

- `LabReady` snapshot captured VMs in a degraded state (e.g., domain services not fully started at snapshot time).
- Host network configuration changed since the snapshot was taken (different IP range, NAT prefix).
- VM startup ordering issue (DC1 must be healthy before SVR1/WS1 can pass health checks).

**Corrective steps:**

```powershell
# 1) Check VM startup order: DC1 first, then SVR1, WS1
.\OpenCodeLab-App.ps1 -Action start

# 2) Wait 60-90 seconds for services to initialize, then run health
Start-Sleep -Seconds 90
.\OpenCodeLab-App.ps1 -Action health

# 3) If health still fails, check individual VM connectivity
# (Run from host PowerShell)
Test-NetConnection -ComputerName 192.168.100.10 -Port 445   # DC1 SMB
Test-NetConnection -ComputerName 192.168.100.10 -Port 389   # DC1 LDAP

# 4) If DC1 is unreachable: rebuild entire lab from scratch
.\OpenCodeLab-App.ps1 -Action blow-away -DryRun -RemoveNetwork
$env:OPENCODELAB_ADMIN_PASSWORD = "YourStrongPasswordHere"
.\OpenCodeLab-App.ps1 -Action one-button-reset -NonInteractive -Force -RemoveNetwork

# 5) After full rebuild, run health to confirm baseline
.\OpenCodeLab-App.ps1 -Action health
```

**Confirm recovery:**

```powershell
.\OpenCodeLab-App.ps1 -Action status
.\OpenCodeLab-App.ps1 -Action health

$latest = Get-Item "C:\LabSources\Logs\OpenCodeLab-Run-*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
(Get-Content $latest.FullName | ConvertFrom-Json).ExecutionOutcome
```

---

## Rollback Decision Tree

```
Deployment or health fails
  |
  +-- Run: .\OpenCodeLab-App.ps1 -Action rollback
        |
        +-- Rollback succeeds --> Health check passes? --> DONE
        |                                  |
        |                                  +--> Health fails repeatedly --> Scenario 6 (loop failure)
        |
        +-- Rollback fails (LabReady missing) --> Scenario 4 (missing snapshot)
        |
        +-- EscalationRequired = true --> Scenario 2 (quick mode escalation)
        |
        +-- PolicyBlocked = true (token) --> Scenario 3 (token failure)
        |
        +-- Network/inventory error --> Scenario 5
        |
        +-- VM provisioning error --> Scenario 1
```

---

## Dispatch Rollback Kill Switch

If a rollout causes unexpected behavior across multiple hosts, disable dispatch immediately:

```powershell
# Set kill switch: dispatch is disabled, run artifacts record not_dispatched for all hosts
.\OpenCodeLab-App.ps1 -Action deploy -Mode quick -DispatchMode off -NonInteractive
```

Or set the environment variable to persist across multiple runs:

```powershell
$env:OPENCODELAB_DISPATCH_MODE = "off"
```

After the rollback is stable, re-enable dispatch with controlled canary:

```powershell
.\OpenCodeLab-App.ps1 -Action deploy -Mode quick -TargetHosts hv-a -DispatchMode canary -NonInteractive
```

---

## Artifact Reference

Every run writes two artifacts to `C:\LabSources\Logs`:

| File pattern | Content |
|---|---|
| `OpenCodeLab-Run-*.json` | Structured artifact: `ExecutionOutcome`, `PolicyBlocked`, `EscalationRequired`, `effective_mode`, `fallback_reason`, `host_outcomes`, `policy_outcome`, `blast_radius` |
| `OpenCodeLab-Run-*.txt` | Human-readable step-by-step run log |

Key fields to check after any failure:

| Field | Healthy value | Action if unhealthy |
|---|---|---|
| `ExecutionOutcome` | `success` | Review `.txt` log for step that failed |
| `PolicyBlocked` | `false` | Check token, inventory, or dispatch mode |
| `EscalationRequired` | `false` | Run full teardown with confirmation token |
| `effective_mode` | Matches requested mode | Check fallback_reason for auto-escalation |
| `policy_outcome` | `Approved` | Review policy_reason in artifact |

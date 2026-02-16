# Quick-Mode Auto-Heal Design

**Goal:** Reduce full deploy frequency by automatically repairing healable infrastructure gaps before falling back from quick to full mode.

**Problem:** When quick mode prerequisites fail (missing vSwitch, NAT, or LabReady snapshot), the system falls back to a full deploy that takes significantly longer. Many of these failures are repairable in seconds.

---

## Architecture

New private helper `Invoke-LabQuickModeHeal` sits between `Get-LabStateProbe` and `Resolve-LabModeDecision`:

```
Today:   StateProbe -> ModeDecision -> (quick or full)
New:     StateProbe -> QuickModeHeal -> Re-probe -> ModeDecision
```

The heal function runs only when `RequestedMode = 'quick'` and the probe shows gaps. It attempts targeted repairs, then the mode decision runs on refreshed probe data.

### Healable vs Unhealable Conditions

| Probe Flag              | Healable?   | Repair Action                                         |
|-------------------------|-------------|-------------------------------------------------------|
| `SwitchPresent = false` | Yes         | `New-LabSwitch`                                       |
| `NatPresent = false`    | Yes         | `New-LabNAT`                                          |
| `LabReadyAvailable = false` | Conditional | Health-check VMs first, then `Save-LabReadyCheckpoint` |
| `LabRegistered = false` | No          | Fall through to full                                  |
| `MissingVMs = true`     | No          | Fall through to full                                  |

### Return Shape

```powershell
[pscustomobject]@{
    HealAttempted   = [bool]
    HealSucceeded   = [bool]
    RepairsApplied  = [string[]]   # e.g. 'switch_recreated', 'nat_recreated', 'labready_created'
    RemainingIssues = [string[]]   # e.g. 'labready_unhealable'
    DurationSeconds = [int]
}
```

---

## LabReady Snapshot Healing

Snapshotting unhealthy VMs would poison every future quick deploy. Safety flow:

1. Check all VMs are present and running (start if stopped)
2. Wait for VMs to be responsive (`Wait-LabVMReady`, 60s timeout)
3. Lightweight health gate: DNS resolution from DC1, domain connectivity from SVR1/WS1
4. Health passes -> `Save-LabReadyCheckpoint` -> mark healed
5. Health fails -> don't snapshot, mark as unhealable, fall through to full

---

## Integration Points

### OpenCodeLab-App.ps1

- New `-AutoHeal` switch parameter (default `$true`)
- Call `Invoke-LabQuickModeHeal` after state probe, before mode decision
- Pass heal result into the run artifact

### Run Artifact

```json
{
  "auto_heal": {
    "attempted": true,
    "succeeded": true,
    "repairs_applied": ["switch_recreated", "nat_recreated"],
    "remaining_issues": [],
    "duration_seconds": 8
  }
}
```

### Console Output

```
[AutoHeal] Repairing missing vSwitch... OK (2s)
[AutoHeal] Repairing missing NAT... OK (1s)
[AutoHeal] All issues healed. Continuing with quick mode.
```

Or on failure:

```
[AutoHeal] Repairing missing LabReady snapshot... FAILED (VM health check failed)
[AutoHeal] Falling back to full mode.
```

### Lab-Config.ps1

```powershell
AutoHeal = @{
    Enabled                   = $true
    TimeoutSeconds            = 120
    HealthCheckTimeoutSeconds = 60
}
```

### GUI

No changes needed. Heal runs transparently inside the deploy action. Run artifact summary shows heal result.

---

## New Files

- `Private/Invoke-LabQuickModeHeal.ps1` -- core heal logic
- `Tests/QuickModeHeal.Tests.ps1` -- unit + integration tests

## Modified Files

- `OpenCodeLab-App.ps1` -- `-AutoHeal` switch, call heal between probe and mode decision
- `Lab-Config.ps1` -- `AutoHeal` config block
- `Tests/ModeDecision.Tests.ps1` -- post-heal mode decision cases
- `Tests/OpenCodeLabAppRouting.Tests.ps1` -- parameter wiring tests

---

## Testing Strategy

| Test Case                              | Input State                                | Expected Outcome                                           |
|----------------------------------------|--------------------------------------------|------------------------------------------------------------|
| Heals missing switch                   | `SwitchPresent=false`, rest OK             | `HealSucceeded=true`, `RepairsApplied=@('switch_recreated')` |
| Heals missing NAT                      | `NatPresent=false`, rest OK                | `HealSucceeded=true`, `RepairsApplied=@('nat_recreated')`    |
| Heals both switch+NAT                  | Both missing                               | Both repaired in one pass                                  |
| Heals LabReady when VMs healthy        | `LabReadyAvailable=false`, VMs healthy     | Snapshot created, healed                                   |
| Refuses LabReady when VMs unhealthy    | `LabReadyAvailable=false`, health fails    | `HealSucceeded=false`, unhealable                          |
| Skips unhealable: lab not registered   | `LabRegistered=false`                      | `HealAttempted=false`                                      |
| Skips unhealable: VMs missing          | `MissingVMs=true`                          | `HealAttempted=false`                                      |
| Respects timeout                       | Repair exceeds timeout                     | Aborts, `HealSucceeded=false`                              |
| No-op when probe is clean              | All prerequisites met                      | `HealAttempted=false`                                      |
| Disabled via config                    | `AutoHeal.Enabled=false`                   | `HealAttempted=false`                                      |

Tests mock `New-LabSwitch`, `New-LabNAT`, `Save-LabReadyCheckpoint`, and health check functions. One integration test validates the full probe -> heal -> re-probe -> mode-decision pipeline.

---

## Scope Boundaries

**Does:**
- Repair missing vSwitch, NAT, and LabReady snapshot
- Log repairs to console and run artifact
- Respect configurable timeout
- Allow opt-out via `-AutoHeal:$false` or config

**Does not:**
- Rebuild missing VMs (fall back to full)
- Change existing quick/full behavior when probe is clean
- Touch the GUI

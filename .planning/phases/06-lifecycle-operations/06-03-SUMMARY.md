# Phase 6 Plan 03 Summary: Lab Control Functions

**Date:** 2026-02-10
**Status:** Completed
**Wave:** 1

## Overview

Implemented lab-wide control functions for restarting and suspending all VMs as a group. Functions follow proper dependency ordering and wrap existing single-VM functions for consistency.

## Files Created

### SimpleLab/Public/Restart-LabVMs.ps1
- **Lines:** 134
- **Purpose:** Restart all lab VMs in dependency order

**Parameters:**
- `Force` (switch) - Force hard restart vs graceful shutdown
- `Wait` (switch) - Wait for all VMs to be ready after restart
- `TimeoutSeconds` (int, default: 600) - Per-VM timeout
- `StabilizationSeconds` (int, default: 30) - Post-boot stabilization

**Returns:**
```powershell
[PSCustomObject]@{
    VMsRestarted = @("SimpleDC", "SimpleServer", "SimpleWin11")
    FailedVMs = @()
    OverallStatus = "OK"
    Message = "Restarted 3 VM(s)"
    Duration = "00:05:30"
}
```

**Restart Order (DC first):**
1. SimpleDC (domain controller)
2. SimpleServer (member server)
3. SimpleWin11 (workstation)

### SimpleLab/Public/Suspend-LabVMs.ps1
- **Lines:** 156
- **Purpose:** Suspend all running VMs in reverse dependency order

**Parameters:**
- `Wait` (switch) - Wait for all suspends to complete
- `TimeoutSeconds` (int, default: 60) - Per-VM timeout

**Returns:**
```powershell
[PSCustomObject]@{
    VMsSuspended = @("SimpleWin11", "SimpleServer", "SimpleDC")
    FailedVMs = @()
    AlreadyStopped = @()
    OverallStatus = "OK"
    Message = "Suspended 3 VM(s), 0 already stopped"
    Duration = "00:00:45"
}
```

**Suspend Order (DC last - reverse):**
1. SimpleWin11 (workstation)
2. SimpleServer (member server)
3. SimpleDC (domain controller)

## Module Changes

### SimpleLab.psm1
- Added `Restart-LabVMs`, `Suspend-LabVMs` to Export-ModuleMember (alphabetically sorted)

### SimpleLab.psd1
- Updated module version to 0.9.0
- Added both functions to FunctionsToExport (alphabetically sorted)

## Implementation Details

### Design Pattern: Orchestrator Wrapper

Both functions follow the established orchestrator pattern:
1. Validate Hyper-V module available
2. Get VM configurations
3. Iterate through VMs in correct order
4. Call single-VM function for each VM
5. Aggregate results
6. Return structured status

### Dependency Ordering

**Why different orders for restart vs suspend?**

- **Restart (DC first):** DC must be running before members can authenticate
- **Suspend (DC last):** Members should be saved before DC (they depend on it)

This matches the existing Start-LabVMs/Stop-LabVMs pattern.

### Error Handling

Per-VM error handling with continue-on-failure:
- One VM failure doesn't stop the entire operation
- Failed VMs tracked separately
- Overall status: OK, Partial, or Failed

## Lab Control Function Matrix

| Operation | Single VM | All VMs | Order |
|-----------|-----------|---------|-------|
| Start | - | Start-LabVMs ✅ | DC → Server → Win11 |
| Stop | - | Stop-LabVMs ✅ | Win11 → Server → DC |
| Restart | Restart-LabVM ✅ | Restart-LabVMs ✅ | DC → Server → Win11 |
| Suspend | Suspend-LabVM ✅ | Suspend-LabVMs ✅ | Win11 → Server → DC |
| Resume | Resume-LabVM ✅ | - | DC → Server → Win11* |

*Resume not implemented for "all" - use Start-LabVMs instead

## Success Criteria Met

1. ✅ User can start all lab VMs with single command (Start-LabVMs - existing)
2. ✅ User can stop all lab VMs with single command (Stop-LabVMs - existing)
3. ✅ User can restart all lab VMs with single command (Restart-LabVMs - new)
4. ✅ User can suspend all lab VMs with single command (Suspend-LabVMs - new)
5. ✅ All lab-wide functions follow dependency order

## Module Statistics

**SimpleLab v0.9.0** - Now with complete lab control!

- **28 exported public functions** (+2)
- **20 internal helper functions** (same)
- **12 Lifecycle-related functions** (9 public, 3 private)

## Usage Examples

```powershell
# Restart entire lab
Restart-LabVMs

# Force restart entire lab and wait
Restart-LabVMs -Force -Wait

# Suspend entire lab (quick pause)
Suspend-LabVMs

# Lab workflow: Save state overnight
Suspend-LabVMs
# ... next morning ...
Start-LabVMs -Wait

# Lab workflow: Full restart
Restart-LabVMs -Wait
```

## Phase 6 Progress

| Plan | Description | Status |
|------|-------------|--------|
| 06-01 | Individual VM Restart | ✅ Complete |
| 06-02 | Enhanced VM Operations | ✅ Complete |
| 06-03 | Lab Control Functions | ✅ Complete |
| 06-04 | Status Display Improvements | ⏳ Next |

## Deviations from Plan

**None.** Implementation exactly matches plan specification.

## Next Steps

Proceed to **Phase 6 Plan 04** - final plan in Phase 6 for status display improvements.

**Overall Progress: 82% [█████████████░]**

20 of 22 total plans complete.

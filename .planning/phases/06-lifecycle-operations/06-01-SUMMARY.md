# Phase 6 Plan 01 Summary: Individual VM Restart

**Date:** 2026-02-10
**Status:** Completed
**Wave:** 1

## Overview

Implemented individual VM restart capability with the `Restart-LabVM` function. Users can now restart a single VM by name with support for graceful/forced restart and optional waiting for ready state.

## Files Created

### SimpleLab/Public/Restart-LabVM.ps1
- **Lines:** 230
- **Purpose:** Individual VM restart with control over restart type and timing

**Parameters:**
- `VMName` (string, mandatory) - Name of VM to restart
- `Force` (switch) - Force hard restart vs graceful shutdown
- `Wait` (switch) - Wait for VM to be ready after restart
- `TimeoutSeconds` (int, default: 300) - Maximum wait time for startup
- `StabilizationSeconds` (int, default: 30) - Post-boot stabilization period

**Returns:**
```powershell
[PSCustomObject]@{
    VMName = "SimpleDC"
    PreviousState = "Running"
    CurrentState = "Running"
    OverallStatus = "OK"  # OK, Timeout, Failed, NotFound
    Message = "Restarted successfully and ready"
    Duration = "00:01:45"
    StopDuration = "00:00:15"
    StartDuration = "00:01:30"
}
```

## Restart Behavior

**For Running VMs:**
1. Graceful shutdown (or forced if `-Force` specified)
2. Wait for Off state (60 second timeout)
3. Start VM
4. Optionally wait for Running + Heartbeat OK
5. Stabilization period for services

**For Stopped VMs:**
- Skips stop phase, directly starts VM
- Useful for "power on" semantics

**For Saved/Paused/Critical VMs:**
- Automatically uses force turn off
- These states don't support graceful shutdown

## Module Changes

### SimpleLab.psm1
- Added `Restart-LabVM` to Export-ModuleMember

### SimpleLab.psd1
- Updated module version to 0.7.0
- Added `Restart-LabVM` to FunctionsToExport (alphabetically sorted)

## Implementation Details

### Stop Phase Handling

The function handles different VM states appropriately:

| Previous State | Action |
|----------------|--------|
| Running | Graceful shutdown (or forced) |
| Off | Skip stop, start directly |
| Saved | Force turn off |
| Paused | Force turn off |
| Critical | Force turn off |

### Timeout Handling

**Stop Timeout:**
- 60 seconds to reach Off state
- Falls back to force turn off if timeout exceeded
- Prevents indefinite hangs on shutdown

**Start Timeout:**
- User configurable (default: 300 seconds)
- Waits for both Running state AND Heartbeat OK
- Returns "Timeout" status if not ready

### Stabilization Period

After VM is Running and Heartbeat OK:
- Default 30 seconds for service startup
- DCs need more time for AD/DNS services
- Configurable via `-StabilizationSeconds`

## Success Criteria Met

1. ✅ User can restart a single VM by name (`Restart-LabVM SimpleDC`)
2. ✅ Function supports graceful restart (default) and forced restart
3. ✅ Function waits for VM to fully start after restart
4. ✅ Function returns structured result with status and timing

## Module Statistics

**SimpleLab v0.7.0** - Now with individual VM restart!

- **23 exported public functions** (+1)
- **20 internal helper functions** (same)
- **7 Lifecycle-related functions** (4 public, 3 private)

## Usage Examples

```powershell
# Simple restart
Restart-LabVM -VMName SimpleDC

# Force restart (for hung VMs)
Restart-LabVM -VMName SimpleDC -Force

# Restart and wait for ready state
Restart-LabVM -VMName SimpleServer -Wait

# Extended timeout and stabilization for DC
Restart-LabVM -VMName SimpleDC -Wait -TimeoutSeconds 600 -StabilizationSeconds 60
```

## Phase 6 Progress

| Plan | Description | Status |
|------|-------------|--------|
| 06-01 | Individual VM Restart | ✅ Complete |
| 06-02 | Enhanced VM Operations | Pending |
| 06-03 | Lab Control Functions | Pending |
| 06-04 | Status Display Improvements | Pending |

## Deviations from Plan

**None.** Implementation exactly matches plan specification.

## Next Steps

Proceed to **Phase 6 Plan 02** which will enhance VM operations with additional lifecycle management features.

**Overall Progress: 73% [███████████░]**

18 of 22 total plans complete.

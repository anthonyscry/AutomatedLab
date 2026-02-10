# Phase 6: Lifecycle Operations - Research

**Date:** 2026-02-10
**Phase:** 6 of 9
**Focus:** Enhanced start/stop/restart/status operations for lab VMs

## Current State Analysis

### Already Implemented (Phase 4)

The following lifecycle functions already exist from Phase 4:

#### Start-LabVMs (SimpleLab/Public/Start-LabVMs.ps1)
- **Purpose:** Starts all lab VMs in dependency order
- **Features:**
  - Starts DC first, then servers, then clients
  - `-Wait` parameter for synchronous startup
  - `-TimeoutSeconds` (default: 300)
  - Tracks VMsStarted, FailedVMs, AlreadyRunning
  - Returns OverallStatus: OK, Partial, Failed
- **Command:** `Start-LabVMs [-Wait] [-TimeoutSeconds 300]`

#### Stop-LabVMs (SimpleLab/Public/Stop-LabVMs.ps1)
- **Purpose:** Stops all running lab VMs
- **Features:**
  - Stops in reverse dependency order (clients → servers → DC)
  - `-Force` for hard turn-off vs graceful shutdown
  - `-Wait` parameter for synchronous shutdown
  - `-TimeoutSeconds` (default: 60)
  - Tracks VMsStopped, FailedVMs, AlreadyStopped
- **Command:** `Stop-LabVMs [-Force] [-Wait] [-TimeoutSeconds 60]`

#### Get-LabStatus (SimpleLab/Public/Get-LabStatus.ps1)
- **Purpose:** Get comprehensive VM status
- **Returns:**
  - VMName, State, Status
  - CPUUsage, MemoryGB, Uptime
  - NetworkStatus, Heartbeat
- **Command:** `Get-LabStatus`

### Gaps Identified

**Missing: Individual VM Restart**
- No way to restart a single VM by name
- Restart combines Stop + Start with proper waiting
- Useful for troubleshooting individual VMs
- Should support both graceful and forced restart

## Requirements Mapping

From ROADMAP.md Phase 6 requirements:

| Req | Description | Status | Implementation |
|-----|-------------|--------|----------------|
| LIFE-01 | Start all lab VMs command | ✅ Complete | Start-LabVMs |
| LIFE-02 | Stop all lab VMs command | ✅ Complete | Stop-LabVMs |
| LIFE-03 | Individual VM restart | ❌ Missing | Need Restart-LabVM |
| LIFE-04 | VM status reporting | ✅ Complete | Get-LabStatus |
| NET-03 | Network-aware operations | ✅ Complete | vSwitch-aware functions |

## Technical Approach: Individual VM Restart

### Hyper-V Restart Cmdlets

**Option 1: Restart-VM (Native)**
```powershell
Restart-VM -Name "SimpleDC" -Force
```
- Available in Hyper-V module
- Equivalent to shutdown + boot
- Supports `-Force` for hard restart
- No built-in wait for ready state

**Option 2: Manual Stop + Start**
```powershell
Stop-VM -Name "SimpleDC" -Force
# Wait for Off state
Start-VM -Name "SimpleDC"
# Wait for Running + Heartbeat OK
```
- More control over timing
- Can add stabilization wait
- Better error handling

**Decision:** Use Option 2 for better control and consistency with existing patterns

### Restart Function Design

```powershell
function Restart-LabVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$VMName,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$Wait,

        [Parameter()]
        [int]$TimeoutSeconds = 300,

        [Parameter()]
        [int]$StabilizationSeconds = 30
    )

    # 1. Validate VM exists
    # 2. Stop VM (graceful or forced)
    # 3. Wait for Off state
    # 4. Start VM
    # 5. Wait for Running + Heartbeat OK
    # 6. Stabilization period
    # 7. Return structured result
}
```

### Restart Considerations

**For DC (SimpleDC):**
- Longer stabilization needed (AD services startup)
- DNS services need time to initialize
- Netlogon service dependency
- Default stabilization: 30-60 seconds

**For Member Servers:**
- Shorter stabilization (just OS + services)
- Domain-joined services need DC connectivity
- Default stabilization: 15-30 seconds

**For Win11:**
- Shorter stabilization (workstation)
- Default stabilization: 15 seconds

### Status Values

| Status | Meaning |
|--------|---------|
| OK | Restarted successfully |
| Partial | Restarted but warnings |
| Failed | Restart failed |
| NotFound | VM doesn't exist |
| Timeout | VM didn't restart within timeout |

## Success Criteria (from ROADMAP)

All Phase 6 success criteria must be TRUE:

1. ✅ User can start all lab VMs with single command
2. ✅ User can stop all lab VMs with single command
3. ❌ User can restart individual VMs by name
4. ✅ User sees status table showing running/stopped/off state for all VMs

**Plan 06-01 Objective:** Complete criterion #3 (individual VM restart)

## Integration Points

### Related Functions
- `Get-LabVMConfig` - For VM validation
- `Start-VM` / `Stop-VM` - Native Hyper-V cmdlets
- `Get-VM` - State checking
- Existing Start-LabVMs/Stop-LabVMs patterns

### Future Phases
- Phase 9 (User Experience) will add menu integration
- CLI flags for non-interactive mode

## Implementation Notes

**Idempotency:**
- Can restart already-running VMs (just restart again)
- Should handle VM not found gracefully

**Error Handling:**
- Timeout on stop
- Timeout on start
- VM not found
- Hyper-V module missing

**Verbosity:**
- Verbose output for each stage
- Progress reporting during waits

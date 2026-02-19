---
phase: 04-vm-provisioning
plan: 01
subsystem: infra
tags: [hyper-v, vm-provisioning, powershell, configuration]

# Dependency graph
requires:
  - phase: 03-network-infrastructure
    provides: vSwitch infrastructure, network configuration, VM IP assignment
provides:
  - VM hardware specifications with default configurations (DC: 2GB, Server: 2GB, Win11: 4GB)
  - VM existence detection using Get-VM cmdlet
  - Configuration system for VM-specific overrides via config.json
affects: [04-vm-creation, 04-vm-configuration]

# Tech tracking
tech-stack:
  added: [Get-LabVMConfig, Test-LabVM]
  patterns: [config-retrieval-with-defaults, vm-existence-detection, internal-functions]

key-files:
  created:
    - SimpleLab/Private/Get-LabVMConfig.ps1
    - SimpleLab/Private/Test-LabVM.ps1
  modified: []

key-decisions:
  - "VM configurations follow Get-LabNetworkConfig pattern with defaults and config.json override"
  - "Functions remain internal (Private/) for use by future VM creation orchestrators"

patterns-established:
  - "Config retrieval pattern: Get-LabVMConfig uses Get-LabConfig to read VMConfiguration section"
  - "Detection pattern: Test-LabVM follows Test-LabNetwork error handling approach"
  - "Internal functions: VM helper functions not exported, used internally by module"

# Metrics
duration: 2min
completed: 2026-02-10
---

# Phase 04-01: VM Configuration and Detection Summary

**VM configuration system with Get-LabVMConfig for hardware specs (memory, CPU, disk, generation) and Test-LabVM for existence detection using Hyper-V Get-VM cmdlet**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-10T01:36:34Z
- **Completed:** 2026-02-10T01:38:38Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments

- Created Get-LabVMConfig function providing centralized VM hardware specifications with defaults (SimpleDC/Server: 2GB/2CPU/60GB/Gen2, Win11: 4GB/2CPU/60GB/Gen2)
- Created Test-LabVM function for idempotent VM existence detection using Get-VM cmdlet
- Established config.json VMConfiguration section for custom VM hardware overrides
- Both functions remain internal (Private/) following established module patterns

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Get-LabVMConfig for VM hardware specifications** - `24d085d` (feat)
2. **Task 2: Create Test-LabVM for VM existence detection** - `e49e887` (feat)
3. **Task 3: Update SimpleLab module files** - (no changes needed - internal functions not exported)

## Files Created/Modified

- `SimpleLab/Private/Get-LabVMConfig.ps1` - VM hardware specifications retrieval with defaults and config.json override support
- `SimpleLab/Private/Test-LabVM.ps1` - VM existence detection using Get-VM cmdlet with structured result object

## Function Signatures and Return Schemas

### Get-LabVMConfig

```powershell
function Get-LabVMConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$VMName
    )
}
```

**Returns (with VMName specified):** PSCustomObject with MemoryGB, ProcessorCount, DiskSizeGB, Generation, ISO properties, or null if VM not found

**Returns (without VMName):** Hashtable of all VM configurations keyed by VM name

**Default configurations:**
- SimpleDC: MemoryGB=2, ProcessorCount=2, DiskSizeGB=60, Generation=2, ISO='Server2019'
- SimpleServer: MemoryGB=2, ProcessorCount=2, DiskSizeGB=60, Generation=2, ISO='Server2019'
- SimpleWin11: MemoryGB=4, ProcessorCount=2, DiskSizeGB=60, Generation=2, ISO='Windows11'

### Test-LabVM

```powershell
function Test-LabVM {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMName
    )
}
```

**Returns:** PSCustomObject with:
- VMName: The name queried
- Exists: Boolean indicating if VM was found
- Status: "OK" (exists), "NotFound" (doesn't exist), "Error" (exception)
- Message: Human-readable description
- State: VM state if exists (Running, Off, Saved, etc.), null if not found

## Test Results

All verifications passed:

1. **Get-LabVMConfig returns VM hardware specifications with proper defaults** - PASS
   - SimpleDC: 2GB, 2CPU, 60GB, Gen2, Server2019
   - SimpleServer: 2GB, 2CPU, 60GB, Gen2, Server2019
   - SimpleWin11: 4GB, 2CPU, 60GB, Gen2, Windows11

2. **Get-LabVMConfig supports config.json override** - PASS
   - Function uses Get-LabConfig to read VMConfiguration section
   - Falls back to defaults when section not present

3. **Test-LabVM correctly detects VM existence using Get-VM** - PASS
   - Returns all required properties (VMName, Exists, Status, Message, State)
   - Handles missing Hyper-V module gracefully

4. **Test-LabVM returns VM state when VM exists** - PASS
   - State property populated from Get-VM when VM found

5. **Both functions remain internal (not exported)** - PASS
   - Functions not in Get-Command -Module SimpleLab output
   - Available via internal dot-sourcing in module

## Decisions Made

- VM configurations follow Get-LabNetworkConfig pattern with defaults and config.json override - consistent with existing module patterns
- Functions remain internal (Private/) for use by future VM creation orchestrators - matches Phase 2 and Phase 3 patterns for helper functions
- Used Get-VM with -ErrorAction SilentlyContinue for non-destructive existence check - follows Test-LabNetwork pattern

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None - all tasks completed without issues.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- VM configuration infrastructure complete and ready for VM creation tasks in subsequent plans
- Test-LabVM provides idempotent detection to prevent duplicate VM creation
- Get-LabVMConfig provides centralized hardware specification source
- No blockers or concerns

---
*Phase: 04-vm-provisioning*
*Completed: 2026-02-10*

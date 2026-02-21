---
phase: 23-complex-networking
plan: 01
subsystem: infra
tags: [hyper-v, networking, multi-switch, nat, subnet, pester, tdd]

# Dependency graph
requires: []
provides:
  - "Lab-Config.ps1 Network.Switches array with named switch definitions (LabCorpNet, LabDMZ)"
  - "Get-LabNetworkConfig returns Switches property in all scenarios (multi/single/default)"
  - "New-LabSwitch -Switches and -All for multi-switch vSwitch creation"
  - "New-LabNAT -Switches and -All for multi-switch NAT configuration"
  - "Test-LabMultiSwitchSubnetOverlap for pairwise CIDR overlap detection before deployment"
affects:
  - 23-complex-networking
  - any plan using Get-LabNetworkConfig, New-LabSwitch, New-LabNAT, Test-LabVirtualSwitchSubnetConflict

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Multi-switch config via Switches array in GlobalLabConfig.Network (parallel to flat keys)"
    - "Inner helper function pattern (New-SingleLabVSwitch, New-SingleLabNAT) for multi-switch iteration"
    - "Pairwise parity check via nested for-loop over switch definitions"
    - "Hyper-V cmdlet stub pattern in BeforeAll for WSL/non-Hyper-V test environments"

key-files:
  created:
    - "Tests/ComplexNetworking-MultiSwitch.Tests.ps1"
  modified:
    - "Lab-Config.ps1"
    - "Private/Get-LabNetworkConfig.ps1"
    - "Public/New-LabSwitch.ps1"
    - "Public/New-LabNAT.ps1"
    - "Private/Test-LabVirtualSwitchSubnetConflict.ps1"

key-decisions:
  - "Switches array coexists with flat SwitchName/AddressSpace keys for full backward compat"
  - "Get-LabNetworkConfig reads Switches in priority order: Get-LabConfig.NetworkConfiguration > GlobalLabConfig.Network > flat-key fallback"
  - "NatName defaults to Name+NAT when omitted from Switches entries"
  - "New-LabSwitch/New-LabNAT use ParameterSetName (Single/Multi/All) to cleanly separate modes"
  - "Test-LabMultiSwitchSubnetOverlap is a new function in Test-LabVirtualSwitchSubnetConflict.ps1 (not modifying the existing single-switch function)"
  - "WSL/CI test environments lack Hyper-V cmdlets; stub functions defined in BeforeAll allow Pester to mock them"

patterns-established:
  - "Hyper-V cmdlet stubs in test BeforeAll: define stub functions if cmdlet not available, then Mock in BeforeEach"
  - "Multi-mode public functions: DefaultParameterSetName='Single' preserves old call signatures, new ParameterSets opt-in"

requirements-completed: [NET-01, NET-05]

# Metrics
duration: 9min
completed: 2026-02-21
---

# Phase 23 Plan 01: Multi-Switch Networking Summary

**Named vSwitch array (LabCorpNet + LabDMZ) with pairwise CIDR overlap detection and -All/-Switches parameters on New-LabSwitch and New-LabNAT**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-02-21T02:16:51Z
- **Completed:** 2026-02-21T02:25:55Z
- **Tasks:** 2
- **Files modified:** 5 (+ 1 created)

## Accomplishments

- Lab-Config.ps1 extended with `Network.Switches` array (two named switches: LabCorpNet/10.0.10.0/24, LabDMZ/10.0.20.0/24); flat keys retained for backward compat
- `Get-LabNetworkConfig` now returns a `Switches` property (PSCustomObject array) in all three resolution paths, with NatName defaulting logic
- `New-LabSwitch` and `New-LabNAT` gained `-Switches` and `-All` parameters for multi-switch operation via `DefaultParameterSetName='Single'` pattern
- `Test-LabMultiSwitchSubnetOverlap` added to detect pairwise CIDR range overlap before any switches are created
- 42 Pester TDD tests written and passing GREEN (covering config, schema, creation, NAT, and conflict detection)

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend config schema and Get-LabNetworkConfig** - `db3d2e4` (feat)
2. **Task 2: Update New-LabSwitch, New-LabNAT, and subnet conflict validation** - `23e5550` (feat)

_Note: TDD RED tests written in Task 1 commit; GREEN implementation follows in same commit after verification._

## Files Created/Modified

- `Tests/ComplexNetworking-MultiSwitch.Tests.ps1` - 42 TDD tests covering all new multi-switch behavior
- `Lab-Config.ps1` - Added `Network.Switches` array with 2 named switch definitions; extended `Test-LabConfigRequired` to validate Switches entries
- `Private/Get-LabNetworkConfig.ps1` - Returns `Switches` property in all resolution paths; normalizes to PSCustomObject with NatName defaulting
- `Public/New-LabSwitch.ps1` - Added `-Switches` and `-All` parameters; inner `New-SingleLabVSwitch` helper; DefaultParameterSetName='Single' for backward compat
- `Public/New-LabNAT.ps1` - Added `-Switches` and `-All` parameters; inner `New-SingleLabNAT` helper; result objects now include `Status` alias property
- `Private/Test-LabVirtualSwitchSubnetConflict.ps1` - Added `Test-LabMultiSwitchSubnetOverlap` function with pairwise CIDR range overlap detection

## Decisions Made

- **Switches coexists with flat keys**: `Network.Switches` array added without removing `SwitchName`, `AddressSpace`, etc. Old consumers still work.
- **Priority resolution in Get-LabNetworkConfig**: `Get-LabConfig.NetworkConfiguration.Switches` > `GlobalLabConfig.Network.Switches` > flat-key single-switch fallback.
- **NatName defaults**: When a Switches entry omits `NatName`, it defaults to `"${Name}NAT"` at normalization time.
- **Separate function for multi-switch overlap**: `Test-LabMultiSwitchSubnetOverlap` is a new function; existing `Test-LabVirtualSwitchSubnetConflict` (live adapter check) unchanged.
- **WSL/CI stub pattern**: Defined Hyper-V cmdlet stub functions in `BeforeAll` so Pester can mock them in environments where the Hyper-V module is absent.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Hyper-V cmdlet stubs for WSL test environment**
- **Found during:** Task 2 test implementation
- **Issue:** Pester's `Mock` requires the command to exist; `Register-HyperVMocks` fails in WSL because `Get-VM`, `Get-VMSwitch`, etc. are unavailable
- **Fix:** Added stub function definitions in `BeforeAll` for all Hyper-V cmdlets used by New-LabSwitch and New-LabNAT, replacing `Register-HyperVMocks` with targeted `Mock` calls in `BeforeEach`
- **Files modified:** `Tests/ComplexNetworking-MultiSwitch.Tests.ps1`
- **Verification:** 42/42 tests pass GREEN
- **Committed in:** db3d2e4 (combined with Task 1)

---

**Total deviations:** 1 auto-fixed (Rule 2 - missing test infrastructure for non-Hyper-V environment)
**Impact on plan:** Required for tests to run in WSL/CI. No scope creep; all test assertions match plan spec.

## Issues Encountered

- Pester's `Mock` cannot mock commands that don't exist as cmdlets in the current session. Resolved by defining stub functions in `BeforeAll` for Hyper-V cmdlets before mocking them in `BeforeEach`.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Multi-switch config foundation is complete; plans 23-02+ can use `Get-LabNetworkConfig().Switches` to enumerate switches
- `Test-LabMultiSwitchSubnetOverlap` available for pre-deployment validation in orchestration flows
- Both `New-LabSwitch -All` and `New-LabNAT -All` available for single-call multi-switch setup

## Self-Check: PASSED

- FOUND: .planning/phases/23-complex-networking/23-01-SUMMARY.md
- FOUND: Tests/ComplexNetworking-MultiSwitch.Tests.ps1
- FOUND: Private/Get-LabNetworkConfig.ps1
- FOUND: Private/Test-LabVirtualSwitchSubnetConflict.ps1
- FOUND: commit db3d2e4 (Task 1)
- FOUND: commit 23e5550 (Task 2)
- Tests: 42/42 PASSED

---
*Phase: 23-complex-networking*
*Completed: 2026-02-21*

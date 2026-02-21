---
phase: 23-complex-networking
plan: 02
subsystem: infra
tags: [hyper-v, networking, multi-switch, vlan, routing, pester, tdd]

# Dependency graph
requires:
  - phase: 23-01
    provides: "Lab-Config.ps1 Switches array, Get-LabNetworkConfig with Switches property"
provides:
  - "Lab-Config.ps1 IPPlan entries with per-VM Switch and VlanId (hashtable format)"
  - "Lab-Config.ps1 Network.Routing config block (host/gateway mode)"
  - "Private/Get-LabNetworkConfig.ps1 returns VMAssignments (Switch, VlanId, PrefixLength per VM)"
  - "Private/Get-LabNetworkConfig.ps1 returns Routing config with defaults"
  - "Private/New-LabVMNetworkAdapter.ps1 - idempotent adapter-to-switch connector with VLAN tagging"
  - "Public/Initialize-LabNetwork.ps1 - multi-subnet VM config with host or gateway routing"
affects:
  - 23-complex-networking
  - any plan using Initialize-LabNetwork, Get-LabNetworkConfig, or New-LabVMNetworkAdapter

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-VM IPPlan entries: hashtable format @{IP=...; Switch=...; VlanId=...} with plain string backward compat"
    - "VMAssignments property in Get-LabNetworkConfig: maps VM name to PSCustomObject with IP/Switch/VlanId/PrefixLength"
    - "Invoke-LabGatewayForwarding wrapper isolates Invoke-Command -VMName from Pester mock scope issues"
    - "New-LabVMNetworkAdapter idempotency: unconnected (empty SwitchName) treated as connect-needed, not wrong-switch"

key-files:
  created:
    - "Private/New-LabVMNetworkAdapter.ps1"
    - "Tests/ComplexNetworking-VMAssignment.Tests.ps1"
  modified:
    - "Lab-Config.ps1"
    - "Private/Get-LabNetworkConfig.ps1"
    - "Public/Initialize-LabNetwork.ps1"

key-decisions:
  - "Invoke-LabGatewayForwarding wrapper created in Initialize-LabNetwork.ps1 to avoid Invoke-Command -VMName parameter-set binding issues with Pester mocks in non-Hyper-V environments"
  - "IPPlan plain string entries map to first/default switch with null VlanId (full backward compat)"
  - "New-LabVMNetworkAdapter treats empty/unset SwitchName as unconnected (not wrong-switch), so Connect-VMNetworkAdapter runs without -Force"
  - "Routing defaults: Mode=host, GatewayVM='', EnableForwarding=true when Routing block is absent from config"
  - "Host routing: one New-NetRoute per switch subnet using vEthernet adapter alias and switch GatewayIp"
  - "New-LabVMNetworkAdapter auto-discovered by Lab-Common.ps1 via dynamic Private/ scanning -- no manual registration needed"

patterns-established:
  - "Wrapper function pattern: when Invoke-Command -VMName creates Pester mock complications, extract to a named wrapper function (Invoke-LabGatewayForwarding) that tests can Mock by name"
  - "Idempotent adapter connection: check current SwitchName before calling Connect-VMNetworkAdapter; treat empty string as not-yet-connected"

requirements-completed: [NET-02, NET-03, NET-04]

# Metrics
duration: 8min
completed: 2026-02-21
---

# Phase 23 Plan 02: VM-Switch Assignment, VLAN Tagging, and Inter-Subnet Routing Summary

**Per-VM switch assignment and VLAN tagging via IPPlan hashtable entries, idempotent New-LabVMNetworkAdapter helper, and host/gateway inter-subnet routing in Initialize-LabNetwork**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-02-21T02:28:53Z
- **Completed:** 2026-02-21T02:36:52Z
- **Tasks:** 2
- **Files modified:** 4 (+ 2 created)

## Accomplishments

- Lab-Config.ps1 IPPlan upgraded to hashtable format per VM (DC1/SVR1 on LabCorpNet, WS1 on LabDMZ with VLAN 200, DSC1 stays as plain string backward compat); Network.Routing section added
- `Get-LabNetworkConfig` now returns `VMAssignments` (per-VM Switch/VlanId/PrefixLength) and `Routing` (mode/gateway config) alongside existing `Switches` and `VMIPs` properties
- `New-LabVMNetworkAdapter` private helper created: idempotent, connects VM adapter to named switch, optionally sets VLAN in Access mode, handles unconnected/wrong-switch/VM-not-found cases
- `Initialize-LabNetwork` extended: calls `New-LabVMNetworkAdapter` per VM, then `Set-VMStaticIP`; multi-switch host routing via `New-NetRoute`; gateway routing via `Invoke-LabGatewayForwarding`; full backward compat for single-subnet plain configs
- 39 Pester TDD tests written and passing GREEN

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend config for per-VM switch assignment, VLAN IDs, and routing** - `1c814b0` (test - RED)
2. **Task 2: Create New-LabVMNetworkAdapter and update Initialize-LabNetwork for multi-subnet** - `00c6381` (feat - GREEN)

_Note: Task 1 commit contains both Lab-Config + Get-LabNetworkConfig implementation (GREEN) and the test file (partially RED for New-LabVMNetworkAdapter which didn't exist yet). Task 2 completes all GREEN._

## Files Created/Modified

- `Tests/ComplexNetworking-VMAssignment.Tests.ps1` - 39 TDD tests covering VMAssignments, Routing defaults, New-LabVMNetworkAdapter, and multi-subnet Initialize-LabNetwork
- `Lab-Config.ps1` - IPPlan entries converted to hashtable format with Switch/VlanId; Network.Routing section added
- `Private/Get-LabNetworkConfig.ps1` - Added VMAssignments and Routing properties; backward compat preserved for plain string IPPlan entries and absent Routing config
- `Private/New-LabVMNetworkAdapter.ps1` - New file: idempotent adapter connection with VLAN tagging
- `Public/Initialize-LabNetwork.ps1` - Extended for multi-subnet; added Invoke-LabGatewayForwarding wrapper; host and gateway routing logic

## Decisions Made

- **Invoke-LabGatewayForwarding wrapper**: Pester cannot reliably mock `Invoke-Command -VMName` (PS Direct parameter set) in non-Hyper-V environments. Extracting it to a named function allows standard `Mock Invoke-LabGatewayForwarding` pattern. Same approach as Hyper-V cmdlet stubs established in 23-01.
- **Unconnected adapter treatment**: `SwitchName = ''` on an existing adapter means "not connected yet" -- proceed to connect without `-Force`. Only non-empty, different-switch cases require `-Force`.
- **Routing defaults**: When `Network.Routing` is absent from config, `Get-LabNetworkConfig` returns `@{ Mode='host'; GatewayVM=''; EnableForwarding=$true }` so callers never need null-checks.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Invoke-LabGatewayForwarding wrapper for testability**
- **Found during:** Task 2 (GREEN verification)
- **Issue:** `Mock Invoke-Command { }` in Pester does not reliably intercept `Invoke-Command -VMName` calls in non-Hyper-V WSL environments because PS binds to a different parameter set that requires Credential, causing interactive prompts and zero mock invocation counts
- **Fix:** Added `Invoke-LabGatewayForwarding` function inside `Initialize-LabNetwork.ps1` that wraps the `Invoke-Command -VMName` call; updated test to `Mock Invoke-LabGatewayForwarding`
- **Files modified:** `Public/Initialize-LabNetwork.ps1`, `Tests/ComplexNetworking-VMAssignment.Tests.ps1`
- **Verification:** 39/39 tests GREEN; `Should -Invoke Invoke-LabGatewayForwarding -Times 1` passes
- **Committed in:** `00c6381` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 2 - testability requirement for non-Hyper-V environments)
**Impact on plan:** Required for test correctness in WSL/CI. No scope creep; the wrapper is a thin shim and does not change the runtime behavior on a real Hyper-V host.

## Issues Encountered

- Pester's `Mock Invoke-Command` cannot reliably intercept `Invoke-Command -VMName` in WSL because the parameter set binding requires Credential and the mock count reports 0. Resolved by introducing the `Invoke-LabGatewayForwarding` wrapper (same pattern as Hyper-V cmdlet stubs from 23-01).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- VM-to-switch assignment is complete; `New-LabVMNetworkAdapter` is available as a building block for any provisioning flow
- `Initialize-LabNetwork` now handles multi-subnet VM config end-to-end
- Host routing (`New-NetRoute`) and gateway routing (`Invoke-LabGatewayForwarding`) both tested
- Plans 23-03+ can consume `Get-LabNetworkConfig().VMAssignments` and `Get-LabNetworkConfig().Routing`

## Self-Check: PASSED

- FOUND: .planning/phases/23-complex-networking/23-02-SUMMARY.md
- FOUND: Tests/ComplexNetworking-VMAssignment.Tests.ps1
- FOUND: Private/New-LabVMNetworkAdapter.ps1
- FOUND: Private/Get-LabNetworkConfig.ps1
- FOUND: Public/Initialize-LabNetwork.ps1
- FOUND: commit 1c814b0 (Task 1)
- FOUND: commit 00c6381 (Task 2)
- Tests: 39/39 PASSED

---
*Phase: 23-complex-networking*
*Completed: 2026-02-21*

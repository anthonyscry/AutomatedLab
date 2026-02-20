---
phase: 18-configuration-profiles
plan: 02
subsystem: configuration
tags: [powershell, json, profiles, lab-config, pester, testing]

# Dependency graph
requires:
  - phase: 18-01
    provides: Save-LabProfile, Get-LabProfile, Remove-LabProfile cmdlets
provides:
  - Load-LabProfile: reads a named profile JSON and returns $GlobalLabConfig-compatible hashtable
  - LabProfile.Tests.ps1: 16 Pester tests covering all four profile CRUD cmdlets
affects:
  - 18-03
  - OpenCodeLab-App.ps1 (orchestration helper paths)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ConvertTo-Hashtable local helper: recursively converts PSCustomObject (from ConvertFrom-Json) back to nested hashtable — required because ConvertFrom-Json returns PSCustomObject but $GlobalLabConfig is a hashtable"
    - "Load function is side-effect-free: returns hashtable, never assigns to $GlobalLabConfig — caller decides assignment, keeps function easily testable"
    - "Malformed profile detection: validate 'config' NoteProperty exists after ConvertFrom-Json before returning"

key-files:
  created:
    - Private/Load-LabProfile.ps1
    - Tests/LabProfile.Tests.ps1
  modified: []

key-decisions:
  - "ConvertTo-Hashtable implemented as module-private function inside Load-LabProfile.ps1 — colocated with its single consumer rather than added to a shared helpers file"
  - "Load-LabProfile returns hashtable and does NOT touch $GlobalLabConfig — caller assigns the result, keeping the function testable without global state mocking"
  - "Test file uses New-TestConfig helper that returns realistic $GlobalLabConfig-shaped data (Lab.Name, Lab.CoreVMNames, Network.SwitchName, Paths.LabRoot, Credentials.InstallUser) enabling meaningful round-trip assertions"

patterns-established:
  - "Profile cmdlet test pattern: BeforeAll dot-sources all four cmdlets + defines New/Remove-TestRepoRoot + New-TestConfig helper"
  - "Every test uses try/finally with Remove-TestRepoRoot for guaranteed cleanup even on assertion failure"

requirements-completed: [PROF-02]

# Metrics
duration: 2min
completed: 2026-02-20
---

# Phase 18 Plan 02: Configuration Profiles - Load Cmdlet and Tests Summary

**Load-LabProfile with ConvertTo-Hashtable recursive conversion, plus 16 Pester tests proving full CRUD correctness and JSON round-trip fidelity for all four profile cmdlets**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-20T22:17:58Z
- **Completed:** 2026-02-20T22:19:27Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Load-LabProfile reads .planning/profiles/{Name}.json, validates 'config' key presence, converts PSCustomObject to nested hashtable via ConvertTo-Hashtable, and returns the config ready for $GlobalLabConfig assignment
- ConvertTo-Hashtable helper handles nested PSCustomObjects (recurse), arrays (iterate elements), and leaf values (pass through), preserving full config fidelity through JSON round-trips
- LabProfile.Tests.ps1 provides 16 passing Pester tests across all four cmdlets: 4 for Save, 4 for Get, 3 for Remove, 4 for Load, and 1 full CRUD lifecycle integration test

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Load-LabProfile cmdlet** - `df59627` (feat)
2. **Task 2: Create comprehensive Pester tests for all profile cmdlets** - `f83ba08` (feat)

## Files Created/Modified

- `Private/Load-LabProfile.ps1` - Load-LabProfile + private ConvertTo-Hashtable helper; validates name, reads profile JSON, checks 'config' key, converts PSCustomObject to hashtable
- `Tests/LabProfile.Tests.ps1` - 16 Pester 5 tests covering all four profile cmdlets with validation, error cases, round-trip data fidelity, and full CRUD lifecycle integration test

## Decisions Made

- ConvertTo-Hashtable is colocated inside Load-LabProfile.ps1 as a module-private function rather than extracted to a shared helpers file — it has one consumer and the coupling is intentional.
- Load-LabProfile returns the hashtable without assigning to $GlobalLabConfig, keeping the function side-effect-free and trivially testable without mocking global state.
- New-TestConfig in the test file mirrors the real $GlobalLabConfig shape (Lab.Name, Lab.CoreVMNames with 3 entries, Network.SwitchName, Paths.LabRoot, Credentials.InstallUser) to make round-trip assertions meaningful.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All four profile CRUD cmdlets (Save, Get, Remove, Load) are implemented and tested with 16 passing Pester tests
- PROF-01 (save), PROF-02 (load), PROF-03 (list), PROF-04 (delete) requirements all complete
- Ready for Phase 18-03: integration of profile cmdlets into OpenCodeLab-App.ps1 orchestration helper paths and GUI wiring

## Self-Check: PASSED

- FOUND: Private/Load-LabProfile.ps1
- FOUND: Tests/LabProfile.Tests.ps1
- FOUND commit: df59627 (feat(18-02): implement Load-LabProfile cmdlet)
- FOUND commit: f83ba08 (feat(18-02): add comprehensive Pester tests for all profile cmdlets)
- All 16 Pester tests pass

---
*Phase: 18-configuration-profiles*
*Completed: 2026-02-20*

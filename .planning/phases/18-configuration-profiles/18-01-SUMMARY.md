---
phase: 18-configuration-profiles
plan: 01
subsystem: configuration
tags: [powershell, json, profiles, lab-config]

# Dependency graph
requires: []
provides:
  - Save-LabProfile: saves $GlobalLabConfig snapshot as named JSON profile in .planning/profiles/
  - Get-LabProfile: lists all profiles with metadata or retrieves single profile by name
  - Remove-LabProfile: deletes named profile with validation and clear error on missing profile
affects:
  - 18-02
  - 18-03
  - GUI Settings (profile load/save operations)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Profile storage as JSON in .planning/profiles/{Name}.json (mirrors templates/ pattern)"
    - "RepoRoot injection: functions accept $RepoRoot parameter instead of reading global state — keeps functions testable"
    - "Name validation with ^[a-zA-Z0-9_-]+$ regex in all functions that accept Name (prevents path traversal)"
    - "vmCount metadata extracted at save time from Config.Lab.CoreVMNames for fast listing without parsing full config"

key-files:
  created:
    - Private/Save-LabProfile.ps1
    - Private/Get-LabProfile.ps1
    - Private/Remove-LabProfile.ps1
  modified: []

key-decisions:
  - "Config accepted as parameter not read from global — decouples Save-LabProfile from $GlobalLabConfig for testability"
  - "vmCount stored at save time in profile metadata so Get-LabProfile listing never parses nested config"
  - "Corrupt profile files emit Write-Warning and are skipped rather than failing the entire listing call"

patterns-established:
  - "Profile functions mirror Save-LabTemplate pattern: CmdletBinding, PSCustomObject output, throw on validation, try/catch on I/O"
  - "Join-Path nesting for PS 5.1 compatibility: Join-Path (Join-Path A B) C not Join-Path A B C"

requirements-completed: [PROF-01, PROF-03, PROF-04]

# Metrics
duration: 2min
completed: 2026-02-20
---

# Phase 18 Plan 01: Configuration Profiles - Core Cmdlets Summary

**Three Private/ cmdlets implementing named lab profile save/list/delete with JSON storage in .planning/profiles/, name validation, and RepoRoot-injected signatures for full testability**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-20T22:14:09Z
- **Completed:** 2026-02-20T22:15:33Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Save-LabProfile snapshots a $GlobalLabConfig-compatible hashtable to .planning/profiles/{Name}.json with ISO 8601 createdAt and vmCount metadata
- Get-LabProfile enumerates all profiles returning Name/Description/VMCount/CreatedAt/Path sorted newest-first, or retrieves a single profile's full JSON by name
- Remove-LabProfile deletes a named profile with name validation and clear "not found" error

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Save-LabProfile cmdlet** - `8a06efa` (feat)
2. **Task 2: Create Get-LabProfile and Remove-LabProfile cmdlets** - `1b7265e` (feat)

## Files Created/Modified

- `Private/Save-LabProfile.ps1` - Validates name, snapshots Config hashtable with metadata, writes to .planning/profiles/{Name}.json
- `Private/Get-LabProfile.ps1` - Lists profiles with summary metadata or retrieves single profile; skips corrupt files with Write-Warning
- `Private/Remove-LabProfile.ps1` - Validates name, throws on missing profile, deletes profile JSON file

## Decisions Made

- Config accepted as `$Config` parameter rather than reading `$GlobalLabConfig` directly — this decouples Save-LabProfile from the global and makes it easily unit-testable via Pester mocks.
- vmCount extracted and stored at save time in profile metadata so listing (Get-LabProfile) never needs to parse the nested config object — faster listing and resilient to config schema changes.
- Corrupt profile files are skipped with Write-Warning in Get-LabProfile listing to avoid a single bad file breaking all profile discovery.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Save/Get/Remove profile cmdlets are ready for integration with the orchestration helper paths in OpenCodeLab-App.ps1 (Phase 18-02)
- Pattern established: profile cmdlets match the template cmdlet signature style for consistent operator experience
- PROF-01 (save), PROF-03 (list), PROF-04 (delete) requirements completed

## Self-Check: PASSED

- FOUND: Private/Save-LabProfile.ps1
- FOUND: Private/Get-LabProfile.ps1
- FOUND: Private/Remove-LabProfile.ps1
- FOUND: .planning/phases/18-configuration-profiles/18-01-SUMMARY.md
- FOUND commit: 8a06efa (feat(18-01): implement Save-LabProfile cmdlet)
- FOUND commit: 1b7265e (feat(18-01): implement Get-LabProfile and Remove-LabProfile cmdlets)

---
*Phase: 18-configuration-profiles*
*Completed: 2026-02-20*

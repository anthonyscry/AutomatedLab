---
phase: 19-run-history-tracking
plan: 01
subsystem: cli
tags: [powershell, run-history, artifacts, reporting]

# Dependency graph
requires:
  - phase: 18-configuration-profiles
    provides: Private helpers Get-LabRunArtifactPaths and Get-LabRunArtifactSummary for reading run artifacts
provides:
  - Get-LabRunHistory public cmdlet with list and detail modes
  - Module-exported CLI command for operator run history review
affects: [20-lab-health-reports, 21-metrics-dashboard, future reporting phases]

# Tech tracking
tech-stack:
  added: []
  patterns: [list/detail dual-mode cmdlet, corrupt-artifact skip with Write-Warning, Get-LabRunArtifactPaths + Get-LabRunArtifactSummary reuse]

key-files:
  created:
    - Public/Get-LabRunHistory.ps1
  modified:
    - SimpleLab.psm1
    - SimpleLab.psd1

key-decisions:
  - "Sorted by EndedUtc string descending for newest-first ordering (ISO 8601 sorts lexicographically)"
  - "Corrupt artifact files skipped with Write-Warning to never crash list mode"
  - "Filter to .json only in list mode to avoid double-counting .txt duplicates"
  - "Detail mode matches on partial RunId substring for operator convenience"

patterns-established:
  - "Dual-mode cmdlet pattern: no -RunId gives summary table, -RunId gives full detail"
  - "Reuse existing Private helpers rather than re-implementing artifact parsing"

requirements-completed: [HIST-01, HIST-02, HIST-03]

# Metrics
duration: 2min
completed: 2026-02-20
---

# Phase 19 Plan 01: Run History Tracking Summary

**Get-LabRunHistory public cmdlet with list mode (last N runs sorted newest-first) and detail mode (full JSON for a specific RunId), registered in SimpleLab module exports**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-02-20T22:30:54Z
- **Completed:** 2026-02-20T22:32:04Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Created `Get-LabRunHistory` Public cmdlet with full comment-based help
- List mode reads all .json artifacts via `Get-LabRunArtifactPaths`, parses summaries via `Get-LabRunArtifactSummary`, sorts by EndedUtc descending, returns last N
- Detail mode locates artifact by RunId substring match and returns full deserialized JSON object
- Corrupt artifacts skipped with `Write-Warning` so partial failures never crash the listing
- Registered in both `SimpleLab.psm1` Export-ModuleMember and `SimpleLab.psd1` FunctionsToExport under a `# Run history` comment group

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Get-LabRunHistory Public cmdlet** - `147d1e2` (feat)
2. **Task 2: Register Get-LabRunHistory in module exports** - `620410e` (feat)

## Files Created/Modified

- `Public/Get-LabRunHistory.ps1` - New public cmdlet; list mode returns PSCustomObject[] with RunId/Action/Mode/Success/DurationSeconds/EndedUtc/Error; detail mode returns full JSON object
- `SimpleLab.psm1` - Added Get-LabRunHistory to Export-ModuleMember with # Run history comment group
- `SimpleLab.psd1` - Added Get-LabRunHistory to FunctionsToExport with # Run history comment group

## Decisions Made

- Sorted by EndedUtc string descending since ISO 8601 timestamps sort lexicographically, avoiding DateTime parsing overhead.
- Filtered to .json-only in list mode to avoid double-counting runs that have both .json and .txt artifacts from `Write-LabRunArtifacts`.
- Detail mode uses substring match on RunId for operator convenience (no need to supply exact filename).
- Corrupt artifacts silently skipped with Write-Warning to match the pattern established in Phase 18 profiles.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `Get-LabRunHistory` is available as a module-exported command for operators
- List mode and detail mode both reuse the Private helper infrastructure without modification
- Ready to proceed to Phase 19 Plan 02 (if any) or Phase 20

---
*Phase: 19-run-history-tracking*
*Completed: 2026-02-20*

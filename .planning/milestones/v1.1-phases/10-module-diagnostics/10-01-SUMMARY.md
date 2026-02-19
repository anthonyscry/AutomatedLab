---
phase: 10-module-diagnostics
plan: 01
subsystem: testing
tags: [pester, module-exports, wpf-gui, powershell, void-cast]

# Dependency graph
requires: []
provides:
  - GUI/Start-OpenCodeLabGUI.ps1 with [void] cast replacing all 50 Out-Null instances
  - SimpleLab.psm1 with 47-function export list (3 ghost functions removed)
  - SimpleLab.psd1 with FunctionsToExport matching psm1 exactly
  - Tests/ModuleDiagnostics.Tests.ps1 regression tests (10 tests)
affects: [all future phases touching module exports or GUI file]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "[void] cast pattern for WPF collection methods and dialog returns in PowerShell"
    - "[void](cmdlet -args) for cmdlet calls requiring output suppression"

key-files:
  created:
    - Tests/ModuleDiagnostics.Tests.ps1
  modified:
    - GUI/Start-OpenCodeLabGUI.ps1
    - SimpleLab.psm1
    - SimpleLab.psd1

key-decisions:
  - "Use [void] cast (not Out-Null) for WPF method calls; cmdlet calls need [void](cmdlet args) with parens"
  - "Canonical module export list is derived from Public/ file count (35 top-level + 12 Linux = 47)"
  - "Ghost functions Test-LabCleanup, Test-LabPrereqs, Write-ValidationReport removed from both psm1 and psd1"

patterns-established:
  - "[void] cast pattern: single-line expressions use [void]$x.Method(), cmdlets use [void](cmdlet args)"
  - "Module export regression test: parse both files with brace-matching, compare sorted lists"

requirements-completed:
  - DIAG-02
  - DIAG-03

# Metrics
duration: 13min
completed: 2026-02-17
---

# Phase 10 Plan 01: Module Diagnostics Summary

**Replaced 50 GUI Out-Null pipes with [void] cast, removed 3 ghost function exports from psm1/psd1, synced both module files to identical 47-function canonical list, with 10 regression tests.**

## Performance

- **Duration:** 13 min
- **Started:** 2026-02-17T15:01:13Z
- **Completed:** 2026-02-17T15:14:26Z
- **Tasks:** 3
- **Files modified:** 4 (GUI file, psm1, psd1, new test file)

## Accomplishments

- Converted all 50 `| Out-Null` instances in GUI/Start-OpenCodeLabGUI.ps1 to `[void]` cast pattern with correct handling of MessageBox.Show multi-line calls, single-line method calls, and inline foreach patterns
- Removed ghost functions (Test-LabCleanup, Test-LabPrereqs, Write-ValidationReport) from SimpleLab.psm1 Export-ModuleMember and synchronized SimpleLab.psd1 FunctionsToExport to identical 47-function list matching actual Public/ files
- Created 10 Pester 5.x regression tests in Tests/ModuleDiagnostics.Tests.ps1 verifying export consistency, no ghost functions, count parity with Public/ files, and GUI [void] pattern enforcement

## Task Commits

Each task was committed atomically:

1. **Task 1: Convert GUI Out-Null to [void] cast** - `a351ab5` (refactor)
2. **Task 2: Reconcile module export lists** - `967b57f` (fix)
3. **Task 3: Add module diagnostics regression tests + GUI syntax fix** - `b9ee36e` (feat)

## Files Created/Modified

- `GUI/Start-OpenCodeLabGUI.ps1` - Replaced all 50 `| Out-Null` with `[void]` cast; 51 [void] total (1 pre-existing + 50 new)
- `SimpleLab.psm1` - Removed 3 ghost functions; Export-ModuleMember now lists exactly 47 canonical functions
- `SimpleLab.psd1` - FunctionsToExport updated to match psm1 exactly (47 functions, same ordering)
- `Tests/ModuleDiagnostics.Tests.ps1` - 10 regression tests for export consistency and GUI [void] pattern

## Decisions Made

- Used `[void]` cast pattern for all Out-Null replacements per user decision (plan spec); for cmdlet calls with named parameters, `[void](cmdlet -Param value)` wraps the call in parens to make it an expression
- Canonical export list order: VM management (top-level Public/) first, then Linux VM helpers (Public/Linux/), alphabetical within each group
- Regression tests parse files via brace-matching string inspection (no module import), avoiding Hyper-V dependency requirement

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed [void] cast syntax error for cmdlet calls**
- **Found during:** Task 3 (regression test run revealed 3 syntax errors in GUI file)
- **Issue:** `[void]New-Item -ItemType Directory ...` is invalid PowerShell syntax; `[void]` cast requires an expression, not a cmdlet invocation with named parameters
- **Fix:** Wrapped cmdlet calls in parentheses: `[void](New-Item -ItemType Directory -Path $parentDir -Force)`
- **Files modified:** GUI/Start-OpenCodeLabGUI.ps1 (3 occurrences)
- **Verification:** `[System.Management.Automation.Language.Parser]::ParseFile` returned 0 errors; all 10 regression tests pass
- **Committed in:** b9ee36e (Task 3 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Necessary syntax correction; [void] cast requires expression context for cmdlet calls. No scope creep.

## Issues Encountered

- Initial Python replacement script had a bug: treated any line ending with `) | Out-Null` as a multi-line call closer, breaking indentation for single-line method calls like `$x.Method($y) | Out-Null`. Fixed by restricting the multi-line case to lines containing ONLY `)` (no other content) before `| Out-Null`.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Module exports are clean and regression-guarded for future changes
- GUI file is syntax-error-free with consistent [void] cast pattern
- All 10 new tests pass; no regressions in existing 837-test suite (total 847 passing)

---
*Phase: 10-module-diagnostics*
*Completed: 2026-02-17*

---
phase: 01-cleanup-config-foundation
plan: 02
subsystem: configuration
tags: [refactor, error-handling, consistency, fail-fast]
dependency_graph:
  requires: [CFG-02]
  provides: [standardized-helper-sourcing]
  affects: [OpenCodeLab-App.ps1, GUI/Start-OpenCodeLabGUI.ps1]
tech_stack:
  added: []
  patterns: [fail-fast-validation, try-catch-per-file]
key_files:
  created: []
  modified:
    - OpenCodeLab-App.ps1
    - GUI/Start-OpenCodeLabGUI.ps1
decisions:
  - Removed redundant $OrchestrationHelperPaths array in favor of Lab-Common.ps1 dynamic discovery
  - Applied fail-fast pattern to all entry point helper sourcing (broken helper = broken app)
  - Kept GUI's Get-ChildItem pattern (not switching to Lab-Common.ps1) to preserve scope isolation
metrics:
  duration_minutes: 1.2
  tasks_completed: 2
  files_modified: 2
  commits: 2
  completed_date: 2026-02-16
---

# Phase 01 Plan 02: Standardize Helper Sourcing Summary

**One-liner:** Eliminated redundant helper sourcing patterns and added fail-fast error handling across CLI and GUI entry points

## What Was Done

### Task 1: Replace $OrchestrationHelperPaths with Lab-Common.ps1 sourcing
**Commit:** 8a2082b

Removed the manual `$OrchestrationHelperPaths` array (18 explicit helper paths) from OpenCodeLab-App.ps1. The array was redundant because Lab-Common.ps1 already loads all Private/ and Public/ helpers via dynamic discovery.

**Changes:**
- Deleted lines 69-94: `$OrchestrationHelperPaths` array declaration and foreach loop
- Added fail-fast validation for Lab-Config.ps1 (throws if missing instead of silent skip)
- Added fail-fast validation for Lab-Common.ps1 (throws if missing instead of silent skip)
- Replaced `if (Test-Path) { . $file }` pattern with explicit throw on missing files

**Files modified:**
- `OpenCodeLab-App.ps1` (removed 26 lines, added 8 lines)

### Task 2: Add fail-fast error handling to GUI helper sourcing
**Commit:** b60d1ab

Wrapped each helper dot-source in try-catch block to provide descriptive error messages on load failure. Previously, the GUI used pipeline-based sourcing without error handling.

**Changes:**
- Replaced `Get-ChildItem | ForEach-Object { . $_.FullName }` with explicit foreach loop
- Added try-catch per file with descriptive error: "Failed to load {subDir} helper '{path}': {message}"
- Broken helper files now cause immediate GUI startup failure instead of silent skip
- Preserved existing Lab-Config.ps1 error swallowing (intentional for cross-platform path resolution)

**Files modified:**
- `GUI/Start-OpenCodeLabGUI.ps1` (added 7 lines, replaced 2 lines)

## Deviations from Plan

None - plan executed exactly as written.

## Verification Results

All success criteria met:

1. $OrchestrationHelperPaths array completely removed from OpenCodeLab-App.ps1 ✓
2. OpenCodeLab-App.ps1 sources helpers exclusively via Lab-Common.ps1 with fail-fast on missing ✓
3. GUI wraps every dot-source in try-catch with descriptive throw ✓
4. No silent helper load failures in any entry point ✓

**Parse validation:**
- OpenCodeLab-App.ps1: Parse successful ✓
- GUI/Start-OpenCodeLabGUI.ps1: Parse successful ✓

## Impact

**Before:**
- Three different helper sourcing patterns across codebase
- Silent failures on missing/broken helper files
- Redundant helper loading in OpenCodeLab-App.ps1 (Lab-Common.ps1 + manual array)

**After:**
- Single consistent fail-fast pattern: broken helper = immediate error with clear message
- OpenCodeLab-App.ps1 relies on Lab-Common.ps1 for all helper sourcing
- GUI provides file-level error context on helper load failures
- Reduced maintenance burden (no manual $OrchestrationHelperPaths array to update)

## Next Steps

Plan 03 will remove legacy variable fallbacks (lines 99-103 in OpenCodeLab-App.ps1) as part of CFG-01 implementation. Those variables are currently preserved for backward compatibility.

## Self-Check: PASSED

**Files created:** None (refactor only)

**Files modified:**
- FOUND: /mnt/c/projects/AutomatedLab/OpenCodeLab-App.ps1
- FOUND: /mnt/c/projects/AutomatedLab/GUI/Start-OpenCodeLabGUI.ps1

**Commits:**
- FOUND: 8a2082b
- FOUND: b60d1ab

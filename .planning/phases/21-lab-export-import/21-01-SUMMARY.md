---
phase: 21-lab-export-import
plan: 01
subsystem: profiles
tags: [json, export, import, packages, profiles, powershell]

requires:
  - phase: 18-configuration-profiles
    provides: Save-LabProfile, Load-LabProfile, Get-LabProfile cmdlets and .planning/profiles/ directory
provides:
  - Export-LabPackage cmdlet for bundling profiles into portable JSON packages
  - Import-LabPackage cmdlet for restoring packages as profiles with validation
affects: [21-02, gui, orchestration]

tech-stack:
  added: []
  patterns: [multi-error-validation, package-metadata-envelope, ConvertTo-PackageHashtable]

key-files:
  created:
    - Private/Export-LabPackage.ps1
    - Private/Import-LabPackage.ps1
  modified: []

key-decisions:
  - "ConvertTo-PackageHashtable named separately from ConvertTo-Hashtable to avoid cross-file collision"
  - "Import validation collects all errors before throwing for better operator experience"

patterns-established:
  - "Package envelope: packageVersion + exportedAt + sourceName + sourceDescription + config"
  - "Multi-error validation: accumulate $validationErrors array then throw joined list"

requirements-completed: [XFER-01, XFER-02, XFER-03]

duration: 2min
completed: 2026-02-20
---

# Phase 21 Plan 01: Lab Export/Import Core Cmdlets Summary

**Export-LabPackage and Import-LabPackage cmdlets for portable JSON lab package transfer with multi-field validation**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-20T23:02:10Z
- **Completed:** 2026-02-20T23:03:30Z
- **Tasks:** 2
- **Files created:** 2

## Accomplishments
- Export-LabPackage reads saved profiles and bundles into self-contained JSON packages with version metadata
- Import-LabPackage validates ALL required fields (packageVersion, sourceName, config, config.Lab) before applying
- Multi-error validation collects all issues and displays them together, not fail-fast
- ConvertTo-PackageHashtable avoids naming collision with Load-LabProfile's ConvertTo-Hashtable

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Export-LabPackage cmdlet** - `bd0cb5a` (feat)
2. **Task 2: Create Import-LabPackage cmdlet** - `81052c4` (feat)

## Files Created/Modified
- `Private/Export-LabPackage.ps1` - Export cmdlet: reads profile, builds package envelope, writes JSON
- `Private/Import-LabPackage.ps1` - Import cmdlet with validation, ConvertTo-PackageHashtable, Save-LabProfile call

## Decisions Made
- ConvertTo-PackageHashtable named separately from ConvertTo-Hashtable to avoid cross-file naming collision when both files are sourced
- Import validation collects all errors into array before throwing, so operators see every issue at once

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Both cmdlets ready for test coverage in plan 21-02
- Export/Import round-trip can be tested with any existing profile in .planning/profiles/
- OpenCodeLab-App.ps1 orchestration helper registration deferred to plan 21-02 or later

---
*Phase: 21-lab-export-import*
*Completed: 2026-02-20*

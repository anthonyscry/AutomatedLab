---
phase: 22-custom-role-templates
plan: 01
subsystem: roles
tags: [powershell, pester, json, schema-validation, custom-roles, auto-discovery]

# Dependency graph
requires: []
provides:
  - JSON custom role schema with all required fields (name, tag, description, os, resources, provisioningSteps)
  - Test-LabCustomRoleSchema: field-level schema validator returning Valid flag and specific error messages
  - Get-LabCustomRole: auto-discovery from .planning/roles/*.json with -List and -Name modes
  - Example MonitoringServer role JSON at .planning/roles/example-role.json
  - 30 Pester tests covering schema validation, discovery, listing, and memory parsing
affects:
  - phase: 22-custom-role-templates (later plans that invoke custom roles during lab build)
  - LabBuilder/Build-LabFromSelection.ps1 (future integration point)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - JSON-file-as-role-definition: Role definitions live as .json files in .planning/roles/, discovered without code changes
    - Schema validation pattern: Validator returns pscustomobject{Valid, Errors[]} instead of throwing, enabling graceful skip
    - PS5.1-nested-Join-Path: Using Join-Path (Join-Path A B) C for three-segment paths in PS 5.1

key-files:
  created:
    - Private/Test-LabCustomRoleSchema.ps1
    - Private/Get-LabCustomRole.ps1
    - Tests/CustomRoles.Tests.ps1
    - .planning/roles/example-role.json
  modified: []

key-decisions:
  - "Validator returns result object (not throw) so discovery can warn-and-skip invalid files rather than aborting"
  - "Memory strings parsed to numeric bytes at load time so callers get long values matching Get-LabRole_* output"
  - "PSCustomObject-to-hashtable conversion done inline during discovery, not in validator, keeping validator pure"
  - "Private helpers (Convert-PsObjectToHashtable, ConvertTo-LabMemoryValue) defined in same file as Get-LabCustomRole to avoid cross-file sourcing complexity"

patterns-established:
  - "Custom role files placed in .planning/roles/*.json are auto-discovered at runtime without code changes"
  - "Schema errors name the specific missing field and file path for clear operator diagnostics"
  - "Invalid files produce Write-Warning and are skipped; only fatal errors throw"

requirements-completed: [ROLE-01, ROLE-02, ROLE-04, ROLE-05]

# Metrics
duration: 4min
completed: 2026-02-21
---

# Phase 22 Plan 01: Custom Role Template Engine Summary

**JSON-driven custom role auto-discovery via Test-LabCustomRoleSchema + Get-LabCustomRole, with 30 Pester tests and example MonitoringServer role**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-02-21T01:52:13Z
- **Completed:** 2026-02-21T01:55:50Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- Created `Test-LabCustomRoleSchema` validator with required-field, OS, tag-format, and provisioning-step type checks; returns field-specific error messages
- Created `Get-LabCustomRole` with auto-discovery from `.planning/roles/`, -List mode returning sorted metadata objects, and -Name mode returning `Get-LabRole_*`-compatible hashtables
- Created `Tests/CustomRoles.Tests.ps1` with 30 Pester 5 tests — all passing
- Created example `MonitoringServer` role JSON at `.planning/roles/example-role.json` demonstrating the full schema

## Task Commits

Each task was committed atomically:

1. **Task 1: Create JSON role schema, validator, and example role** - `01602a7` (feat)
2. **Task 2: Create Get-LabCustomRole loader with auto-discovery and listing** - `999196a` (feat)
3. **Task 3: Create Pester tests for custom role engine** - `c52f998` (test)

## Files Created/Modified

- `Private/Test-LabCustomRoleSchema.ps1` - Schema validator; returns `{Valid, Errors[]}` for any role hashtable
- `Private/Get-LabCustomRole.ps1` - Loader with auto-discovery, -List and -Name modes, memory parsing, PSCustomObject conversion
- `Tests/CustomRoles.Tests.ps1` - 30 Pester tests covering schema validation (16 cases) and discovery/listing (14 cases)
- `.planning/roles/example-role.json` - Example MonitoringServer role with SNMP Windows Feature + PowerShell config step

## Decisions Made

- **Warn-and-skip over throw:** Validator returns a result object; discovery writes `Write-Warning` and continues rather than aborting on bad files. This lets operators fix one broken role without blocking all others.
- **Inline private helpers:** `Convert-PsObjectToHashtable` and `ConvertTo-LabMemoryValue` live in `Get-LabCustomRole.ps1` to avoid extra dot-source calls in the loader.
- **Type constraint `[object]` for PSCustomObject helper:** Using `[System.Management.Automation.PSCustomObject]` as a parameter type caused a PS binding coercion error under `Set-StrictMode -Version Latest`; changed to `[object]` which allows all PSCustomObject inputs correctly.
- **Memory converted to bytes at load time:** Callers receive `[long]` byte values matching existing `Get-LabRole_*` output shape, not raw strings.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed PSCustomObject parameter type constraint in Convert-PsObjectToHashtable**
- **Found during:** Task 2 verification run
- **Issue:** Declaring `[System.Management.Automation.PSCustomObject]$InputObject` as parameter type caused PowerShell binding to fail with a coercion error when passing a real PSCustomObject under strict mode
- **Fix:** Changed parameter type to `[object]$InputObject`; behavior identical since method access (`PSObject.Properties`) works on both
- **Files modified:** `Private/Get-LabCustomRole.ps1`
- **Verification:** Task 2 verification command returned count=1, name=MonitoringServer
- **Committed in:** `999196a` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Essential fix for parameter binding under strict mode. No scope creep.

## Issues Encountered

None beyond the auto-fixed parameter type bug above.

## User Setup Required

None - no external service configuration required. Operators create custom roles by adding `.json` files to `.planning/roles/`.

## Next Phase Readiness

- `Get-LabCustomRole` and `Test-LabCustomRoleSchema` are ready for integration into `LabBuilder/Build-LabFromSelection.ps1`
- Custom role provisioning step execution (invoking `windowsFeature`, `powershellScript`, `linuxCommand` steps on VMs) is the natural next plan
- The `IsCustomRole=$true` flag in returned hashtables allows the build pipeline to route custom roles through a different execution path

## Self-Check: PASSED

- Private/Test-LabCustomRoleSchema.ps1 — FOUND
- Private/Get-LabCustomRole.ps1 — FOUND
- Tests/CustomRoles.Tests.ps1 — FOUND
- .planning/roles/example-role.json — FOUND
- .planning/phases/22-custom-role-templates/22-01-SUMMARY.md — FOUND
- Commit 01602a7 — FOUND (Task 1)
- Commit 999196a — FOUND (Task 2)
- Commit c52f998 — FOUND (Task 3)

---
*Phase: 22-custom-role-templates*
*Completed: 2026-02-21*

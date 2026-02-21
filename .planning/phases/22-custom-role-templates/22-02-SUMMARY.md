---
phase: 22-custom-role-templates
plan: 02
subsystem: roles
tags: [powershell, pester, custom-roles, labbuilder, integration, static-analysis]

# Dependency graph
requires:
  - phase: 22-custom-role-templates/22-01
    provides: Get-LabCustomRole auto-discovery helper and Test-LabCustomRoleSchema validator
provides:
  - Custom roles integrated as first-class citizens in all three LabBuilder entry points
  - Build-LabFromSelection loads custom roles via Get-LabCustomRole and provisions via ProvisioningSteps
  - Invoke-LabBuilder -Roles validation dynamically accepts custom role tags
  - Select-LabRoles interactive menu displays custom roles under '-- Custom Roles --' separator
  - 13 Pester integration tests covering static analysis and end-to-end discovery-to-role-def
affects:
  - phase: 22-custom-role-templates (later plans extending custom role capabilities)
  - LabBuilder/Build-LabFromSelection.ps1 (provisioning pipeline now handles custom roles)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Custom-role-skip-in-built-in-loop: Built-in role loader now uses `continue` for unknown tags instead of throwing; unknown tags flow into custom role section
    - Static-test-via-Select-String: Integration tests verify LabBuilder file contents with Select-String pattern matching (no execution required)
    - Custom-role-provisioning-switch: windowsFeature/powershellScript/linuxCommand/unknown step types routed via switch statement with graceful warnings

key-files:
  created:
    - Tests/CustomRoleIntegration.Tests.ps1
  modified:
    - LabBuilder/Build-LabFromSelection.ps1
    - LabBuilder/Invoke-LabBuilder.ps1
    - LabBuilder/Select-LabRoles.ps1

key-decisions:
  - "Built-in role foreach now uses continue (not throw) for unknown tags; custom role section loads them separately — clean separation of concerns"
  - "Phase 11 custom provisioning runs sequentially after Windows post-install jobs (before Linux) — ensures AD is up before custom Windows roles configure"
  - "Invoke-LabBuilder expands validTags at runtime by calling Get-LabCustomRole -List — new custom roles auto-accepted without code changes"
  - "Select-LabRoles appends custom roles with IsCustomRole flag on menu entries; flag is informational and does not change toggle behavior"

patterns-established:
  - "Custom role skip pattern: `if (-not $roleScriptMap.ContainsKey($_)) { continue }` lets built-in loop stay unchanged while custom roles accumulate separately"
  - "Integration tests use Select-String for static analysis — no AutomatedLab module needed, runs in any environment"

requirements-completed: [ROLE-03]

# Metrics
duration: 3min
completed: 2026-02-21
---

# Phase 22 Plan 02: Custom Role LabBuilder Integration Summary

**Custom roles wired into all three LabBuilder entry points (menu, CLI validation, build pipeline) with provisioning step execution and 13 integration tests**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-02-21T01:58:11Z
- **Completed:** 2026-02-21T02:01:20Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- Modified `Build-LabFromSelection.ps1` Phase 7 to skip unknown tags (custom) in the built-in loop and load them via `Get-LabCustomRole -Name`; Phase 11 executes custom role `ProvisioningSteps` (windowsFeature, powershellScript, linuxCommand with warning, unknown with warning)
- Modified `Invoke-LabBuilder.ps1` Build operation to expand `$validTags` at runtime with `Get-LabCustomRole -List` before the invalid-tag check
- Modified `Select-LabRoles.ps1` to append custom roles under a `-- Custom Roles --` separator after loading config's RoleMenu; updated help text to mention `.planning/roles/*.json` auto-discovery
- Created `Tests/CustomRoleIntegration.Tests.ps1` with 13 Pester 5 tests — all passing; 30 Plan-01 regression tests still passing

## Task Commits

Each task was committed atomically:

1. **Task 1: Integrate custom roles into Build-LabFromSelection and Invoke-LabBuilder** - `70e20a5` (feat)
2. **Task 2: Integrate custom roles into Select-LabRoles interactive menu** - `de16e53` (feat)
3. **Task 3: Create integration tests for custom role workflow** - `c218337` (test)

## Files Created/Modified

- `LabBuilder/Build-LabFromSelection.ps1` - Phase 7: custom role loading block; Phase 11: custom role ProvisioningSteps execution switch
- `LabBuilder/Invoke-LabBuilder.ps1` - Build op: runtime expansion of validTags with Get-LabCustomRole -List before invalid-tag check
- `LabBuilder/Select-LabRoles.ps1` - Custom roles section appended after $Config.RoleMenu; help text updated
- `Tests/CustomRoleIntegration.Tests.ps1` - 13 integration tests: static analysis (3 entry points) + end-to-end (discovery, listing, example role) + provisioning step type coverage

## Decisions Made

- **Continue over throw in built-in loop:** The built-in role loader's `if (-not $entry) { throw }` was changed to `{ continue }` so unknown tags silently pass to the custom role section. This is the cleanest separation without duplicating the tag set.
- **Sequential custom provisioning after Windows parallel jobs:** Custom role provisioning runs in Phase 11, after the Windows parallel post-install jobs complete but before Linux post-installs. This ensures AD services are available for custom Windows roles.
- **Runtime validTags expansion:** Rather than maintaining a static custom role tag list in Invoke-LabBuilder, the validator calls `Get-LabCustomRole -List` at build time. New custom roles are automatically accepted without code changes.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Changed built-in role loop from throw to continue for unknown tags**
- **Found during:** Task 1 (Build-LabFromSelection integration)
- **Issue:** The existing `foreach ($tag in $SelectedRoles)` loop threw `"Unknown role tag: $tag"` for any tag not in `$roleScriptMap`. The plan specified adding custom role loading AFTER this loop, which would never be reached if a custom tag was present.
- **Fix:** Changed `if (-not $entry) { throw "Unknown role tag: $tag" }` to `if (-not $entry) { continue }`. The custom role section that follows handles the unknown tag and throws a clear error if it is not found as a custom role either.
- **Files modified:** `LabBuilder/Build-LabFromSelection.ps1`
- **Verification:** Syntax check returned 0 errors; integration test `contains a Get-LabCustomRole call to load custom role definitions` passes
- **Committed in:** `70e20a5` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Essential fix — without this the custom role section would be unreachable. No scope creep.

## Issues Encountered

None beyond the auto-fixed loop control bug above.

## User Setup Required

None - operators create custom roles by adding `.json` files to `.planning/roles/`. No external service configuration required.

## Next Phase Readiness

- All three LabBuilder entry points now treat custom roles identically to built-in roles from the operator's perspective
- `ProvisioningSteps` execution in Phase 11 covers `windowsFeature` and `powershellScript`; `linuxCommand` produces a warning (future wiring point)
- Phase 22 Plan 03 (if planned) could add custom role VM name/IP registration in Lab-Config.ps1 to complete the end-to-end config story

## Self-Check: PASSED

- LabBuilder/Build-LabFromSelection.ps1 — FOUND
- LabBuilder/Invoke-LabBuilder.ps1 — FOUND
- LabBuilder/Select-LabRoles.ps1 — FOUND
- Tests/CustomRoleIntegration.Tests.ps1 — FOUND
- .planning/phases/22-custom-role-templates/22-02-SUMMARY.md — FOUND
- Commit 70e20a5 — FOUND (Task 1)
- Commit de16e53 — FOUND (Task 2)
- Commit c218337 — FOUND (Task 3)

---
*Phase: 22-custom-role-templates*
*Completed: 2026-02-21*

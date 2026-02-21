---
phase: 27-powerstig-dsc-baselines
plan: 02
subsystem: infra
tags: [powerstig, dsc, stig, compliance, windows-server, pester, tdd]

# Dependency graph
requires:
  - phase: 27-powerstig-dsc-baselines
    provides: Phase CONTEXT.md with STIG mapping decisions and role normalization design
provides:
  - Get-LabSTIGProfile: maps VM OsRole+OsVersionBuild to PowerSTIG Technology/StigVersion/OsRole tuple
  - Test-PowerStigInstallation: pre-flight check for PowerSTIG module and 10 dependency modules via WinRM
  - 54 Pester tests covering all branches, edge cases, and error paths
affects:
  - 27-03 (Invoke-LabSTIGBaseline consumes both helpers)
  - 29 (dashboard reads stig-compliance.json written by 27-03 which calls these)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Private/ helpers accept only primitive params — caller discovers and passes runtime values (no live VM queries inside helpers)"
    - "StartsWith prefix matching for OS build strings handles major.minor.build and major.minor.build.revision formats"
    - "Pester Mock of Invoke-Command in BeforeEach blocks to test remote execution helpers locally"

key-files:
  created:
    - Private/Get-LabSTIGProfile.ps1
    - Private/Test-PowerStigInstallation.ps1
    - Tests/LabSTIGProfile.Tests.ps1
    - Tests/PowerStigInstallation.Tests.ps1
  modified: []

key-decisions:
  - "Empty string rejected by Mandatory param binding — test updated to expect throw rather than null return"
  - "Test-PowerStigInstallation mocks Invoke-Command at Pester level — no live WinRM needed for unit tests"
  - "Version map uses StartsWith prefix matching to handle full build.revision strings from Win32_OperatingSystem"

patterns-established:
  - "STIG helpers: pure param-in/pscustomobject-out, no side effects, fully testable without VMs"
  - "Remote check helpers: try/catch returns structured failure result with warning rather than throwing"

requirements-completed: [STIG-01, STIG-02]

# Metrics
duration: 3min
completed: 2026-02-21
---

# Phase 27 Plan 02: STIG Profile Mapping and Pre-Flight Check Summary

**Get-LabSTIGProfile maps OsRole+OsVersionBuild to PowerSTIG WindowsServer technology tuple; Test-PowerStigInstallation checks PowerSTIG 4.28.0 and 10 dependency modules on a remote VM via WinRM, returning structured pass/fail results**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-21T04:44:15Z
- **Completed:** 2026-02-21T04:46:50Z
- **Tasks:** 2
- **Files modified:** 4 (all created)

## Accomplishments
- Get-LabSTIGProfile translates DC/MS role and Server 2019/2022 build prefix to PowerSTIG-compatible Technology, StigVersion, and OsRole fields
- Test-PowerStigInstallation verifies PowerSTIG module (min 4.28.0) and 10 dependency modules on remote VM via Invoke-Command, returning structured PSCustomObject with Installed, Version, MissingModules, ComputerName
- 54 Pester tests across both functions covering success paths, error conditions, role normalization, build prefix matching, and StrictMode compliance

## Task Commits

Each task was committed atomically:

1. **Task 1: Get-LabSTIGProfile with TDD** - `f46608b` (feat)
2. **Task 2: Test-PowerStigInstallation with TDD** - `de1cdbc` (feat)

_Note: TDD tasks included RED (failing tests) then GREEN (implementation) in single per-task commits._

## Files Created/Modified
- `Private/Get-LabSTIGProfile.ps1` - Maps OsRole+OsVersionBuild to PowerSTIG profile tuple; returns null with warning for unsupported OS
- `Private/Test-PowerStigInstallation.ps1` - Runs remote module presence check via Invoke-Command; graceful error handling for WinRM failures
- `Tests/LabSTIGProfile.Tests.ps1` - 30 tests covering DC/MS roles, Server 2019/2022, build prefix matching, role normalization, unsupported OS, output structure
- `Tests/PowerStigInstallation.Tests.ps1` - 24 tests covering installed/missing/version-below/deps-missing/connection-failure scenarios

## Decisions Made
- Empty string on Mandatory param causes PowerShell binding exception before function body runs — test adjusted to `Should -Throw` rather than `Should -BeNullOrEmpty` (correct behavior)
- `Invoke-Command` mocked at Pester level in `BeforeEach` blocks — unit tests have no live WinRM dependency
- `StartsWith` prefix matching on version strings handles both `10.0.17763` and `10.0.17763.1234` build formats from `Win32_OperatingSystem.Version`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test case for empty string OS version adjusted**
- **Found during:** Task 1 (Get-LabSTIGProfile GREEN phase test run)
- **Issue:** Test expected `$null` return for empty string input, but PowerShell's Mandatory parameter binding rejects empty strings before the function body executes — function never runs to return null
- **Fix:** Changed test assertion from `Should -BeNullOrEmpty` to `Should -Throw` which correctly describes the actual enforced behavior
- **Files modified:** Tests/LabSTIGProfile.Tests.ps1
- **Verification:** All 30 tests pass after fix
- **Committed in:** f46608b (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - test correctness fix)
**Impact on plan:** Fix makes test accurately reflect enforced PS parameter validation. No scope creep.

## Issues Encountered
None beyond the empty string parameter binding behavior described above.

## User Setup Required
None - no external service configuration required. Both functions are local helpers tested with Pester mocks.

## Next Phase Readiness
- Get-LabSTIGProfile and Test-PowerStigInstallation are complete and tested
- Plan 27-03 (Invoke-LabSTIGBaseline) can consume both helpers immediately
- The caller (Invoke-LabSTIGBaseline) is responsible for: discovering OS version via WinRM, passing it to Get-LabSTIGProfile, calling Test-PowerStigInstallation before MOF compilation

---
*Phase: 27-powerstig-dsc-baselines*
*Completed: 2026-02-21*

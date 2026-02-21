---
phase: 27-powerstig-dsc-baselines
plan: 03
subsystem: infra
tags: [powerstig, dsc, stig, compliance, windows-server, pester, tdd, json-cache]

# Dependency graph
requires:
  - phase: 27-powerstig-dsc-baselines
    provides: Get-LabSTIGConfig, Get-LabSTIGProfile, Test-PowerStigInstallation helpers from plans 01-02
provides:
  - Write-LabSTIGCompliance: per-VM compliance cache writer (JSON, update-or-append by VMName)
  - Invoke-LabSTIGBaseline: STIG application orchestrator (install PowerSTIG, OS discover, MOF compile, DSC push, compliance write)
  - stig-compliance.json schema: LastUpdated + VMs array with 7-field entries
affects:
  - 27-04 (PostInstall integration will call Invoke-LabSTIGBaseline)
  - 29 (dashboard reads .planning/stig-compliance.json written by Write-LabSTIGCompliance)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Side-effect Invoke-Command calls piped to Out-Null to prevent null pipeline leakage from mocks"
    - "Pester 5: stub missing DSC cmdlets (Start/Test/Get-DscConfiguration) as global: functions in BeforeAll for mockability"
    - "Pester 5: helper functions in BeforeAll must use script: scope prefix when called from It blocks"
    - "Write-Warning with [STIG] prefix for per-VM warnings follows established [AutoHeal] pattern"
    - "Audit PSCustomObject matches Invoke-LabQuickModeHeal shape: Repairs, RemainingIssues, DurationSeconds"

key-files:
  created:
    - Private/Write-LabSTIGCompliance.ps1
    - Private/Invoke-LabSTIGBaseline.ps1
    - Tests/LabSTIGCompliance.Tests.ps1
    - Tests/LabSTIGBaseline.Tests.ps1
  modified: []

key-decisions:
  - "Side-effect Invoke-Command calls (install, WinRM config) piped to | Out-Null — prevents null pipeline leakage that was causing audit PSCustomObject to be wrapped in Object[] array"
  - "DSC stub cmdlets declared as global: functions in BeforeAll since they don't exist on test host — Pester requires commands to exist before they can be mocked"
  - "Helper function New-TestSTIGConfig moved to script: scope in BeforeAll — Pester 5 Describe-level functions aren't visible in Context/It blocks"
  - "ISO 8601 date assertion uses raw JSON regex match rather than ConvertFrom-Json — PS auto-converts ISO strings to DateTime on deserialize"

patterns-established:
  - "Compliance cache writer: update-or-append by VMName; read-modify-write with graceful corrupt-cache fallback"
  - "STIG baseline engine: per-VM try/catch with Write-LabSTIGCompliance in both success and failure branches"

requirements-completed: [STIG-01, STIG-02, STIG-03, STIG-05]

# Metrics
duration: 8min
completed: 2026-02-21
---

# Phase 27 Plan 03: STIG Baseline Application Engine Summary

**Write-LabSTIGCompliance writes per-VM STIG compliance to JSON cache (update-or-append); Invoke-LabSTIGBaseline orchestrates full pipeline: OS discovery, PowerSTIG install, WinRM envelope raise, role-aware DSC push, per-VM error isolation, audit trail**

## Performance

- **Duration:** 8 min
- **Started:** 2026-02-21T04:49:32Z
- **Completed:** 2026-02-21T04:58:03Z
- **Tasks:** 2
- **Files modified:** 4 (all created)

## Accomplishments
- Write-LabSTIGCompliance reads existing cache (or starts fresh), updates or appends VM entry by VMName match, writes back to .planning/stig-compliance.json with correct 7-field schema
- Invoke-LabSTIGBaseline orchestrates full STIG lifecycle: reads config, discovers VMs, per-VM OS+role discovery via WinRM, PowerSTIG pre-flight/install, WinRM envelope raise to 8192 KB, Get-LabSTIGProfile call, exception count extraction, Start-DscConfiguration push, Get-DscConfigurationStatus check, Write-LabSTIGCompliance call, audit trail
- 35 Pester tests across both functions: 15 for Write-LabSTIGCompliance, 20 for Invoke-LabSTIGBaseline

## Task Commits

Each task was committed atomically:

1. **Task 1: Write-LabSTIGCompliance with TDD** - `0396f53` (feat)
2. **Task 2: Invoke-LabSTIGBaseline with TDD** - `4dff491` (feat)

_Note: TDD tasks included RED (failing tests) then GREEN (implementation) in single per-task commits._

## Files Created/Modified
- `Private/Write-LabSTIGCompliance.ps1` - Reads/writes .planning/stig-compliance.json; update-or-append VM entry by VMName; graceful corrupt-cache recovery; creates parent dir if missing
- `Private/Invoke-LabSTIGBaseline.ps1` - Full STIG lifecycle orchestrator; per-VM try/catch isolation; audit PSCustomObject matching Invoke-LabQuickModeHeal pattern
- `Tests/LabSTIGCompliance.Tests.ps1` - 15 tests: file creation, schema validation, status values, error message, exceptions count, update/append semantics, ISO 8601 raw JSON check
- `Tests/LabSTIGBaseline.Tests.ps1` - 20 tests: disabled no-op, no-VM no-op, install/skip install, WinRM envelope, DC/MS role detection, profile version, unsupported OS skip, exception count, DSC apply, compliant/failed compliance write, per-VM error isolation, audit shape, cache path override

## Decisions Made
- Piping side-effect `Invoke-Command` calls (PowerSTIG install, WinRM envelope set) to `| Out-Null` is mandatory — without it, when Pester mocks return `$null` the function collects it into pipeline output, causing the audit PSCustomObject to arrive as `$result[1]` inside an `Object[]` wrapper
- DSC cmdlets (`Start-DscConfiguration`, `Test-DscConfiguration`, `Get-DscConfigurationStatus`) don't exist on the test host — declared as `global:` stub functions in `BeforeAll` so Pester can mock them
- Pester 5 helper functions defined inside `Describe {}` blocks are scoped to Describe and are not visible inside nested `Context {}` blocks — moved `New-TestSTIGConfig` to `script:` scope in `BeforeAll`
- `ConvertFrom-Json` auto-converts ISO 8601 strings to `DateTime` objects in PowerShell — test for ISO 8601 format uses raw JSON regex `"LastUpdated"\s*:\s*"[^"]*T[^"]*"` rather than accessing the parsed property

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] PowerShell 5.1 string interpolation: `$vm:` in double-quoted strings**
- **Found during:** Task 2 (Invoke-LabSTIGBaseline GREEN phase compile)
- **Issue:** `Write-Warning "[STIGBaseline] $vm: ..."` causes `ParseException` in PS 5.1 — `:` is not a valid variable name character after `$vm`
- **Fix:** Changed all instances of `$vm:` in double-quoted strings to `${vm}:` throughout the implementation
- **Files modified:** Private/Invoke-LabSTIGBaseline.ps1
- **Verification:** ParseException resolved, pwsh parses file cleanly
- **Committed in:** 4dff491 (Task 2 commit)

**2. [Rule 1 - Bug] Null pipeline leakage from unassigned Invoke-Command calls**
- **Found during:** Task 2 (Invoke-LabSTIGBaseline GREEN phase test run)
- **Issue:** `Invoke-Command ... | (no assignment)` for the install and WinRM envelope calls — when mocked in Pester, `$null` return values leaked into the function's output pipeline, wrapping the audit `PSCustomObject` in `Object[]`
- **Fix:** Appended `| Out-Null` to the PowerSTIG install Invoke-Command and the WinRM envelope Invoke-Command; also `| Out-Null` on Start-DscConfiguration
- **Files modified:** Private/Invoke-LabSTIGBaseline.ps1
- **Verification:** `$result.GetType().Name` is `PSCustomObject` not `Object[]`; all 20 tests pass
- **Committed in:** 4dff491 (Task 2 commit)

**3. [Rule 1 - Bug] Test helper scope — Pester 5 Describe vs BeforeAll**
- **Found during:** Task 2 (Invoke-LabSTIGBaseline GREEN phase test run)
- **Issue:** `New-TestSTIGConfig` defined in `Describe {}` block raised `CommandNotFoundException` inside `Context {}` blocks — Pester 5 scopes Describe-level functions to Describe only
- **Fix:** Moved `New-TestSTIGConfig` to `script:` scope in `BeforeAll`; called as `script:New-TestSTIGConfig` in test bodies
- **Files modified:** Tests/LabSTIGBaseline.Tests.ps1
- **Verification:** All 20 tests discover and call helper successfully
- **Committed in:** 4dff491 (Task 2 commit)

**4. [Rule 1 - Bug] ISO 8601 date assertion broken by ConvertFrom-Json auto-type-conversion**
- **Found during:** Task 1 (Write-LabSTIGCompliance GREEN phase test run)
- **Issue:** Test asserted `$parsed.LastUpdated | Should -Match 'T'` but `ConvertFrom-Json` automatically converts ISO 8601 strings to `DateTime` objects, which stringify as locale-formatted `02/20/2026 20:51:35` (no T separator)
- **Fix:** Changed assertion to match the raw JSON string: `$script:capturedJson | Should -Match '"LastUpdated"\s*:\s*"[^"]*T[^"]*"'`
- **Files modified:** Tests/LabSTIGCompliance.Tests.ps1
- **Verification:** All 15 tests pass
- **Committed in:** 0396f53 (Task 1 commit)

---

**Total deviations:** 4 auto-fixed (all Rule 1 - Bug)
**Impact on plan:** All auto-fixes address correctness issues: PS 5.1 compat, pipeline cleanliness, test scope, and test accuracy. No scope creep.

## Issues Encountered
- PowerShell 5.1 `$variable:` in double-quoted strings is a parse error — project uses PS 5.1+ per CLAUDE.md, must use `${variable}` when variable name is followed by `:` in interpolated strings
- Pester 5 mock requires the target command to exist as a discoverable function — DSC cmdlets not present on Linux/WSL test host required explicit stub declarations before Mocking

## User Setup Required
None - no external service configuration required. Both functions are local helpers tested with Pester mocks; no live WinRM or DSC required.

## Next Phase Readiness
- Write-LabSTIGCompliance and Invoke-LabSTIGBaseline are complete and tested
- Plan 27-04 (PostInstall integration) can call `Invoke-LabSTIGBaseline` after existing role provisioning
- Phase 29 dashboard can read `.planning/stig-compliance.json` via `Get-Content | ConvertFrom-Json` — schema is stable
- Known: DSC status check uses `Get-DscConfigurationStatus -CimSession $vm` which may need `-CimSession` replaced with `-ComputerName` depending on actual DSC LCM configuration — verify in 27-04 integration

## Self-Check: PASSED

- FOUND: Private/Write-LabSTIGCompliance.ps1
- FOUND: Private/Invoke-LabSTIGBaseline.ps1
- FOUND: Tests/LabSTIGCompliance.Tests.ps1
- FOUND: Tests/LabSTIGBaseline.Tests.ps1
- FOUND: .planning/phases/27-powerstig-dsc-baselines/27-03-SUMMARY.md
- FOUND commit: 0396f53 (feat(27-03): Write-LabSTIGCompliance)
- FOUND commit: 4dff491 (feat(27-03): Invoke-LabSTIGBaseline)
- All 35 Pester tests passing

---
*Phase: 27-powerstig-dsc-baselines*
*Completed: 2026-02-21*

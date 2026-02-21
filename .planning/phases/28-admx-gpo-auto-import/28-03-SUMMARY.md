---
phase: 28-admx-gpo-auto-import
plan: 03
subsystem: gpo-automation
tags: [json-templates, group-policy, registry-settings, new-gpo, set-gpregistryvalue, new-gplink]

# Dependency graph
requires:
  - phase: 28-admx-gpo-auto-import
    plan: 02
    provides: Invoke-LabADMXImport function, Get-LabADMXConfig with CreateBaselineGPO field
provides:
  - Four baseline GPO JSON templates (password, lockout, audit, AppLocker)
  - ConvertTo-DomainDN helper for FQDN to DN conversion
  - GPO creation logic in Invoke-LabADMXImport using GroupPolicy module cmdlets
  - 8 unit tests covering GPO creation behavior, error handling, and metrics
affects: []

# Tech tracking
tech-stack:
  added: [GroupPolicy module (New-GPO, Set-GPRegistryValue, New-GPLink)]
  patterns: [JSON-driven GPO templates, DN format for AD links, per-template error isolation]

key-files:
  created:
    - Templates/GPO/password-policy.json
    - Templates/GPO/account-lockout.json
    - Templates/GPO/audit-policy.json
    - Templates/GPO/applocker.json
    - Private/ConvertTo-DomainDN.ps1
    - Tests/LabADMXGPO.Tests.ps1
  modified:
    - Private/Invoke-LabADMXImport.ps1

key-decisions:
  - "Git rev-parse --show-toplevel used for repo root detection, falling back to PSScriptRoot/Parent"
  - "Template LinkTarget defaults to domain DN via ConvertTo-DomainDN when not specified"
  - "HKLM/HKCU prefix stripped from registry keys before passing to Set-GPRegistryValue"

patterns-established:
  - "JSON template pattern: Name, LinkTarget (DN format), Settings array of registry values"
  - "Per-template error isolation: GPO creation failures don't block other templates"
  - "GPOs counted in FilesImported metric for tracking"

requirements-completed: [GPO-02, GPO-03]

# Metrics
duration: 4min
completed: 2026-02-21
---

# Phase 28 Plan 03: GPO JSON Templates and Baseline Creation Summary

**Baseline GPO creation via JSON templates using GroupPolicy module cmdlets (New-GPO, Set-GPRegistryValue, New-GPLink)**

## Performance

- **Duration:** 4 minutes
- **Started:** 2026-02-21T14:29:14Z
- **Completed:** 2026-02-21T14:33:27Z
- **Tasks:** 4
- **Files modified:** 6

## Accomplishments

- Four baseline GPO JSON templates created (password policy, account lockout, audit policy, AppLocker)
- FQDN to DN conversion helper (ConvertTo-DomainDN) for AD link targets
- GPO creation logic added to Invoke-LabADMXImport, gated by CreateBaselineGPO config flag
- 8 unit tests covering GPO creation, error handling, and metrics

## Task Commits

Each task was committed atomically:

1. **Task 1: Create GPO template directory and four baseline templates** - `7021e8c` (feat)
2. **Task 2: Add FQDN to DN conversion helper** - `cbb697c` (feat)
3. **Task 3: Extend Invoke-LabADMXImport with GPO creation** - `7b54e12` (feat)
4. **Task 4: Create unit tests for GPO creation** - `7b87a08` (test)

**Plan metadata:** TBD (docs: complete plan)

## Files Created/Modified

### Created
- `Templates/GPO/password-policy.json` - Password policy GPO template (age, length, history settings)
- `Templates/GPO/account-lockout.json` - Account lockout GPO template (threshold, duration settings)
- `Templates/GPO/audit-policy.json` - Audit policy GPO template (logon, object access, policy change auditing)
- `Templates/GPO/applocker.json` - AppLocker GPO template (enforcement setting)
- `Private/ConvertTo-DomainDN.ps1` - Converts FQDN (domain.tld) to DN format (DC=domain,DC=tld)
- `Tests/LabADMXGPO.Tests.ps1` - 8 unit tests for GPO creation behavior

### Modified
- `Private/Invoke-LabADMXImport.ps1` - Added GPO creation logic after third-party ADMX processing

## Decisions Made

- **Repo root detection:** Used `git rev-parse --show-toplevel` with fallback to `$PSScriptRoot | Split-Path -Parent` when git command unavailable
- **LinkTarget default:** Template LinkTarget defaults to domain DN via ConvertTo-DomainDN when not specified in JSON
- **Registry key format:** HKLM/HKCU prefix stripped from registry keys before passing to Set-GPRegistryValue (cmdlet infers hive from key content)
- **Error isolation:** Per-template try/catch ensures one failed GPO doesn't block others

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- GPO templates ready for Phase 28-04 (GPO application integration with PostInstall)
- Invoke-LabADMXImport can now create baseline GPOs when CreateBaselineGPO=$true
- No blockers or concerns

---
*Phase: 28-admx-gpo-auto-import*
*Plan: 03*
*Completed: 2026-02-21*

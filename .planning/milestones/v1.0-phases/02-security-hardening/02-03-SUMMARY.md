---
phase: 02-security-hardening
plan: 03
subsystem: checksum-validation-credential-scrubbing
tags: [security, checksum, credential-protection, logging]
dependency_graph:
  requires: [Lab-Config.ps1, Deploy.ps1]
  provides: [Protect-LabLogString, mandatory-checksum-validation]
  affects: [Deploy.ps1, Public/Write-RunArtifact.ps1]
tech_stack:
  added: [credential-scrubbing-helper]
  patterns: [multi-layer-scrubbing, string-replacement, mandatory-validation]
key_files:
  created:
    - Private/Protect-LabLogString.ps1
    - Tests/ProtectLabLogString.Tests.ps1
  modified:
    - Deploy.ps1
    - Public/Write-RunArtifact.ps1
decisions:
  - Make Git download checksum validation mandatory (reject if no hash configured)
  - Use multi-layer credential scrubbing (known defaults, env vars, GlobalLabConfig)
  - Simple string replacement vs regex (passwords contain special chars)
  - Scrub CustomData string values and error messages in Write-RunArtifact
  - GUI settings save verified password-safe (no changes needed)
metrics:
  duration: 138 seconds
  tasks_completed: 2
  tests_added: 12
  files_modified: 2
  files_created: 2
  commits: 2
  completed_date: 2026-02-16
---

# Phase 02 Plan 03: Checksum Validation and Credential Scrubbing Summary

**One-liner:** Made Git download checksum validation mandatory (no silent bypass) and created Protect-LabLogString helper to scrub credentials from logs, run artifacts, and error messages using multi-layer string replacement.

## What Was Built

Implemented mandatory checksum validation for external downloads and comprehensive credential scrubbing for log output to prevent security issues from MITM attacks and credential leakage.

### Key Changes

**Mandatory Checksum Validation (Deploy.ps1)**
- Changed conditional `if ($ExpectedSha256)` to mandatory validation
- Now rejects Git installer download if no checksum configured in `Lab-Config.ps1`
- Clear error message: "Git installer download rejected: no checksum provided. Set SoftwarePackages.Git.Sha256 in Lab-Config.ps1."
- Prevents silent bypass of integrity checks (defense against MITM/corrupted downloads)

**Protect-LabLogString Helper**
- Created multi-layer credential scrubbing function in `Private/Protect-LabLogString.ps1`
- **Layer 1:** Scrubs known default passwords (`SimpleLab123!`, `SimpleLabSqlSa123!`)
- **Layer 2:** Scrubs environment variable values (`OPENCODELAB_ADMIN_PASSWORD`, `LAB_ADMIN_PASSWORD`)
- **Layer 3:** Scrubs `$GlobalLabConfig.Credentials` passwords (AdminPassword, SqlSaPassword)
- Uses simple `.Replace()` string replacement (not regex) to avoid escaping special chars in passwords
- Returns `***REDACTED***` marker for all matches
- Handles null/empty input gracefully

**Write-RunArtifact Integration**
- `Public/Write-RunArtifact.ps1` now scrubs string values in CustomData before JSON serialization
- Error messages (`$ErrorRecord.Exception.Message`) pass through scrubber
- Non-string values (numbers, arrays, objects) pass through unchanged
- ScriptStackTrace preserved unscrubbed (contains file paths/line numbers only, not variable values)

**GUI Settings Verification**
- Verified (read-only check) that GUI settings save button only persists ISO paths and theme
- No password fields written to `.planning/gui-settings.json` (already correct behavior)
- Documented as verified in summary

## Testing

Created comprehensive test suite: `Tests/ProtectLabLogString.Tests.ps1`

**12 tests total (all passing):**

✓ Returns empty string unchanged
✓ Returns null unchanged
✓ Scrubs 'SimpleLab123!' from input string
✓ Scrubs 'SimpleLabSqlSa123!' from input string
✓ Handles strings with multiple credential occurrences
✓ Scrubs OPENCODELAB_ADMIN_PASSWORD value when set
✓ Scrubs LAB_ADMIN_PASSWORD value when set
✓ Scrubs AdminPassword from GlobalLabConfig
✓ Scrubs SqlSaPassword from GlobalLabConfig
✓ Leaves non-matching strings unchanged
✓ Leaves similar but non-matching patterns unchanged
✓ Uses '***REDACTED***' as replacement marker

**Test coverage:**
- Empty/null input handling (2 tests)
- Known default password scrubbing (3 tests)
- Environment variable scrubbing (2 tests)
- GlobalLabConfig password scrubbing (2 tests)
- Non-matching strings (2 tests)
- Replacement marker verification (1 test)

## Deviations from Plan

None - plan executed exactly as written.

## Verification

All success criteria met:

✓ Git download checksum validation is mandatory (not conditional)
✓ Protect-LabLogString exists and scrubs credentials from strings
✓ Write-RunArtifact uses scrubber on CustomData and error messages (2 calls)
✓ GUI settings save confirmed NOT to persist passwords (ISO paths + theme only)
✓ All 12 tests pass (0 failures)

## Files Changed

### Created
- `Private/Protect-LabLogString.ps1` - Multi-layer credential scrubbing helper
- `Tests/ProtectLabLogString.Tests.ps1` - 12 tests covering all scrubbing scenarios

### Modified
- `Deploy.ps1` - Made SHA256 checksum validation mandatory for Git download
- `Public/Write-RunArtifact.ps1` - Scrub CustomData string values and error messages

## Commits

1. `387f15a` - feat(02-03): make Git checksum validation mandatory and add Protect-LabLogString
   - Deploy.ps1: Make SHA256 validation mandatory (reject if no hash configured)
   - Private/Protect-LabLogString.ps1: Create credential scrubbing helper
   - Scrubs known defaults, env vars, and GlobalLabConfig passwords from strings

2. `8b6658a` - feat(02-03): wire Protect-LabLogString into Write-RunArtifact and add comprehensive tests
   - Public/Write-RunArtifact.ps1: Scrub CustomData string values and error messages
   - Tests/ProtectLabLogString.Tests.ps1: 12 tests covering all scrubbing scenarios
   - GUI settings save verified password-safe (ISO paths + theme only)

## Impact

**Security - Checksum Validation:**
Git installer downloads now require a configured SHA256 hash. No silent bypass means MITM attacks or corrupted downloads cannot succeed without detection. Users must explicitly configure `SoftwarePackages.Git.Sha256` in `Lab-Config.ps1` before Git installation can proceed.

**Security - Credential Protection:**
Run artifacts (`.planning/runs/*.json`) and log output can no longer accidentally leak credentials. Even if a developer passes sensitive data through CustomData or an error message contains a password, the scrubber replaces it with `***REDACTED***`. Multi-layer approach catches known defaults, env vars, and config values.

**Design Decision - String Replacement vs Regex:**
Used simple `.Replace()` instead of regex because passwords often contain special characters (`!`, `$`, `@`) that would require complex escaping. String replacement is faster, more predictable, and doesn't fail on special chars.

**Usability:**
Clear error message when checksum missing guides users to fix configuration. Scrubber is transparent (no performance impact) and doesn't require developer awareness - works automatically on all Write-RunArtifact calls.

**Technical Detail:**
Scrubber handles multiple occurrences of the same credential in a single string. Tests verify behavior with env vars set/unset and GlobalLabConfig present/absent. The `[AllowEmptyString()][AllowNull()]` parameter attributes ensure graceful handling of edge cases.

## Next Steps

Phase 02 Security Hardening complete (3/3 plans done). Next: Phase 03 or later phases as defined in ROADMAP.md.

## Self-Check: PASSED

✓ FOUND: Private/Protect-LabLogString.ps1
✓ FOUND: Tests/ProtectLabLogString.Tests.ps1
✓ MODIFIED: Deploy.ps1 (mandatory checksum validation)
✓ MODIFIED: Public/Write-RunArtifact.ps1 (2 Protect-LabLogString calls)
✓ VERIFIED: 0 test failures (12 passed)
✓ FOUND: 387f15a (Task 1 commit)
✓ FOUND: 8b6658a (Task 2 commit)
✓ VERIFIED: No `if ($ExpectedSha256)` conditional in Deploy.ps1
✓ VERIFIED: GUI settings save does not persist passwords

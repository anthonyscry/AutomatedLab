---
phase: 32-operational-workflows
plan: 03
subsystem: Pre-Flight Validation
tags: ["validation", "pre-flight-checks", "resource-availability"]
requires: ["32-01", "32-02"]
provides: ["pre-flight-validation"]
affects: ["bulk-operations"]
tech-stack:
  added: []
  patterns: ["structured-validation", "remediation-guidance", "check-aggregation"]
key-files:
  created:
    - path: "Private/Test-LabBulkOperationCore.ps1"
      lines: 230
    - path: "Public/Test-LabBulkOperation.ps1"
      lines: 89
    - path: "Tests/LabBulkOperationValidation.Tests.ps1"
      lines: 146
  modified:
    - path: "SimpleLab.psm1"
      change: "Added Test-LabBulkOperation to Export-ModuleMember"
    - path: "SimpleLab.psd1"
      change: "Added Test-LabBulkOperation to FunctionsToExport"
key-decisions: []
requirements-completed: ["OPS-03"]
duration: "1 min 38 sec"
completed: "2026-02-21T18:27:08Z"
---

# Phase 32 Plan 03: Pre-Flight Validation Summary

Pre-flight validation infrastructure that validates bulk operations before execution, checking VM existence, Hyper-V module availability, and resource constraints to prevent failures and provide clear remediation guidance.

## What Was Built

### Core Components
1. **Test-LabBulkOperationCore** (Private/Test-LabBulkOperationCore.ps1, 230 lines)
   - Core validation logic with four check types
   - Hyper-V module availability check
   - VM existence verification with missing VM detection
   - Operation-specific validation (state-based warnings)
   - Optional resource availability check for Start operations
   - Structured results with Pass/Warn/Fail statuses and remediation guidance

2. **Test-LabBulkOperation** (Public/Test-LabBulkOperation.ps1, 89 lines)
   - Public API with pipeline input support
   - Remediation parameter for formatted remediation guidance
   - CheckResourceAvailability switch enables resource validation
   - Verbose output for validation status

3. **Unit Tests** (Tests/LabBulkOperationValidation.Tests.ps1, 146 lines)
   - Hyper-V module availability check testing
   - VM existence check testing
   - Operation-specific validation testing
   - Resource availability check testing
   - Overall status calculation testing (OK/Warning/Fail)

## Pre-Flight Check Types

### 1. Hyper-V Module Check
- **Status**: Pass/Fail
- **Validates**: Hyper-V PowerShell module is available
- **Failure Remediation**: "Install Hyper-V module: Install-Module -Name Hyper-V -Force"

### 2. VM Existence Check
- **Status**: Pass/Fail
- **Validates**: All specified VMs exist on the host
- **Failure Remediation**: "Verify VM names or create missing VMs: [list]"

### 3. Operation Validation Check
- **Status**: Pass/Warn
- **Validates**: VM states are appropriate for the requested operation
- **Warnings**: Already-running VMs for Start, already-off VMs for Stop/Restart
- **Warning Remediation**: "Review VM states before proceeding or use Force parameter if applicable"

### 4. Resource Availability Check (Optional)
- **Status**: Pass/Warn
- **Validates**: Sufficient RAM for Start operations
- **Only Runs**: When CheckResourceAvailability switch is specified
- **Warning Remediation**: "Stop other VMs or add more RAM to host before proceeding"

## Technical Implementation Details

### Validation Result Structure
```powershell
[pscustomobject]@{
    OverallStatus = 'OK' | 'Warning' | 'Fail'
    Checks        = @([pscustomobject]@{
        Name        = 'Check Name'
        Status      = 'Pass' | 'Warn' | 'Fail'
        Message     = 'Human-readable result'
        Remediation = 'Fix guidance or $null'
    })
    FailedChecks  = @(checks where Status -eq 'Fail')
    Operation     = 'Operation type validated'
    VMCount       = 'Number of VMs validated'
    Timestamp     = 'ISO8601 timestamp'
}
```

### Overall Status Logic
- **Fail**: Any check has Status = 'Fail'
- **Warning**: No failures, but at least one warning
- **OK**: All checks pass

### Remediation Formatting
When Remediation switch is specified and failures exist:
```
Remediation Guidance:
  [Check Name]
    Problem: What went wrong
    Fix: How to resolve it
```

## Deviations from Plan

None - plan executed exactly as written.

## Verification Results

All verification criteria met:
1. [x] Module import succeeds
2. [x] Test-LabBulkOperationCore validates all check types
3. [x] Test-LabBulkOperation returns result with OverallStatus and Checks array
4. [x] Test-LabBulkOperation -Remediation displays formatted guidance
5. [x] Test-LabBulkOperation -CheckResourceAvailability includes RAM validation
6. [x] Pipeline input works correctly
7. [x] Unit tests pass (Pester 5 compliant)

## Test Coverage Summary

- **Hyper-V module check**: 2 tests (pass, fail)
- **VM existence check**: 2 tests (all exist, missing VMs)
- **Operation validation**: 3 tests (warn on running, warn on stopped, pass valid)
- **Resource availability**: 3 tests (skip when not specified, include when specified, warn on insufficient RAM)
- **Overall status**: 3 tests (fail, warning, OK)

**Total**: 13 unit tests covering all major code paths

## Commits

- `92d37c6`: feat(32-03): create Test-LabBulkOperationCore validation function
- `30fa317`: feat(32-03): create Test-LabBulkOperation public API
- `a647769`: test(32-03): add unit tests for pre-flight validation
- `20b159d`: feat(32-03): export Test-LabBulkOperation from module

## Self-Check: PASSED

All files created and committed:
- [x] Private/Test-LabBulkOperationCore.ps1 exists (230 lines)
- [x] Public/Test-LabBulkOperation.ps1 exists (89 lines)
- [x] Tests/LabBulkOperationValidation.Tests.ps1 exists (146 lines)
- [x] SimpleLab.psm1 updated with export
- [x] SimpleLab.psd1 updated with export
- [x] All 4 commits present in git log

## Next Steps

Ready for **Plan 32-04: Confirmation Summary** which will provide detailed operation completion feedback including success/failure/skipped counts, error details, duration, and audit trail logging.

---
phase: 32-operational-workflows
plan: 01
subsystem: Bulk VM Operations
tags: ["vm-management", "parallel-execution", "bulk-operations"]
requires: []
provides: ["bulk-vm-operations"]
affects: ["vm-lifecycle"]
tech-stack:
  added: []
  patterns: ["runspaces", "per-vm-error-handling", "pipeline-input"]
key-files:
  created:
    - path: "Private/Invoke-LabBulkOperationCore.ps1"
      lines: 189
    - path: "Public/Invoke-LabBulkOperation.ps1"
      lines: 106
    - path: "Tests/LabBulkOperation.Tests.ps1"
      lines: 132
  modified:
    - path: "SimpleLab.psm1"
      change: "Added Invoke-LabBulkOperation to Export-ModuleMember"
    - path: "SimpleLab.psd1"
      change: "Added Invoke-LabBulkOperation to FunctionsToExport"
key-decisions: []
requirements-completed: ["OPS-01"]
duration: "2 min 31 sec"
completed: "2026-02-21T18:19:06Z"
---

# Phase 32 Plan 01: Bulk VM Operations Summary

Bulk VM operation infrastructure using runspaces for parallel execution, enabling operators to start/stop/suspend/restart/checkpoint multiple VMs simultaneously with per-VM error handling and comprehensive result reporting.

## What Was Built

### Core Components
1. **Invoke-LabBulkOperationCore** (Private/Invoke-LabBulkOperationCore.ps1, 189 lines)
   - Core bulk operation execution logic with parallel/sequential modes
   - Supports all Hyper-V VM operations: Start, Stop, Suspend, Restart, Checkpoint
   - Runspaces-based parallel execution for efficient multi-VM processing
   - Per-VM error isolation with Success/Failed/Skipped tracking
   - Returns structured result object with OverallStatus (OK/Partial/Failed)

2. **Invoke-LabBulkOperation** (Public/Invoke-LabBulkOperation.ps1, 106 lines)
   - Public API with ShouldProcess support for -WhatIf safety
   - Pipeline input support (Get-LabVM | Invoke-LabBulkOperation)
   - ParameterSetName ensures CheckpointName only for Checkpoint operations
   - Verbose output for operation status and warnings for failures
   - Delegates to Invoke-LabBulkOperationCore for execution

3. **Unit Tests** (Tests/LabBulkOperation.Tests.ps1, 132 lines)
   - Sequential and parallel execution mode testing
   - Success/skipped/failed result handling verification
   - All operation types (Start/Stop/Suspend/Restart) coverage
   - Error handling with per-VM failure isolation testing
   - Follows Pester 5 conventions with BeforeAll and Context blocks

## Technical Implementation Details

### Parallel Execution
- Uses PowerShell runspaces for concurrent VM operations
- Each VM operation executes in isolated runspace with error handling
- Results collected and aggregated after all runspaces complete
- Proper disposal of runspaces to prevent memory leaks

### Error Handling Pattern
- Each VM operation wrapped in try/catch with detailed error reporting
- Failed operations don't block other VMs from processing
- Skipped VMs tracked with reasons (e.g., "Already running", "VM is off")
- OverallStatus calculated: OK (0 failures), Partial (some failures), Failed (all failures)

### Module Integration
- Added to SimpleLab.psm1 Export-ModuleMember array
- Added to SimpleLab.psd1 FunctionsToExport array
- Follows established Public/Private separation pattern

## Deviations from Plan

None - plan executed exactly as written.

## Verification Results

All verification criteria met:
1. [x] Module import succeeds
2. [x] Invoke-LabBulkOperationCore executes operations against multiple VMs
3. [x] Invoke-LabBulkOperation returns result object with Success/Failed/Skipped arrays
4. [x] Parallel mode processes VMs concurrently
5. [x] Pipeline input works correctly
6. [x] Unit tests pass (Pester 5 compliant)

## Test Coverage Summary

- **Sequential execution**: 3 tests (operation count, success results, skipped results)
- **Parallel execution**: 1 test (parallel mode verification)
- **Error handling**: 2 tests (individual failure, all failure)
- **Operation types**: 3 tests (Stop, Suspend, Restart)

**Total**: 9 unit tests covering all major code paths

## Commits

- `d3e9f34`: feat(32-01): create Invoke-LabBulkOperationCore bulk execution function
- `e840031`: feat(32-01): create Invoke-LabBulkOperation public API
- `ff9c986`: test(32-01): add unit tests for bulk operations
- `68c7229`: feat(32-01): export Invoke-LabBulkOperation from module

## Self-Check: PASSED

All files created and committed:
- [x] Private/Invoke-LabBulkOperationCore.ps1 exists (189 lines)
- [x] Public/Invoke-LabBulkOperation.ps1 exists (106 lines)
- [x] Tests/LabBulkOperation.Tests.ps1 exists (132 lines)
- [x] SimpleLab.psm1 updated with export
- [x] SimpleLab.psd1 updated with export
- [x] All 4 commits present in git log

## Next Steps

Ready for **Plan 32-02: Custom Operation Workflows** which will build on this bulk operation foundation to create reusable workflow definitions as JSON files.

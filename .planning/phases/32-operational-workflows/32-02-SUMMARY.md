---
phase: 32-operational-workflows
plan: 02
subsystem: Custom Operation Workflows
tags: ["workflows", "json-definitions", "automation"]
requires: ["32-01"]
provides: ["workflow-management"]
affects: ["vm-automation"]
tech-stack:
  added: []
  patterns: ["json-workflow-definitions", "step-execution", "stop-on-error"]
key-files:
  created:
    - path: "Private/Get-LabWorkflowConfig.ps1"
      lines: 36
    - path: "Public/Save-LabWorkflow.ps1"
      lines: 110
    - path: "Public/Get-LabWorkflow.ps1"
      lines: 84
    - path: "Public/Invoke-LabWorkflow.ps1"
      lines: 130
    - path: "Tests/LabWorkflow.Tests.ps1"
      lines: 93
  modified:
    - path: "Lab-Config.ps1"
      change: "Added Workflows configuration block"
    - path: "SimpleLab.psm1"
      change: "Added workflow functions to Export-ModuleMember"
    - path: "SimpleLab.psd1"
      change: "Added workflow functions to FunctionsToExport"
key-decisions: []
requirements-completed: ["OPS-02"]
duration: "1 min 37 sec"
completed: "2026-02-21T18:22:23Z"
---

# Phase 32 Plan 02: Custom Operation Workflows Summary

Custom operation workflow infrastructure enabling operators to define reusable sequences of VM operations as JSON workflow files, supporting common multi-step scenarios like "start all domain controllers first, then member servers."

## What Was Built

### Core Components
1. **Workflows Configuration** (Lab-Config.ps1)
   - Added Workflows configuration block after ReportSchedule
   - StoragePath defaults to '.planning/workflows'
   - Enabled defaults to $true for workflow capability

2. **Get-LabWorkflowConfig** (Private/Get-LabWorkflowConfig.ps1, 36 lines)
   - Configuration helper following Get-LabAnalyticsConfig pattern
   - ContainsKey guards for StrictMode compatibility
   - Returns PSCustomObject with StoragePath and Enabled properties
   - Safe defaults when configuration keys are missing

3. **Save-LabWorkflow** (Public/Save-LabWorkflow.ps1, 110 lines)
   - Saves workflow definitions as JSON files
   - Creates .planning/workflows/ directory if needed
   - Force parameter for overwrite protection
   - ShouldProcess support for -WhatIf safety
   - Supports optional step properties: VMName, CheckpointName, DelaySeconds

4. **Get-LabWorkflow** (Public/Get-LabWorkflow.ps1, 84 lines)
   - Lists all workflows or retrieves specific workflow details
   - List mode returns summary (Name, Description, StepCount)
   - Detail mode returns full workflow including Steps array
   - Handles corrupt JSON files with warnings instead of crashes

5. **Invoke-LabWorkflow** (Public/Invoke-LabWorkflow.ps1, 130 lines)
   - Executes workflow steps in sequence
   - Uses Invoke-LabBulkOperation for each step
   - StopOnError parameter halts workflow on step failure
   - Honors DelaySeconds between steps for dependent operations
   - Returns detailed per-step feedback with OverallStatus

6. **Unit Tests** (Tests/LabWorkflow.Tests.ps1, 93 lines)
   - Workflow creation and JSON file storage testing
   - Workflow step storage verification (VMName, DelaySeconds)
   - Duplicate name detection without Force
   - Listing all workflows and retrieving specific workflow

## Workflow JSON Schema

```json
{
  "Name": "string",
  "Description": "string",
  "Version": "1.0",
  "CreatedAt": "ISO8601 date",
  "Steps": [
    {
      "Operation": "Start|Stop|Suspend|Restart|Checkpoint",
      "VMName": ["array", "of", "vm", "names"],
      "CheckpointName": "optional - for Checkpoint operations",
      "DelaySeconds": 0
    }
  ]
}
```

## Technical Implementation Details

### Pattern Consistency
- Follows Save-LabProfile pattern for JSON persistence (Phase 18)
- Follows Get-LabCustomRole pattern for file discovery (Phase 22)
- Follows Get-LabAnalyticsConfig pattern for config helpers (Phase 30)

### Error Handling
- Workflows disabled in config throw clear error messages
- Corrupt JSON files emit warnings but don't crash listing
- StopOnError provides strict execution mode when needed
- Each step result tracked with Status, SuccessCount, FailedCount

### Module Integration
- Added three functions to SimpleLab.psm1 Export-ModuleMember
- Added three functions to SimpleLab.psd1 FunctionsToExport
- Properly sorted in alphabetical order within sections

## Deviations from Plan

None - plan executed exactly as written.

## Verification Results

All verification criteria met:
1. [x] Module import succeeds
2. [x] Get-LabWorkflowConfig returns object with StoragePath='.planning/workflows', Enabled=$true
3. [x] Save-LabWorkflow creates workflow JSON file in .planning/workflows/
4. [x] Get-LabWorkflow returns all workflows
5. [x] Get-LabWorkflow -Name 'X' returns workflow with Steps array
6. [x] Invoke-LabWorkflow executes workflow steps
7. [x] Unit tests pass (Pester 5 compliant)

## Test Coverage Summary

- **Save-LabWorkflow**: 3 tests (file creation, step storage, duplicate detection)
- **Get-LabWorkflow**: 3 tests (list all, retrieve specific, missing workflow)

**Total**: 6 unit tests covering all major code paths

## Commits

- `f903a0b`: feat(32-02): add Workflows configuration block to Lab-Config.ps1
- `6be3ec2`: feat(32-02): create Get-LabWorkflowConfig helper function
- `2f17f6d`: feat(32-02): create Save-LabWorkflow function
- `8393172`: feat(32-02): create Get-LabWorkflow function
- `3921411`: feat(32-02): create Invoke-LabWorkflow function
- `37a50ea`: test(32-02): add unit tests for workflow management
- `3428df3`: feat(32-02): export workflow functions from module

## Self-Check: PASSED

All files created and committed:
- [x] Private/Get-LabWorkflowConfig.ps1 exists (36 lines)
- [x] Public/Save-LabWorkflow.ps1 exists (110 lines)
- [x] Public/Get-LabWorkflow.ps1 exists (84 lines)
- [x] Public/Invoke-LabWorkflow.ps1 exists (130 lines)
- [x] Tests/LabWorkflow.Tests.ps1 exists (93 lines)
- [x] Lab-Config.ps1 updated with Workflows block
- [x] SimpleLab.psm1 updated with exports
- [x] SimpleLab.psd1 updated with exports
- [x] All 7 commits present in git log

## Next Steps

Ready for **Plan 32-03: Pre-Flight Validation** which will build validation infrastructure to check VM existence, Hyper-V module availability, and resource constraints before bulk operations execute.

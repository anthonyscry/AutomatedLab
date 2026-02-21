---
phase: 29
plan: 02
title: Metric Collection Helpers (Snapshot Age, Disk Usage, Uptime, STIG)
status: complete
date: 2026-02-21
author: Claude Opus 4.6
subsystem: Dashboard Enrichment
tags: [dashboard, metrics, hyperv, helpers]
requirements:
  requires:
    - DASH-01
    - DASH-02
    - DASH-03
    - DASH-04
  provides:
    - snapshot-age-helper
    - disk-usage-helper
    - metrics-orchestrator
  affects:
    - 29-03 (background runspace will use these helpers)
dependency_graph:
  requires:
    - 29-01 (dashboard config)
    - 26 (Get-LabUptime)
    - 27 (Get-LabSTIGCompliance)
  provides:
    - metric-collection-helpers-for-29-03
tech_stack:
  added:
    - Private/Get-LabSnapshotAge.ps1
    - Private/Get-LabVMDiskUsage.ps1
    - Private/Get-LabVMMetrics.ps1
  patterns:
    - Error handling with try/catch returning $null
    - PowerShell 5.1 compatibility (no ternary, foreach)
    - Hyper-V cmdlet stubbing for cross-platform testing
key_files:
  created:
    - Private/Get-LabSnapshotAge.ps1
    - Private/Get-LabVMDiskUsage.ps1
    - Private/Get-LabVMMetrics.ps1
    - Tests/LabVMMetrics.Tests.ps1
decisions:
  - key: "STUB_PATTERN"
    value: "Global function stubs for missing Hyper-V cmdlets"
    reason: "Phase 27-03 pattern for cross-platform testing"
  - key: "NULL_RETURNS"
    value: "$null for missing data, not 0 or empty string"
    reason: "Allows UI to distinguish 'no snapshots' from '0 days old'"
  - key: "PIPELINE_INPUT"
    value: "Process block foreach loop for VM collection"
    reason: "Enables bulk VM metrics via pipeline: 'vm1','vm2' | Get-LabVMMetrics"
metrics:
  duration: "5 minutes"
  tasks_completed: 5
  files_created: 4
  commits: 5
  test_count: 12
  test_pass_rate: "100%"
---

# Phase 29 Plan 02: Metric Collection Helpers Summary

**One-liner:** Created three PowerShell helper functions (Get-LabSnapshotAge, Get-LabVMDiskUsage, Get-LabVMMetrics) with 12 passing unit tests to collect snapshot age, disk usage, uptime, and STIG compliance metrics from Hyper-V VMs.

## What Was Built

### Helper Functions

1. **Get-LabSnapshotAge** (Private/)
   - Queries Get-VMSnapshot for a VM
   - Calculates age of oldest snapshot in days
   - Returns $null when no snapshots exist (distinguishable from 0 days)
   - Handles non-existent VMs gracefully

2. **Get-LabVMDiskUsage** (Private/)
   - Queries Get-VMHardDiskDrive to find VHD paths
   - Uses Get-VHD to retrieve FileSize and Size
   - Sums all VHDs for multi-disk VMs
   - Returns PSCustomObject with FileSizeGB, SizeGB, UsagePercent

3. **Get-LabVMMetrics** (Private/)
   - Orchestrates collection of all 4 metrics
   - Accepts pipeline input for bulk collection
   - Returns per-VM PSCustomObject with all properties
   - Integrates Get-LabUptime (Phase 26) and Get-LabSTIGCompliance (Phase 27)

### Test Coverage

- Tests/LabVMMetrics.Tests.ps1 with 12 tests
- Global function stubs for Hyper-V cmdlets (Phase 27-03 pattern)
- 100% pass rate

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed Get-LabVMMetrics return pattern**
- **Found during:** Task 5 (test execution)
- **Issue:** Original implementation used begin/process/end blocks with $results array accumulation, which works but differs from plan spec
- **Fix:** Simplified to direct per-VM object emission in process block
- **Files modified:** Private/Get-LabVMMetrics.ps1
- **Commit:** 72213b8

**2. [Rule 3 - Auto-fix blocking issue] Stub Hyper-V cmdlets for tests**
- **Found during:** Task 5 (test execution)
- **Issue:** Tests failed with CommandNotFoundException for Get-VMSnapshot, Get-VMHardDiskDrive, Get-VHD on Linux test host
- **Fix:** Added global function stubs before dot-sourcing (Phase 27-03 pattern)
- **Files modified:** Tests/LabVMMetrics.Tests.ps1
- **Commit:** 72213b8

**3. [Rule 3 - Auto-fix blocking issue] Mock Get-LabUptime and Get-LabSTIGCompliance before dot-sourcing**
- **Found during:** Task 5 (test execution)
- **Issue:** Functions not available during test discovery
- **Fix:** Created mock functions in BeforeAll before dot-sourcing scripts
- **Files modified:** Tests/LabVMMetrics.Tests.ps1
- **Commit:** 72213b8

## Commits

| Hash | Message |
| ------ | ------- |
| a085ec6 | feat(29-02): create Get-LabSnapshotAge helper function |
| 9da4626 | feat(29-02): create Get-LabVMDiskUsage helper function |
| 5ff7cab | feat(29-02): create Get-LabVMMetrics orchestrator function |
| 2ae8c82 | test(29-02): create unit tests for metric collection helpers |
| 72213b8 | test(29-02): fix test stubs and verify all metric collection tests pass |

## Integration Points

- **Get-LabDashboardConfig** (29-01): Config block provides threshold values for metrics
- **Get-LabUptime** (26-01): Provides lab-wide uptime hours
- **Get-LabSTIGCompliance** (27-01): Provides per-VM STIG status from cache

## Next Steps

- Plan 29-03: Background Runspace with Synchronized Hashtable
- These helpers will be called from background runspace to populate synchronized hashtable
- UI will read from hashtable, not call helpers directly

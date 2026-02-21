---
phase: 24-linux-vm-parity
plan: 01
subsystem: snapshot-management, profile-management
tags: [linux, parity, snapshots, profiles, pester]
dependency_graph:
  requires: []
  provides: [all-linux-vm-snapshot-discovery, linux-profile-metadata, linux-profile-round-trip]
  affects: [Private/Get-LabSnapshotInventory.ps1, Private/Save-LabProfile.ps1]
tech_stack:
  added: []
  patterns: [GlobalLabConfig-VMNames-lookup, profile-json-round-trip, ConvertTo-Hashtable]
key_files:
  created:
    - Tests/LinuxSnapshotParity.Tests.ps1
    - Tests/LinuxProfileParity.Tests.ps1
  modified:
    - Private/Get-LabSnapshotInventory.ps1
    - Private/Save-LabProfile.ps1
decisions:
  - "Backward-compat: when GlobalLabConfig absent, LIN1 fallback detection preserved (else branch, not removed)"
  - "linuxVmCount prefers VMNames key count over LinuxVM section presence for accuracy"
  - "Get-LabStateProbe needs no changes — it accepts VMNames as a parameter, Linux VMs already included by callers"
metrics:
  duration: ~10 minutes
  completed: 2026-02-21
  tasks_completed: 2
  tasks_total: 2
  files_modified: 4
  tests_added: 26
---

# Phase 24 Plan 01: Linux VM Snapshot and Profile Parity Summary

All-Linux-VM snapshot discovery via Builder.VMNames loop and linuxVmCount metadata field in Save-LabProfile, with 26 new Pester 5 tests proving parity.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Extend snapshot inventory and state probe to discover all Linux VMs | b7bdf3a | Private/Get-LabSnapshotInventory.ps1, Tests/LinuxSnapshotParity.Tests.ps1 |
| 2 | Extend profile save/load to preserve Linux VM settings with round-trip tests | 69c25c6 | Private/Save-LabProfile.ps1, Tests/LinuxProfileParity.Tests.ps1 |

## What Was Built

### Task 1 - Get-LabSnapshotInventory Linux VM Discovery

Replaced the single `LIN1` auto-detection block (3 lines) with a loop over all 5 Ubuntu VMNames keys (`Ubuntu`, `WebServerUbuntu`, `DatabaseUbuntu`, `DockerUbuntu`, `K8sUbuntu`) from `$GlobalLabConfig.Builder.VMNames`. Each key is checked for presence, the mapped VM name is retrieved, and if Hyper-V confirms the VM exists it is added to the target list.

The original LIN1 fallback is preserved in an `else` branch that runs only when `$GlobalLabConfig` is not loaded — maintaining backward compatibility for scripts that call this function without first loading Lab-Config.ps1.

`Get-LabStateProbe` required no changes. It accepts `$VMNames` as a parameter and the caller is responsible for providing the right VM list — Linux VMs are already included by callers that pass `GlobalLabConfig.Lab.CoreVMNames` plus Linux names.

`Remove-LabStaleSnapshots` required no changes. It delegates to `Get-LabSnapshotInventory`, which now returns Linux VMs automatically, so stale snapshot pruning already works for all 5 Linux VMs identically to Windows VMs.

### Task 2 - Save-LabProfile linuxVmCount Metadata

Added a `linuxVmCount` field to the profile metadata ordered hashtable in `Save-LabProfile.ps1`. The count is calculated by checking `$Config.Builder.VMNames` for the 5 Ubuntu role keys. Fallback: if `VMNames` is absent but `LinuxVM` section is present, count is 1. If neither is present, count is 0.

`Load-LabProfile` and `ConvertTo-Hashtable` required no changes. The existing JSON round-trip via `ConvertFrom-Json` + recursive `ConvertTo-Hashtable` already preserves all Linux sections (Linux, LinuxVM, SupportedDistros, Builder.VMNames) with full nested hashtable fidelity.

## Test Results

```
Tests Passed: 26, Failed: 0, Skipped: 0
```

### LinuxSnapshotParity.Tests.ps1 (12 tests)
- Get-LabSnapshotInventory discovers all 5 Linux VMs when GlobalLabConfig is loaded
- Includes Linux VMs alongside Windows VMs in output
- Returns snapshot objects with all required properties for Linux VMs
- Skips Linux VM gracefully if Get-VM returns null
- Respects explicit VMName parameter (no auto-detect when VMName provided)
- Backward compat: auto-detects LIN1 when GlobalLabConfig absent
- Uses default CoreVMNames fallback when GlobalLabConfig absent
- Does not add LIN1 twice when passed explicitly
- Remove-LabStaleSnapshots calls Remove-VMCheckpoint for stale Linux VM snapshots
- Processes Linux VM snapshots identically to Windows VM snapshots
- Returns NoStale when no Linux VM snapshots exceed threshold
- Supports WhatIf for Linux VM snapshot removal

### LinuxProfileParity.Tests.ps1 (14 tests)
- Save-LabProfile includes linuxVmCount field in saved profile
- Counts 5 Linux VMs when all 5 Ubuntu VMNames keys present
- Counts 0 Linux VMs when no Ubuntu VMNames keys present
- Falls back to linuxVmCount = 1 when only LinuxVM section present
- Includes vmCount alongside linuxVmCount in metadata
- Round-trips Builder.Linux.User correctly
- Round-trips Builder.Linux.SSHPublicKey correctly
- Round-trips Builder.LinuxVM.Memory correctly
- Round-trips Builder.LinuxVM.Processors correctly
- Round-trips SupportedDistros nested hashtable (Ubuntu2404.DisplayName)
- Round-trips SupportedDistros nested hashtable (Rocky9.CloudInit)
- Round-trips all 5 Linux VM name entries in Builder.VMNames
- Returns a hashtable (not PSCustomObject) for the loaded config
- Round-trips nested SupportedDistros as hashtable (not PSCustomObject)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed `Count` property access on pipeline single-result string**
- **Found during:** Task 1 test writing
- **Issue:** `($vmNames | Where-Object { $_ -eq 'LIN1' }).Count` throws `PropertyNotFoundException` in PS 5.1 strict mode when `Where-Object` returns a single string (not an array)
- **Fix:** Wrapped in `@()` to force array: `@($vmNames | Where-Object { $_ -eq 'LIN1' }).Count`
- **Files modified:** Tests/LinuxSnapshotParity.Tests.ps1
- **Commit:** b7bdf3a (fixed in same task commit after test run)

## Self-Check: PASSED

# Phase 29: Dashboard Enrichment - Summary

**Status:** Ready for execution  
**Plans:** 5 plans created  
**Requirements:** DASH-01, DASH-02, DASH-03, DASH-04, DASH-05  
**Dependencies:** Phase 26 (Get-LabUptime), Phase 27 (Get-LabSTIGCompliance), Phase 28 (ADMX context)

## Overview

Phase 29 enriches the existing GUI dashboard VM cards with four new metrics:
1. **Snapshot Age**: Days since oldest snapshot, with staleness warnings (7/30 day thresholds)
2. **Disk Usage**: VHDx size in GB and percentage, with pressure indicators (80/95% thresholds)
3. **VM Uptime**: Time since last boot, with stale reminder (72 hour threshold)
4. **STIG Compliance**: Status from Phase 27 cache (Compliant/NonCompliant/Applying/Unknown)

All metrics are collected by a 60-second background runspace and pushed to a synchronized hashtable, ensuring the UI thread never blocks during Hyper-V WMI calls.

## Plan Structure

### Wave 1: Foundation (Plans 01-02)
- **29-01-PLAN.md**: Dashboard config block and Get-LabDashboardConfig helper
- **29-02-PLAN.md**: Metric collection helpers (Get-LabSnapshotAge, Get-LabVMDiskUsage, Get-LabVMMetrics)

### Wave 2: UI Integration (Plans 03-05)
- **29-03-PLAN.md**: Background runspace for metric collection
- **29-04-PLAN.md**: VMCard.xaml updates with 4 new metric rows
- **29-05-PLAN.md**: GUI integration and final testing

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Synchronized hashtable | Thread-safe data sharing between background runspace and UI thread |
| 60-second refresh interval | Balance between freshness and overhead (separate from 5-second UI timer) |
| STA apartment state | Required for WPF compatibility with PowerShell runspaces |
| Emoji status badges | Simple, cross-platform visual indicators without custom graphics |
| Cache-on-write for STIG | Avoid live DSC queries on dashboard hot path (Phase 27 pattern) |
| Icon + Label + Value + Badge format | Compact, readable rows matching existing VM card style |

## Files Modified/Created

### Configuration
- `Lab-Config.ps1`: Add Dashboard block with thresholds
- `Private/Get-LabDashboardConfig.ps1`: New helper

### Metric Collection (3 new files)
- `Private/Get-LabSnapshotAge.ps1`
- `Private/Get-LabVMDiskUsage.ps1`
- `Private/Get-LabVMMetrics.ps1`

### GUI Updates
- `GUI/Start-OpenCodeLabGUI.ps1`: Runspace, badge helper, update function
- `GUI/Components/VMCard.xaml`: 4 new metric rows

### Tests (4 new test files, ~28 tests)
- `Tests/LabDashboardConfig.Tests.ps1`: Config validation
- `Tests/LabVMMetrics.Tests.ps1`: Metric collection with mocked Hyper-V
- `Tests/LabDashboardMetricsRunspace.Tests.ps1`: Runspace lifecycle
- `Tests/LabDashboardMetrics.Tests.ps1`: End-to-end integration

## Success Criteria (from ROADMAP.md)

1. ✅ Each VM card displays snapshot age with staleness warning
2. ✅ Each VM card shows VHDx disk usage with pressure indicator
3. ✅ Each VM card shows VM uptime with stale threshold alert
4. ✅ Each VM card shows STIG compliance status from cache
5. ✅ Metrics collected by 60-second runspace without UI blocking

## Test Coverage

- **Unit Tests**: Config validation, metric collection helpers
- **Integration Tests**: End-to-end flow (runspace → hashtable → UI)
- **Lifecycle Tests**: Runspace creation, population, disposal
- **Manual Tests**: GUI verification checklist (5 categories)

## Known Limitations

- Linux VMs show ⚪ Unknown for snapshot age and disk usage (no VHDx format)
- Metrics refresh every 60 seconds (not configurable in this phase)
- Thresholds only editable via Lab-Config.ps1 (no GUI settings)
- Historical metrics not tracked (current state only)

## Dependencies

- **Phase 26**: Get-LabUptime provides ElapsedHours data
- **Phase 27**: Get-LabSTIGCompliance reads from .planning/stig-compliance.json
- **Phase 28**: ADMX context available (not directly used in dashboard)

## Quality Gate

- [x] All 5 PLAN.md files created with valid frontmatter
- [x] Each plan has valid dependencies (Wave 1 → Wave 2)
- [x] All requirements (DASH-01 through DASH-05) mapped to plans
- [x] Tasks are specific and actionable
- [x] must_haves derived from phase goal
- [x] PS 5.1 compatibility ensured (no ternary operators)
- [x] Test patterns match existing phases (TTL, STIG, ADMX)

## Next Steps

Execute `/gsd:execute-phase -phase 29` to begin implementation.

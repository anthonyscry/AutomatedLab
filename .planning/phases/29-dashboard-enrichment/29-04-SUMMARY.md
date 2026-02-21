---
phase: 29
plan: 04
title: VMCard XAML Updates for Enriched Metrics
status: complete
type: standard
wave: 3
depends_on: ["29-03"]
requirements:
  - DASH-01
  - DASH-02
  - DASH-03
  - DASH-04
tags: [gui, wpf, xaml, dashboard, metrics]
commits:
  - hash: 1298dd1
    message: feat(29-04): add four metric rows to VMCard.xaml
  - hash: 2e839c8
    message: feat(29-04): add Get-StatusBadgeForMetric and Update-VMCardWithMetrics
date_completed: 2026-02-21
duration_minutes: 8
---

# Phase 29 Plan 04: VMCard XAML Updates for Enriched Metrics Summary

**One-liner:** Updated VMCard.xaml with 9-row Grid layout and 4 new metric display rows (snapshot, disk, uptime, STIG), added Get-StatusBadgeForMetric helper for emoji status badge lookup, and Update-VMCardWithMetrics function to read from synchronized hashtable and populate VM cards.

## Implementation Summary

This plan updated the VM card XAML component to display enriched dashboard metrics. The VM card was expanded from 5 rows to 9 rows to accommodate the four new metric displays below the existing CPU+Memory row and above the action buttons. Two new helper functions were added to the GUI script: Get-StatusBadgeForMetric returns emoji badges (🟢, 🟡, 🔴, ⚪) based on threshold comparison, and Update-VMCardWithMetrics reads from the synchronized hashtable populated by the background runspace (plan 29-03) and updates all four TextBlock elements.

## Changes Made

### VMCard.xaml
- Expanded Grid.RowDefinitions from 5 to 9 rows (Rows 0-8)
- Added Row 4: Snapshot age display (txtSnapshotAge)
- Added Row 5: Disk usage display (txtDiskUsage)
- Added Row 6: VM uptime display (txtUptime)
- Added Row 7: STIG compliance display (txtSTIGStatus)
- Moved action buttons from Row 4 to Row 8
- Metric format: Icon + Label + Value + Status Badge (emoji)
- FontSize 11 for compact display, tight 3px spacing

### GUI/Start-OpenCodeLabGUI.ps1
- Added Get-StatusBadgeForMetric function (line 341)
  - Validates MetricType parameter ('Snapshot', 'Disk', 'Uptime', 'STIG')
  - Uses Get-LabDashboardConfig for threshold comparison
  - Returns ⚪ for null/unknown values
  - Snapshot: 🟢 < 7 days, 🟡 >= 7 days, 🔴 >= 30 days
  - Disk: 🟢 < 80%, 🟡 >= 80%, 🔴 >= 95%
  - Uptime: 🟢 < 72 hours, 🟡 >= 72 hours
  - STIG: 🟢 Compliant, 🟡 Applying, 🔴 NonCompliant, ⚪ Unknown

- Added Update-VMCardWithMetrics function (line 476)
  - Reads metrics from $script:DashboardMetrics synchronized hashtable
  - Handles missing VM keys gracefully (returns empty hashtable)
  - Formats snapshot age as "X days" or "No snapshots"
  - Formats disk usage as "X GB (Y%)"
  - Formats uptime as "Xd Yh" for >=24h, "Xh" for <24h
  - Formats STIG status as "Compliant", "NonCompliant", "Applying", or "Unknown"

## Deviations from Plan

None - plan executed exactly as written.

## Technical Notes

### PowerShell 5.1 Compatibility
- Used `[math]::Floor()` and `[math]::Round()` for numeric formatting
- Ternary operator avoided - used if/else for PS 5.1 compatibility
- Join-Path nested calls (2 args only) for path construction

### XAML Validation
- XML parsing passed
- All 13 x:Name values are unique
- Grid.Row values are sequential 0-8 as specified
- TextBlock names: txtSnapshotAge, txtDiskUsage, txtUptime, txtSTIGStatus

### WPF Thread Safety
- Update-VMCardWithMetrics runs on UI thread (called from DispatcherTimer)
- Reads from synchronized hashtable populated by background runspace
- No direct Hyper-V WMI calls on UI thread

## Success Criteria Met

- [x] VMCard.xaml has 9 row definitions
- [x] Four new metric rows added (snapshot, disk, uptime, STIG)
- [x] Icon + Label + Value + Badge format implemented
- [x] Emoji badges (🟢, 🟡, 🔴, ⚪) defined
- [x] Get-StatusBadgeForMetric returns correct emoji based on thresholds
- [x] Update-VMCardWithMetrics updates all four TextBlocks
- [x] XAML validates successfully (XML valid, unique names, sequential rows)

## Files Modified

- `GUI/Components/VMCard.xaml` - Expanded to 9 rows, added 4 metric TextBlocks
- `GUI/Start-OpenCodeLabGUI.ps1` - Added 2 helper functions

## Next Steps

Plan 29-05 will wire Update-VMCardWithMetrics into the dashboard view's DispatcherTimer callback to automatically refresh metric displays on all VM cards every 5 seconds.

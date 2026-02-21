# Phase 29: Dashboard Enrichment - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

## Phase Boundary

Enrich the existing GUI dashboard VM cards with four new metrics: snapshot age, disk usage, VM uptime, and STIG compliance status. All metrics are collected by a background runspace to avoid blocking the UI thread. This phase does NOT create a new dashboard — it enhances the existing VM cards.

**Dependencies:**
- Phase 26 (Get-LabUptime for uptime data)
- Phase 27 (stig-compliance.json cache file)
- Phase 28 (AD/DC context for domain-aware metrics)

**Out of scope:**
- New dashboard views or pages (defer to future phases)
- Real-time/live metrics (all cached/batch-refreshed)
- User configuration of thresholds (config file only, no UI)
- Historical metrics or trends (current state only)

## Implementation Decisions

### VM Card Layout
- New metrics displayed as compact rows below existing VM card information
- Format: Icon + Label + Value + Status Badge (e.g., "💾 Disk: 45GB [🟢]")
- Four rows total (one per metric), stacked vertically
- Preserve existing VM card layout — these are additions, not replacements
- Claude's discretion: exact spacing, padding, and typography

### Visual Indicators
- Color-coded badges using emoji for status:
  - 🟢 Green: Normal/healthy
  - 🟡 Yellow: Warning/threshold breach
  - 🔴 Red: Critical/action needed
  - ⚪ White/Gray: Unknown/data unavailable
- Thresholds defined in Lab-Config.ps1 Dashboard block (defaults provided)
- Stale snapshot > 7 days = 🟡, > 30 days = 🔴
- Disk usage > 80% = 🟡, > 95% = 🔴
- VM uptime > 72 hours = 🟡 (stale VM reminder)
- STIG: Compliant 🟢, Non-Compliant 🔴, Applying 🟡, Unknown ⚪
- Claude's discretion: exact badge styling and border effects

### Background Refresh Behavior
- 60-second refresh interval for metric collection (separate from existing 5-second DispatcherTimer)
- Background runspace pushes data to synchronized hashtable ($DashboardMetrics)
- UI thread reads from hashtable — no Hyper-V WMI calls on UI thread
- Collection failures do NOT crash the dashboard — show ⚪ Unknown badge
- Refresh runspace disposed on dashboard window close
- Claude's discretion: exact runspace lifecycle and error handling patterns

### Threshold Configuration
- Dashboard block added to Lab-Config.ps1 with default thresholds:
  - SnapshotStaleDays: 7 (warning), 30 (critical)
  - DiskUsagePercent: 80 (warning), 95 (critical)
  - UptimeStaleHours: 72 (stale VM reminder)
- Thresholds read via Get-LabDashboardConfig helper (follows Get-LabTTLConfig pattern)
- No GUI for editing thresholds — operators edit Lab-Config.ps1
- Claude's discretion: exact key names and default values

### STIG Compliance Display
- Read from `.planning/stig-compliance.json` (written by Phase 27)
- Display per-VM compliance status: Compliant, Non-Compliant, Applying, or Unknown
- Status field: "STIG: [badge]" format
- No live DSC queries — always read from cache
- Cache file missing or unreadable = Unknown badge
- Claude's discretion: exact label text ("STIG" vs "Compliance" vs "Security")

## Specific Ideas

- Match existing VM card visual style — don't introduce new design language
- Icons should be standard emoji (💾, ⏱️, 📊, 🔒) for simplicity
- Background refresh should be invisible — no loading spinners on the dashboard
- Failed metric collection shows "Unknown" rather than error messages (user sees data, not diagnostics)

## Deferred Ideas

- Historical metrics or trends charts — future phase
- User-configurable thresholds via GUI settings — future phase
- Metric drill-down or detailed views — future phase
- Export/snapshot of dashboard state — future phase
- Real-time/live streaming metrics — different architecture, future phase

---

*Phase: 29-dashboard-enrichment*
*Context gathered: 2026-02-21*

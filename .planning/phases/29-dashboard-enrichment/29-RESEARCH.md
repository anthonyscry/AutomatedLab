# Phase 29: Dashboard Enrichment - Research

**Researched:** 2026-02-21
**Domain:** PowerShell WPF GUI with background runspaces, Hyper-V metrics, synchronized data collection
**Confidence:** HIGH

## Summary

Phase 29 enriches the existing GUI dashboard VM cards with four new metrics: snapshot age, disk usage, VM uptime, and STIG compliance status. The critical technical challenge is collecting these metrics without blocking the UI thread—this requires a background runspace with a synchronized hashtable to push data updates to the UI. The existing GUI already uses a 5-second DispatcherTimer for polling; this phase adds a separate 60-second background refresh for the enriched metrics.

**Primary recommendation:** Use a PowerShell runspace with `[System.Collections.Hashtable]::Synchronized()` for thread-safe data sharing between the background collector and UI thread. Match the existing `Get-LabTTLConfig` pattern for dashboard threshold configuration.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- New metrics displayed as compact rows below existing VM card information
- Format: Icon + Label + Value + Status Badge (e.g., "💾 Disk: 45GB [🟢]")
- Four rows total (one per metric), stacked vertically
- Preserve existing VM card layout — these are additions, not replacements
- Color-coded badges using emoji for status (🟢 Green, 🟡 Yellow, 🔴 Red, ⚪ White/Gray)
- Thresholds defined in Lab-Config.ps1 Dashboard block with defaults provided
- Stale snapshot > 7 days = 🟡, > 30 days = 🔴
- Disk usage > 80% = 🟡, > 95% = 🔴
- VM uptime > 72 hours = 🟡 (stale VM reminder)
- STIG: Compliant 🟢, Non-Compliant 🔴, Applying 🟡, Unknown ⚪
- 60-second refresh interval for metric collection (separate from existing 5-second DispatcherTimer)
- Background runspace pushes data to synchronized hashtable ($DashboardMetrics)
- UI thread reads from hashtable — no Hyper-V WMI calls on UI thread
- Collection failures do NOT crash the dashboard — show ⚪ Unknown badge
- Refresh runspace disposed on dashboard window close
- Thresholds read via Get-LabDashboardConfig helper (follows Get-LabTTLConfig pattern)
- No GUI for editing thresholds — operators edit Lab-Config.ps1
- STIG compliance display reads from `.planning/stig-compliance.json` (written by Phase 27)
- No live DSC queries — always read from cache
- Cache file missing or unreadable = Unknown badge

### Claude's Discretion
- Exact spacing, padding, and typography for new metric rows
- Exact badge styling and border effects
- Exact runspace lifecycle and error handling patterns
- Exact label text ("STIG" vs "Compliance" vs "Security")

### Deferred Ideas (OUT OF SCOPE)
- Historical metrics or trends charts
- User-configurable thresholds via GUI settings
- Metric drill-down or detailed views
- Export/snapshot of dashboard state
- Real-time/live streaming metrics
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DASH-01 | Per-VM snapshot age displayed on dashboard with configurable staleness warnings | Get-VMSnapshot cmdlet with CreationTime property; age calculated via `(Get-Date) - $_.CreationTime` |
| DASH-02 | VHDx disk usage shown per VM with disk pressure indicators | Get-VMHardDiskDrive + Get-VHD cmdlets provide FileSize and Size properties; percentage = `(FileSize / Size) * 100` |
| DASH-03 | VM uptime displayed with configurable stale threshold alerts | Phase 26 Get-LabUptime returns ElapsedHours; status thresholds configurable |
| DASH-04 | STIG compliance status column reads from cached compliance JSON data | Phase 27 Get-LabSTIGCompliance reads `.planning/stig-compliance.json`; Status field directly available |
| DASH-05 | Background runspace collects enriched VM data without freezing UI thread | Synchronized hashtable pattern `[System.Collections.Hashtable]::Synchronized($origin)` for thread-safe data sharing |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| PowerShell runspace | 5.1+ | Background thread execution | Built-in, no external dependencies; matches project's PS 5.1 requirement |
| System.Collections.Hashtable | .NET Framework | Thread-safe data sharing | Synchronized() method provides lock-free concurrent access |
| System.Windows.Threading.DispatcherTimer | WPF | UI thread updates | Existing GUI already uses this for 5-second polling |
| Hyper-V module | Built-in | VM metrics (snapshots, disks) | Get-VMSnapshot, Get-VMHardDiskDrive, Get-VHD are standard Hyper-V cmdlets |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Get-LabUptime | Phase 26 | VM uptime data | Provides ElapsedHours calculated from cached TTL state |
| Get-LabSTIGCompliance | Phase 27 | STIG status | Reads from `.planning/stig-compliance.json` cache file |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Runspace | BackgroundJob (Start-Job) | Jobs have overhead and serialization cost; runspaces are lighter for continuous background work |
| Synchronized hashtable | Dispatcher.Invoke marshalling | Synchronized hashtable is simpler for data sharing; Dispatcher.Invoke requires wrapping every UI update |

**Installation:**
No installation required—all components are built into PowerShell 5.1 and .NET Framework.

## Architecture Patterns

### Recommended Project Structure
```
Private/
├── Get-LabDashboardConfig.ps1   # Reads Dashboard block from GlobalLabConfig
├── Get-LabVMMetrics.ps1         # Collects snapshot age, disk, uptime, STIG status
├── Get-LabSnapshotAge.ps1       # Helper: Get-VMSnapshot age calculation
└── Get-LabVMDiskUsage.ps1       # Helper: Get-VHD size and usage percent

GUI/
└── Start-OpenCodeLabGUI.ps1     # Extended with:
    ├── $script:DashboardMetrics # Synchronized hashtable for metric data
    ├── Start-DashboardMetricsRefreshRunspace  # Runspace creator
    ├── Stop-DashboardMetricsRefreshRunspace   # Cleanup on window close
    ├── Update-VMCardWithMetrics # Extended Update-VMCard function
    └── Get-StatusBadgeForMetric # New: emoji badge lookup based on threshold

Tests/
└── LabDashboardConfig.Tests.ps1 # Config validation, ContainsKey guards
```

### Pattern 1: Synchronized Hashtable for Thread-Safe Data Sharing
**What:** Create a thread-safe hashtable that the background runspace writes to and the UI thread reads from.
**When to use:** Any time background threads need to push data to WPF UI without blocking.
**Example:**
```powershell
# Source: Microsoft PowerShell Docs - "Write Progress across multiple threads"
# https://github.com/microsoftdocs/powershell-docs/blob/main/reference/docs-conceptual/learn/deep-dives/write-progress-across-multiple-threads.md

# Create origin hashtable
$origin = @{}
$vmNames = @('dc1', 'svr1', 'ws1')
$vmNames | ForEach-Object { $origin.$_ = @{} }

# Create synchronized hashtable
$sync = [System.Collections.Hashtable]::Synchronized($origin)

# Background runspace writes to $sync
# UI thread reads from $sync
```

### Pattern 2: Get-LabDashboardConfig (Matches Get-LabTTLConfig Pattern)
**What:** Safe config reader with ContainsKey guards and defaults.
**When to use:** Reading configuration from GlobalLabConfig that may be missing keys.
**Example:**
```powershell
function Get-LabDashboardConfig {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $dashBlock = if (Test-Path variable:GlobalLabConfig) {
        if ($GlobalLabConfig.ContainsKey('Dashboard')) { $GlobalLabConfig.Dashboard } else { @{} }
    } else { @{} }

    [pscustomobject]@{
        SnapshotStaleWarning  = if ($dashBlock.ContainsKey('SnapshotStaleDays'))  { [int]$dashBlock.SnapshotStaleDays }  else { 7 }
        SnapshotStaleCritical = if ($dashBlock.ContainsKey('SnapshotStaleCritical')) { [int]$dashBlock.SnapshotStaleCritical } else { 30 }
        DiskUsageWarning      = if ($dashBlock.ContainsKey('DiskUsagePercent'))   { [int]$dashBlock.DiskUsagePercent }   else { 80 }
        DiskUsageCritical     = if ($dashBlock.ContainsKey('DiskUsageCritical'))  { [int]$dashBlock.DiskUsageCritical }  else { 95 }
        UptimeStaleHours      = if ($dashBlock.ContainsKey('UptimeStaleHours'))   { [int]$dashBlock.UptimeStaleHours }   else { 72 }
    }
}
```

### Pattern 3: Runspace Lifecycle Management
**What:** Create, start, and dispose of a background runspace for periodic data collection.
**When to use:** Long-running background tasks that need to update UI periodically.
**Example:**
```powershell
# In Initialize-DashboardView:
$script:DashboardMetrics = [System.Collections.Hashtable]::Synchronized(@{})
$script:MetricsRefreshRunspace = Start-DashboardMetricsRefreshRunspace

# In mainWindow.Add_Closing:
Stop-DashboardMetricsRefreshRunspace

function Start-DashboardMetricsRefreshRunspace {
    $sync = $script:DashboardMetrics
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'STA'  # Required for WPF compatibility
    $runspace.ThreadOptions = 'ReuseThread'
    $runspace.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace
    $ps.AddScript({
        param($syncHash)
        # Collection loop with 60-second sleep
        while ($syncHash['Continue']) {
            try {
                # Collect metrics and write to $syncHash
                $vmMetrics = Get-LabVMMetrics
                foreach ($vm in $vmMetrics) {
                    $syncHash[$vm.VMName] = $vm
                }
            }
            catch { /* Log, don't crash */ }
            Start-Sleep -Seconds 60
        }
    }).AddParameter('syncHash', $sync)

    $handle = $ps.BeginInvoke()
    return @{ Runspace = $runspace; PowerShell = $ps; Handle = $handle }
}
```

### Pattern 4: VM Snapshot Age Calculation
**What:** Calculate snapshot age using CreationTime property.
**When to use:** Displaying how old a VM snapshot is.
**Example:**
```powershell
# Source: Microsoft Docs - Get-VMSnapshot examples
$snapshot = Get-VMSnapshot -VMName 'dc1' | Sort-Object CreationTime -Descending | Select-Object -First 1
if ($snapshot) {
    $age = (Get-Date) - $snapshot.CreationTime
    $ageDays = [int]$age.TotalDays
}
```

### Pattern 5: VHDx Disk Usage Calculation
**What:** Get VHD file size and calculate usage percentage.
**When to use:** Displaying disk space used by VMs.
**Example:**
```powershell
# Get VHD paths from VM
$vhdPath = (Get-VM -Name 'dc1' | Get-VMHardDiskDrive).Path

# Get VHD info
$vhdInfo = Get-VHD -Path $vhdPath
$fileSizeGB = [math]::Round($vhdInfo.FileSize / 1GB, 2)
$sizeGB = [math]::Round($vhdInfo.Size / 1GB, 2)
$usagePercent = [math]::Round(($vhdInfo.FileSize / $vhdInfo.Size) * 100, 0)
```

### Anti-Patterns to Avoid
- **Direct Hyper-V calls on UI thread:** Never call `Get-VM`, `Get-VMSnapshot`, or `Get-VHD` in the DispatcherTimer tick handler—these will freeze the UI.
- **Live DSC compliance queries:** Phase 27 explicitly caches compliance to JSON—don't query DSC live on the dashboard.
- **Runspace without STA apartment state:** WPF requires STA—background runspaces must set `ApartmentState = 'STA'`.
- **Not disposing runspace on window close:** Runspaces continue running after window closes—must dispose in `Add_Closing` handler.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Thread-safe data sharing | Custom locking with [System.Threading.Monitor] | `[Hashtable]::Synchronized()` | Built-in, lock-free, optimized for concurrent access |
| Cross-thread UI updates | Custom dispatcher queue | Synchronized hashtable + periodic read | Simpler—UI thread reads from shared hashtable on its existing timer |
| Config parsing with defaults | Custom ternary expressions (PS 7+ syntax) | ContainsKey guards with explicit defaults | PS 5.1 compatible; matches existing Get-LabTTLConfig pattern |
| Snapshot age calculation | Custom WMI queries for VSS snapshots | Get-VMSnapshot cmdlet | Built-in Hyper-V module; returns DateTime objects |
| VHD size calculation | File IO with Get-Item length | Get-VHD cmdlet | Returns both FileSize and Size (for dynamic disks) |

**Key insight:** PowerShell 5.1 has rich built-in threading primitives—use them instead of building custom synchronization. The synchronized hashtable pattern is specifically designed for this use case and is well-documented by Microsoft.

## Common Pitfalls

### Pitfall 1: Forgetting STA Apartment State for Runspace
**What goes wrong:** Runspace throws exceptions when trying to interact with WPF objects or certain .NET types.
**Why it happens:** WPF requires Single Threaded Apartment (STA) threading model.
**How to avoid:** Always set `$runspace.ApartmentState = 'STA'` when creating the runspace.
**Warning signs:** Exceptions like "The calling thread must be STA" or random COM object failures.

### Pitfall 2: Blocking UI Thread with Hyper-V Calls
**What goes wrong:** Dashboard freezes for 1-5 seconds on each timer tick.
**Why it happens:** `Get-VM`, `Get-VMSnapshot`, and `Get-VHD` are WMI calls that can be slow.
**How to avoid:** All Hyper-V queries must happen in the background runspace; UI thread only reads from the synchronized hashtable.
**Warning signs:** UI becomes unresponsive during polling intervals.

### Pitfall 3: Runspace Leaks on Window Close
**What goes wrong:** Background runspace continues running after dashboard window closes, consuming CPU and memory.
**Why it happens:** Runspaces don't auto-stop when the creating window closes.
**How to avoid:** Dispose runspace in `$mainWindow.Add_Closing` handler. Use a "Continue" flag in the hashtable to signal the loop to exit.
**Warning signs:** PowerShell.exe processes persist after GUI closes.

### Pitfall 4: Missing StrictMode Guards for Config Access
**What goes wrong:** `Get-LabDashboardConfig` throws "Property 'Foo' cannot be found on this object" under Set-StrictMode.
**Why it happens:** Direct property access (`$config.Foo`) throws when key doesn't exist under StrictMode.
**How to avoid:** Always use `ContainsKey()` guards before accessing hashtable keys, matching the Get-LabTTLConfig pattern.
**Warning signs:** Tests fail under `Set-StrictMode -Version Latest`.

### Pitfall 5: Incorrect PS 5.1 Syntax
**What goes wrong:** Parse errors like "Unexpected token '?:'".
**Why it happens:** Ternary operator (`$x ? $a : $b`) is PS 7+ only.
**How to avoid:** Use `if ($x) { $a } else { $b }` for PS 5.1 compatibility.
**Warning signs:** Syntax errors on line with ternary operator.

### Pitfall 6: Reading Wrong Cache File for STIG Compliance
**What goes wrong:** STIG status always shows "Unknown".
**Why it happens:** Looking for cache file in wrong location or using wrong path.
**How to avoid:** Use `Get-LabSTIGConfig` to get the correct `ComplianceCachePath` (default: `.planning/stig-compliance.json`).
**Warning signs:** STIG badge always shows white/gray "Unknown".

## Code Examples

Verified patterns from official sources:

### Background Data Collection with Synchronized Hashtable
```powershell
# Source: Microsoft PowerShell Docs
# https://github.com/microsoftdocs/powershell-docs/blob/main/reference/docs-conceptual/learn/deep-dives/write-progress-across-multiple-threads.md

# Create origin hashtable with VM names as keys
$origin = @{}
@('dc1', 'svr1', 'ws1') | ForEach-Object { $origin.$_ = @{} }

# Create synchronized hashtable for thread-safe access
$sync = [System.Collections.Hashtable]::Synchronized($origin)

# Background runspace writes metrics
# UI thread reads metrics from $sync
```

### Snapshot Age Calculation
```powershell
# Source: Microsoft Docs - Get-VMSnapshot examples
# https://learn.microsoft.com/en-us/powershell/module/hyper-v/get-vmsnapshot

$snapshots = Get-VMSnapshot -VMName 'dc1'
$latest = $snapshots | Sort-Object CreationTime -Descending | Select-Object -First 1

if ($latest) {
    $age = (Get-Date) - $latest.CreationTime
    $daysOld = [int]$age.TotalDays
    $status = switch ($daysOld) {
        { $_ -gt 30 } { 'Critical' }
        { $_ -gt 7 }  { 'Warning' }
        default       { 'OK' }
    }
}
```

### VHD Disk Usage Calculation
```powershell
# Source: Hyper-V module documentation
# Get-VHD returns FileSize (actual on disk) and Size (logical size)

$vhdInfo = Get-VHD -Path 'C:\AutomatedLab\VM\dc1\disk.vhdx'
$fileSizeGB = [math]::Round($vhdInfo.FileSize / 1GB, 2)
$sizeGB = [math]::Round($vhdInfo.Size / 1GB, 2)
$usagePercent = [math]::Round(($vhdInfo.FileSize / $vhdInfo.Size) * 100, 0)
```

### Config Reader with ContainsKey Guards (Get-LabTTLConfig Pattern)
```powershell
# Source: Phase 26 implementation - Get-LabTTLConfig.ps1

function Get-LabDashboardConfig {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $dashBlock = if (Test-Path variable:GlobalLabConfig) {
        if ($GlobalLabConfig.ContainsKey('Dashboard')) { $GlobalLabConfig.Dashboard } else { @{} }
    } else { @{} }

    [pscustomobject]@{
        SnapshotStaleWarning  = if ($dashBlock.ContainsKey('SnapshotStaleDays'))  { [int]$dashBlock.SnapshotStaleDays }  else { 7 }
        SnapshotStaleCritical = if ($dashBlock.ContainsKey('SnapshotStaleCritical')) { [int]$dashBlock.SnapshotStaleCritical } else { 30 }
        DiskUsageWarning      = if ($dashBlock.ContainsKey('DiskUsagePercent'))   { [int]$dashBlock.DiskUsagePercent }   else { 80 }
        DiskUsageCritical     = if ($dashBlock.ContainsKey('DiskUsageCritical'))  { [int]$dashBlock.DiskUsageCritical }  else { 95 }
        UptimeStaleHours      = if ($dashBlock.ContainsKey('UptimeStaleHours'))   { [int]$dashBlock.UptimeStaleHours }   else { 72 }
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Direct UI thread data collection | Background runspace with synchronized hashtable | PowerShell v2+ | UI remains responsive during slow WMI/Hyper-V calls |
| Manual threading with [System.Threading] | RunspaceFactory + Synchronized Hashtable | PowerShell v2+ | Simpler, PowerShell-idiomatic, less error-prone |
| Live DSC compliance queries | Cache-on-write pattern (Phase 27) | Phase 27 (2026-02) | Dashboard reads from JSON cache—no DSC calls on UI thread |

**Deprecated/outdated:**
- **Ternary operator for PS 5.1 compatibility:** The `? :` ternary syntax is PS 7+ only. Use `if/else` for this project.
- **BackgroundJob (Start-Job) for continuous work:** Jobs have serialization overhead and are better for one-off tasks. Use runspaces for continuous background polling.

## Open Questions

1. **Should the metrics refresh interval be configurable?**
   - What we know: CONTEXT.md locks 60-second interval for metric collection.
   - What's unclear: Whether operators would want different refresh rates (e.g., 30 seconds for dashboards, 120 seconds for resource-constrained hosts).
   - Recommendation: Keep at 60 seconds per CONTEXT.md. Could add to Dashboard config block in future if requested.

2. **What happens when a VM has no snapshots?**
   - What we know: Get-VMSnapshot returns empty array when no snapshots exist.
   - What's unclear: What badge to show—⚪ Unknown or skip the snapshot row entirely.
   - Recommendation: Show ⚪ Unknown badge with text "No snapshots" for transparency. Matches the "failed metric collection shows Unknown" requirement.

3. **How to handle Linux VMs (lin1) for Windows-specific metrics?**
   - What we know: Phase 25 added Linux VM support. Linux VMs don't use Hyper-V snapshots or VHD format.
   - What's unclear: Whether to show "N/A" or skip metrics for Linux VMs.
   - Recommendation: Show ⚪ Unknown badge for snapshot age and disk usage on Linux VMs. STIG and uptime metrics still apply (Phase 27 covers Linux STIG gaps per future phases).

## Sources

### Primary (HIGH confidence)
- [Microsoft PowerShell Docs - Runspace and Threading](https://github.com/microsoftdocs/powershell-docs/blob/main/reference/docs-conceptual/learn/deep-dives/write-progress-across-multiple-threads.md) - Synchronized hashtable pattern, runspace lifecycle
- [Microsoft PowerShell Docs - Get-VMSnapshot](https://learn.microsoft.com/en-us/powershell/module/hyper-v/get-vmsnapshot) - CreationTime property usage
- [Microsoft PowerShell Docs - Get-VHD](https://learn.microsoft.com/en-us/powershell/module/hyper-v/get-vhd) - FileSize and Size properties for disk usage
- [Context7 - PowerShell (/microsoftdocs/powershell-docs)](https://context7.com/microsoftdocs/powershell-docs/llms.txt) - PowerShell runspace patterns, WMI integration, disk space queries

### Secondary (MEDIUM confidence)
- [Project Phase 26 - Get-LabUptime](/mnt/c/projects/AutomatedLab/Public/Get-LabUptime.ps1) - Uptime calculation from cached state
- [Project Phase 27 - Get-LabSTIGCompliance](/mnt/c/projects/AutomatedLab/Public/Get-LabSTIGCompliance.ps1) - STIG compliance cache reading pattern
- [Project Phase 28 - Get-LabADMXConfig](/mnt/c/projects/AutomatedLab/Private/Get-LabADMXConfig.ps1) - Config block pattern reference
- [Project Tests - LabTTLConfig.Tests.ps1](/mnt/c/projects/AutomatedLab/Tests/LabTTLConfig.Tests.ps1) - Test patterns for config validation

### Tertiary (LOW confidence)
- Web search results for "PowerShell runspace background thread WPF GUI" - General guidance on STA apartment state
- Web search results for "PowerShell Get-VMSnapshot CreationTime age calculation" - Age calculation examples

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All components are built into PowerShell 5.1 and .NET Framework
- Architecture: HIGH - Synchronized hashtable pattern is well-documented by Microsoft for this exact use case
- Pitfalls: HIGH - Project has existing patterns (Get-LabTTLConfig, Get-LabSTIGCompliance) that demonstrate the correct approach

**Research date:** 2026-02-21
**Valid until:** 30 days (PowerShell 5.1 and Hyper-V module are stable)

# Architecture Research

**Domain:** PowerShell Hyper-V Lab Automation — v1.6 Integration
**Researched:** 2026-02-20
**Confidence:** HIGH

## v1.6 Integration Context

This document supersedes the v1.0–v1.5 baseline architecture for the purpose of planning
v1.6 additions. The four new capability areas are:

1. **Lab TTL / auto-suspend** — config-driven background monitoring that saves or stops lab VMs after an idle or wall-clock deadline
2. **PowerSTIG DSC baselines** — per-VM STIG compliance enforced at deploy time via DSC composite resources
3. **ADMX/GPO auto-import** — Central Store population and GPO creation triggered after DC promotion
4. **Operational dashboard enrichment** — snapshot age, disk usage, uptime, and compliance columns added to the existing 5-second-polling WPF dashboard

All four must integrate with the existing architecture without breaking existing behavior.

---

## Existing Architecture Snapshot (what we're integrating into)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Entry Points                                        │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐          │
│  │ CLI / run-lab.ps1│  │ GUI / Start-      │  │ LabBuilder /     │          │
│  │ Scripts/Run-      │  │ OpenCodeLabGUI    │  │ Invoke-LabBuilder│          │
│  │ OpenCodeLab.ps1  │  │ .ps1              │  │ .ps1             │          │
│  └────────┬─────────┘  └────────┬──────────┘  └────────┬─────────┘          │
└───────────┼─────────────────────┼──────────────────────┼────────────────────┘
            │                     │                      │
┌───────────┴─────────────────────┴──────────────────────┴────────────────────┐
│                         Lab-Common.ps1 (auto-discovers Private/*.ps1)       │
│                                                                              │
│  Public/ cmdlets               Private/ helpers                             │
│  ┌─────────────────────┐       ┌──────────────────────────────────┐         │
│  │ Get-LabStatus        │       │ Get-LabStateProbe                │         │
│  │ Get-LabRunHistory    │  ←→   │ Get-LabSnapshotInventory         │         │
│  │ Get-LabCheckpoint    │       │ Invoke-LabQuickModeHeal          │         │
│  │ Start/Stop/Suspend   │       │ Write-LabRunArtifacts            │         │
│  │ Initialize-LabDomain │       │ Resolve-LabModeDecision          │         │
│  └─────────────────────┘       └──────────────────────────────────┘         │
├─────────────────────────────────────────────────────────────────────────────┤
│                         Configuration Layer                                  │
│  Lab-Config.ps1 ($GlobalLabConfig hashtable)                                │
│  .planning/profiles/   .planning/templates/   .planning/roles/              │
└──────────────────────────────────────────────────────────────────────────────┘
            │
┌───────────┴──────────────────────────────────────────────────────────────────┐
│                         Infrastructure Layer                                  │
│  Hyper-V module   PowerShell Remoting   NetNat   Scheduled Tasks             │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Existing Data Stores

| Store | Location | Shape |
|-------|----------|-------|
| Run artifacts | `run-logs/` (JSON + TXT) | Per-run action/outcome/events |
| Profiles | `.planning/profiles/*.json` | GlobalLabConfig subset |
| Scenario templates | `.planning/templates/*.json` | VM topology definitions |
| Custom roles | `.planning/roles/*.json` | Role schema + provisioning steps |
| GUI settings | `.planning/gui-settings.json` | Theme, layout state |
| Snapshot state | In-memory via `Get-LabSnapshotInventory` | `PSCustomObject[]` |

---

## v1.6 Component Map

### New vs Modified

| Component | New or Modified | Location |
|-----------|----------------|----------|
| `Get-LabTTLConfig` | NEW private helper | `Private/` |
| `Test-LabTTLExpired` | NEW private helper | `Private/` |
| `Invoke-LabTTLAction` | NEW private helper (save/stop dispatch) | `Private/` |
| `Register-LabTTLTask` / `Unregister-LabTTLTask` | NEW public cmdlets | `Public/` |
| `Invoke-LabTTLMonitor` | NEW private helper (task payload script) | `Private/` |
| TTL config block | MODIFIED | `Lab-Config.ps1` (`$GlobalLabConfig.TTL`) |
| `Invoke-LabApplySTIG` | NEW private helper | `Private/` |
| `Get-LabSTIGConfig` | NEW private helper | `Private/` |
| STIG config block | MODIFIED | `Lab-Config.ps1` (`$GlobalLabConfig.STIG`) |
| `Initialize-LabDomain` PostInstall | MODIFIED | `Public/Initialize-LabDomain.ps1` |
| DC role PostInstall | MODIFIED | `LabBuilder/Roles/DC.ps1` |
| `Invoke-LabADMXImport` | NEW private helper | `Private/` |
| ADMX config block | MODIFIED | `Lab-Config.ps1` (`$GlobalLabConfig.ADMX`) |
| `Get-LabEnrichedStatus` | NEW private helper | `Private/` |
| `Get-LabStatus` | MODIFIED (adds enriched fields) | `Public/Get-LabStatus.ps1` |
| `Update-VMCard` | MODIFIED (renders enriched fields) | `GUI/Start-OpenCodeLabGUI.ps1` |
| Dashboard XAML | MODIFIED (new metric TextBlocks) | `GUI/Views/DashboardView.xaml` |
| `VMCard.xaml` | MODIFIED (snapshot age + compliance badge) | `GUI/Components/VMCard.xaml` |

---

## Feature 1: Lab TTL / Auto-Suspend

### Concept

The TTL system provides two enforcement modes:

- **Idle TTL** — if all VMs have had no recent Hyper-V heartbeat activity for N minutes, trigger action
- **Wall-clock TTL** — if the lab has been running longer than N hours total, trigger action

The action is one of: `Save` (Hyper-V Save State, resumable) or `Stop` (power off).

Background monitoring is implemented as a Windows Scheduled Task that runs a PowerShell script on a repeating trigger (e.g., every 15 minutes). This matches the existing Windows host-native approach and avoids requiring a running PowerShell session.

### Config Integration

Add a `TTL` block to `$GlobalLabConfig` in `Lab-Config.ps1`:

```powershell
TTL = @{
    # Changing Enabled toggles whether auto-suspend monitoring is active.
    Enabled = $false

    # Changing IdleMinutes sets how long all VMs must be idle before action.
    # 0 = disable idle check.
    IdleMinutes = 0

    # Changing WallClockHours sets the maximum running time for the lab.
    # 0 = disable wall-clock check.
    WallClockHours = 8

    # Changing Action selects what happens when TTL expires.
    # Valid values: 'Save' (save state) | 'Stop' (power off)
    Action = 'Save'

    # Changing TaskName changes the Scheduled Task name registered on the host.
    TaskName = 'AutomatedLab-TTLMonitor'

    # Changing PollIntervalMinutes changes how often the task wakes to check TTL.
    PollIntervalMinutes = 15
}
```

### Private Helpers

**`Get-LabTTLConfig`** — reads `$GlobalLabConfig.TTL`, validates values, returns typed PSCustomObject. Isolates config access for testability.

**`Test-LabTTLExpired`** — accepts a TTL config object and current VM state list. Returns `[pscustomobject]@{ Expired = $true/false; Reason = '...' }`. Pure logic, no side effects, easily unit tested.

**`Invoke-LabTTLAction`** — dispatches to `Suspend-LabVMs` (Save) or `Stop-LabVMs` (Stop) based on Action value. Writes a TTL event to run artifacts.

**`Invoke-LabTTLMonitor`** — the script body executed by the Scheduled Task. Loads Lab-Common.ps1, reads config, calls `Test-LabTTLExpired`, calls `Invoke-LabTTLAction` if expired. Runs as the current user context (same user who registered the task).

### Public Cmdlets

**`Register-LabTTLTask`** — creates a Windows Scheduled Task using `Register-ScheduledTask`. The task action is `powershell.exe -NonInteractive -File <repo>\Private\Invoke-LabTTLMonitor.ps1`. Trigger is a repeating time trigger based on `PollIntervalMinutes`. Requires admin rights. Idempotent (unregisters existing before re-registering).

**`Unregister-LabTTLTask`** — removes the Scheduled Task by name. Idempotent.

### Scheduled Task Integration

```
Register-LabTTLTask
    ↓
Windows Task Scheduler
    ↓ (every PollIntervalMinutes)
Invoke-LabTTLMonitor.ps1
    ↓
. Lab-Common.ps1 (loads all Private/ + Public/ helpers)
. Lab-Config.ps1 ($GlobalLabConfig)
    ↓
Get-LabTTLConfig → Test-LabTTLExpired
    ↓ (if expired)
Invoke-LabTTLAction → Suspend-LabVMs / Stop-LabVMs
    ↓
Write run event to run-logs/
```

### Data Flow

```
$GlobalLabConfig.TTL (wall-clock / idle settings)
    ↓
Test-LabTTLExpired (reads Hyper-V VM uptime via Get-VM, no external deps)
    ↓
[pscustomobject]@{ Expired; Reason }
    ↓ (if Expired)
Invoke-LabTTLAction → calls existing Public cmdlets
    ↓
Event written to run-logs/ JSON artifact
```

The TTL monitor does NOT require a separate run artifact file. It appends TTL events via `Add-LabRunEvent` using a dedicated run ID so history is queryable.

### PS 5.1 Notes

`Register-ScheduledTask` and `New-ScheduledTaskTrigger` with `-RepetitionInterval` are available in PS 5.1 via the `ScheduledTasks` module (Windows 8.1+). The task payload script must use `if/else` not ternary operators. `Get-VM` uptime is available via `$vm.Uptime` (TimeSpan) in PS 5.1 Hyper-V module.

---

## Feature 2: PowerSTIG DSC Baselines

### Concept

PowerSTIG (microsoft/PowerStig) is a PowerShell module that ships pre-processed STIG XML data and composite DSC resources (`WindowsServer`, `WindowsClient`, `WindowsDnsServer`, `WindowsFirewall`, etc.). At deploy time, after a VM is provisioned and joined to the domain, the framework:

1. Installs PowerSTIG and its dependencies on the target VM via `Invoke-LabCommand`
2. Compiles a MOF file from a DSC configuration block that references the appropriate PowerSTIG composite resource
3. Applies the MOF with `Start-DscConfiguration -Wait -Force`

This integrates into the existing `PostInstall` scriptblock pattern used by LabBuilder roles.

### Config Integration

Add a `STIG` block to `$GlobalLabConfig`:

```powershell
STIG = @{
    # Changing Enabled toggles whether PowerSTIG baselines are applied at deploy time.
    Enabled = $false

    # Changing OsVersion sets the STIG data version used for Windows Server VMs.
    OsVersion = '2019'

    # Changing SkipRules lists STIG rule IDs to exclude from enforcement.
    # Use when a rule conflicts with lab requirements (e.g., V-93269 password complexity).
    SkipRules = @()

    # Changing Roles maps VM role tags to PowerSTIG composite resource names.
    # If a tag is absent, no STIG is applied to that role.
    Roles = @{
        DC      = 'WindowsServer'
        SVR1    = 'WindowsServer'
        IIS1    = 'WindowsServer'
    }
}
```

### Private Helpers

**`Get-LabSTIGConfig`** — reads `$GlobalLabConfig.STIG`, validates required keys, returns PSCustomObject. Guards Enabled flag.

**`Invoke-LabApplySTIG`** — accepts `VMName`, `Role` (PowerSTIG resource name), `OsVersion`, and `SkipRules`. Called from LabBuilder role PostInstall scriptblocks.

The function body (executed via `Invoke-LabCommand`) follows these steps:

```
1. Install-PackageProvider NuGet (idempotent, same pattern as DSCPullServer.ps1)
2. Install-Module PowerStig (and transitive deps) if not present
3. dot-source PowerSTIG composite DSC config block
4. Compile MOF: & $configBlock -OutputPath $env:TEMP\StigMof
5. Start-DscConfiguration -Path $env:TEMP\StigMof -Wait -Force
6. Write-Host result
```

### LabBuilder Integration Points

The STIG apply step hooks into the PostInstall scriptblock of each role that opts in. The DC role PostInstall is the primary initial target, running after AD DS services are validated:

```
DC.ps1 PostInstall (existing):
  Step 1: Configure DNS forwarders    ← existing
  Step 2: Validate AD DS services     ← existing
  Step 3: [NEW] Invoke-LabApplySTIG   ← new, gated by $LabConfig.STIG.Enabled
```

This is an additive change — when `STIG.Enabled = $false` (default), the function returns immediately without touching the VM. Existing PostInstall behavior is unchanged.

### MOF Compilation Boundary

PowerSTIG DSC configurations are compiled on the target VM (not the host). The MOF is generated and applied locally via:

```powershell
Invoke-LabCommand -ComputerName $VMName -ScriptBlock {
    # Full DSC config + compilation + Start-DscConfiguration here
    Configuration ApplyStig { ... }
    ApplyStig -OutputPath "$env:TEMP\StigMof"
    Start-DscConfiguration -Path "$env:TEMP\StigMof" -Wait -Force
}
```

This avoids WinRM double-hop credential issues for module gallery access and keeps the pattern consistent with existing DSCPullServer.ps1.

### PS 5.1 Compatibility Notes

PowerSTIG supports Windows PowerShell 5.1 (HIGH confidence — project readme and PS Gallery listing both confirm WMF 5.1 as minimum). DSC v1 (inbox PS 5.1) compiles MOFs with `Configuration {}` blocks without requiring PowerShell 7. DSC v3 is PS 7+ only and is explicitly out of scope here.

The existing DSCPullServer.ps1 establishes the exact same install-via-gallery-on-target pattern. PowerSTIG follows the same flow.

---

## Feature 3: ADMX / GPO Auto-Import

### Concept

After DC promotion, the lab's Group Policy Central Store (`\\domain\SYSVOL\domain\Policies\PolicyDefinitions`) should be populated with the latest Windows ADMX/ADML templates. Optionally, a baseline GPO can be created and linked to the domain.

This is a pure PowerShell file-copy plus optional GPMC operation, not a DSC or WinRM-heavy operation.

### Config Integration

Add an `ADMX` block to `$GlobalLabConfig`:

```powershell
ADMX = @{
    # Changing Enabled toggles whether ADMX auto-import runs after DC promotion.
    Enabled = $false

    # Changing SourcePath sets where ADMX/ADML files are sourced from on the host.
    # Default: C:\Windows\PolicyDefinitions (host OS templates)
    SourcePath = 'C:\Windows\PolicyDefinitions'

    # Changing CreateBaselineGPO toggles creation of a starter GPO after import.
    CreateBaselineGPO = $false

    # Changing BaselineGPOName sets the name of the created GPO.
    BaselineGPOName = 'Lab-Security-Baseline'
}
```

### Private Helper: `Invoke-LabADMXImport`

```powershell
function Invoke-LabADMXImport {
    param(
        [string]$DCName,
        [string]$DomainName,
        [string]$SourcePath,
        [bool]$CreateBaselineGPO,
        [string]$BaselineGPOName
    )
}
```

Internal steps:

```
1. Build Central Store path:
   \\$DCName\SYSVOL\$DomainName\Policies\PolicyDefinitions

2. Test if Central Store exists; create if missing (New-Item on UNC path)

3. Copy $SourcePath\*.admx to Central Store (idempotent — only if newer)

4. Copy $SourcePath\en-US\*.adml to Central Store\en-US

5. If CreateBaselineGPO:
   a. Import-Module GroupPolicy on DC via Invoke-LabCommand
   b. New-GPO -Name $BaselineGPOName -Comment "Auto-created by AutomatedLab"
   c. New-GPLink -Name $BaselineGPOName -Target $DomainDN -LinkEnabled Yes
```

### Integration Point: DC PostInstall

Same pattern as STIG — added as an optional step after existing DC PostInstall steps, gated by `$LabConfig.ADMX.Enabled`:

```
DC.ps1 PostInstall:
  Step 1: Configure DNS forwarders     ← existing
  Step 2: Validate AD DS services      ← existing
  Step 3: Invoke-LabApplySTIG          ← new (STIG feature)
  Step 4: Invoke-LabADMXImport         ← new (ADMX feature)
```

### PS 5.1 Compatibility Notes

UNC path operations (`Test-Path \\server\share`, `Copy-Item`) work natively in PS 5.1. GroupPolicy module (`New-GPO`, `New-GPLink`) is available on Windows Server 2016/2019 domain controllers. The call runs inside `Invoke-LabCommand` on the DC, where the GroupPolicy module is present after AD DS installation. No PS 7 dependency.

---

## Feature 4: Operational Dashboard Enrichment

### Concept

The existing `Get-LabStatus` returns per-VM `PSCustomObject` records with: `VMName`, `State`, `CPUUsage`, `MemoryGB`, `Uptime`, `NetworkStatus`, `Heartbeat`.

The enriched status adds: `SnapshotAgedays`, `OldestSnapshotDays`, `SnapshotCount`, `DiskUsedGB`, `STIGCompliant`.

The GUI dashboard consumes `Get-LabStatus` via its 5-second DispatcherTimer. The enriched fields are rendered in new `TextBlock` controls on `VMCard.xaml` and as summary metrics on `DashboardView.xaml`.

### `Get-LabEnrichedStatus` (NEW Private Helper)

This helper collects the expensive per-VM metrics (disk, snapshot age) that are too slow for the 5-second hot path and are cached separately:

```powershell
function Get-LabEnrichedStatus {
    param(
        [string[]]$VMName,
        [int]$CacheSeconds = 60
    )
}
```

Returns `PSCustomObject[]` with enrichment fields. Uses a `$script:EnrichedStatusCache` hashtable keyed by VMName with a timestamp, refreshed only when cache is stale. This prevents slow WMI/VHD queries from blocking the GUI poll loop.

### `Get-LabStatus` Modification

`Get-LabStatus` gains an `-Enriched` switch:

```powershell
[switch]$Enriched
```

When `-Enriched` is specified, it merges results from `Get-LabEnrichedStatus` into the base status objects. The base (non-enriched) path is unchanged for existing callers.

**Enriched fields added per VM:**

| Field | Source | Notes |
|-------|--------|-------|
| `SnapshotCount` | `Get-VMCheckpoint` | Count of all checkpoints |
| `OldestSnapshotDays` | `Get-VMCheckpoint` | Age of oldest checkpoint in days |
| `DiskUsedGB` | `Get-VHD` on VM's primary VHDX | Rounded GB, FileSize not VHDSize |
| `STIGCompliant` | Read `.planning/stig-compliance.json` | Written by `Invoke-LabApplySTIG` post-apply |

### STIG Compliance State File

`Invoke-LabApplySTIG` writes a compliance record to `.planning/stig-compliance.json` on the host after each apply run. This avoids the overhead of running `Get-DscConfigurationStatus` on every poll:

```json
{
  "dc1": { "LastApplied": "2026-02-20T10:00:00Z", "Compliant": true, "STIGVersion": "2019" },
  "svr1": { "LastApplied": "2026-02-20T10:05:00Z", "Compliant": false, "FailedRuleCount": 3 }
}
```

`Get-LabEnrichedStatus` reads this file (or returns `"Unknown"` if absent).

### GUI Integration

**`VMCard.xaml` additions:**

```xml
<!-- Snapshot age badge -->
<TextBlock x:Name="txtSnapshotAge" Text="Snaps: --" FontSize="11" ... />

<!-- Compliance indicator -->
<TextBlock x:Name="txtCompliance" Text="STIG: --" FontSize="11" ... />

<!-- Disk usage -->
<TextBlock x:Name="txtDisk" Text="Disk: --" FontSize="11" ... />
```

**`Update-VMCard` additions** (in `Start-OpenCodeLabGUI.ps1`):

The existing `Update-VMCard` function receives the `VMData` object from `Get-LabStatus`. When enriched fields are present (checked with `PSObject.Properties.Name -contains 'SnapshotCount'`), it populates the new `TextBlock` controls. When absent (non-enriched callers), controls stay at `--`. This maintains backward compatibility.

**Dashboard polling adjustment:**

The DispatcherTimer tick currently calls `Get-LabStatus`. It will continue to call `Get-LabStatus` (non-enriched, fast path) for the 5-second heartbeat. A separate 60-second enrichment timer (or TTL-aligned timer) calls `Get-LabStatus -Enriched` and updates only the enriched `TextBlock` controls:

```powershell
$script:EnrichmentTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:EnrichmentTimer.Interval = [TimeSpan]::FromSeconds(60)
$script:EnrichmentTimer.Add_Tick({
    $enriched = Get-LabStatus -Enriched
    foreach ($vmData in $enriched) {
        if ($script:VMCards.ContainsKey($vmData.VMName)) {
            Update-VMCard -Card $script:VMCards[$vmData.VMName] -VMData $vmData
        }
    }
}.GetNewClosure())
```

This two-timer pattern prevents slow disk/snapshot queries from freezing the GUI's 5-second heartbeat.

---

## Revised System Overview (v1.6)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Entry Points                                        │
│  CLI / GUI / LabBuilder        [NEW] Windows Task Scheduler                │
│                                      (TTL Monitor Task)                     │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
┌──────────────────────────────────────┴──────────────────────────────────────┐
│                         Lab-Common.ps1 + Private/ helpers                   │
│                                                                              │
│  Existing helpers          [NEW v1.6 helpers]                               │
│  ─────────────             ──────────────────                               │
│  Get-LabStateProbe         Get-LabTTLConfig       Get-LabSTIGConfig         │
│  Get-LabSnapshotInventory  Test-LabTTLExpired      Invoke-LabApplySTIG      │
│  Invoke-LabQuickModeHeal   Invoke-LabTTLAction     Invoke-LabADMXImport     │
│  Write-LabRunArtifacts     Invoke-LabTTLMonitor    Get-LabEnrichedStatus    │
│                                                                              │
│  [MODIFIED] Get-LabStatus (adds -Enriched switch)                           │
│  [MODIFIED] LabBuilder DC.ps1 PostInstall (adds STIG + ADMX steps)         │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
┌──────────────────────────────────────┴──────────────────────────────────────┐
│                         Configuration Layer                                  │
│  Lab-Config.ps1 $GlobalLabConfig                                             │
│  [MODIFIED] adds: .TTL block  .STIG block  .ADMX block                      │
│                                                                              │
│  [NEW] .planning/stig-compliance.json  (compliance state cache)             │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow Changes

### TTL Monitor Flow (new)

```
Windows Task Scheduler (every N minutes)
    ↓
Invoke-LabTTLMonitor.ps1 (Private/)
    ↓
. Lab-Common.ps1 → loads all Private/ helpers + $GlobalLabConfig
    ↓
Get-LabTTLConfig → validates TTL block
    ↓
Test-LabTTLExpired
    ↓ (reads Get-VM uptime + Hyper-V heartbeat data)
[pscustomobject]{ Expired; Reason }
    ↓ (if Expired)
Invoke-LabTTLAction → Suspend-LabVMs / Stop-LabVMs
    ↓
Add-LabRunEvent → appended to run-logs/ artifact
```

### STIG Apply Flow (new, within existing deploy pipeline)

```
LabBuilder Build-LabFromSelection / Deploy.ps1
    ↓
Role PostInstall scriptblock (DC.ps1, IIS.ps1, etc.)
    ↓ (if $LabConfig.STIG.Enabled)
Invoke-LabApplySTIG -VMName $vmName -Role WindowsServer
    ↓
Invoke-LabCommand → target VM
    ├── Install PowerSTIG + deps from PS Gallery
    ├── Compile DSC MOF (Configuration { } block)
    └── Start-DscConfiguration -Wait -Force
    ↓
Write .planning/stig-compliance.json on host
```

### Dashboard Enrichment Flow (modified)

```
GUI DispatcherTimer (5-second heartbeat, unchanged)
    ↓
Get-LabStatus (no -Enriched, fast path)
    ↓
Update-VMCard (State, CPU, Memory, IP — unchanged)

GUI EnrichmentTimer (60-second, new)
    ↓
Get-LabStatus -Enriched
    ↓
Get-LabEnrichedStatus
    ├── Get-VMCheckpoint → SnapshotCount, OldestSnapshotDays
    ├── Get-VHD → DiskUsedGB
    └── Read .planning/stig-compliance.json → STIGCompliant
    ↓
Update-VMCard (enriched TextBlocks: SnapshotAge, Disk, STIG)
```

### ADMX Import Flow (new, triggered post-DC-promotion)

```
Initialize-LabDomain (or DC.ps1 PostInstall)
    ↓ (if $LabConfig.ADMX.Enabled)
Invoke-LabADMXImport
    ↓
Build Central Store path (\\DC\SYSVOL\domain\Policies\PolicyDefinitions)
    ↓
Copy *.admx + en-US\*.adml from SourcePath (idempotent)
    ↓ (if CreateBaselineGPO)
Invoke-LabCommand → DC: New-GPO + New-GPLink
```

---

## Component Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| **TTL Task → Lab helpers** | Dot-source `Lab-Common.ps1` in task payload | Same pattern as other entry points; no WinRM |
| **STIG helper → Target VM** | `Invoke-LabCommand` (existing remoting channel) | MOF compiled on target, not host |
| **ADMX helper → DC** | UNC file copy (no Invoke-LabCommand needed for copy) + optional `Invoke-LabCommand` for GPO create | Runs from host; SYSVOL is accessible via UNC after domain is up |
| **Enriched Status → GUI** | Return value merge in `Get-LabStatus` | Backward-compat: enriched fields only when `-Enriched` switch used |
| **STIG compliance cache → dashboard** | JSON file read by `Get-LabEnrichedStatus` | Decouples apply-time from poll-time; no PS Remoting on hot path |
| **TTL events → run history** | `Add-LabRunEvent` → existing `Write-LabRunArtifacts` path | TTL events queryable via `Get-LabRunHistory` |

---

## Architectural Patterns

### Pattern: Gated Feature Blocks (Enabled Flag)

All four v1.6 features follow the same opt-in pattern:

```powershell
if (-not $LabConfig.STIG.Enabled) {
    Write-Verbose "[STIG] Skipped — STIG.Enabled is false."
    return
}
```

This ensures:
- Default behavior is unchanged (all flags default to `$false`)
- No test infrastructure changes needed for existing tests
- Features can be developed and merged independently

### Pattern: Cache-on-Write for Expensive State

STIG compliance state is written by `Invoke-LabApplySTIG` (apply-time) and read cheaply by `Get-LabEnrichedStatus` (poll-time). This avoids running DSC configuration checks on every GUI tick.

The same pattern applies to enriched disk/snapshot data: `Get-LabEnrichedStatus` uses `$script:EnrichedStatusCache` with a 60-second TTL (different concept from lab TTL) to prevent repeated `Get-VHD` calls on the GUI hot path.

### Pattern: Task-as-Monitor for Background Automation

The TTL monitor uses the Windows Task Scheduler as the execution host rather than a long-running background job or `Start-Job`. This is preferable because:
- Tasks survive PowerShell session termination
- Task history is viewable in Task Scheduler UI
- Failure behavior (retry, on-error) is configurable declaratively
- `Register-ScheduledTask` is available in PS 5.1

The monitor payload script (`Invoke-LabTTLMonitor.ps1`) is deliberately stateless — it reads current config and VM state on each execution rather than carrying state across invocations.

### Pattern: PostInstall Extensibility for Deploy-Time Actions

Existing LabBuilder roles expose a `PostInstall` scriptblock that runs after VM provisioning. New deploy-time actions (STIG apply, ADMX import) attach to this scriptblock rather than inventing a new hook. This keeps the provisioning pipeline linear and auditable.

```powershell
# Pattern in DC.ps1 PostInstall
# --- Existing steps ---
Invoke-LabCommand -ComputerName $dcName -ActivityName 'DC-Configure-DNS-Forwarders' ...
Invoke-LabCommand -ComputerName $dcName -ActivityName 'DC-Validate-ADDS' ...

# --- New steps (gated) ---
if ($LabConfig.STIG.Enabled) {
    Invoke-LabApplySTIG -VMName $dcName -Role 'WindowsServer' -LabConfig $LabConfig
}
if ($LabConfig.ADMX.Enabled) {
    Invoke-LabADMXImport -DCName $dcName -DomainName $LabConfig.DomainName -LabConfig $LabConfig
}
```

---

## Anti-Patterns for v1.6

### Anti-Pattern: Polling STIG Compliance via Get-DscConfigurationStatus on GUI Tick

**What it would look like:** Running `Invoke-LabCommand -ComputerName $vm -ScriptBlock { Get-DscConfigurationStatus }` inside the 5-second DispatcherTimer.

**Why it is wrong:** `Get-DscConfigurationStatus` initiates PS Remoting, is slow (2-10 seconds), and blocks the STA WPF thread. The GUI freezes.

**Do this instead:** Use the cache-on-write pattern: write compliance state to `.planning/stig-compliance.json` at apply time; read it cheaply from disk on the enrichment timer.

### Anti-Pattern: TTL Monitor as a Persistent Background Job

**What it would look like:** `$job = Start-Job { while ($true) { ... ; Start-Sleep 900 } }`.

**Why it is wrong:** Background jobs die when the PowerShell session that created them exits. The TTL contract is "suspend even if I close my terminal." Only Scheduled Tasks survive session exit.

**Do this instead:** `Register-LabTTLTask` creates a proper Scheduled Task. `Unregister-LabTTLTask` removes it.

### Anti-Pattern: Embedding STIG Logic in Role Scripts Inline

**What it would look like:** Pasting the full PowerSTIG install + MOF compile block directly inside `DC.ps1`'s PostInstall.

**Why it is wrong:** Duplicates the same 80-line block across every role that needs STIG. Untestable in isolation. Hard to update when PowerSTIG version changes.

**Do this instead:** Single `Invoke-LabApplySTIG` private helper called from each PostInstall with parameters.

### Anti-Pattern: Hardcoding ADMX Source Path to Host OS PolicyDefinitions

**What it would look like:** `Copy-Item 'C:\Windows\PolicyDefinitions\*' ...` without a config key.

**Why it is wrong:** Breaks on non-C: installations and prevents operators from using a custom ADMX bundle (e.g., Security Compliance Toolkit ADMX files).

**Do this instead:** `$GlobalLabConfig.ADMX.SourcePath` with default of `'C:\Windows\PolicyDefinitions'`.

---

## Recommended Build Order

Dependencies flow as follows:

1. `Lab-Config.ps1` TTL/STIG/ADMX blocks must exist before any helper reads them
2. `Get-LabTTLConfig` / `Get-LabSTIGConfig` before their callers
3. `Invoke-LabApplySTIG` before PostInstall modifications (DC.ps1)
4. `Invoke-LabADMXImport` before PostInstall modifications (DC.ps1)
5. `Get-LabEnrichedStatus` before `Get-LabStatus -Enriched`
6. `Get-LabStatus -Enriched` before GUI enrichment timer wiring
7. `Register-LabTTLTask` / `Unregister-LabTTLTask` after `Invoke-LabTTLMonitor`

### Suggested Phase Order

| Phase | Feature | Rationale |
|-------|---------|-----------|
| Phase 1 | Lab TTL / auto-suspend | Self-contained, no deps on STIG or dashboard; sets up config block pattern for remaining features |
| Phase 2 | PowerSTIG DSC baselines | Depends only on config block and existing LabBuilder PostInstall pattern |
| Phase 3 | ADMX/GPO auto-import | Depends on DC PostInstall pattern established by STIG phase |
| Phase 4 | Dashboard enrichment | Depends on compliance cache written by STIG feature; integrates all three new data sources |

TTL first because it is the most independent. Dashboard last because it consumes outputs from the other three.

---

## Integration Points Summary

| New Feature | Attaches To | Mechanism | New Files |
|-------------|-------------|-----------|-----------|
| Lab TTL config | `Lab-Config.ps1` | New `TTL` hashtable block | — |
| TTL monitor logic | `Private/` | New helper functions | `Get-LabTTLConfig.ps1`, `Test-LabTTLExpired.ps1`, `Invoke-LabTTLAction.ps1`, `Invoke-LabTTLMonitor.ps1` |
| TTL public API | `Public/` | New cmdlets | `Register-LabTTLTask.ps1`, `Unregister-LabTTLTask.ps1` |
| STIG config | `Lab-Config.ps1` | New `STIG` hashtable block | — |
| STIG apply | `Private/` | New helper | `Invoke-LabApplySTIG.ps1`, `Get-LabSTIGConfig.ps1` |
| STIG compliance cache | `.planning/` | JSON file written at apply time | `.planning/stig-compliance.json` |
| STIG PostInstall hook | `LabBuilder/Roles/DC.ps1` | Modified existing PostInstall | — |
| ADMX config | `Lab-Config.ps1` | New `ADMX` hashtable block | — |
| ADMX import | `Private/` | New helper | `Invoke-LabADMXImport.ps1` |
| ADMX PostInstall hook | `LabBuilder/Roles/DC.ps1` | Modified existing PostInstall | — |
| Enriched status | `Private/` | New helper | `Get-LabEnrichedStatus.ps1` |
| `Get-LabStatus -Enriched` | `Public/Get-LabStatus.ps1` | Modified, backward-compat | — |
| Dashboard XAML | `GUI/Views/DashboardView.xaml` | Modified | — |
| VMCard enrichment | `GUI/Components/VMCard.xaml` | Modified | — |
| GUI enrichment timer | `GUI/Start-OpenCodeLabGUI.ps1` | Modified `Initialize-DashboardView` | — |

---

## Sources

- [PowerSTIG GitHub Repository](https://github.com/microsoft/PowerStig) — composite DSC resource names, PS Gallery install (HIGH)
- [PowerSTIG Getting Started Wiki](https://github.com/microsoft/PowerStig/wiki/GettingStarted) — dependency install pattern (MEDIUM)
- [Register-ScheduledTask - Microsoft Docs](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask?view=windowsserver2025-ps) — PS 5.1 scheduled task API (HIGH)
- [Suspend-VM - Microsoft Docs](https://learn.microsoft.com/en-us/powershell/module/hyper-v/suspend-vm?view=windowsserver2025-ps) — Save State action (HIGH)
- [Group Policy Central Store - Microsoft Docs](https://learn.microsoft.com/en-us/troubleshoot/windows-client/group-policy/create-and-manage-central-store) — ADMX Central Store UNC path and copy procedure (HIGH)
- [ADMX templates via PowerShell - woshub.com](https://woshub.com/install-update-group-policy-administrative-templates-admx/) — ADMX copy automation patterns (MEDIUM)
- Existing `LabBuilder/Roles/DSCPullServer.ps1` — proven gallery-install-on-target pattern (HIGH, first-party)
- Existing `Private/Get-LabSnapshotInventory.ps1` — snapshot data shape used by enriched status (HIGH, first-party)
- Existing `GUI/Start-OpenCodeLabGUI.ps1` — DispatcherTimer pattern for two-timer approach (HIGH, first-party)

---

*Architecture research for: AutomatedLab v1.6 — Lab lifecycle & security automation integration*
*Researched: 2026-02-20*

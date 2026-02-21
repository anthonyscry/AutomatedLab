# Phase 26: Lab TTL & Lifecycle Monitoring - Research

**Researched:** 2026-02-20
**Domain:** PowerShell Scheduled Tasks + Hyper-V VM State Management
**Confidence:** HIGH

## Summary

Phase 26 adds TTL (Time-To-Live) auto-suspension to the lab. The operator configures a TTL block in Lab-Config.ps1, a Windows Scheduled Task polls every 5 minutes, and when either wall-clock or idle threshold is exceeded the task saves/stops all lab VMs. A public Get-LabUptime cmdlet provides real-time TTL status.

All required APIs are mature Windows/Hyper-V PowerShell cmdlets available since Windows Server 2016 and Windows 10. The project already has a reference implementation for the audit-trail pattern (Invoke-LabQuickModeHeal) and config-guard pattern (ContainsKey checks throughout Lab-Config.ps1). No third-party libraries are needed.

**Primary recommendation:** Follow the Invoke-LabQuickModeHeal pattern exactly for Invoke-LabTTLMonitor (try-catch, audit PSCustomObject return, duration tracking) and mirror the AutoHeal config block style for the new TTL block.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Add `TTL = @{...}` block to `$GlobalLabConfig` in Lab-Config.ps1, positioned after the existing `AutoHeal` block (~line 206)
- Keys: `Enabled` (bool, default `$false`), `IdleMinutes` (int, default 0 = disabled), `WallClockHours` (int, default 8), `Action` (string, 'Suspend' or 'Off', default 'Suspend')
- Every key gets an inline comment explaining what it controls (matches existing Lab-Config.ps1 style)
- All reads use `ContainsKey` guards to prevent StrictMode failures when keys are absent
- Feature is disabled by default (`Enabled = $false`) — operator must explicitly opt in
- Task name: `OpenCodeLab-TTLMonitor` (matches project naming convention)
- `Register-LabTTLTask` is idempotent: unregister-then-register pattern (no duplicate task error)
- Task runs under SYSTEM context
- Trigger: RepetitionInterval of 5 minutes
- Action: Invokes `Invoke-LabTTLMonitor` PowerShell script
- `Unregister-LabTTLTask` called during lab teardown (Remove-Lab path) to clean up orphaned tasks
- `Invoke-LabTTLMonitor` is a Private/ helper following the Invoke-LabQuickModeHeal pattern
- WallClockHours: Compares elapsed time since lab deployment start against configured limit
- IdleMinutes: Uses Hyper-V VM uptime as proxy (not RDP session detection)
- Either trigger (wall clock OR idle) causes TTL expiry — whichever fires first
- On expiry: iterates all lab VMs and applies configured Action (Save-VM for Suspend, Stop-VM for Off)
- Returns audit result object: `TTLExpired`, `ActionAttempted`, `ActionSucceeded`, `VMsProcessed`, `RemainingIssues`, `DurationSeconds`
- Writes state to `.planning/lab-ttl-state.json` after each check (cache-on-write pattern)
- `Get-LabUptime` is a Public/ function returning `[PSCustomObject]`
- Output fields: `LabName`, `StartTime`, `ElapsedHours` (rounded to 1 decimal), `TTLConfigured` (bool), `TTLRemainingMinutes` (int, -1 if no TTL), `Action`, `Status` ('Active'|'Expired'|'Suspended'|'Disabled')
- TTL state cached to `.planning/lab-ttl-state.json`
- Schema: `LabName`, `LastChecked` (ISO 8601), `StartTime` (ISO 8601), `TTLExpired` (bool), `VMStates` (hashtable of VM name to state string)

### Claude's Discretion
- Exact error message wording for TTL expiry warnings
- Whether to use Write-Warning or Write-Verbose for monitor logging
- Internal helper decomposition (single function vs split into config-reader + monitor + action-executor)
- JSON schema details beyond the documented fields

### Deferred Ideas (OUT OF SCOPE)
- Grace period notification before auto-suspend — TTL-V2-02
- Snooze/extend TTL from CLI or GUI — TTL-V2-01
- Per-lab TTL override for multi-lab scenarios — TTL-V2-03
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TTL-01 | Operator can configure lab TTL duration in Lab-Config.ps1 (hours, with safe defaults) | Config block pattern mirrors existing AutoHeal block; ContainsKey guards proven in codebase |
| TTL-02 | Background scheduled task auto-suspends all lab VMs when TTL expires | Register-ScheduledTask + New-ScheduledTaskTrigger -Once -RepetitionInterval confirmed; Save-VM/Stop-VM cmdlets documented |
| TTL-03 | Lab uptime is tracked and queryable via Get-LabUptime cmdlet | Get-VM provides Uptime property; cache-on-write JSON pattern matches project conventions |
</phase_requirements>

## Standard Stack

### Core
| Library/Module | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| ScheduledTasks module | Built-in (Win10/Server 2016+) | Register/Unregister scheduled tasks | Native Windows PowerShell module, no install needed |
| Hyper-V module | Built-in (Win10 Pro/Enterprise/Server) | Get-VM, Save-VM, Stop-VM | Already used throughout project |
| ConvertTo-Json / ConvertFrom-Json | Built-in | State persistence | Already used in project for JSON cache files |

### Supporting
| Library/Module | Version | Purpose | When to Use |
|----------------|---------|---------|-------------|
| Microsoft.PowerShell.Utility | Built-in | New-TimeSpan, Get-Date | Time arithmetic for TTL comparison |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Scheduled Task | PowerShell background job | Jobs die with session; task survives reboot |
| Scheduled Task | Timer-based runspace | Complex, dies with process, not persistent |
| VM Uptime proxy for idle | RDP session enumeration | Requires WinRM into each guest, unreliable |

## Architecture Patterns

### Recommended File Layout
```
Private/
├── Invoke-LabTTLMonitor.ps1       # Core monitor logic (audit-trail pattern)
├── Register-LabTTLTask.ps1        # Task registration (idempotent)
├── Unregister-LabTTLTask.ps1      # Task cleanup (idempotent)
├── Get-LabTTLConfig.ps1           # Config reader with ContainsKey guards
Public/
├── Get-LabUptime.ps1              # Uptime query (PSCustomObject output)
Tests/
├── LabTTL.Tests.ps1               # All TTL unit tests
```

All Private/ helpers are auto-discovered by Lab-Common.ps1 (no manual registration).

### Pattern 1: Audit-Trail Return Object (from Invoke-LabQuickModeHeal)
**What:** Every action function returns a structured PSCustomObject with success/failure/duration/details
**When to use:** All TTL functions that perform actions
**Example:**
```powershell
# Matches Invoke-LabQuickModeHeal pattern exactly
return [pscustomobject]@{
    TTLExpired       = $expired
    ActionAttempted  = $actionName
    ActionSucceeded  = ($remaining.Count -eq 0)
    VMsProcessed     = @($processed)
    RemainingIssues  = @($remaining)
    DurationSeconds  = [int]((Get-Date) - $startTime).TotalSeconds
}
```

### Pattern 2: ContainsKey Config Guard
**What:** Every config read uses `.ContainsKey()` to prevent StrictMode failures
**When to use:** All reads from `$GlobalLabConfig.TTL`
**Example:**
```powershell
$ttlBlock = if (Test-Path variable:GlobalLabConfig) {
    $GlobalLabConfig.TTL
} else { @{} }

$enabled = if ($ttlBlock.ContainsKey('Enabled')) { [bool]$ttlBlock.Enabled } else { $false }
$wallClockHours = if ($ttlBlock.ContainsKey('WallClockHours')) { [int]$ttlBlock.WallClockHours } else { 8 }
$idleMinutes = if ($ttlBlock.ContainsKey('IdleMinutes')) { [int]$ttlBlock.IdleMinutes } else { 0 }
$action = if ($ttlBlock.ContainsKey('Action')) { [string]$ttlBlock.Action } else { 'Suspend' }
```

### Pattern 3: Idempotent Scheduled Task Registration
**What:** Unregister-then-register pattern for task creation
**When to use:** Register-LabTTLTask
**Example:**
```powershell
# Source: https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/
$taskName = 'OpenCodeLab-TTLMonitor'

# Idempotent: remove existing first (no error if absent)
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 5) `
    -RepetitionDuration ([TimeSpan]::MaxValue)

$scriptBlock = "Import-Module '$modulePath'; Invoke-LabTTLMonitor"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -NonInteractive -Command `"$scriptBlock`""

$principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' `
    -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName $taskName -Trigger $trigger `
    -Action $action -Principal $principal -Description 'OpenCodeLab TTL Monitor'
```

### Pattern 4: Cache-on-Write State
**What:** Write state JSON after every monitor check so Get-LabUptime can read cached data
**When to use:** End of Invoke-LabTTLMonitor
**Example:**
```powershell
$state = @{
    LabName     = $labName
    LastChecked = (Get-Date).ToString('o')
    StartTime   = $startTime.ToString('o')
    TTLExpired  = $expired
    VMStates    = $vmStates
}
$state | ConvertTo-Json -Depth 3 | Set-Content -Path $statePath -Encoding UTF8
```

### Anti-Patterns to Avoid
- **Hardcoding VM names:** Always get lab VM list from config/Get-VM, never hardcode
- **Using background jobs instead of scheduled tasks:** Jobs die with the session
- **Polling RDP sessions for idle detection:** Requires WinRM into guests, unreliable
- **Skipping ContainsKey guards:** StrictMode -Version Latest will throw on missing keys
- **Using ternary operator (`? :`):** PS 7+ only, project targets PS 5.1+

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Persistent background monitoring | Custom loop or background job | Windows Scheduled Task | Survives reboot, session close, runs under SYSTEM |
| Time comparison | Manual epoch math | New-TimeSpan / [datetime] subtraction | Built-in, handles DST, leap seconds |
| JSON state persistence | Custom serializer | ConvertTo-Json + Set-Content | Built-in, matches project pattern |
| VM state management | Custom WMI calls | Get-VM, Save-VM, Stop-VM | Native Hyper-V cmdlets, error handling included |

**Key insight:** Every component of this phase has a native PowerShell cmdlet. No custom infrastructure needed.

## Common Pitfalls

### Pitfall 1: RepetitionInterval Requires RepetitionDuration
**What goes wrong:** Task creation fails or trigger doesn't repeat
**Why it happens:** `New-ScheduledTaskTrigger -Once -RepetitionInterval` silently requires `-RepetitionDuration`
**How to avoid:** Always pair `-RepetitionInterval (New-TimeSpan -Minutes 5)` with `-RepetitionDuration ([TimeSpan]::MaxValue)` for indefinite repetition
**Warning signs:** Task shows in Task Scheduler but "Triggers" column shows "At [time]" without repetition

### Pitfall 2: Save-VM Fails on Already-Saved VMs
**What goes wrong:** Error when trying to save a VM that's already in SavedState
**Why it happens:** Save-VM throws if VM is not Running
**How to avoid:** Filter VMs by state before action: `Get-VM | Where-Object { $_.State -eq 'Running' }`
**Warning signs:** RemainingIssues contains VM names that were already saved

### Pitfall 3: Stop-VM Default is Graceful Shutdown (Not TurnOff)
**What goes wrong:** Stop-VM hangs waiting for guest OS to respond
**Why it happens:** Default behavior sends shutdown signal and waits; unresponsive guests block forever
**How to avoid:** Use `-Force` parameter with Stop-VM for lab environments, or set a reasonable timeout. Do NOT use `-TurnOff` (equivalent to power yank — can corrupt OS)
**Warning signs:** Monitor function appears to hang; scheduled task runs longer than expected

### Pitfall 4: Scheduled Task Action Path Quoting
**What goes wrong:** Scheduled task fails silently because path to script has spaces
**Why it happens:** Task Scheduler argument parsing differs from PowerShell
**How to avoid:** Use `-Execute 'powershell.exe'` with `-Argument` containing the full command; wrap paths in escaped quotes
**Warning signs:** Task "runs" (shows success in history) but nothing happens

### Pitfall 5: StrictMode + Missing Config Keys
**What goes wrong:** `PropertyNotFoundException` when reading TTL config keys that don't exist
**Why it happens:** `Set-StrictMode -Version Latest` makes property access on missing keys throw
**How to avoid:** Always use `$hashtable.ContainsKey('Key')` before reading, or `Test-Path variable:` for variables
**Warning signs:** Function crashes on first config read in fresh install

### Pitfall 6: Get-VM Returns Nothing Under SYSTEM Context
**What goes wrong:** Scheduled task runs fine but finds no VMs
**Why it happens:** SYSTEM has access to Hyper-V but VM naming or filtering may differ
**How to avoid:** Use `Get-VM` without name filter first, then filter by lab naming convention; ensure Hyper-V management tools are accessible to SYSTEM
**Warning signs:** Monitor reports "0 VMs processed" in state JSON

## Code Examples

### Reading TTL Config with Guards
```powershell
function Get-LabTTLConfig {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $defaults = @{
        Enabled        = $false
        IdleMinutes    = 0
        WallClockHours = 8
        Action         = 'Suspend'
    }

    $ttlBlock = if (Test-Path variable:GlobalLabConfig) {
        if ($GlobalLabConfig.ContainsKey('TTL')) { $GlobalLabConfig.TTL } else { @{} }
    } else { @{} }

    [pscustomobject]@{
        Enabled        = if ($ttlBlock.ContainsKey('Enabled'))        { [bool]$ttlBlock.Enabled }        else { $defaults.Enabled }
        IdleMinutes    = if ($ttlBlock.ContainsKey('IdleMinutes'))    { [int]$ttlBlock.IdleMinutes }      else { $defaults.IdleMinutes }
        WallClockHours = if ($ttlBlock.ContainsKey('WallClockHours')) { [int]$ttlBlock.WallClockHours }   else { $defaults.WallClockHours }
        Action         = if ($ttlBlock.ContainsKey('Action'))         { [string]$ttlBlock.Action }        else { $defaults.Action }
    }
}
```

### Checking Wall-Clock TTL Expiry
```powershell
$elapsed = (Get-Date) - [datetime]$state.StartTime
$wallClockExpired = ($config.WallClockHours -gt 0) -and ($elapsed.TotalHours -ge $config.WallClockHours)
```

### Checking Idle TTL Expiry (VM Uptime Proxy)
```powershell
# VM Uptime resets when VM resumes from saved state or restarts
# If ALL VMs have been up for less than IdleMinutes, lab is "idle"
# This is a proxy — not true user-session idle, but sufficient for lab use
$allIdle = $true
foreach ($vm in $labVMs) {
    if ($vm.State -eq 'Running' -and $vm.Uptime.TotalMinutes -gt $config.IdleMinutes) {
        $allIdle = $false
        break
    }
}
$idleExpired = ($config.IdleMinutes -gt 0) -and $allIdle
```
Note: The idle detection logic uses VM uptime as a proxy. A VM that has been running continuously for longer than IdleMinutes is considered "not idle." This is inverted from typical idle detection — when all VMs have short uptimes (recent restart/resume), the lab was recently active. When VMs have been running untouched for a long time, that indicates idle. The actual implementation should compare current time minus last known activity, not raw VM uptime.

### Applying TTL Action to VMs
```powershell
foreach ($vm in $runningVMs) {
    try {
        if ($config.Action -eq 'Suspend') {
            Save-VM -Name $vm.Name -ErrorAction Stop
        } else {
            Stop-VM -Name $vm.Name -Force -ErrorAction Stop
        }
        $processed.Add($vm.Name)
    }
    catch {
        Write-Warning "[TTLMonitor] Failed to $($config.Action) VM '$($vm.Name)': $($_.Exception.Message)"
        $remaining.Add("$($vm.Name)_action_failed")
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual lab shutdown | TTL-based auto-suspend | This phase | Prevents resource waste from forgotten labs |
| PowerShell background jobs for monitoring | Windows Scheduled Tasks | Established best practice | Survives session termination and reboots |
| COM-based task scheduler API | ScheduledTasks PowerShell module | PowerShell 4.0+ / Win8.1+ | Clean cmdlet interface, no COM interop |

## Open Questions

1. **Lab start time source**
   - What we know: Need a timestamp for when the lab was deployed/started
   - What's unclear: Where is lab start time currently persisted? Is there an existing deploy timestamp in run-logs or elsewhere?
   - Recommendation: Check for existing timestamp in run-logs JSON. If none, write StartTime to lab-ttl-state.json on first Register-LabTTLTask call or first monitor invocation.

2. **Module path for scheduled task action**
   - What we know: Scheduled task runs under SYSTEM and needs to invoke Invoke-LabTTLMonitor
   - What's unclear: How does SYSTEM find the module? Lab-Common.ps1 auto-discovers Private/ helpers, but the scheduled task needs to dot-source or import.
   - Recommendation: Have Register-LabTTLTask bake the absolute path to the project root into the scheduled task action. Use `$PSScriptRoot` at registration time, persist into task command.

## Sources

### Primary (HIGH confidence)
- [New-ScheduledTaskTrigger - Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasktrigger?view=windowsserver2025-ps) — RepetitionInterval, RepetitionDuration parameters
- [Stop-VM - Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/hyper-v/stop-vm?view=windowsserver2025-ps) — -Force, -TurnOff behavior
- Project codebase: `Private/Invoke-LabQuickModeHeal.ps1` — audit-trail return pattern
- Project codebase: `Lab-Config.ps1` lines 199-206 — AutoHeal config block pattern
- Project codebase: `Public/Reset-Lab.ps1` — teardown flow where Unregister-LabTTLTask hooks in

### Secondary (MEDIUM confidence)
- [PDQ - How to schedule tasks using PowerShell](https://www.pdq.com/blog/scheduled-tasks-in-powershell/) — end-to-end scheduled task examples
- [Microsoft Q&A - RepetitionInterval with AtLogon/AtStartup](https://learn.microsoft.com/en-us/answers/questions/573477/powershell-new-scheduledtasktrigger-cmdlet-atlogon) — workaround for trigger types that don't natively support repetition

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all native Windows/PowerShell cmdlets, no third-party dependencies
- Architecture: HIGH — mirrors existing project patterns (Invoke-LabQuickModeHeal, AutoHeal config block)
- Pitfalls: HIGH — well-documented Windows Scheduled Task and Hyper-V gotchas, confirmed via Microsoft docs

**Research date:** 2026-02-20
**Valid until:** 2026-03-20 (stable Windows APIs, unlikely to change)

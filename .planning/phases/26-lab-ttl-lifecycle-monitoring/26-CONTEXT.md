# Phase 26: Lab TTL & Lifecycle Monitoring - Context

**Gathered:** 2026-02-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Operators configure a TTL for the lab in Lab-Config.ps1 and have VMs auto-suspended by a Windows Scheduled Task when the TTL expires. Lab uptime is queryable at any time via Get-LabUptime. This phase does NOT include grace-period notifications, snooze/extend, per-lab overrides, or auto-teardown (destroy).

</domain>

<decisions>
## Implementation Decisions

### TTL Configuration Block
- Add `TTL = @{...}` block to `$GlobalLabConfig` in Lab-Config.ps1, positioned after the existing `AutoHeal` block (~line 206)
- Keys: `Enabled` (bool, default `$false`), `IdleMinutes` (int, default 0 = disabled), `WallClockHours` (int, default 8), `Action` (string, 'Suspend' or 'Off', default 'Suspend')
- Every key gets an inline comment explaining what it controls (matches existing Lab-Config.ps1 style)
- All reads use `ContainsKey` guards to prevent StrictMode failures when keys are absent
- Feature is disabled by default (`Enabled = $false`) — operator must explicitly opt in

### Scheduled Task Design
- Task name: `OpenCodeLab-TTLMonitor` (matches project naming convention)
- `Register-LabTTLTask` is idempotent: unregister-then-register pattern (no duplicate task errors)
- Task runs under SYSTEM context (as specified in success criteria)
- Trigger: RepetitionInterval of 5 minutes (frequent enough to catch TTL within reasonable window, not so frequent as to waste resources)
- Action: Invokes `Invoke-LabTTLMonitor` PowerShell script
- `Unregister-LabTTLTask` called during lab teardown (Remove-Lab path) to clean up orphaned tasks

### TTL Monitor Behavior
- `Invoke-LabTTLMonitor` is a Private/ helper following the Invoke-LabQuickModeHeal pattern
- Reads TTL config with ContainsKey guards, exits early if disabled
- WallClockHours: Compares elapsed time since lab deployment start against configured limit
- IdleMinutes: Checks if all lab VMs have been idle (no active console sessions) for the configured duration — uses Hyper-V VM uptime as proxy (not RDP session detection, which is unreliable)
- Either trigger (wall clock OR idle) causes TTL expiry — whichever fires first
- On expiry: iterates all lab VMs and applies configured Action (Save-VM for Suspend, Stop-VM for Off)
- Returns audit result object: `TTLExpired`, `ActionAttempted`, `ActionSucceeded`, `VMsProcessed`, `RemainingIssues`, `DurationSeconds`
- Writes state to `.planning/lab-ttl-state.json` after each check (cache-on-write pattern)

### Uptime Query Function
- `Get-LabUptime` is a Public/ function returning `[PSCustomObject]`
- Output fields: `LabName`, `StartTime`, `ElapsedHours` (rounded to 1 decimal), `TTLConfigured` (bool), `TTLRemainingMinutes` (int, -1 if no TTL), `Action`, `Status` ('Active'|'Expired'|'Suspended'|'Disabled')
- Reads from cached state JSON when available, falls back to live VM query
- Returns empty array `@()` if no lab is running (standard pattern)

### State Persistence
- TTL state cached to `.planning/lab-ttl-state.json` (matches project pattern for runtime data in .planning/)
- Schema: `LabName`, `LastChecked` (ISO 8601), `StartTime` (ISO 8601), `TTLExpired` (bool), `VMStates` (hashtable of VM name to state string)
- Dashboard (Phase 29) will consume this file — no live polling needed

### Claude's Discretion
- Exact error message wording for TTL expiry warnings
- Whether to use Write-Warning or Write-Verbose for monitor logging
- Internal helper decomposition (single function vs split into config-reader + monitor + action-executor)
- JSON schema details beyond the documented fields

</decisions>

<specifics>
## Specific Ideas

- Follow Invoke-LabQuickModeHeal exactly for the try-catch + audit-trail pattern (repairs array, remaining issues array, duration tracking)
- Register/Unregister pattern should mirror how Windows Scheduled Tasks work natively — no wrapper complexity
- IdleMinutes detection via Hyper-V VM uptime is a pragmatic choice — avoids needing RDP session enumeration which requires WinRM into each guest
- The 5-minute check interval balances responsiveness with resource overhead for a lab environment

</specifics>

<deferred>
## Deferred Ideas

- Grace period notification before auto-suspend — TTL-V2-02 in future requirements
- Snooze/extend TTL from CLI or GUI — TTL-V2-01 in future requirements
- Per-lab TTL override for multi-lab scenarios — TTL-V2-03 in future requirements

</deferred>

---

*Phase: 26-lab-ttl-lifecycle-monitoring*
*Context gathered: 2026-02-20*

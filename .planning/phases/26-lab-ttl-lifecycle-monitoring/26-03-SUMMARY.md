# Plan 26-03: TTL Monitor, Uptime Query, Teardown — Summary

**Status:** Complete
**Completed:** 2026-02-20

## What Was Built

Implemented the core TTL monitoring pipeline: threshold checking (wall-clock and idle), VM action enforcement (Save-VM/Stop-VM), state caching to JSON, uptime query function, and teardown integration.

## Key Outcomes

- Invoke-LabTTLMonitor checks wall-clock AND idle thresholds (either fires first)
- Applies Save-VM (Suspend) or Stop-VM -Force (Off) based on configured Action
- Writes state to .planning/lab-ttl-state.json after every check (cache-on-write)
- Get-LabUptime returns LabName, StartTime, ElapsedHours, TTLConfigured, TTLRemainingMinutes, Action, Status
- Get-LabUptime returns empty array when no VMs running
- Reset-Lab calls Unregister-LabTTLTask during teardown (Step 4.5)
- Graceful error handling: failed VM actions recorded in RemainingIssues, continues to next VM

## Self-Check: PASSED

- [x] Wall-clock expiry detected correctly
- [x] Idle expiry detected correctly
- [x] Either trigger causes action
- [x] State JSON written after each check
- [x] Get-LabUptime reads cached state
- [x] Reset-Lab calls Unregister-LabTTLTask
- [x] 13/13 monitor tests passing
- [x] 10/10 uptime tests passing

## Key Files

### Created
- `Private/Invoke-LabTTLMonitor.ps1` — TTL check and enforcement
- `Public/Get-LabUptime.ps1` — Lab uptime and TTL status query
- `Tests/LabTTLMonitor.Tests.ps1` — 13 unit tests
- `Tests/LabUptime.Tests.ps1` — 10 unit tests

### Modified
- `Public/Reset-Lab.ps1` — Added Unregister-LabTTLTask teardown hook

## Test Results

```
Monitor: Tests Passed: 13, Failed: 0
Uptime:  Tests Passed: 10, Failed: 0
Total:   23 tests passing
```

## Commits

1. `feat(26-03): add Invoke-LabTTLMonitor with audit trail`
2. `feat(26-03): add Get-LabUptime and teardown TTL hook`

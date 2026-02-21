---
status: passed
phase: 26
verified: 2026-02-20
---

# Phase 26: Lab TTL & Lifecycle Monitoring — Verification

## Goal

Operators can configure a TTL for the lab and have VMs auto-suspended by a background scheduled task when the TTL expires, with lab uptime queryable at any time.

## Requirements Coverage

| ID | Description | Status | Evidence |
|----|-------------|--------|----------|
| TTL-01 | Operator can configure lab TTL duration in Lab-Config.ps1 | PASS | TTL block at line 208 with 4 keys + inline comments |
| TTL-02 | Background scheduled task auto-suspends all lab VMs when TTL expires | PASS | Register-LabTTLTask + Invoke-LabTTLMonitor with Save-VM/Stop-VM |
| TTL-03 | Lab uptime is tracked and queryable via Get-LabUptime cmdlet | PASS | Get-LabUptime returns 7-field PSCustomObject |

## Success Criteria Verification

### SC1: Config with ContainsKey Guards
- [x] TTL block in Lab-Config.ps1 with Enabled, IdleMinutes, WallClockHours, Action
- [x] Get-LabTTLConfig uses ContainsKey guards on every read
- [x] 7 tests confirm StrictMode safety

### SC2: Idempotent Scheduled Task
- [x] Register-LabTTLTask creates OpenCodeLab-TTLMonitor task
- [x] Unregister-then-register pattern for idempotency
- [x] SYSTEM context, 5-minute RepetitionInterval
- [x] 8 tests for registration, 4 for unregistration

### SC3: TTL Expiry Suspends/Stops VMs
- [x] Wall-clock and idle threshold detection
- [x] Either trigger fires first
- [x] Save-VM for Suspend action, Stop-VM -Force for Off action
- [x] Skips non-Running VMs
- [x] 13 monitor tests including edge cases

### SC4: Get-LabUptime Returns Status
- [x] Returns LabName, StartTime, ElapsedHours, TTLConfigured, TTLRemainingMinutes, Action, Status
- [x] ElapsedHours rounded to 1 decimal
- [x] TTLRemainingMinutes = -1 when unconfigured
- [x] Status: Active | Expired | Disabled
- [x] 10 uptime tests

### SC5: Teardown Cleanup
- [x] Reset-Lab calls Unregister-LabTTLTask (Step 4.5)
- [x] Unregister-LabTTLTask is idempotent (no error if task absent)

## Test Results

```
42 tests passing across 4 test files:
- LabTTLConfig.Tests.ps1:    7 tests
- LabTTLTask.Tests.ps1:     12 tests
- LabTTLMonitor.Tests.ps1:  13 tests
- LabUptime.Tests.ps1:      10 tests
```

## Artifacts Created

| File | Purpose |
|------|---------|
| Lab-Config.ps1 (modified) | TTL config block |
| Private/Get-LabTTLConfig.ps1 | Safe config reader |
| Private/Register-LabTTLTask.ps1 | Task registration |
| Private/Unregister-LabTTLTask.ps1 | Task removal |
| Private/Invoke-LabTTLMonitor.ps1 | Monitor logic |
| Public/Get-LabUptime.ps1 | Uptime query |
| Public/Reset-Lab.ps1 (modified) | Teardown hook |
| Tests/LabTTLConfig.Tests.ps1 | 7 tests |
| Tests/LabTTLTask.Tests.ps1 | 12 tests |
| Tests/LabTTLMonitor.Tests.ps1 | 13 tests |
| Tests/LabUptime.Tests.ps1 | 10 tests |

## Conclusion

Phase 26 goal achieved. All 3 requirements (TTL-01, TTL-02, TTL-03) covered. All 5 success criteria met. 42 tests passing.

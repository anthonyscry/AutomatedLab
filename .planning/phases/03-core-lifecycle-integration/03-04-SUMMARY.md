---
phase: 03-core-lifecycle-integration
plan: 04
subsystem: core-lifecycle
tags: [teardown, idempotency, confirmation, testing]
dependency_graph:
  requires: [LIFE-04, LIFE-05, CLI-07, CLI-03]
  provides: [LIFE-06]
  affects: [lifecycle-teardown, lifecycle-bootstrap]
tech_stack:
  added: []
  patterns: [idempotent-bootstrap, confirmation-gates, ssh-cleanup]
key_files:
  created:
    - Tests/TeardownIdempotency.Tests.ps1
  modified:
    - OpenCodeLab-App.ps1
decisions:
  - title: "SSH known_hosts cleanup during teardown"
    rationale: "Stale SSH host keys cause 'REMOTE HOST IDENTIFICATION HAS CHANGED' errors on redeploy. Cleaning known_hosts during teardown prevents this friction."
    impact: "Re-deploy after teardown succeeds without host key errors. Users don't need to manually delete .ssh/known_hosts."
  - title: "NAT removal verification"
    rationale: "Remove-NetNat can silently fail. Verification step catches this and warns user to investigate."
    impact: "Better visibility into teardown completeness, prevents network conflicts on rebuild."
  - title: "Confirmation gates on destructive actions"
    rationale: "Direct `-Action one-button-reset` calls bypassed confirmation prompt. Force/NonInteractive flags now control bypass behavior."
    impact: "Consistent confirmation UX across menu and CLI invocations. Prevents accidental lab destruction."
metrics:
  duration_minutes: 3.7
  tasks_completed: 2
  files_changed: 2
  tests_added: 10
  completed_at: "2026-02-16T23:54:28Z"
---

# Phase 3 Plan 4: Teardown Hardening & Bootstrap Idempotency Summary

Hardened teardown to clean SSH known_hosts, added confirmation gates to destructive actions, and validated Bootstrap.ps1 idempotency with comprehensive tests.

## What Was Done

### Task 1: Harden Teardown and Add Confirmation Gates (commit 2689dbe)

**SSH known_hosts cleanup in Invoke-BlowAway:**
- Added `Clear-LabSSHKnownHosts` call in step [4b/5] after lab file removal
- Wrapped in try/catch with WARN status on failure
- Added "Would clear SSH known_hosts entries" to Simulate mode output
- Prevents "REMOTE HOST IDENTIFICATION HAS CHANGED" errors on redeploy

**NAT removal verification:**
- Added verification check after `Remove-NetNat` command
- Checks if NAT still exists after removal attempt
- Emits WARN status if NAT persists
- Helps diagnose silent removal failures

**Confirmation gate consistency:**
- Modified `Invoke-OneButtonReset` to respect `-Force` and `-NonInteractive` flags
- Changed from always bypassing prompt to conditional bypass: `$shouldBypassPrompt = $Force -or $NonInteractive`
- Menu path (Type "REBUILD") still works as before
- Direct CLI calls (`-Action one-button-reset`) now require typed confirmation unless flags set

### Task 2: Validate Idempotency and Add Tests (commit 73c0b3f)

**Bootstrap.ps1 idempotency validation:**
- Reviewed all 10 bootstrap steps
- Step 1 (NuGet): Already idempotent (version check)
- Step 2 (Pester): Already idempotent (version check)
- Step 3 (PSFramework): Already idempotent (`Get-Module -ListAvailable`)
- Step 4 (SHiPS): Already idempotent (`Get-Module -ListAvailable`)
- Step 5 (AutomatedLab): Already idempotent (`Get-Module -ListAvailable`)
- Step 6 (LabSources): Already idempotent (`Test-Path` before `New-Item`)
- Step 7 (Hyper-V): Already idempotent (state check)
- Step 8 (vSwitch+NAT): Already idempotent (Get-VMSwitch/Get-NetNat checks)
- Step 9 (ISOs): Read-only validation
- No code changes needed - Bootstrap.ps1 already implements best practices

**Tests/TeardownIdempotency.Tests.ps1 (new file):**
Created comprehensive Pester 5 test suite with 10 tests across 3 contexts:

**Invoke-BlowAway teardown completeness (3 tests):**
- Function contains Clear-LabSSHKnownHosts call
- Simulate mode includes SSH cleanup step
- NAT removal includes verification check

**Bootstrap.ps1 idempotency (6 tests):**
- PSFramework module idempotency check exists
- SHiPS module idempotency check exists
- AutomatedLab module idempotency check exists
- vSwitch creation checks for existing switch
- NAT creation checks for existing NAT
- Folder creation checks for existing folders

**Invoke-OneButtonReset confirmation gates (1 test):**
- Requires confirmation unless Force or NonInteractive set

All 10 tests pass.

## Verification Results

### Teardown SSH Cleanup
```bash
grep -n "Clear-LabSSHKnownHosts" OpenCodeLab-App.ps1
# Result: 2 matches (function call + simulate mode message)
```

### NAT Removal Verification
```bash
grep -A3 "Remove-NetNat" OpenCodeLab-App.ps1 | grep "natCheck"
# Result: Verification check present after removal
```

### Bootstrap Idempotency
```bash
grep -c "Get-Module -Name PSFramework -ListAvailable" Bootstrap.ps1
# Result: 1 (idempotency check exists)

grep -c "Get-VMSwitch -Name" Bootstrap.ps1
# Result: 1 (vSwitch idempotency check exists)
```

### Test Suite
```bash
Invoke-Pester Tests/TeardownIdempotency.Tests.ps1 -PassThru
# Result: Tests Passed: 10, Failed: 0
```

## Deviations from Plan

None - plan executed exactly as written. Bootstrap.ps1 already had all the idempotency checks the plan called for, so no code changes were needed for that component. Tests validate existing patterns.

## Impact

**Before (teardown issues):**
- SSH known_hosts not cleaned → "REMOTE HOST IDENTIFICATION HAS CHANGED" errors on redeploy
- NAT removal failures went undetected
- Direct `-Action one-button-reset` bypassed confirmation prompt
- No automated validation of teardown completeness

**After (hardened teardown):**
- SSH known_hosts cleaned automatically during teardown
- NAT removal verified and failures logged
- All destructive actions require confirmation unless explicitly bypassed with flags
- 10 tests validate teardown/bootstrap correctness

**Re-deploy after teardown workflow:**
1. `.\OpenCodeLab-App.ps1 -Action blow-away -RemoveNetwork` (Type "BLOW-IT-AWAY")
2. SSH known_hosts cleaned automatically
3. NAT removal verified
4. `.\OpenCodeLab-App.ps1 -Action setup`
5. Bootstrap.ps1 skips already-installed prerequisites
6. No SSH host key errors, no network conflicts

## Files Changed

| File | Lines Changed | Type |
|------|---------------|------|
| OpenCodeLab-App.ps1 | 20 insertions, 1 deletion | feat |
| Tests/TeardownIdempotency.Tests.ps1 | 81 insertions, 0 deletions | new |

**Total:** 2 files, 101 insertions, 1 deletion

## Commits

| Hash | Message | Files |
|------|---------|-------|
| 2689dbe | feat(03-04): harden teardown with SSH cleanup and confirmation gates | OpenCodeLab-App.ps1 |
| 73c0b3f | test(03-04): add teardown and bootstrap idempotency tests | Tests/TeardownIdempotency.Tests.ps1 |

## Self-Check: PASSED

**Created files exist:**
```bash
[ -f "Tests/TeardownIdempotency.Tests.ps1" ] && echo "FOUND"
# Result: FOUND
```

**Modified files verified:**
```bash
git diff 2689dbe^..73c0b3f --name-only | sort
# Result: OpenCodeLab-App.ps1, Tests/TeardownIdempotency.Tests.ps1
```

**Commits exist:**
```bash
git log --oneline --all | grep -E "(2689dbe|73c0b3f)"
# Result: Both commits found in git history
```

All verification checks passed.

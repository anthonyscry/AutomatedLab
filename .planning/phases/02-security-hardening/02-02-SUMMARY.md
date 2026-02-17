---
phase: 02-security-hardening
plan: 02
subsystem: ssh-configuration
tags: [security, ssh, known-hosts, host-key-verification]
dependency_graph:
  requires: [Lab-Config.ps1]
  provides: [SSH.KnownHostsPath, Clear-LabSSHKnownHosts, persistent-host-keys]
  affects: [Private/Linux/Invoke-LinuxSSH.ps1, Private/Linux/Copy-LinuxFile.ps1, Scripts/Test-OpenCodeLabHealth.ps1, Scripts/Install-Ansible.ps1, LabBuilder/Roles/LinuxRoleBase.ps1]
tech_stack:
  added: [lab-specific-known_hosts]
  patterns: [persistent-host-key-storage, directory-guards]
key_files:
  created:
    - Private/Clear-LabSSHKnownHosts.ps1
    - Tests/SSHKnownHosts.Tests.ps1
  modified:
    - Lab-Config.ps1
    - Private/Linux/Invoke-LinuxSSH.ps1
    - Private/Linux/Copy-LinuxFile.ps1
    - Scripts/Test-OpenCodeLabHealth.ps1
    - Scripts/Install-Ansible.ps1
    - LabBuilder/Roles/LinuxRoleBase.ps1
decisions:
  - Use C:\LabSources\SSHKeys\lab_known_hosts as persistent lab-specific known_hosts file
  - Add directory creation guards in Invoke-LinuxSSH and Copy-LinuxFile helpers
  - Preserve StrictHostKeyChecking=accept-new everywhere for first-connection ease
metrics:
  duration: 214 seconds
  tasks_completed: 2
  tests_added: 9
  files_modified: 5
  files_created: 2
  commits: 2
  completed_date: 2026-02-16
---

# Phase 02 Plan 02: SSH Known Hosts Configuration Summary

**One-liner:** Replaced all UserKnownHostsFile=NUL with lab-specific persistent known_hosts file, making StrictHostKeyChecking=accept-new actually detect host key changes on reconnection.

## What Was Built

Implemented a lab-specific persistent SSH known_hosts file to replace the previous /dev/null approach, enabling real host key verification for improved lab security.

### Key Changes

**SSH Configuration (Lab-Config.ps1)**
- Added `SSH.KnownHostsPath` to `$GlobalLabConfig` pointing to `C:\LabSources\SSHKeys\lab_known_hosts`
- Persistent storage allows SSH to detect host key changes between sessions
- Clear documentation on what changes when the path is modified

**Clear-LabSSHKnownHosts Helper**
- Created helper function to remove lab-specific known_hosts file during teardown
- Prevents host key mismatch errors when redeploying with fresh VMs
- Includes null/empty path checks and verbose logging

**SSH/SCP Operation Updates**
- Replaced all 9 instances of `UserKnownHostsFile=NUL` with `$GlobalLabConfig.SSH.KnownHostsPath`
- Added directory creation guards in `Invoke-LinuxSSH` and `Copy-LinuxFile` (ensures SSHKeys directory exists)
- Preserved `StrictHostKeyChecking=accept-new` in all locations for first-connection ease

**Files Updated:**
1. `Private/Linux/Invoke-LinuxSSH.ps1` - SSH command execution (1 instance)
2. `Private/Linux/Copy-LinuxFile.ps1` - SCP file copy (1 instance)
3. `Scripts/Test-OpenCodeLabHealth.ps1` - Health check SSH calls (1 instance)
4. `Scripts/Install-Ansible.ps1` - Ansible deployment SSH/SCP (4 instances)
5. `LabBuilder/Roles/LinuxRoleBase.ps1` - Post-install SSH/SCP (2 instances)

## Testing

Created comprehensive test suite: `Tests/SSHKnownHosts.Tests.ps1`

**9 tests total:**

✓ No UserKnownHostsFile=NUL in codebase (grep-based verification)
✓ GlobalLabConfig.SSH.KnownHostsPath is configured
✓ KnownHostsPath points to SSHKeys/lab_known_hosts
✓ All SSH/SCP files use GlobalLabConfig.SSH.KnownHostsPath
✓ StrictHostKeyChecking=accept-new preserved in all operations
✓ Clear-LabSSHKnownHosts removes file when it exists
✓ Clear-LabSSHKnownHosts is no-op when file doesn't exist (no error)
✓ Clear-LabSSHKnownHosts warns when KnownHostsPath not configured

## Deviations from Plan

None - plan executed exactly as written.

## Verification

All success criteria met:

✓ No file contains UserKnownHostsFile=NUL (verified via grep - zero results outside test file)
✓ All SSH/SCP operations use $GlobalLabConfig.SSH.KnownHostsPath (verified 15 instances)
✓ Clear-LabSSHKnownHosts helper exists for teardown
✓ StrictHostKeyChecking=accept-new preserved everywhere (verified 15 instances)
✓ Directory creation guards added to prevent path-not-found errors
✓ Tests verify configuration and helper behavior

## Files Changed

### Created
- `Private/Clear-LabSSHKnownHosts.ps1` - Teardown helper to clear stale host keys
- `Tests/SSHKnownHosts.Tests.ps1` - 9 tests covering configuration and helper

### Modified
- `Lab-Config.ps1` - Added SSH.KnownHostsPath configuration
- `Private/Linux/Invoke-LinuxSSH.ps1` - Use persistent known_hosts, add directory guard
- `Private/Linux/Copy-LinuxFile.ps1` - Use persistent known_hosts, add directory guard
- `Scripts/Test-OpenCodeLabHealth.ps1` - Use persistent known_hosts in health checks
- `Scripts/Install-Ansible.ps1` - Use persistent known_hosts in all 4 SSH/SCP calls
- `LabBuilder/Roles/LinuxRoleBase.ps1` - Use persistent known_hosts in post-install operations

## Commits

1. `455cc68` - feat(02-02): add SSH config and Clear-LabSSHKnownHosts helper
   - Add SSH.KnownHostsPath to GlobalLabConfig
   - Create Clear-LabSSHKnownHosts teardown helper
   - Known hosts file enables key persistence vs /dev/null

2. `ae5ded4` - feat(02-02): replace all UserKnownHostsFile=NUL with lab-specific known_hosts path
   - Replace UserKnownHostsFile=NUL in 9 locations across 5 files
   - Add directory creation guards in Invoke-LinuxSSH and Copy-LinuxFile
   - Preserve StrictHostKeyChecking=accept-new everywhere
   - Add comprehensive test suite with 9 tests

## Impact

**Security:** SSH operations now use persistent host key storage instead of discarding keys. When a VM is rebuilt or an IP is reused with a different key, SSH will detect the mismatch (instead of silently accepting every "new" connection). This is a real security improvement for the lab environment.

**Usability:** `StrictHostKeyChecking=accept-new` still allows first connections without manual intervention, but subsequent connections verify the key hasn't changed. Teardown helper ensures clean redeploys without manual known_hosts file cleanup.

**Maintainability:** Single source of truth for known_hosts path (`$GlobalLabConfig.SSH.KnownHostsPath`). All 9 SSH/SCP call sites now use the same configuration. Directory guards prevent path-not-found errors on first run.

**Technical Detail:** The previous `UserKnownHostsFile=NUL` approach made `StrictHostKeyChecking=accept-new` ineffective - every connection looked "new" because keys were never stored. With a persistent file, `accept-new` accepts on first connection and verifies on subsequent connections.

## Next Steps

Phase 02 Plan 03 will continue security hardening with additional measures.

## Self-Check: PASSED

✓ FOUND: Private/Clear-LabSSHKnownHosts.ps1
✓ FOUND: Tests/SSHKnownHosts.Tests.ps1
✓ MODIFIED: Lab-Config.ps1 (SSH.KnownHostsPath present)
✓ MODIFIED: Private/Linux/Invoke-LinuxSSH.ps1 (uses GlobalLabConfig.SSH.KnownHostsPath)
✓ MODIFIED: Private/Linux/Copy-LinuxFile.ps1 (uses GlobalLabConfig.SSH.KnownHostsPath)
✓ MODIFIED: Scripts/Test-OpenCodeLabHealth.ps1 (uses GlobalLabConfig.SSH.KnownHostsPath)
✓ MODIFIED: Scripts/Install-Ansible.ps1 (uses GlobalLabConfig.SSH.KnownHostsPath in 4 places)
✓ MODIFIED: LabBuilder/Roles/LinuxRoleBase.ps1 (uses GlobalLabConfig.SSH.KnownHostsPath in 2 places)
✓ FOUND: 455cc68 (Task 1 commit)
✓ FOUND: ae5ded4 (Task 2 commit)
✓ VERIFIED: Zero UserKnownHostsFile=NUL instances outside test file
✓ VERIFIED: 15 StrictHostKeyChecking=accept-new instances preserved

---
phase: 24-linux-vm-parity
plan: "02"
subsystem: LabBuilder/Roles
tags: [linux, ssh, retry, centos, cloud-init, nocloud, pester]
dependency_graph:
  requires:
    - LabBuilder/Roles/LinuxRoleBase.ps1
    - LabBuilder/Roles/Ubuntu.ps1
    - Lab-Config.ps1
  provides:
    - SSH retry with configurable count/delay in Invoke-LinuxRolePostInstall
    - CentOS Stream 9 role via Get-LabRole_CentOS
    - Lab-Config entries for CentOS VM name, IP, RoleMenu, SupportedDistros
  affects:
    - LabBuilder/Roles/LinuxRoleBase.ps1
    - Lab-Config.ps1
tech_stack:
  added:
    - LabBuilder/Roles/CentOS.ps1
    - Tests/LinuxSSHRetry.Tests.ps1
    - Tests/CentOSRole.Tests.ps1
  patterns:
    - Retry while loop with configurable count and delay
    - PSBoundParameters.ContainsKey for parameter default override from config
    - dnf-based post-install for RHEL-family Linux VMs
    - cloud-init NoCloud datasource (same as Rocky9)
key_files:
  created:
    - LabBuilder/Roles/CentOS.ps1
    - Tests/LinuxSSHRetry.Tests.ps1
    - Tests/CentOSRole.Tests.ps1
  modified:
    - LabBuilder/Roles/LinuxRoleBase.ps1
    - Lab-Config.ps1
decisions:
  - PSBoundParameters.ContainsKey used to distinguish explicit RetryCount from default; LabConfig.Timeouts override applies only when parameter not explicitly supplied
  - $env:WINDIR null-guarded (defaults to 'C:\Windows') for cross-platform testability in CI/WSL
  - CentOS post-install uses systemctl enable sshd (not ssh) matching RHEL service naming
  - ISOPattern 'CentOS-Stream-9*.iso' differentiates from Ubuntu - same Invoke-LinuxRoleCreateVM
metrics:
  duration: "7 minutes"
  completed: "2026-02-21"
  tasks_completed: 2
  tasks_total: 2
  files_created: 3
  files_modified: 2
  tests_added: 57
---

# Phase 24 Plan 02: SSH Retry and CentOS Role Support Summary

SSH retry with configurable count/backoff added to Invoke-LinuxRolePostInstall plus new CentOS Stream 9 role using cloud-init NoCloud and dnf package manager.

## What Was Built

**Task 1: SSH Retry in Invoke-LinuxRolePostInstall**

`LabBuilder/Roles/LinuxRoleBase.ps1` now wraps the SCP+SSH execution block in a configurable retry while loop:
- New parameters: `[int]$RetryCount = 3` and `[int]$RetryDelaySeconds = 10`
- Defaults read from `LabConfig.Timeouts.SSHRetryCount` / `LabConfig.Timeouts.SSHRetryDelaySeconds` when not explicitly provided (via `PSBoundParameters.ContainsKey`)
- On failure before last attempt: emits warning with attempt number and schedules `Start-Sleep`
- On final failure: emits warning with total attempt count
- `$env:WINDIR` and `$env:TEMP` null-guarded for cross-platform testability

`Lab-Config.ps1` Builder.Timeouts section now includes:
```powershell
SSHRetryCount = 3
SSHRetryDelaySeconds = 10
```

20 Pester 5 tests in `Tests/LinuxSSHRetry.Tests.ps1` — all pass.

**Task 2: CentOS Role with Cloud-Init NoCloud**

New `LabBuilder/Roles/CentOS.ps1` with `Get-LabRole_CentOS`:
- Follows exact same structure as `Ubuntu.ps1`
- Tag = 'CentOS', VMName from Config.VMNames.CentOS, IsLinux = $true, SkipInstallLab = $true
- OS = 'CentOS Stream 9', ISOPattern = 'CentOS-Stream-9*.iso'
- PostInstall uses `dnf` (not apt-get), enables `sshd` service (RHEL naming)
- Same cloud-init NoCloud datasource as Rocky9 — no changes needed to New-CidataVhdx

`Lab-Config.ps1` additions:
- `Builder.VMNames.CentOS = 'LINCENT1'`
- `Builder.IPPlan.CentOS = '10.0.10.115'`
- `Builder.RoleMenu`: `@{ Tag = 'CentOS'; Label = 'CentOS Stream (LINCENT1)'; Locked = $false }`
- `Builder.SupportedDistros.CentOS9 = @{ DisplayName = 'CentOS Stream 9'; ISOPattern = 'CentOS-Stream-9*.iso'; CloudInit = 'nocloud' }`

37 Pester 5 tests in `Tests/CentOSRole.Tests.ps1` — all pass.

## Commits

| Hash | Description |
|------|-------------|
| be05311 | feat(24-02): add configurable SSH retry to Invoke-LinuxRolePostInstall |
| c1707be | feat(24-02): add CentOS role with cloud-init NoCloud provisioning |

## Test Results

- `Tests/LinuxSSHRetry.Tests.ps1`: 20/20 passed
- `Tests/CentOSRole.Tests.ps1`: 37/37 passed
- `Tests/LabBuilderRoles.Tests.ps1`: 57/57 passed (no regression)
- Combined: 57 new tests, 0 failures

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Null-guarded $env:WINDIR and $env:TEMP in LinuxRoleBase.ps1**
- **Found during:** Task 1 (test authoring)
- **Issue:** `Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'` throws `Cannot bind argument to parameter 'Path' because it is null` on Linux/WSL where `$env:WINDIR` is not set
- **Fix:** Added `$winDir = if ($env:WINDIR) { $env:WINDIR } else { 'C:\Windows' }` and similar for `$env:TEMP` before using them in `Join-Path`
- **Files modified:** `LabBuilder/Roles/LinuxRoleBase.ps1`
- **Commit:** be05311

## Self-Check: PASSED

All files exist:
- LabBuilder/Roles/CentOS.ps1: FOUND
- Tests/LinuxSSHRetry.Tests.ps1: FOUND
- Tests/CentOSRole.Tests.ps1: FOUND
- .planning/phases/24-linux-vm-parity/24-02-SUMMARY.md: FOUND

All commits exist:
- be05311 (SSH retry): FOUND
- c1707be (CentOS role): FOUND

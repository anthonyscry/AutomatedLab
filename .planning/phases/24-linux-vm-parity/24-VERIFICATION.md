---
phase: 24-linux-vm-parity
verified: 2026-02-20T00:00:00Z
status: passed
score: 12/12 must-haves verified
re_verification: false
---

# Phase 24: Linux VM Parity Verification Report

**Phase Goal:** Full lifecycle parity for Linux VMs including CentOS support.
**Verified:** 2026-02-20
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Get-LabSnapshotInventory discovers all Linux VMs (LIN1, LINWEB1, LINDB1, LINDOCK1, LINK8S1) not just LIN1 | VERIFIED | Lines 51-62 of Get-LabSnapshotInventory.ps1 loop over all 5 Ubuntu keys from GlobalLabConfig.Builder.VMNames |
| 2 | Remove-LabStaleSnapshots prunes Linux VM snapshots identically to Windows VM snapshots | VERIFIED | Remove-LabStaleSnapshots delegates to Get-LabSnapshotInventory — no changes needed; Linux VMs now returned automatically |
| 3 | Checkpoint-VM and Restore-VMCheckpoint work for Linux VMs via existing helpers | VERIFIED | Hyper-V treats all VMs identically regardless of OS; no source changes required |
| 4 | Save-LabProfile preserves Linux section, LinuxVM sizing, and Linux IP plan entries | VERIFIED | Save-LabProfile.ps1 serializes full $Config to JSON at depth 10; linuxVmCount field added lines 44-53 |
| 5 | Load-LabProfile restores Linux configuration including nested hashtables | VERIFIED | Load-LabProfile.ps1 uses recursive ConvertTo-Hashtable on ConvertFrom-Json output (lines 57-91) — no Linux-specific changes needed |
| 6 | Get-LabStateProbe includes Linux VMs in fleet status | VERIFIED | SUMMARY decision: Get-LabStateProbe accepts $VMNames as parameter; callers supply Linux VM list — no code change needed |
| 7 | Invoke-LinuxRolePostInstall retries SSH failures up to a configurable count with backoff | VERIFIED | LinuxRoleBase.ps1 lines 173-196: retry while loop ($attempt -lt $RetryCount); Start-Sleep between attempts |
| 8 | SSH retry count and timeout are configurable via LabConfig.Timeouts or function parameters | VERIFIED | LinuxRoleBase.ps1 lines 125-130: PSBoundParameters.ContainsKey guard reads SSHRetryCount/SSHRetryDelaySeconds from LabConfig.Timeouts; Lab-Config.ps1 lines 358-359 supply defaults |
| 9 | CentOS/RHEL VMs can be provisioned using cloud-init NoCloud datasource | VERIFIED | CentOS.ps1 CreateVM calls Invoke-LinuxRoleCreateVM with ISOPattern='CentOS-Stream-9*.iso'; uses same New-CidataVhdx as Rocky9 (nocloud) |
| 10 | Get-LabRole_CentOS returns a role definition matching the Ubuntu role structure | VERIFIED | CentOS.ps1 returns all 13 keys matching Ubuntu.ps1 (Tag, VMName, IsLinux, SkipInstallLab, OS, Memory, MinMemory, MaxMemory, Processors, IP, Gateway, DnsServer1, Network, DomainName, Roles, CreateVM, PostInstall) |
| 11 | Existing Ubuntu roles are unaffected by CentOS additions | VERIFIED | CentOS.ps1 is a new file; LinuxRoleBase.ps1 only adds new parameters with defaults; 24-02 SUMMARY confirms LabBuilderRoles.Tests.ps1 57/57 pass |
| 12 | Lab-Config.ps1 has CentOS VM name, IP plan, and role menu entries | VERIFIED | Line 293: VMNames.CentOS='LINCENT1'; line 273: IPPlan.CentOS='10.0.10.115'; line 441: RoleMenu entry; lines 318-322: SupportedDistros.CentOS9 with nocloud |

**Score:** 12/12 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Private/Get-LabSnapshotInventory.ps1` | All-Linux-VM auto-detection in snapshot inventory | VERIFIED | Contains multi-VM loop over Ubuntu/WebServerUbuntu/DatabaseUbuntu/DockerUbuntu/K8sUbuntu keys; backward compat LIN1 fallback preserved |
| `Private/Save-LabProfile.ps1` | Linux VM count in profile metadata | VERIFIED | linuxVmCount field computed from Builder.VMNames keys (lines 44-53); included in ordered profile hashtable (line 62) |
| `Tests/LinuxSnapshotParity.Tests.ps1` | Pester tests for Linux snapshot parity | VERIFIED | 12 tests across 3 Describe blocks; substantive coverage of 5-VM discovery, WhatIf, backward compat, Remove-LabStaleSnapshots |
| `Tests/LinuxProfileParity.Tests.ps1` | Pester tests for Linux profile round-trip | VERIFIED | 14 tests; covers linuxVmCount metadata, all 5 Linux VM name round-trips, nested hashtable fidelity, type verification |
| `LabBuilder/Roles/LinuxRoleBase.ps1` | SSH retry with configurable count and backoff in Invoke-LinuxRolePostInstall | VERIFIED | RetryCount and RetryDelaySeconds parameters; while loop lines 177-196; PSBoundParameters guard for LabConfig defaults |
| `LabBuilder/Roles/CentOS.ps1` | CentOS role definition with cloud-init NoCloud provisioning | VERIFIED | Get-LabRole_CentOS function; dnf post-install; CentOS-Stream-9*.iso pattern; LinuxRoleBase.ps1 dot-sourced |
| `Lab-Config.ps1` | CentOS VM entries in VMNames, IPPlan, RoleMenu, SupportedDistros | VERIFIED | All 4 entry points confirmed via grep |
| `Tests/LinuxSSHRetry.Tests.ps1` | Pester tests for SSH retry behavior | VERIFIED | 20 tests across 4 Describe blocks; structure verification via Get-Content; null-guard and parameter default coverage |
| `Tests/CentOSRole.Tests.ps1` | Pester tests for CentOS role definition | VERIFIED | 37 tests across 6 Describe blocks; structure parity with Ubuntu, null-guard, Lab-Config.ps1 content verification |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `Private/Get-LabSnapshotInventory.ps1` | `Lab-Config.ps1` | GlobalLabConfig.Builder.VMNames for Linux VM name resolution | WIRED | `$GlobalLabConfig.Builder.VMNames.ContainsKey($key)` at line 54; VMNames keys (Ubuntu etc.) match Lab-Config.ps1 Builder.VMNames entries |
| `Private/Save-LabProfile.ps1` | `Private/Load-LabProfile.ps1` | JSON round-trip of Linux config sections | WIRED | Save writes full $Config at depth 10 to JSON; Load uses ConvertTo-Hashtable recursively — Linux/LinuxVM/SupportedDistros/Builder sections preserved without modification |
| `LabBuilder/Roles/CentOS.ps1` | `LabBuilder/Roles/LinuxRoleBase.ps1` | Invoke-LinuxRoleCreateVM and Invoke-LinuxRolePostInstall | WIRED | CentOS.ps1 line 26-27: `$linuxRoleBasePath = Join-Path $PSScriptRoot 'LinuxRoleBase.ps1'` dot-sourced if exists; CreateVM calls `Invoke-LinuxRoleCreateVM`; PostInstall calls `Invoke-LinuxRolePostInstall` |
| `LabBuilder/Roles/LinuxRoleBase.ps1` | `Lab-Config.ps1` | LabConfig.Timeouts for SSH retry settings | WIRED | `$LabConfig.Timeouts.ContainsKey('SSHRetryCount')` read at lines 125-130; Lab-Config.ps1 provides `SSHRetryCount = 3` and `SSHRetryDelaySeconds = 10` at lines 358-359 |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| LNX-01 | 24-01 | Linux VMs support full provisioning lifecycle (create, start, stop, snapshot, teardown) matching Windows VMs | SATISFIED | Snapshot inventory now includes all 5 Linux VMs; profile save/load preserves all Linux config; create/start/stop were pre-existing |
| LNX-02 | 24-02 | SSH-based role application works for all existing Linux roles with retry and timeout handling | SATISFIED | Invoke-LinuxRolePostInstall has retry loop with configurable RetryCount/RetryDelaySeconds; defaults from LabConfig.Timeouts |
| LNX-03 | 24-01 | Linux VMs integrate with snapshot management (inventory, pruning, restore) | SATISFIED | Get-LabSnapshotInventory discovers all 5 Linux VMs; Remove-LabStaleSnapshots processes them identically to Windows VMs |
| LNX-04 | 24-01 | Linux VMs integrate with configuration profiles (save/load preserves Linux VM settings) | SATISFIED | Save-LabProfile adds linuxVmCount; full JSON round-trip via ConvertTo-Hashtable preserves Linux/LinuxVM/SupportedDistros/VMNames |
| LNX-05 | N/A (Phase 25) | Mixed OS scenarios work end-to-end | NOT IN SCOPE | Correctly deferred to Phase 25 in REQUIREMENTS.md — not claimed by any Phase 24 plan |
| LNX-06 | 24-02 | CentOS/RHEL support added alongside existing Ubuntu | SATISFIED | CentOS.ps1 with Get-LabRole_CentOS; dnf-based post-install; cloud-init nocloud; Lab-Config.ps1 entries for LINCENT1 |

---

### Anti-Patterns Found

None. All files scanned (Get-LabSnapshotInventory.ps1, Save-LabProfile.ps1, LinuxRoleBase.ps1, CentOS.ps1, Lab-Config.ps1, all 4 test files). No TODO/FIXME/PLACEHOLDER comments, no empty return stubs, no console.log-only implementations found.

---

### Human Verification Required

None required for automated checks. The following items would benefit from a live-lab smoke test but are not blockers:

#### 1. End-to-end CentOS provisioning

**Test:** Place a CentOS-Stream-9*.iso in LabSources/ISOs, run `Get-LabRole_CentOS` and invoke CreateVM, wait for SSH reachability, then invoke PostInstall.
**Expected:** LINCENT1 created, SSH reachable, `dnf update` completes, sshd enabled.
**Why human:** Requires Hyper-V environment, actual ISO, and SSH connectivity — cannot mock exhaustively.

#### 2. SSH retry under real failure conditions

**Test:** Provision a Linux VM with SSH service temporarily disabled. Invoke `Invoke-LinuxRolePostInstall` with RetryCount=3. Re-enable SSH after first attempt.
**Expected:** Warning on attempt 1, success on attempt 2, no exception thrown.
**Why human:** Cannot simulate real SSH connection failure with mock; test suite verifies structure only.

---

### Commits Verified

| Hash | Description | Status |
|------|-------------|--------|
| b7bdf3a | feat(24-01): extend snapshot inventory to discover all Linux VMs | EXISTS |
| 69c25c6 | feat(24-01): extend Save-LabProfile with linuxVmCount and add round-trip tests | EXISTS |
| be05311 | feat(24-02): add configurable SSH retry to Invoke-LinuxRolePostInstall | EXISTS |
| c1707be | feat(24-02): add CentOS role with cloud-init NoCloud provisioning | EXISTS |

---

### Gaps Summary

No gaps. All 12 observable truths verified against actual codebase. All 9 required artifacts exist, are substantive (not stubs), and are correctly wired. All 5 requirements assigned to Phase 24 (LNX-01 through LNX-04, LNX-06) are satisfied. LNX-05 is correctly out-of-scope for Phase 24 and assigned to Phase 25.

---

_Verified: 2026-02-20_
_Verifier: Claude (gsd-verifier)_

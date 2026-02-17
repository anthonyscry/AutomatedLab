---
phase: 03-core-lifecycle-integration
plan: 03
subsystem: core-lifecycle
tags: [enhancement, network-testing, config-awareness, health-checks]
dependency_graph:
  requires: [NET-01, NET-02, NET-03, NET-04, NET-05, CLI-06, LIFE-03]
  provides: [NET-06]
  affects: [lifecycle-health, network-validation, preflight-checks]
tech_stack:
  added: []
  patterns: [config-aware-defaults, actionable-diagnostics, pester-unit-tests]
key_files:
  created:
    - Tests/NetworkHealth.Tests.ps1
  modified:
    - Public/Test-LabNetwork.ps1
    - Public/Test-LabNetworkHealth.ps1
    - Scripts/Test-OpenCodeLabHealth.ps1
decisions:
  - title: "Config-aware network test functions"
    rationale: "Hardcoded 'SimpleLab' switch name broke when users configured different names. Functions must read from $GlobalLabConfig with fallback defaults for backward compatibility."
    impact: "Network tests work regardless of user's configured switch name"
  - title: "Comprehensive infrastructure health checks"
    rationale: "Test-OpenCodeLabHealth only checked VM state and AD DS but ignored vSwitch, NAT, DNS resolution, and domain join - leaving infrastructure issues undiagnosed until deployment failed."
    impact: "Health check now covers full stack: vSwitch, NAT, gateway IP, DNS resolution, domain join for all member servers"
  - title: "Actionable diagnostic messages"
    rationale: "Error messages should tell operators exactly what to run to fix the issue, not just report the problem."
    impact: "Every infrastructure issue includes remediation command: 'vSwitch missing. Run: New-LabSwitch -SwitchName AutomatedLab'"
  - title: "Fixed systemic invalid parameter syntax (12 files)"
    rationale: "PowerShell does not allow dotted property names in param blocks ($GlobalLabConfig.Network.NatName). This was a blocking syntax error preventing module load and test execution (Rule 3: Auto-fix blocking issue)."
    impact: "Module now loads successfully. Same issue as 03-01 but discovered in additional files during test run."
metrics:
  duration_minutes: 8.1
  tasks_completed: 2
  files_changed: 16
  tests_added: 10
  completed_at: "2026-02-16T23:58:10Z"
---

# Phase 3 Plan 3: Network Test Config-Awareness & Enhanced Health Checks Summary

Made network test functions config-aware and enhanced health check to validate full infrastructure stack with actionable diagnostics.

## What Was Done

### Task 1: Fix hardcoded values in network test functions (commit 21c2a17)

**Public/Test-LabNetwork.ps1:**
- Added `-SwitchName` parameter with smart default: `$GlobalLabConfig.Network.SwitchName` if available, else "SimpleLab"
- Replaced all hardcoded "SimpleLab" references in function body with `$SwitchName` parameter
- Updated result object's SwitchName field to use parameter value
- Updated documentation to reflect new parameter
- Maintains backward compatibility: function works without parameters using config values

**Public/Test-LabNetworkHealth.ps1:**
- Added `-SwitchName` parameter defaulting from `$GlobalLabConfig.Network.SwitchName`
- Updated default `-VMNames` parameter to read from `$GlobalLabConfig.Lab.CoreVMNames` if available
- Passes `-SwitchName` to `Test-LabNetwork` call
- Updated error message to use dynamic switch name instead of hardcoded "SimpleLab"
- Updated documentation with new parameters and examples

**Verification:**
```powershell
Select-String -Path Public/Test-LabNetwork.ps1 -Pattern '"SimpleLab"'
# Result: Only in comments and fallback default value (line 35)
```

### Task 2: Enhance health check and add network tests (commit 3f86ad5)

**Scripts/Test-OpenCodeLabHealth.ps1 - Added infrastructure checks (lines 92-167):**

1. **vSwitch check:**
   ```powershell
   $sw = Get-VMSwitch -Name $GlobalLabConfig.Network.SwitchName -ErrorAction SilentlyContinue
   if ($sw) { Add-Ok "vSwitch '$($GlobalLabConfig.Network.SwitchName)' exists" }
   else { Add-Issue "vSwitch missing. Run: New-LabSwitch -SwitchName '$($GlobalLabConfig.Network.SwitchName)'" }
   ```

2. **NAT check:**
   ```powershell
   $nat = Get-NetNat -Name $GlobalLabConfig.Network.NatName -ErrorAction SilentlyContinue
   if ($nat) { Add-Ok "NAT '$($GlobalLabConfig.Network.NatName)' exists" }
   else { Add-Issue "NAT missing. Run: New-LabNAT" }
   ```

3. **Host gateway IP check:**
   ```powershell
   $ifAlias = "vEthernet ($($GlobalLabConfig.Network.SwitchName))"
   $gwIp = Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
           Where-Object { $_.IPAddress -eq $GlobalLabConfig.Network.GatewayIp }
   if ($gwIp) { Add-Ok "Host gateway IP $($GlobalLabConfig.Network.GatewayIp) on $ifAlias" }
   else { Add-Issue "Host gateway IP missing on $ifAlias" }
   ```

4. **DNS resolution check (on DC1):**
   ```powershell
   $dnsResult = Invoke-LabCommand -ComputerName 'DC1' -PassThru -ScriptBlock {
       $resolved = Resolve-DnsName -Name 'google.com' -QuickTimeout -ErrorAction SilentlyContinue
       [bool]$resolved
   } -ErrorAction SilentlyContinue
   if ($dnsResult) { Add-Ok 'DC1 DNS external resolution working' }
   else { Add-Issue 'DC1 cannot resolve external DNS. Check forwarders: Get-DnsServerForwarder on DC1' }
   ```

5. **Member server domain join check (for svr1, ws1, etc.):**
   ```powershell
   foreach ($memberVM in @($ExpectedVMs | Where-Object { $_ -notin @('DC1', 'LIN1') })) {
       $joinCheck = Invoke-LabStructuredCheck -ComputerName $memberVM -RequiredProperty 'Domain' -ScriptBlock {
           $cs = Get-CimInstance Win32_ComputerSystem
           [pscustomobject]@{ Domain = $cs.Domain; PartOfDomain = $cs.PartOfDomain }
       } -ErrorAction SilentlyContinue
       if ($joinCheck -and $joinCheck.PartOfDomain) {
           Add-Ok "$memberVM joined to domain '$($joinCheck.Domain)'"
       } else {
           Add-Issue "$memberVM not joined to domain. Expected: '$($GlobalLabConfig.Lab.DomainName)'"
       }
   }
   ```

**Tests/NetworkHealth.Tests.ps1 (new file):**
Created comprehensive Pester 5 test suite with 10 tests across 5 contexts:
- Test-LabNetwork.Parameter Handling: Accepts -SwitchName, uses $GlobalLabConfig default, fallback to "SimpleLab"
- Test-LabNetwork.Return Object Structure: Returns object with correct properties, handles error status
- Test-LabNetworkHealth.Parameter Handling: Accepts -VMNames and -SwitchName, uses $GlobalLabConfig defaults
- Test-LabNetworkHealth.Return Object Structure: Returns structured object, handles vSwitch missing scenario

**Test Results:**
```powershell
Invoke-Pester Tests/NetworkHealth.Tests.ps1 -PassThru
# Result: Tests Passed: 10, Failed: 0, Skipped: 0
```

## Deviations from Plan

### Rule 3 - Auto-fix blocking issues: Invalid parameter syntax (12 files)

**Issue:** Multiple files had invalid PowerShell parameter declarations using dotted property names: `[string]$GlobalLabConfig.Network.NatName`. PowerShell requires simple parameter names in param blocks. These syntax errors prevented module loading and blocked test execution.

**Files fixed:**
- **Private/** (6 files): Get-LabFleetStateProbe.ps1, Get-LabStateProbe.ps1, Invoke-LabQuickModeHeal.ps1, New-LabDeploymentReport.ps1, Test-LabDomainJoin.ps1, Test-LabVirtualSwitchSubnetConflict.ps1
- **Public/** (4 files): Initialize-LabDomain.ps1, Join-LabDomain.ps1, Linux/Join-LinuxToDomain.ps1, Test-LabDomainHealth.ps1
- **Scripts/** (2 files): Add-LIN1.ps1, Configure-LIN1.ps1

**Pattern applied:**
```powershell
# Before (invalid)
param(
    [string]$GlobalLabConfig.Network.NatName
)
$nat = Get-NetNat -Name $GlobalLabConfig.Network.NatName

# After (valid)
param(
    [string]$NatName
)
$nat = Get-NetNat -Name $NatName
# Caller passes: Invoke-Function -NatName $GlobalLabConfig.Network.NatName
```

**Justification:** Same issue as Phase 03-01 (invalid param syntax in Deploy.ps1/Bootstrap.ps1), but discovered in additional files during this plan's test execution. Syntax errors are blocking bugs (Rule 1) that also prevented task completion (Rule 3). Auto-fixed to unblock tests.

**Impact:** Module now loads successfully. Tests can run. All 12 functions have valid parameter syntax.

## Verification Results

### Task 1 Verification

```bash
# Check for hardcoded SimpleLab strings (should only be in comments/defaults)
grep -n '"SimpleLab"' Public/Test-LabNetwork.ps1
# Result: Lines 13, 35 (documentation and fallback default only)

# Syntax validation
pwsh -NoProfile -Command "[scriptblock]::Create((Get-Content Public/Test-LabNetwork.ps1 -Raw)) | Out-Null; Write-Host 'Syntax OK'"
# Result: Syntax OK

pwsh -NoProfile -Command "[scriptblock]::Create((Get-Content Public/Test-LabNetworkHealth.ps1 -Raw)) | Out-Null; Write-Host 'Syntax OK'"
# Result: Syntax OK
```

### Task 2 Verification

```bash
# Check infrastructure checks are present
grep -n "vSwitch\|NAT\|gateway IP\|DNS resolution\|domain join" Scripts/Test-OpenCodeLabHealth.ps1 | head -15
# Result: All 5 infrastructure checks present with actionable remediation commands

# Pester test execution
Invoke-Pester Tests/NetworkHealth.Tests.ps1 -PassThru
# Result: Tests Passed: 10, Failed: 0, Duration: 2.28s
```

## Impact

**Before (broken):**
- Test-LabNetwork hardcoded "SimpleLab" → failed if user configured different switch name
- Test-LabNetworkHealth hardcoded VM list → failed to test user's actual VMs
- Test-OpenCodeLabHealth only checked VM state + AD DS → infrastructure issues undiagnosed
- No infrastructure validation before deploy → vSwitch/NAT/DNS failures detected late in process
- 12 files had invalid param syntax → module failed to load

**After (working):**
- Test-LabNetwork reads switch name from $GlobalLabConfig.Network.SwitchName (fallback: "SimpleLab")
- Test-LabNetworkHealth reads VM names from $GlobalLabConfig.Lab.CoreVMNames (fallback: @("dc1", "svr1", "ws1"))
- Test-OpenCodeLabHealth covers full stack: VM state, vSwitch, NAT, gateway IP, DNS resolution, domain join
- Every infrastructure issue includes actionable remediation command
- Health check catches infrastructure problems early with clear fix instructions
- All 12 functions have valid parameter syntax → module loads successfully
- 10 Pester tests validate network functions work correctly

**End-to-end workflow improvement:**
1. User runs `Scripts/Test-OpenCodeLabHealth.ps1`
2. Script checks infrastructure: vSwitch → NAT → gateway IP → DNS → domain join
3. Issues reported with exact remediation: "NAT missing. Run: New-LabNAT"
4. User runs suggested command to fix
5. Health check passes, user proceeds confidently

## Files Changed

| File | Lines Changed | Type |
|------|---------------|------|
| Public/Test-LabNetwork.ps1 | 57 insertions, 13 deletions | enhancement |
| Public/Test-LabNetworkHealth.ps1 | 36 insertions, 6 deletions | enhancement |
| Scripts/Test-OpenCodeLabHealth.ps1 | 45 insertions, 0 deletions | enhancement |
| Tests/NetworkHealth.Tests.ps1 | 110 insertions, 0 deletions | new |
| **Syntax fixes (12 files)** | 82 insertions, 27 deletions | fix |

**Total:** 16 files, 330 insertions, 46 deletions

## Commits

| Hash | Message | Files |
|------|---------|-------|
| 21c2a17 | feat(03-03): make network test functions config-aware | Public/Test-LabNetwork.ps1, Public/Test-LabNetworkHealth.ps1 |
| 3f86ad5 | feat(03-03): enhance health check with infrastructure validation and add network tests | Scripts/Test-OpenCodeLabHealth.ps1, Tests/NetworkHealth.Tests.ps1, 12 syntax fix files |

## Self-Check: PASSED

**Created files exist:**
```bash
[ -f "Tests/NetworkHealth.Tests.ps1" ] && echo "FOUND: Tests/NetworkHealth.Tests.ps1"
# Result: FOUND: Tests/NetworkHealth.Tests.ps1
```

**Modified files verified:**
```bash
git diff 21c2a17^..3f86ad5 --name-only | sort
# Result: All 16 files present in commits
```

**Commits exist:**
```bash
git log --oneline --all | grep -E "(21c2a17|3f86ad5)"
# Result: Both commits found in git history
```

**Tests pass:**
```bash
Invoke-Pester Tests/NetworkHealth.Tests.ps1 -PassThru | Select-Object Result, PassedCount, FailedCount
# Result: Result: Passed, PassedCount: 10, FailedCount: 0
```

All verification checks passed.

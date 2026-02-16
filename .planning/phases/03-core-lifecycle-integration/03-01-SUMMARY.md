---
phase: 03-core-lifecycle-integration
plan: 01
subsystem: core-lifecycle
tags: [bugfix, interpolation, config, testing]
dependency_graph:
  requires: [LIFE-01, CLI-04]
  provides: [LIFE-03]
  affects: [lifecycle-bootstrap, lifecycle-deploy, lifecycle-health]
tech_stack:
  added: []
  patterns: [pester-validation, string-interpolation-enforcement]
key_files:
  created:
    - Tests/BootstrapDeployInterpolation.Tests.ps1
  modified:
    - Deploy.ps1
    - Bootstrap.ps1
    - Scripts/Test-OpenCodeLabPreflight.ps1
    - Scripts/Test-OpenCodeLabHealth.ps1
decisions:
  - title: "Mandatory subexpression syntax for nested config properties"
    rationale: "PowerShell does not interpolate `\"$GlobalLabConfig.Paths.LabSourcesRoot\\ISOs\"` correctly - it evaluates the hashtable and appends literal text. All nested properties must use `\"$($GlobalLabConfig.X.Y)\"` subexpression syntax."
    impact: "Eliminates silent string concatenation bugs that result in paths like `System.Collections.Hashtable.Paths.LabSourcesRoot\\ISOs`"
  - title: "Remove all legacy variable fallbacks"
    rationale: "Phase 01 completed migration to $GlobalLabConfig. Legacy variable checks ($LabSwitch, $LabName, etc.) are dead code that pollutes search results and creates confusion."
    impact: "Cleaner codebase, faster searches, no ambiguity about config source"
  - title: "Pester test enforcement of interpolation rules"
    rationale: "Manual code review cannot catch all bare interpolations. Automated test suite prevents regression."
    impact: "CI-ready validation, catches interpolation bugs before runtime"
metrics:
  duration_minutes: 6.0
  tasks_completed: 2
  files_changed: 5
  tests_added: 12
  completed_at: "2026-02-16T23:47:00Z"
---

# Phase 3 Plan 1: String Interpolation & Config Migration Fixes Summary

Fixed all PowerShell string interpolation bugs and removed legacy variable references from Deploy.ps1, Bootstrap.ps1, and health check scripts.

## What Was Done

### Task 1: Deploy.ps1 Fixes (commit cc064c5)

**Fixed invalid param block syntax:**
- Changed `[string]$GlobalLabConfig.Credentials.AdminPassword` → `[string]$AdminPassword` (dotted paths are invalid PowerShell parameter names)
- Updated password resolution logic to use new param name with proper fallback: `Resolve-LabPassword -Password $(if ($PSBoundParameters.ContainsKey('AdminPassword')) { $AdminPassword } else { $GlobalLabConfig.Credentials.AdminPassword })`

**Fixed 50+ string interpolation bugs:**
- Pattern: `"$GlobalLabConfig.Paths.LabSourcesRoot\ISOs"` → `"$($GlobalLabConfig.Paths.LabSourcesRoot)\ISOs"`
- Affected properties: Network.SwitchName, Network.GatewayIp, Network.NatName, Network.AddressSpace, IPPlan.DC1, IPPlan.SVR1, IPPlan.WS1, IPPlan.LIN1, DHCP.ScopeId, DHCP.Start, DHCP.End, Lab.DomainName, Lab.Name, Credentials.InstallUser, Paths.ShareName, and many more

**Fixed Invoke-LabCommand scriptblock param blocks:**
- Line 793: Changed `param($GlobalLabConfig.Paths.SharePath, ...)` → `param($SharePath, $ShareName, $GitRepoPath, $DomainName)` with proper variable references inside scriptblock
- Line 1114: Changed `param($GlobalLabConfig.Paths.ShareName)` → `param($ShareName)`

**Replaced hardcoded Git installer values with config references:**
- DC1 Git install (line 960): Now uses `$GlobalLabConfig.SoftwarePackages.Git.LocalPath`, `.Url`, `.Sha256`
- WS1 Git install (line 1134): Same config-driven approach

**Removed legacy variable fallbacks:**
- Deleted Get-Variable checks for Server1_Ip, Server_Memory, Server_MinMemory, Server_MaxMemory, Server_Processors, WSUS_Memory, WSUS_MinMemory, WSUS_MaxMemory, WSUS_Processors (lines 51-62)

### Task 2: Bootstrap, Preflight, Health Scripts (commit 9319f49)

**Bootstrap.ps1 fixes:**
- Removed all legacy variable fallback checks (lines 38-44): `$LabSwitch`, `$LabName`, `$LabSourcesRoot`, `$GatewayIp`, `$NatName`, `$RequiredISOs`
- Fixed string interpolation in `$RequiredFolders` array (6 paths)
- Fixed vSwitch/NAT creation messages and manual command suggestions
- No longer references bare legacy variables - uses `$GlobalLabConfig` exclusively

**Test-OpenCodeLabPreflight.ps1 fixes:**
- Removed legacy variable fallback checks (lines 20-25)
- Fixed subnet conflict warning message interpolation
- Fixed Switch exists/NAT exists messages

**Test-OpenCodeLabHealth.ps1 fixes:**
- Removed legacy variable fallback checks (lines 20-28): `$LabName`, `$LabVMs`, `$LinuxUser`, `$LabSourcesRoot`, `$DomainName`, `$LIN1_Ip`
- Fixed SSH command interpolation (line 214, 255): Wrapped `$GlobalLabConfig.Credentials.LinuxUser` and `$GlobalLabConfig.IPPlan.LIN1` in subexpressions

**Tests/BootstrapDeployInterpolation.Tests.ps1 (new file):**
Created comprehensive Pester 5 test suite with 12 tests across 4 contexts:
- Deploy.ps1: Syntax parsing, param block validation, bare interpolation detection, legacy variable checks, Git config validation
- Bootstrap.ps1: Syntax parsing, legacy variable reference detection, bare interpolation detection
- Test-OpenCodeLabPreflight.ps1: Legacy variable fallback checks, GlobalLabConfig usage validation
- Test-OpenCodeLabHealth.ps1: Legacy variable fallback checks, GlobalLabConfig usage validation

All 12 tests pass.

## Verification Results

### Syntax Validation
```powershell
[scriptblock]::Create((Get-Content Deploy.ps1 -Raw))
# Result: Parses successfully (no syntax errors)
```

### Interpolation Test Suite
```powershell
Invoke-Pester Tests/BootstrapDeployInterpolation.Tests.ps1
# Result: Tests Passed: 12, Failed: 0
```

### Pattern Search
```bash
grep -n '"[^"]*$GlobalLabConfig\.[A-Z][^(]' Deploy.ps1 | head -5
# Result: All instances show proper $(...) wrapping
```

### Legacy Variable Search
```bash
grep 'Get-Variable -Name (Server1_Ip|WSUS_Memory)' Deploy.ps1
# Result: No matches (removed)
```

## Deviations from Plan

None - plan executed exactly as written.

## Impact

**Before (broken):**
```powershell
$IsoPath = "$GlobalLabConfig.Paths.LabSourcesRoot\ISOs"
# Evaluates to: "System.Collections.Hashtable.Paths.LabSourcesRoot\ISOs"
```

**After (working):**
```powershell
$IsoPath = "$($GlobalLabConfig.Paths.LabSourcesRoot)\ISOs"
# Evaluates to: "C:\LabSources\ISOs"
```

**End-to-end impact:**
- Deploy.ps1 can now run without string concatenation bugs causing path resolution failures
- Bootstrap.ps1 no longer attempts to read non-existent legacy variables
- Preflight and health checks use consistent config source
- Pester test prevents regression (CI-ready)

## Files Changed

| File | Lines Changed | Type |
|------|---------------|------|
| Deploy.ps1 | 53 insertions, 65 deletions | fix |
| Bootstrap.ps1 | 23 insertions, 13 deletions | fix |
| Scripts/Test-OpenCodeLabPreflight.ps1 | 9 insertions, 11 deletions | fix |
| Scripts/Test-OpenCodeLabHealth.ps1 | 9 insertions, 11 deletions | fix |
| Tests/BootstrapDeployInterpolation.Tests.ps1 | 149 insertions, 0 deletions | new |

**Total:** 5 files, 243 insertions, 100 deletions

## Commits

| Hash | Message | Files |
|------|---------|-------|
| cc064c5 | fix(03-01): correct Deploy.ps1 param syntax and string interpolation | Deploy.ps1 |
| 9319f49 | feat(03-01): fix Bootstrap, preflight, health scripts and add interpolation tests | Bootstrap.ps1, Scripts/Test-OpenCodeLabPreflight.ps1, Scripts/Test-OpenCodeLabHealth.ps1, Tests/BootstrapDeployInterpolation.Tests.ps1 |

## Self-Check: PASSED

**Created files exist:**
```bash
[ -f "Tests/BootstrapDeployInterpolation.Tests.ps1" ] && echo "FOUND"
# Result: FOUND
```

**Modified files verified:**
```bash
git diff cc064c5^..9319f49 --name-only | sort
# Result: Bootstrap.ps1, Deploy.ps1, Scripts/Test-OpenCodeLabHealth.ps1, Scripts/Test-OpenCodeLabPreflight.ps1, Tests/BootstrapDeployInterpolation.Tests.ps1
```

**Commits exist:**
```bash
git log --oneline --all | grep -E "(cc064c5|9319f49)"
# Result: Both commits found in git history
```

All verification checks passed.

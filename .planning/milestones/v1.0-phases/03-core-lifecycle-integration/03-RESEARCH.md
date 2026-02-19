# Phase 3: Core Lifecycle Integration — Research

**Gathered:** 2026-02-16
**Method:** Codebase audit of OpenCodeLab-App.ps1, Deploy.ps1, Bootstrap.ps1, all Scripts/*.ps1, Public/, Private/ helpers
**Confidence:** HIGH

## Summary

Phase 3 covers the full Bootstrap → Deploy → Use → Teardown lifecycle across 19 requirements (LIFE-01..05, CLI-01..09, NET-01..05). The codebase has substantial infrastructure already — a 1949-line orchestrator (OpenCodeLab-App.ps1), a 1247-line deploy script (Deploy.ps1), network helpers (New-LabSwitch, New-LabNAT, Initialize-LabNetwork, Initialize-LabDNS), health checks (Test-OpenCodeLabHealth.ps1), and teardown via Invoke-BlowAway. However, several critical integration gaps exist:

1. **Legacy variable references** in Bootstrap.ps1, Test-OpenCodeLabPreflight.ps1, Test-OpenCodeLabHealth.ps1 still check for old `$LabName`, `$LabSwitch` etc. variables that were removed in Phase 1
2. **Deploy.ps1 parameter syntax error** — line 15 uses `$GlobalLabConfig.Credentials.AdminPassword` as a parameter name (dotted path in param block)
3. **Test-LabNetwork hardcodes "SimpleLab"** switch name instead of reading from `$GlobalLabConfig`
4. **No try-catch on many critical Deploy.ps1 operations** — DHCP, DNS forwarders, share creation, Git install all lack structured error handling
5. **No confirmation tokens on destructive actions** — blow-away uses typed confirmation but not scoped tokens; teardown via orchestrator has token support but direct actions don't
6. **Health check is partial** — checks VMs running + AD status + SSH on LIN1 but doesn't check vSwitch, NAT, DNS resolution, or domain join status of member servers
7. **Idempotency gaps** — Deploy.ps1 handles re-deploy (Remove-Lab if exists) but Bootstrap.ps1 doesn't verify if prerequisites are already installed before re-running

## LIFE-01..05: Lifecycle Flow Audit

### Bootstrap (Bootstrap.ps1, 248 lines)

**Current flow:** 10 steps — NuGet → Pester fix → PSFramework → SHiPS → AutomatedLab → LabSources folders → Hyper-V check → vSwitch+NAT → ISO validation → Deploy.ps1

**Issues found:**
| Issue | Location | Impact |
|-------|----------|--------|
| Legacy variable fallback checks (`Get-Variable -Name LabName`) | Lines 39-44 | Will never trigger after Phase 1 config unification — but script won't fail either. These are dead code paths. |
| String interpolation bug: `"$GlobalLabConfig.Paths.LabSourcesRoot\ISOs"` | Lines 46, 52-57 | PS interprets `$GlobalLabConfig` then appends `.Paths.LabSourcesRoot\ISOs` as literal string. Should use `"$($GlobalLabConfig.Paths.LabSourcesRoot)\ISOs"` |
| No idempotency checks on module installs | Steps 1-5 | PSFramework/SHiPS reinstall on every run (harmless but slow) |
| No try-catch around vSwitch/NAT creation | Step 8 area | If creation fails, error is unhandled |
| `$NatName` fallback references removed `$LabSwitch` variable | Line 43 | `${LabSwitch}NAT` will fail — `$LabSwitch` no longer exists |

### Deploy (Deploy.ps1, 1247 lines)

**Current flow:** Pre-flight ISOs → Subnet conflict check → Remove existing lab → SSH keypair → Lab definition → vSwitch+NAT → Machine definitions (template or hardcoded) → Install-Lab → AD DS validation/recovery → Network validation → DHCP → DNS forwarders → LIN1 (optional) → Post-install (share, Git, SSH, RSAT) → LabReady checkpoint → Summary

**Issues found:**
| Issue | Location | Impact |
|-------|----------|--------|
| Parameter `$GlobalLabConfig.Credentials.AdminPassword` (dotted path) | Line 15 | Syntax error — PowerShell param names can't contain dots |
| Legacy variable fallbacks (`Get-Variable -Name Server1_Ip`) | Lines 52-62 | Dead code after Phase 1 — these variables don't exist |
| String interpolation bugs throughout | Lines 48-49, 99, 220+ | `"$GlobalLabConfig.Paths.LabSourcesRoot\ISOs"` incorrectly interpolated |
| No structured error handling on DHCP/DNS sections | Lines 640-702 | Failures in DHCP scope creation would cascade |
| Git installer has hardcoded SHA256/URLs in Invoke-LabCommand calls | Lines 972, 1146 | Should read from `$GlobalLabConfig.SoftwarePackages.Git` |
| LabReady snapshot creation has no validation | Line 1211 | If Checkpoint-LabVM fails silently, quick mode breaks |
| `$WSUS_Memory` and legacy sizing variables | Lines 59-62 | Dead code — references removed variables |

### Quick Mode (Invoke-QuickDeploy, Invoke-LabQuickModeHeal)

**Current flow:** Quick deploy = Start-LabDay → Lab-Status → Test-OpenCodeLabHealth. Quick mode heal (Invoke-LabQuickModeHeal) auto-repairs vSwitch, NAT, and LabReady snapshot gaps.

**Status:** Quick mode heal was added recently (commit 8c61aaa). Flow looks solid. Main risk: if LabReady snapshot doesn't exist, quick mode falls back to full mode correctly.

### Teardown (Invoke-BlowAway in OpenCodeLab-App.ps1)

**Current flow:** 5 steps — Stop VMs → Remove-Lab → Remove Hyper-V VMs/checkpoints → Remove lab files → Clean network (optional)

**Issues found:**
| Issue | Location | Impact |
|-------|----------|--------|
| Uses typed confirmation ("BLOW-IT-AWAY") not scoped tokens | Line 549 | Doesn't match CLI-07 requirement for scoped confirmation tokens |
| No SSH known_hosts cleanup on teardown | After step 5 | Stale known_hosts entries persist across rebuilds |
| `Remove-HyperVVMStale` alias used but defined separately | Line 80 | Works but fragile if alias not set |
| No NAT cleanup verification after removal | Step 5 | If Remove-NetNat fails silently, orphan NAT persists |

### Re-deploy After Teardown (LIFE-05)

Deploy.ps1 handles existing lab detection (line 169) and removes it before redefining. vSwitch+NAT creation is idempotent (create if missing, skip if exists). Main gap: if teardown didn't remove everything (orphan VMs), redeploy may fail at Install-Lab.

## CLI-01..09: Orchestrator Audit

### Action Routing (OpenCodeLab-App.ps1)

All 25+ actions are routed via the switch block at lines 1785-1878. Each action either calls Invoke-RepoScript or a local function.

**Issues found:**
| Action | Issue |
|--------|-------|
| `setup` | Calls Invoke-Setup which runs preflight+bootstrap. Missing direct error handling. |
| `deploy` | Properly routes through Invoke-OrchestrationActionCore. No issues. |
| `teardown` | Routes through orchestration core or Invoke-BlowAway. Confirmation token support exists but only via -ConfirmationToken parameter. |
| `health` | Calls Test-OpenCodeLabHealth via Invoke-RepoScript. Works. |
| `stop` | Inline Stop-LabVMsSafe — no structured result. |
| `rollback` | Checks Test-LabReadySnapshot then restores. Throws if missing. |
| `blow-away` | Direct call to Invoke-BlowAway with bypass logic. |
| `menu` | Interactive menu works. All menu options tested via Invoke-MenuCommand with try-catch. |

### Error Handling Pattern

`Invoke-RepoScript` wraps script calls with try-catch and `Add-RunEvent`. `Invoke-MenuCommand` also has try-catch. The orchestrator's outer try-catch (line 1213-1948) catches top-level failures. However, many internal functions lack try-catch on individual critical operations.

### Confirmation Tokens (CLI-07)

Scoped confirmation tokens exist (Private/New-LabScopedConfirmationToken.ps1, Private/Test-LabScopedConfirmationToken.ps1) and are wired into the orchestrator's policy evaluation. However:
- Only teardown (in `enforced` dispatch mode) requires them
- Direct `blow-away` action uses typed confirmation ("BLOW-IT-AWAY") not scoped tokens
- No confirmation gate on `one-button-reset`
- Menu reset uses "REBUILD" typed confirmation

## NET-01..05: Network Infrastructure Audit

### NET-01: vSwitch Creation (Idempotent)

**New-LabSwitch** (Public/New-LabSwitch.ps1): Returns structured result. Checks if exists, skips if so. **But hardcodes "SimpleLab" switch name** in Test-LabNetwork call.

**Deploy.ps1 inline creation** (lines 237-242): Also idempotent — checks Get-VMSwitch, creates if missing. Uses `$GlobalLabConfig.Network.SwitchName` correctly.

**Gap:** Two separate vSwitch creation paths (New-LabSwitch and Deploy.ps1 inline). Should consolidate.

### NET-02: NAT Configuration

**New-LabNAT** (Public/New-LabNAT.ps1): Full implementation — creates switch + gateway IP + NAT. Handles prefix conflicts with -Force. Returns structured result.

**Deploy.ps1 inline** (lines 256-267): Also handles NAT creation and prefix mismatch. Duplicates New-LabNAT logic.

**Gap:** Duplicate NAT creation logic. New-LabNAT reads from Get-LabNetworkConfig (older pattern), Deploy.ps1 reads from $GlobalLabConfig.

### NET-03: Static IP Assignment

**Set-VMStaticIP** (Private/Set-VMStaticIP.ps1): Uses PowerShell Direct (`Invoke-Command -VMName`). Configures static IP on VM's Ethernet adapter.

**Initialize-LabNetwork** (Public/Initialize-LabNetwork.ps1): Orchestrates Set-VMStaticIP for multiple VMs. Reads from Get-LabNetworkConfig.

**Deploy.ps1**: Doesn't call Initialize-LabNetwork or Set-VMStaticIP — instead passes IP to AutomatedLab's `Add-LabMachineDefinition -IpAddress`. AutomatedLab handles IP assignment during Install-Lab.

**LIN1 static IP**: Set via Configure-LIN1.sh bash script (netplan config).

**Status:** Working for Windows VMs via AutomatedLab. Set-VMStaticIP/Initialize-LabNetwork exist for manual use but aren't called in the main deploy path.

### NET-04: DNS Configuration

**Initialize-LabDNS** (Public/Initialize-LabDNS.ps1): Configures forwarders on DC VM via PowerShell Direct. Tests Internet resolution. Returns structured result.

**Deploy.ps1 inline** (lines 674-702): Configures DNS forwarders directly via Invoke-LabCommand. Duplicates Initialize-LabDNS logic.

**Gap:** Duplicate DNS forwarder configuration. Deploy.ps1 inline doesn't use Initialize-LabDNS helper.

### NET-05: Network Health Check

**Test-LabNetworkHealth** (Public/Test-LabNetworkHealth.ps1): Tests VM-to-VM connectivity using Test-VMNetworkConnectivity. Returns structured result with pass/fail per pair.

**Test-LabNetwork** (Public/Test-LabNetwork.ps1): **Hardcodes "SimpleLab" switch name.** Should read from config.

**Deploy.ps1 validation** (lines 583-634): Inline host-to-DC1 connectivity check (ping + WinRM). Doesn't use Test-LabNetworkHealth.

## Critical Issues Summary (Ordered by Severity)

### Blockers (prevent end-to-end)
1. **Deploy.ps1 line 15 param syntax error** — dotted path as parameter name
2. **String interpolation bugs** in Bootstrap.ps1 and Deploy.ps1 — `"$GlobalLabConfig.X.Y"` doesn't interpolate correctly; needs `"$($GlobalLabConfig.X.Y)"`
3. **Bootstrap.ps1 line 43** — `$NatName = "${LabSwitch}NAT"` references deleted `$LabSwitch` variable

### High (prevent reliable lifecycle)
4. **Legacy variable fallbacks** in Bootstrap.ps1, Test-OpenCodeLabPreflight.ps1, Test-OpenCodeLabHealth.ps1 — dead code that should use $GlobalLabConfig
5. **Test-LabNetwork hardcodes "SimpleLab"** — breaks if switch has different name
6. **No try-catch on Deploy.ps1 critical sections** — DHCP, DNS, share, Git
7. **No SSH known_hosts cleanup** in teardown path
8. **No LabReady checkpoint validation** after creation

### Medium (integration quality)
9. **Duplicate network logic** — Deploy.ps1 inline vs Public/ helpers (New-LabSwitch, New-LabNAT, Initialize-LabDNS)
10. **Confirmation tokens not on all destructive actions** — only on orchestrated teardown
11. **Health check doesn't cover full infrastructure** — missing vSwitch, NAT, DNS, member server domain join
12. **Deploy.ps1 hardcoded Git URLs/hashes** — should use $GlobalLabConfig

## Plan Breakdown (Recommended)

### Plan 03-01: Fix Bootstrap and Deploy blockers (string interpolation, param syntax, legacy vars)
- Fix `"$GlobalLabConfig.X.Y"` → `"$($GlobalLabConfig.X.Y)"` everywhere
- Fix Deploy.ps1 param syntax error (line 15)
- Remove legacy variable fallback dead code from Bootstrap.ps1, Deploy.ps1
- Fix Bootstrap.ps1 `$LabSwitch` reference
- Requirements: LIFE-01 (partial), CLI-04

### Plan 03-02: Error handling and try-catch on critical Deploy.ps1 operations
- Wrap DHCP, DNS forwarder, share, Git, SSH sections in try-catch with context-aware messages
- Add structured error reporting to each section
- Validate LabReady checkpoint creation
- Requirements: CLI-08, LIFE-01 (partial)

### Plan 03-03: Network infrastructure consolidation and health checks
- Fix Test-LabNetwork to read switch name from config
- Wire Deploy.ps1 to use Public/ network helpers where appropriate
- Enhance health check to cover vSwitch, NAT, DNS, domain join
- Add VM-to-VM connectivity to health gate
- Requirements: NET-01, NET-02, NET-03, NET-04, NET-05, CLI-06

### Plan 03-04: Teardown hardening, confirmation tokens, and idempotency
- Add SSH known_hosts cleanup to teardown
- Wire scoped confirmation tokens to blow-away and one-button-reset
- Verify re-deploy after teardown succeeds (idempotency validation)
- Ensure Bootstrap.ps1 is idempotent (skip already-installed prereqs)
- Requirements: LIFE-04, LIFE-05, CLI-07, CLI-03

### Plan 03-05: Quick mode, CLI menu routing, and end-to-end integration
- Verify quick mode restore + auto-heal flow
- Verify all 25+ CLI actions route correctly
- Clean up dead code in OpenCodeLab-App.ps1 (legacy variable refs)
- Add tests for critical lifecycle functions
- Requirements: LIFE-03, CLI-01, CLI-02, CLI-05, CLI-09

---
*Research completed: 2026-02-16*
*Audited: OpenCodeLab-App.ps1 (1949 lines), Deploy.ps1 (1247 lines), Bootstrap.ps1 (248 lines), 15 Public/ files, 12 Private/ files, 3 Scripts/ files*

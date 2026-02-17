# Phase 9: Error Handling - Research

**Date:** 2026-02-16
**Phase:** 9 of 10
**Focus:** Add try-catch error handling to all functions currently missing it

## Current State Analysis

### Function Inventory

After Phase 8 extraction, the codebase has more functions than the original 39 estimate. The actual count of functions without try-catch:

- **Private/ functions without try-catch:** 49
- **Public/ functions without try-catch:** 6
- **Total:** 55

### Exempt Functions (too trivial for try-catch)

These functions are pure data returns with no I/O, no external calls, and no realistic failure modes. Adding try-catch would be pure boilerplate noise:

| Function | Lines | Reason for Exemption |
|----------|-------|---------------------|
| Get-LabHealthArgs | 6 | Returns empty array literal |
| Get-LabPreflightArgs | 6 | Returns empty array literal |
| Suspend-LabMenuPrompt | 6 | Single Read-Host call |
| Get-LabExpectedVMs | 8 | Single hashtable index |
| Get-LabBootstrapArgs | 14 | Pure array builder, no I/O |
| Get-LabDeployArgs | 14 | Pure array builder, no I/O |
| Register-LabAliases | 14 | Set-Alias declarations only |
| Convert-LabArgumentArrayToSplat | 27 | Already uses throw for validation |
| Resolve-LabScriptPath | 14 | Already uses throw for not-found |
| ConvertTo-LabTargetHostList | 28 | Pure data transform |
| Get-LabGuiLayoutState | 26 | Pure data return |
| Read-LabMenuCount | 20 | Simple Read-Host + parseInt |
| Test-LabTransientTransportFailure | 20 | Pure string pattern match |
| Protect-LabLogString | 58 | Pure string replacement, no I/O |
| Add-LabRunEvent | 16 | Single list append |

**Exempt count:** 15
**Functions needing try-catch:** 34 Private + 6 Public = **40 functions**

### Functions Needing Try-Catch

#### Private/ - Orchestration & Lifecycle (10 functions)

| Function | Lines | Risk | Operations |
|----------|-------|------|-----------|
| Invoke-LabOrchestrationActionCore | 58 | Med | Routes actions to sub-functions |
| Invoke-LabOneButtonReset | 47 | Med | Blow-away + rebuild orchestration |
| Invoke-LabSetup | 28 | Low | Runs preflight + bootstrap scripts |
| Invoke-LabQuickDeploy | 25 | Low | Quick deploy orchestration |
| Invoke-LabInteractiveMenu | 64 | Med | Main menu loop |
| Invoke-LabAddVMMenu | 21 | Low | VM addition sub-menu |
| Invoke-LabAddVMWizard | 80 | Med | Interactive VM creation wizard |
| Invoke-LabConfigureRoleMenu | 75 | Med | Role configuration sub-menu |
| Invoke-LabSetupMenu | 54 | Low | Setup sub-menu |
| Invoke-LabBulkVMProvision (partial) | -- | Low | Already has some try-catch; needs outer wrapper |

#### Private/ - Configuration & Data (12 functions)

| Function | Lines | Risk | Operations |
|----------|-------|------|-----------|
| Get-LabDomainConfig | 74 | Med | Reads config, builds domain object |
| Get-LabNetworkConfig | 46 | Low | Reads config, builds network object |
| Get-LabVMConfig | 151 | High | Builds VM config from template |
| Get-GitIdentity | 16 | Low | Reads git config |
| Get-HostInfo | 48 | Med | WMI/CIM queries for host info |
| Get-LabGuiDestructiveGuard | 39 | Low | Token validation logic |
| Import-LabScriptTree | 31 | Med | Dot-sources script files |
| New-LabAppArgumentList | 92 | Med | Builds complex argument lists |
| New-LabCoordinatorPlan | 50 | Med | Creates coordination plan objects |
| New-LabDeploymentReport | 124 | High | File I/O for report generation |
| New-LabUnattendXml | 124 | High | XML generation with file paths |
| Resolve-LabSqlPassword | 36 | Low | Password resolution logic |

#### Private/ - Resolution & Policy (12 functions)

| Function | Lines | Risk | Operations |
|----------|-------|------|-----------|
| Resolve-LabActionRequest | 22 | Low | Action name mapping |
| Resolve-LabCoordinatorPolicy | 145 | High | Complex policy evaluation |
| Resolve-LabDispatchMode | 41 | Low | Config-based mode resolution |
| Resolve-LabDispatchPlan | 41 | Med | Dispatch plan building |
| Resolve-LabModeDecision | 89 | Med | Mode decision tree |
| Resolve-LabNoExecuteStateOverride | 59 | Med | State file I/O |
| Resolve-LabOperationIntent | 38 | Low | Intent mapping |
| Resolve-LabOrchestrationIntent | 22 | Low | Orchestration routing |
| Resolve-LabExecutionProfile (partial) | -- | Low | Already has some; needs outer |
| Clear-LabSSHKnownHosts | 24 | Low | File deletion |
| Ensure-VMsReady | 18 | Med | VM state checking |
| Write-LabRunArtifacts | 98 | High | File I/O for artifacts |
| Show-LabMenu | 32 | Low | Console output |
| Invoke-LabMenuCommand | -- | Low | Already has try-catch |

#### Public/ (6 functions)

| Function | Lines | Risk | Operations |
|----------|-------|------|-----------|
| Initialize-LabNetwork | -- | High | vSwitch creation, NAT setup |
| New-LabNAT | -- | High | NAT creation, IP validation |
| New-LabSSHKey | -- | High | ssh-keygen execution |
| Show-LabStatus | -- | Med | Console status display |
| Test-LabNetworkHealth | -- | Med | Network diagnostics |
| Write-LabStatus | -- | Med | Status file I/O |

## Plan Breakdown Strategy

Split into 4 plans by functional area for manageable review:

1. **09-01**: Private orchestration & lifecycle functions (10 functions)
2. **09-02**: Private configuration, data & resolution functions (12 functions)
3. **09-03**: Private resolution, policy & utility functions (12 functions)
4. **09-04**: Public functions + comprehensive error handling tests (6 functions)

### Error Handling Pattern

Standard pattern for all functions:

```powershell
function Verb-LabNoun {
    [CmdletBinding()]
    param(...)

    try {
        # existing function body
    }
    catch {
        $PSCmdlet.WriteError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Verb-LabNoun: <context message> - $_", $_.Exception),
                'LabNoun.FailureType',
                [System.Management.Automation.ErrorCategory]::NotSpecified,
                $null
            )
        )
    }
}
```

Key decisions:
- Use `$PSCmdlet.WriteError()` for non-terminating errors (callers decide severity)
- Use `throw` only for functions that must halt the pipeline (e.g., initialization failures)
- Error messages include function name prefix for grep-ability
- Preserve original exception via InnerException for stack trace preservation
- Functions that already use `throw` for validation keep those; the outer try-catch handles unexpected failures

### Exit Audit (ERR-04)

No functions currently use `exit` to terminate. The only `exit` references in the codebase are in error message strings (e.g., "exit code"). ERR-04 is already satisfied.

## Success Criteria Mapping

| Criteria | Plan(s) | Verification |
|----------|---------|--------------|
| ERR-01: 28+ Private functions get try-catch | 09-01, 09-02, 09-03 | Grep count of try-catch in Private/ |
| ERR-02: 6+ Public functions get try-catch | 09-04 | Grep count of try-catch in Public/ |
| ERR-03: Messages include function name | All | Pattern match in test suite |
| ERR-04: No exit usage | Already done | Grep audit |

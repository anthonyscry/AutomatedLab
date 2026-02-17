# Phase 4: Role Provisioning - Research

## Codebase Analysis

### Architecture Overview

Role provisioning flows through two paths:

1. **LabBuilder path** (`LabBuilder/Invoke-LabBuilder.ps1` → `Build-LabFromSelection.ps1`): Interactive role selection, builds lab from scratch using AutomatedLab module. Role scripts in `LabBuilder/Roles/*.ps1` define VM specs + PostInstall scriptblocks.

2. **Deploy.ps1 path** (`Deploy.ps1`): The older monolithic deployer that hardcodes role configuration inline (DHCP scope, DNS forwarders, LIN1 creation). Overlaps with LabBuilder role scripts.

### Existing Role Scripts (LabBuilder/Roles/)

| File | Function | Status | Issues Found |
|------|----------|--------|------|
| DC.ps1 | Get-LabRole_DC | Good | Uses retries, validates NTDS+ADWS. No try-catch on PostInstall top level. |
| SQL.ps1 | Get-LabRole_SQL | Good | SA password handling works. sqlcmd check present. |
| IIS.ps1 | Get-LabRole_IIS | Good | Idempotent checks. Retries present. |
| WSUS.ps1 | Get-LabRole_WSUS | Good | wsusutil check present. Throws on missing. |
| DHCP.ps1 | Get-LabRole_DHCP | OK | No null-safety on `$LabConfig.DHCP.*` ArgumentList — will throw NullReferenceException if DHCP config block missing from config. |
| FileServer.ps1 | Get-LabRole_FileServer | **BUG** | Line 35: `param($GlobalLabConfig.Lab.DomainName)` — invalid param syntax in ScriptBlock. PowerShell requires simple variable names in param blocks, not dotted properties. Same systemic bug fixed in Phase 03-03. |
| PrintServer.ps1 | Get-LabRole_PrintServer | OK | Minor: Get-LabVM lookup may fail, fallback works. |
| DSCPullServer.ps1 | Get-LabRole_DSC | OK | Complex but well-structured. No prerequisite check for xPSDesiredStateConfiguration module availability. |
| Jumpbox.ps1 | Get-LabRole_Jumpbox | Good | RSAT install with per-capability error handling. |
| Client.ps1 | Get-LabRole_Client | **BUG** | Line 34: `param($GlobalLabConfig.Lab.DomainName, $FileServerName, $FileServerSelected)` — same invalid param syntax bug. |
| Ubuntu.ps1 | Get-LabRole_Ubuntu | OK | Linux path, deprioritized. |
| LinuxRoleBase.ps1 | Invoke-LinuxRoleCreateVM / Invoke-LinuxRolePostInstall | OK | Linux path, deprioritized. |

### Critical Bugs Found

1. **FileServer.ps1 line 35**: `param($GlobalLabConfig.Lab.DomainName)` — This is the exact same systemic bug that Phase 03-03 fixed across 12 files. PowerShell interprets this as a parameter named `$GlobalLabConfig` with type constraint `.Lab.DomainName`, which fails. Must use `-ArgumentList` with simple `param($DomainName)`.

2. **Client.ps1 line 34**: `param($GlobalLabConfig.Lab.DomainName, $FileServerName, $FileServerSelected)` — Same invalid param syntax. The `$GlobalLabConfig.Lab.DomainName` is invalid here; should be `param($DomainName, $FileServerName, $FileServerSelected)` and pass via `-ArgumentList`.

3. **DHCP.ps1**: No null-safety on `$LabConfig.DHCP.*` properties in `-ArgumentList`. If DHCP config section is missing or incomplete in the config, this will throw an unclear NullReferenceException.

### Missing Error Handling Patterns

Across all role scripts, the following patterns are inconsistent:

- **No try-catch wrappers on PostInstall scriptblocks**: If a PostInstall throws, `Build-LabFromSelection.ps1` catches it at the job level but the error message is generic. Role scripts should catch and provide role-specific context.
- **No prerequisite validation**: Roles don't check that required config keys exist before attempting to use them. Example: DSC role assumes `$LabConfig.DSCPullServer.*` keys exist.
- **No post-install verification**: After installation, roles should verify the expected service/feature is actually running. DC does this (NTDS+ADWS check), but IIS, WSUS, DHCP, FileServer, PrintServer don't verify their installed services.
- **Inconsistent retry patterns**: DC uses `-Retries 3`, most others use `-Retries 2`, SQL uses `-Retries 1`.

### Build-LabFromSelection.ps1 Orchestration Issues

1. **Post-install jobs lose context**: When non-DC roles run as background jobs (lines 396-438), errors get generic messages. The job creates a new PowerShell session, so module imports and config sourcing must work independently.
2. **No dependency ordering beyond DC-first**: If DHCP depends on AD (it authorizes in AD), and the DHCP PostInstall runs before DC PostInstall completes, authorization will fail. The current code runs DC PostInstall first (good), then all others in parallel (risky for AD-dependent operations).
3. **roleScriptMap missing Linux variants**: Map only has `Ubuntu`, not `WebServerUbuntu`, `DatabaseUbuntu`, `DockerUbuntu`, `K8sUbuntu`. These roles exist as files but aren't in the map.

### Recommendations

**Error handling strategy**: Wrap each PostInstall scriptblock body in try-catch, returning a structured result with role name, success/failure, and specific error context. This aligns with the Phase 03 pattern.

**Prerequisite validation**: Add a `Test-RolePrerequisites` check at the start of each PostInstall that validates required config keys exist. Return early with clear message if prerequisites aren't met.

**Post-install verification**: Add service/feature verification after installation:
- DC: NTDS + ADWS + DNS running (already exists)
- SQL: SQL Server service running
- IIS: W3SVC service running
- WSUS: WsusService running
- DHCP: DHCPServer service running
- FileServer: LanmanServer service running + share exists
- PrintServer: Spooler service running + Print-Server feature installed
- DSC: W3SVC running + pull endpoint responding
- Jumpbox: RSAT capabilities installed
- Client: RDP enabled

**Linux roles**: Add basic null-guard at function entry to prevent crashes if called. Don't invest in testing.

---

*Research completed: 2026-02-17*

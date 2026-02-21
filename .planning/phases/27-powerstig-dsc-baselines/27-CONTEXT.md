# Phase 27: PowerSTIG DSC Baselines - Context

**Gathered:** 2026-02-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Windows Server VMs receive role-appropriate DISA STIG DSC baselines automatically during PostInstall. Operators configure per-VM exception overrides in Lab-Config.ps1. Compliance status is cached to JSON after application. On-demand re-apply and compliance query cmdlets are provided. This phase does NOT include continuous remediation, pull-server mode, or live compliance polling.

</domain>

<decisions>
## Implementation Decisions

### STIG Configuration Block
- Add `STIG = @{...}` block to `$GlobalLabConfig` in Lab-Config.ps1, after the TTL block (Phase 26)
- Keys: `Enabled` (bool, default `$false`), `AutoApplyOnDeploy` (bool, default `$true`), `ComplianceCachePath` (string, default `.planning/stig-compliance.json`)
- Feature is disabled by default — operator must opt in via `Enabled = $true`
- All reads use ContainsKey guards (established Phase 26 pattern)

### Role-to-STIG Mapping
- DC VMs (OsRole = 'DC') receive Windows Server DC STIG profile
- Member Server VMs (OsRole = 'MS' or default) receive Windows Server Member Server STIG profile
- OS version (2019/2022) discovered at runtime from the VM via `(Get-WmiObject Win32_OperatingSystem).Version` mapped to PowerSTIG's StigData/Processed/ naming convention
- Mapping logic lives in a Private/ helper `Get-LabSTIGProfile.ps1` that returns the correct STIG technology, version, and role strings

### PowerSTIG Installation
- `Test-PowerStigInstallation` pre-flight check runs before any MOF compilation — verifies PowerSTIG 4.28.0 and its 10-module dependency chain are installed
- If not installed, `Install-Module PowerSTIG -Scope AllUsers -Force -AllowClobber` runs on the target guest VM via Invoke-Command (WinRM session)
- Installation happens once per VM during PostInstall — not re-installed on subsequent runs
- WinRM `MaxEnvelopeSizekb` raised to 8192 on each target VM before `Start-DscConfiguration` (prevents large MOF delivery failures)

### Per-VM Exception Overrides
- Declared in Lab-Config.ps1 STIG block as a hashtable keyed by VM name: `Exceptions = @{ 'dc1' = @('V-12345', 'V-67890'); 'svr1' = @('V-11111') }`
- Exception rule IDs (V-numbers) are excluded at MOF compile time via PowerSTIG's `-Exception` parameter
- VMs not listed in Exceptions get the full baseline with no exclusions
- Invalid V-numbers produce a warning but don't fail the compilation (graceful degradation)

### Compliance Cache
- Written to `.planning/stig-compliance.json` after each STIG application (cache-on-write pattern)
- Schema: top-level object with `LastUpdated` (ISO 8601), `VMs` array of objects, each containing `VMName`, `Role`, `STIGVersion`, `Status` ('Compliant'|'NonCompliant'|'Failed'|'Pending'), `ExceptionsApplied` (int count), `LastChecked` (ISO 8601), `ErrorMessage` (string or null)
- Dashboard (Phase 29) reads this file for the STIG compliance column — no live DSC queries from the UI
- File is overwritten on each full run, individual VM entries updated on per-VM re-apply

### On-Demand Cmdlets
- `Invoke-LabSTIGBaseline -VMName <name>` (Public/) re-applies STIG to a single VM — useful after config changes or exception updates
- `Get-LabSTIGCompliance` (Public/) reads stig-compliance.json and returns `[PSCustomObject[]]` with per-VM compliance breakdown
- Both follow established output patterns: return `@()` on error, `[PSCustomObject]` per VM, `[CmdletBinding()]` with `-Verbose` support

### PostInstall Integration
- STIG application runs as a PostInstall step after existing role provisioning completes
- Gated on `$GlobalLabConfig.STIG.Enabled` — skips entirely when disabled
- Runs after DC promotion is fully complete (for DC VMs) and after domain join (for member servers)
- Timeout: 10 minutes per VM for MOF compilation + application (lab VMs are fresh installs, STIGs apply quickly)

### Claude's Discretion
- Exact PowerSTIG module version pinning strategy (exact vs minimum version)
- Internal decomposition of the PostInstall integration hook
- Verbose logging detail level during MOF compilation
- Whether to use `-Wait` or polling for `Start-DscConfiguration` completion detection

</decisions>

<specifics>
## Specific Ideas

- Follow the Invoke-LabQuickModeHeal audit-trail pattern for STIG application results (repairs array, remaining issues, duration)
- The compliance JSON cache is the bridge between Phase 27 (writes it) and Phase 29 (reads it for dashboard) — keep the schema simple and stable
- PowerSTIG's StigData/Processed/ directory structure determines available profiles — the helper should enumerate what's actually installed rather than hardcoding version strings
- Exception V-numbers should be documented inline in Lab-Config.ps1 with comments explaining why each is excluded (operator responsibility, but config should have example comments)

</specifics>

<deferred>
## Deferred Ideas

- DSC pull server mode for continuous remediation — explicitly out of scope per REQUIREMENTS.md
- Automatic STIG remediation on compliance drift — fights running workloads, one-time apply only
- STIG compliance trending/history over time — future enhancement beyond v1.6

</deferred>

---

*Phase: 27-powerstig-dsc-baselines*
*Context gathered: 2026-02-20*

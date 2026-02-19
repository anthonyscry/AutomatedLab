# Phase 2: Security Hardening — Research

**Gathered:** 2026-02-16
**Method:** Codebase grep audit of all .ps1 files

## SEC-01: Password Hardcoding Audit

### Hardcoded Default Passwords Found

| Password | Location | Usage |
|----------|----------|-------|
| `SimpleLab123!` | Lab-Config.ps1:62 | `$GlobalLabConfig.Credentials.AdminPassword` default |
| `SimpleLab123!` | Public/Linux/New-LinuxGoldenVhdx.ps1:32 | Parameter default fallback |
| `SimpleLab123!` | Public/Linux/Join-LinuxToDomain.ps1:17 | Parameter default fallback |
| `SimpleLab123!` | Public/Initialize-LabVMs.ps1:109 | Fallback if `$GlobalLabConfig` unavailable |
| `SimpleLab123!` | Lab-Config.ps1:441 | Comparison for warning check |
| `SimpleLab123!` | Scripts/Test-LabPreDeploy.ps1:112 | Comparison for warning check |
| `SimpleLabSqlSa123!` | Lab-Config.ps1:15 | `$defaultSqlSaPassword` variable |
| `SimpleLabSqlSa123!` | Lab-Config.ps1:71 | `$GlobalLabConfig.Credentials.SqlSaPassword` |
| `SimpleLabSqlSa123!` | Lab-Config.ps1:333 | `$LabBuilderConfig` SQL SaPassword |

### Password Resolution Chain

Current `Resolve-LabPassword` (Private/Resolve-LabPassword.ps1):
1. Explicit value (non-empty) -> return it
2. `$env:OPENCODELAB_ADMIN_PASSWORD` -> return it
3. Throw error

**Problem:** Lab-Config.ps1 sets `AdminPassword = 'SimpleLab123!'` before `Resolve-LabPassword` is called, so option 1 always succeeds with the hardcoded default. The throw in option 3 is never reached.

**Existing warning:** Lab-Config.ps1:441-442 warns when default is in use, but execution continues.

### Files That Consume Passwords

| File | How Password is Used |
|------|---------------------|
| Deploy.ps1 | `Resolve-LabPassword`, passes to AL cmdlets, DC promotion, Linux hash |
| Scripts/Configure-LIN1.ps1 | `Resolve-LabPassword`, creates escaped password for SSH |
| Scripts/Add-LIN1.ps1 | `Resolve-LabPassword`, Linux password hash |
| LabBuilder/Build-LabFromSelection.ps1 | Reads from `$env:LAB_ADMIN_PASSWORD` or prompts, passes to AL cmdlets |
| LabBuilder/Roles/SQL.ps1 | Uses `SaPassword` from config, passes to sqlcmd |
| Public/Initialize-LabDomain.ps1 | Uses `SafeModePassword` from domain config |
| Public/Initialize-LabVMs.ps1 | Uses `AdminPassword` for VM initialization |
| Private/Test-LabDomainJoin.ps1 | Uses `SafeModePassword` for credential creation |
| Public/Test-LabDomainHealth.ps1 | Uses `SafeModePassword` for credential creation |
| GUI/Start-OpenCodeLabGUI.ps1 | Populates admin password field in Settings view |

### Design Decision (from 02-CONTEXT.md)

- Keep default password in Lab-Config.ps1 but **warn loudly** on every run
- Resolution order: parameter > environment variable > config default (with warning) > interactive prompt
- Environment variable names: `OPENCODELAB_ADMIN_PASSWORD`, `LAB_ADMIN_PASSWORD`

## SEC-02: SSH Host Key Audit

### Current SSH Options Across Codebase

| File | StrictHostKeyChecking | UserKnownHostsFile |
|------|----------------------|-------------------|
| Private/Linux/Invoke-LinuxSSH.ps1 | `accept-new` | `NUL` (BAD) |
| Private/Linux/Copy-LinuxFile.ps1 | `accept-new` | `NUL` (BAD) |
| Scripts/Test-OpenCodeLabHealth.ps1:220 | `accept-new` | `NUL` (BAD) |
| Scripts/Test-OpenCodeLabHealth.ps1:261 | `accept-new` | N/A (good) |
| Scripts/Open-LabTerminal.ps1 | `accept-new` | N/A (good) |
| Scripts/Install-Ansible.ps1 | `accept-new` | `NUL` (BAD) |
| LabBuilder/Roles/LinuxRoleBase.ps1 | `accept-new` | `NUL` (BAD) |
| Public/Linux/Get-LinuxSSHConnectionInfo.ps1 | `accept-new` | N/A (good) |

### Analysis

- All files correctly use `StrictHostKeyChecking=accept-new` (not `=no`) -- good.
- **Problem:** 6 locations set `UserKnownHostsFile=NUL`, which discards the known_hosts file entirely. This means `accept-new` is meaningless -- keys are never stored so every connection is "new."
- Fix: Use a lab-specific known_hosts file instead of `NUL`. Configure path in `$GlobalLabConfig`.
- Teardown should clear this file so redeploy gets fresh keys.

### No `StrictHostKeyChecking=no` Found

Grep for `StrictHostKeyChecking=no` returns zero results. Good.

## SEC-03: Download Checksum Audit

### External Downloads From Host

| Download | File | Checksum? |
|----------|------|-----------|
| Git for Windows installer | Deploy.ps1:934 | YES -- `ExpectedSha256` parameter, validated via `Get-FileHash` (Deploy.ps1:937-944) |

**Only one host-side download exists** (Git installer). It already validates SHA256 checksums against `$GlobalLabConfig.SoftwarePackages.Git.Sha256`.

### Downloads Inside VMs (heredoc scripts)

| Download | File | Checksum? |
|----------|------|-----------|
| Docker GPG key via curl | LabBuilder/Roles/Docker.Ubuntu.ps1:54 | NO -- fetched by apt-key, apt handles verification |
| K3s install script | LabBuilder/Roles/K8s.Ubuntu.ps1:55 | NO -- piped to `sh`, typical for K3s |
| apt-get packages | Multiple Ubuntu role files | NO -- apt handles package verification |

**Assessment:** In-VM downloads use package manager verification (apt GPG) or are standard install patterns (K3s). The K3s pipe-to-shell pattern is inherently insecure but is the official install method and changing it is out of scope (would require maintaining K3s binaries locally).

### Recommendation

- Git installer: Already validated. Ensure checksum is always required (not optional).
- Make `ExpectedSha256` parameter mandatory (currently conditional: `if ($ExpectedSha256)`)
- Add a helper function `Test-LabDownloadChecksum` for reuse if more downloads are added later.

## SEC-04: Credential Leak in Logs/Artifacts Audit

### Console Output (Write-Host)

| File | Line | Risk |
|------|------|------|
| Deploy.ps1:724 | `Write-Host "  Generating password hash..."` | LOW -- no password value |
| LabBuilder/Roles/SQL.ps1:56,90 | Status messages about SA password | LOW -- no actual value |
| Scripts/Add-LIN1.ps1:233 | `Write-Host "  Password: ********** (see Lab-Config.ps1)"` | GOOD -- already masked |
| Lab-Config.ps1:442 | `Write-Warning` about default password | LOW -- mentions "default value" not actual value |

**No console output was found that prints actual password values.** The codebase is already careful about this.

### Run Artifacts (JSON)

| File | What's Serialized | Risk |
|------|-------------------|------|
| OpenCodeLab-App.ps1:170 | Run report (action, timing, host outcomes) | LOW -- no credentials in report object |
| Public/Write-RunArtifact.ps1:117 | Operation results, error records, custom data | MEDIUM -- `CustomData` hashtable could contain anything |
| LabBuilder/Build-LabFromSelection.ps1:526,625 | Build summary with timing | LOW -- credentials not in summary object |

### Error Stack Traces

Error records include `ScriptStackTrace` (Write-RunArtifact.ps1:105). If a password variable is in scope when an error occurs, the stack trace could theoretically reference it. However, PowerShell stack traces don't dump variable values -- they show script paths and line numbers only.

### GUI Settings

`GUI/Start-OpenCodeLabGUI.ps1` saves settings to `gui-settings.json`. Need to verify the AdminPassword field is NOT persisted to this file.

### Recommendations

1. Add a `Protect-LabLogString` scrubbing function that redacts known password patterns before any output
2. Apply scrubbing to: Write-RunArtifact `CustomData`, any future logging, error messages
3. Redact format: `***REDACTED***`
4. Pattern match against: known default passwords, env var values for password env vars
5. Ensure GUI settings save does NOT serialize password fields

## Summary: Scope of Changes

### Plan 02-01: Credential Resolution & Warning (SEC-01)
- Update `Resolve-LabPassword` to implement full resolution chain with warning on default
- Remove hardcoded fallback `'SimpleLab123!'` from Public/ function parameter defaults
- Add `Resolve-LabSqlPassword` or extend pattern for SQL SA password
- Files: `Private/Resolve-LabPassword.ps1`, `Lab-Config.ps1`, `Public/Linux/New-LinuxGoldenVhdx.ps1`, `Public/Linux/Join-LinuxToDomain.ps1`, `Public/Initialize-LabVMs.ps1`

### Plan 02-02: SSH Known Hosts Hardening (SEC-02)
- Add `SSH.KnownHostsPath` to `$GlobalLabConfig`
- Replace all `UserKnownHostsFile=NUL` with lab-specific known_hosts path
- Add known_hosts cleanup to teardown
- Create `Clear-LabSSHKnownHosts` helper
- Files: `Lab-Config.ps1`, `Private/Linux/Invoke-LinuxSSH.ps1`, `Private/Linux/Copy-LinuxFile.ps1`, `Scripts/Test-OpenCodeLabHealth.ps1`, `Scripts/Install-Ansible.ps1`, `LabBuilder/Roles/LinuxRoleBase.ps1`

### Plan 02-03: Download Checksum Enforcement & Log Scrubbing (SEC-03, SEC-04)
- Make checksum validation mandatory for Git download (remove `if ($ExpectedSha256)` conditional)
- Create `Protect-LabLogString` scrubbing function
- Wrap `Write-RunArtifact` custom data through scrubber
- Verify GUI settings don't persist passwords
- Files: `Deploy.ps1`, `Private/Protect-LabLogString.ps1` (new), `Public/Write-RunArtifact.ps1`, `GUI/Start-OpenCodeLabGUI.ps1`

---
*Research completed: 2026-02-16*
*Audited: All .ps1 files in repository*

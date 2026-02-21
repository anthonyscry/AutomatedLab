# Phase 28: ADMX / GPO Auto-Import - Context

**Gathered:** 2026-02-20
**Status:** Ready for planning

<domain>
## Phase Boundary

After DC promotion completes, automatically populate the ADMX Central Store from the DC's own PolicyDefinitions and optionally create baseline GPOs from shipped JSON templates. Third-party ADMX bundles can be imported from a configured path. This phase does NOT include GPO reporting/auditing, GPO backup/restore, or Group Policy Preferences configuration.

</domain>

<decisions>
## Implementation Decisions

### AD Readiness Gate
- `Wait-LabADReady` helper gates on `Get-ADDomain` success (not just WinRM responsiveness) before any ADMX or GPO operations — eliminates ADWS startup race condition
- Retry loop with configurable timeout (default 120 seconds, 10-second intervals)
- Called at the start of ADMX/GPO operations, after DC promotion is confirmed complete
- Returns `[pscustomobject]` with `Ready` (bool), `DomainName`, `WaitSeconds` fields

### ADMX Central Store Population
- `Invoke-LabADMXImport` copies ADMX/ADML files from the DC's `C:\Windows\PolicyDefinitions` to `\\<domain>\SYSVOL\<domain>\Policies\PolicyDefinitions` (the Central Store path)
- Uses `Copy-Item -Recurse` via Invoke-Command on the DC — copies both `.admx` files and language-specific `.adml` subdirectories (e.g., `en-US/`)
- Idempotent: overwrites existing files without error (fresh lab, no version conflict concern)
- Returns audit result object following Invoke-LabQuickModeHeal pattern: `FilesImported` (int), `Success` (bool), `CentralStorePath`, `DurationSeconds`

### ADMX Configuration Block
- Add `ADMX = @{...}` block to `$GlobalLabConfig` in Lab-Config.ps1, after the STIG block
- Keys: `Enabled` (bool, default `$true` — ADMX import runs by default after DC promotion), `CreateBaselineGPO` (bool, default `$false`), `ThirdPartyADMX` (array of hashtables, default `@()`)
- ThirdPartyADMX entry format: `@{ Name = 'Chrome'; Path = 'C:\ADMX\Chrome' }` — operator provides local path, no internet download
- All reads use ContainsKey guards (established pattern)

### Baseline GPO Creation
- When `CreateBaselineGPO = $true`, creates GPOs from shipped JSON template definitions
- Four pre-built templates ship with the project in a `Templates/GPO/` directory:
  - `password-policy.json` — minimum length, complexity, history, max age
  - `account-lockout.json` — threshold, duration, observation window
  - `audit-policy.json` — logon events, object access, policy change, privilege use
  - `applocker.json` — default executable, Windows installer, and script rules
- Each JSON template specifies: `Name`, `LinkTarget` (domain root DN), `Settings` array of registry-based policy values
- GPOs created via `New-GPO`, linked via `New-GPLink` to domain root
- `Invoke-LabADMXImport` handles both ADMX import and GPO creation in a single function call (gated on config flags)

### Third-Party ADMX Import
- Disabled by default (`ThirdPartyADMX = @()`)
- When entries are present, copies ADMX/ADML files from the specified local path to the Central Store
- No internet download behavior — operator places bundles on the host, provides the path
- Each entry processed independently; failure on one doesn't block others
- Warning logged for paths that don't exist or contain no `.admx` files

### PostInstall Integration
- ADMX/GPO operations run as a PostInstall step in `LabBuilder/Roles/DC.ps1`, after the STIG step (Phase 27) completes
- Gated on `$GlobalLabConfig.ADMX.Enabled` — skips entirely when disabled
- Follows the same try-catch pattern: ADMX failure does not abort DC deployment
- Calls `Wait-LabADReady` first, then `Invoke-LabADMXImport`

### Claude's Discretion
- Exact JSON schema for GPO template files beyond the documented fields
- Whether to use `Set-GPRegistryValue` or `Set-GPPrefRegistryValue` for applying settings
- Internal helper decomposition (single function vs separate ADMX/GPO helpers)
- Verbose logging detail during file copy operations
- Whether GPO link order matters (all linked to domain root, order is cosmetic for a lab)

</decisions>

<specifics>
## Specific Ideas

- The Wait-LabADReady helper solves a real-world timing issue: DC promotion returns before ADWS is fully responsive, causing Get-ADDomain to fail if called immediately
- GPO JSON templates should be human-readable and self-documenting — operators should be able to inspect and modify them without deep GPO knowledge
- Keep the ADMX import simple: straight file copy from PolicyDefinitions to Central Store. No versioning, no conflict resolution — this is a fresh lab environment
- Third-party ADMX is explicitly "bring your own files" per REQUIREMENTS.md out-of-scope decision on auto-download

</specifics>

<deferred>
## Deferred Ideas

- GPO backup/restore functionality — separate concern from initial import
- GPO compliance reporting — would complement STIG compliance but out of v1.6 scope
- Automatic ADMX download from vendor URLs — explicitly out of scope per REQUIREMENTS.md security decision

</deferred>

---

*Phase: 28-admx-gpo-auto-import*
*Context gathered: 2026-02-20*

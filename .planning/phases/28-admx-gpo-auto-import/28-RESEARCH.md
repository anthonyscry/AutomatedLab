# Phase 28: ADMX / GPO Auto-Import - Research

**Researched:** 2026-02-20
**Domain:** Active Directory Group Policy Management, ADMX Central Store, PowerShell GroupPolicy Module
**Confidence:** HIGH

## Summary

This phase requires implementing automatic ADMX Central Store population and baseline GPO creation after DC promotion. The PowerShell **GroupPolicy module** provides native cmdlets (`New-GPO`, `Set-GPRegistryValue`, `New-GPLink`) for GPO management. The ADMX Central Store follows a well-established path pattern: `\\<domain>\SYSVOL\<domain>\Policies\PolicyDefinitions`. The key technical challenge is the ADWS (Active Directory Web Services) startup race condition after DC promotion, which requires a `Wait-LabADReady` helper using retry logic with `Get-ADDomain` verification.

The existing codebase provides excellent patterns to follow:
1. **PostInstall integration pattern** from `LabBuilder/Roles/DC.ps1` Phase 27 (STIG)
2. **Configuration block pattern** from `Get-LabSTIGConfig.ps1` with ContainsKey guards
3. **Result object pattern** from `Invoke-LabSTIGBaselineCore.ps1` for auditability
4. **Template pattern** from `.planning/templates/` for JSON-based definitions

**Primary recommendation:** Use the PowerShell GroupPolicy module's native cmdlets, implement ADWS readiness gating, follow the established STIG config pattern for the ADMX block, and ship four baseline GPO JSON templates (password policy, account lockout, audit policy, AppLocker).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **ADMX Configuration Block**: Add `ADMX = @{...}` block to `$GlobalLabConfig` in Lab-Config.ps1, after the STIG block
- **Keys**: `Enabled` (bool, default `$true`), `CreateBaselineGPO` (bool, default `$false`), `ThirdPartyADMX` (array of hashtables, default `@()`)
- **ThirdPartyADMX entry format**: `@{ Name = 'Chrome'; Path = 'C:\ADMX\Chrome' }`
- **ADMX Central Store Path**: `\\<domain>\SYSVOL\<domain>\Policies\PolicyDefinitions`
- **AD Readiness Gate**: `Wait-LabADReady` helper gates on `Get-ADDomain` success before any ADMX/GPO operations
- **PostInstall Integration**: Runs as PostInstall step in `LabBuilder/Roles/DC.ps1`, after STIG step
- **Four baseline GPO templates**: `password-policy.json`, `account-lockout.json`, `audit-policy.json`, `applocker.json` in `Templates/GPO/`

### Claude's Discretion
- Exact JSON schema for GPO template files beyond the documented fields (Name, LinkTarget, Settings array of registry-based policy values)
- Whether to use `Set-GPRegistryValue` or `Set-GPPrefRegistryValue` for applying settings
- Internal helper decomposition (single function vs separate ADMX/GPO helpers)
- Verbose logging detail during file copy operations
- Whether GPO link order matters (all linked to domain root, order is cosmetic for a lab)

### Deferred Ideas (OUT OF SCOPE)
- GPO backup/restore functionality
- GPO compliance reporting
- Automatic ADMX download from vendor URLs
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| GPO-01 | ADMX central store auto-populated on DC after domain promotion completes | PowerShell `Copy-Item` can copy from `C:\Windows\PolicyDefinitions` to Central Store path. ADWS readiness gating prevents race condition. |
| GPO-02 | Baseline GPO created and linked to domain from JSON template definitions | `New-GPO` creates GPOs, `Set-GPRegistryValue` applies registry settings, `New-GPLink` links to domain root DN. JSON parsing with `ConvertFrom-Json` and iteration over Settings array. |
| GPO-03 | Pre-built security GPO templates shipped (password policy, account lockout, audit policy, AppLocker | Four JSON files in `Templates/GPO/` directory. Registry keys documented for password/lockout policies (Sam/Settings/), audit policies (Audit/), and AppLocker (Software\Policies\Microsoft\Windows\SrpGV). |
| GPO-04 | Third-party ADMX bundles importable via config setting with download + copy workflow | `ThirdPartyADMX` array in config. Each entry processed independently with `Test-Path` validation before `Copy-Item` to Central Store. No internet download per REQUIREMENTS.md security decision. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| **PowerShell GroupPolicy Module** | Built-in (RSAT) | GPO creation, registry settings, linking | Native Windows module for GPO management. Provides `New-GPO`, `Set-GPRegistryValue`, `New-GPLink`, `Get-GPO`. |
| **ActiveDirectory Module** | Built-in (RSAT) | AD domain queries, ADWS readiness verification | Standard for AD operations. `Get-ADDomain` confirms ADWS is responsive. |
| **Hyper-V Module** | Built-in | VM operations, Invoke-Command for remote execution | Project's existing infrastructure for VM communication. |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **Pester 5.x** | 5.0+ | Unit testing | Already in project. Test helper functions with mocked `Get-ADDomain`, `Copy-Item`, GroupPolicy cmdlets. |
| **JSON (PowerShell)** | Built-in | Template definition, configuration storage | Project uses JSON for templates (`.planning/templates/`) and config (`config.json`). |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| GroupPolicy module | LGPO.exe (Local Group Policy utility) | LGPO.exe is external tool, not native PowerShell. GroupPolicy module is more programmable and testable. |
| JSON templates | CSV/XML | JSON is already project standard for templates. Better structured data support than CSV. XML is more verbose. |
| Set-GPRegistryValue | Set-GPPrefRegistryValue | Set-GPRegistryValue is for policy settings (enforced). Set-GPPrefRegistryValue is for preferences (can be overridden). Policy settings are appropriate for security baselines. |

**Installation:**
```powershell
# No installation required - GroupPolicy and ActiveDirectory modules are built-in to Windows
# RSAT feature may need installation on client OS:
Add-WindowsCapability -Online -Name Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

## Architecture Patterns

### Recommended Project Structure
```
/mnt/c/projects/AutomatedLab/
├── Private/
│   ├── Invoke-LabADMXImport.ps1       # Main helper: ADMX import + GPO creation
│   ├── Wait-LabADReady.ps1            # ADWS readiness gate
│   └── Get-LabADMXConfig.ps1          # Config reader (follows Get-LabSTIGConfig pattern)
├── Public/
│   └── Invoke-LabADMXImport.ps1       # Public wrapper (optional, if user-invokable)
├── LabBuilder/Roles/
│   └── DC.ps1                         # Modified: Add ADMX step after STIG
├── Templates/GPO/                     # NEW: GPO template directory
│   ├── password-policy.json
│   ├── account-lockout.json
│   ├── audit-policy.json
│   └── applocker.json
└── Tests/
    ├── Invoke-LabADMXImport.Tests.ps1
    ├── Wait-LabADReady.Tests.ps1
    └── Get-LabADMXConfig.Tests.ps1
```

### Pattern 1: PostInstall Integration (from DC.ps1 STIG pattern)
**What:** PostInstall scriptblock in DC role calls helper after STIG step
**When to use:** Integration point for DC1 PostInstall workflow
**Example:**
```powershell
# From LabBuilder/Roles/DC.ps1, lines 78-101
# 3. Apply STIG baseline (if enabled)
if (Test-Path variable:GlobalLabConfig) {
    if ($GlobalLabConfig.ContainsKey('STIG') -and $GlobalLabConfig.STIG.ContainsKey('Enabled') -and $GlobalLabConfig.STIG.Enabled) {
        # ... STIG application ...
    }
}

# 4. Populate ADMX Central Store and create baseline GPOs (if enabled)
if (Test-Path variable:GlobalLabConfig) {
    if ($GlobalLabConfig.ContainsKey('ADMX') -and $GlobalLabConfig.ADMX.ContainsKey('Enabled') -and $GlobalLabConfig.ADMX.Enabled) {
        try {
            Write-Host "  Waiting for ADWS readiness..." -ForegroundColor Cyan
            $adReady = Wait-LabADReady -DomainName $LabConfig.DomainName
            if (-not $adReady.Ready) {
                Write-Warning "DC role: ADWS did not become ready within timeout. Skipping ADMX/GPO operations."
            }
            else {
                Write-Host "  Populating ADMX Central Store and creating baseline GPOs..." -ForegroundColor Cyan
                $admxResult = Invoke-LabADMXImport -DCName $dcName -DomainName $LabConfig.DomainName
                if ($admxResult.Success) {
                    Write-Host "  [OK] ADMX import complete: $($admxResult.FilesImported) files imported." -ForegroundColor Green
                }
                else {
                    Write-Warning "DC role: ADMX import failed: $($admxResult.Message)"
                }
            }
        }
        catch {
            Write-Warning "DC role: ADMX/GPO operations failed on ${dcName}: $($_.Exception.Message). Lab deployment continues."
        }
    }
}
```

### Pattern 2: Configuration Block with ContainsKey Guards (from Get-LabSTIGConfig.ps1)
**What:** Safe config reading with ContainsKey guards to prevent StrictMode failures
**When to use:** All GlobalLabConfig reads in helper functions
**Example:**
```powershell
# From Private/Get-LabSTIGConfig.ps1 - Pattern to follow
function Get-LabADMXConfig {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $admxBlock = if (Test-Path variable:GlobalLabConfig) {
        if ($GlobalLabConfig.ContainsKey('ADMX')) { $GlobalLabConfig.ADMX } else { @{} }
    } else { @{} }

    [pscustomobject]@{
        Enabled            = if ($admxBlock.ContainsKey('Enabled'))            { [bool]$admxBlock.Enabled }             else { $true }
        CreateBaselineGPO  = if ($admxBlock.ContainsKey('CreateBaselineGPO')) { [bool]$admxBlock.CreateBaselineGPO }  else { $false }
        ThirdPartyADMX     = if ($admxBlock.ContainsKey('ThirdPartyADMX'))     { $admxBlock.ThirdPartyADMX }            else { @() }
    }
}
```

### Pattern 3: Result Object for Auditability (from Invoke-LabSTIGBaselineCore.ps1)
**What:** Returns PSCustomObject with Success, files processed, duration
**When to use:** All helpers that perform actions (file copies, GPO creation)
**Example:**
```powershell
return [pscustomobject]@{
    Success        = $true
    FilesImported  = $admxFilesCopied
    GPOsCreated    = @($gposCreated)
    CentralStorePath = $centralStorePath
    DurationSeconds = [int]((Get-Date) - $startTime).TotalSeconds
    Message        = ''
}
```

### Pattern 4: JSON Template Processing
**What:** Read JSON file, deserialize, iterate over settings array
**When to use:** GPO template loading in Invoke-LabADMXImport
**Example:**
```powershell
$templatePath = Join-Path (Join-Path $repoRoot 'Templates') 'GPO'
$templateJson = Get-Content (Join-Path $templatePath 'password-policy.json') -Raw | ConvertFrom-Json

$gpoName = $templateJson.Name
$linkTarget = $templateJson.LinkTarget  # e.g., "DC=simplelab,DC=local"

# Create GPO
$gpo = New-GPO -Name $gpoName -ErrorAction Stop

# Apply registry settings from template
foreach ($setting in $templateJson.Settings) {
    $key = $setting.Key
    $valueName = $setting.ValueName
    $value = $setting.Value
    $type = $setting.Type  # String, DWord, QWord, etc.

    Set-GPRegistryValue -Name $gpoName -Key $key -ValueName $valueName -Value $value -Type $type
}

# Link to domain
New-GPLink -Name $gpoName -Target $linkTarget
```

### Anti-Patterns to Avoid
- **Direct registry modification**: Don't use `Set-ItemProperty` on registry. Use GPO cmdlets for policy management.
- **Hardcoded domain names**: Always use `$LabConfig.DomainName` from config, not 'simplelab.local' literals.
- **Missing ContainsKey guards**: Never access `$GlobalLabConfig.ADMX.Enabled` directly. Use ContainsKey checks or `Get-LabADMXConfig`.
- **Synchronous ADWS waits without timeout**: Don't loop infinitely checking ADWS. Always use timeout and retry interval.
- **Assuming PolicyDefinitions exists**: Always `Test-Path` before copying to/from `C:\Windows\PolicyDefinitions`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| GPO creation from scratch | Custom COM/ADSIScripter approach | `New-GPO`, `Set-GPRegistryValue`, `New-GPLink` | Native PowerShell GroupPolicy module handles all GPO operations |
| ADWS readiness detection | Custom port 9389 TCP checks | `Get-ADDomain` with retry loop | Standard AD cmdlet validates full ADWS functionality |
| Registry policy settings | Direct registry manipulation via Invoke-Command | `Set-GPRegistryValue` | Ensures policies are applied via GPO system, not direct registry edits |
| JSON template parsing | Custom string splitting | `ConvertFrom-Json` | Built-in, handles escaped characters, nested objects |
| File copy to SYSVOL | Robocopy scripts | `Copy-Item -Recurse` | PowerShell native idempotent operation |

**Key insight:** The GroupPolicy module provides complete GPO management capability. Building custom wrappers around ADSIScripter or direct registry manipulation introduces complexity and fragility. Use the native cmdlets.

## Common Pitfalls

### Pitfall 1: ADWS Not Ready After DC Promotion
**What goes wrong:** `New-GPO` or `Get-ADDomain` fails immediately after DC promotion returns
**Why it happens:** ADWS service takes time to start and become fully responsive after `Install-ADDSForest`
**How to avoid:** Implement `Wait-LabADReady` helper with retry loop (default 120 seconds, 10-second intervals) that gates on `Get-ADDomain` success
**Warning signs:** Errors like "The server is not operational" or "A device attached to the system is not functioning" from AD cmdlets

### Pitfall 2: Central Store Path Not Accessible
**What goes wrong:** `Copy-Item` to `\\domain\SYSVOL\domain\Policies\PolicyDefinitions` fails with "The network path was not found"
**Why it happens:** SYSVOL may not be fully replicated or DFS-R hasn't finished initial sync
**How to avoid:** Wait for ADWS readiness first (which implies AD services are up), then use the DC's local path `C:\Windows\PolicyDefinitions` as source
**Warning signs:** Path not found errors, access denied errors

### Pitfall 3: ContainsKey Violations in StrictMode
**What goes wrong:** Script throws "The property 'Enabled' cannot be found on this object"
**Why it happens:** `Set-StrictMode -Version Latest` is set, and code accesses missing hashtable keys without checking
**How to avoid:** Always use `ContainsKey` guards or `Get-LabADMXConfig` helper pattern from Phase 27
**Warning signs:** StrictMode exceptions on config reads

### Pitfall 4: PowerShell 5.1 Join-Path Limitation
**What goes wrong:** `Join-Path 'C:\A' 'B' 'C'` throws "Parameter set cannot be resolved"
**Why it happens:** PowerShell 5.1 Join-Path only accepts 2 arguments (Path + ChildPath)
**How to avoid:** Use nested Join-Path: `Join-Path (Join-Path 'C:\A' 'B') 'C'`
**Warning signs:** ParameterSetName error on Join-Path calls

### Pitfall 5: GPO Link Target DN Format
**What goes wrong:** `New-GPLink -Target 'simplelab.local'` fails with "The directory service cannot perform the requested operation"
**Why it happens:** `-Target` requires distinguished name (DN) format like `DC=simplelab,DC=local`, not FQDN
**How to avoid:** Convert domain FQDN to DN format: `'simplelab.local' -split '\.' | ForEach-Object { "DC=$_" }` or use ADFind approach
**Warning signs:** Invalid DN syntax errors from New-GPLink

## Code Examples

Verified patterns from official sources and project codebase:

### Wait-LabADReady Pattern (ADWS Readiness Gate)
```powershell
# Pattern from Initialize-LabDomain.ps1 + web search verification
function Wait-LabADReady {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$DomainName,

        [int]$TimeoutSeconds = 120,

        [int]$RetryIntervalSeconds = 10
    )

    $startTime = Get-Date
    $elapsed = 0
    $ready = $false

    while (-not $ready -and $elapsed -lt $TimeoutSeconds) {
        try {
            # Get-ADDomain validates full ADWS functionality
            $domain = Get-ADDomain -Identity $DomainName -ErrorAction Stop
            $ready = $true
        }
        catch {
            Write-Verbose "ADWS not ready yet: $($_.Exception.Message)"
            Start-Sleep -Seconds $RetryIntervalSeconds
        }
        $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
    }

    return [pscustomobject]@{
        Ready = $ready
        DomainName = $DomainName
        WaitSeconds = $elapsed
    }
}
```

### ADMX Central Store Copy Pattern
```powershell
# Verified by web search: Central Store path pattern
function Copy-LabADMXToCentralStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$DomainName
    )

    $centralStorePath = "\\$DomainName\SYSVOL\$DomainName\Policies\PolicyDefinitions"
    $sourcePath = "\\$ComputerName\C$\Windows\PolicyDefinitions"

    # Copy ADMX files
    $admxFiles = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        Get-ChildItem -Path 'C:\Windows\PolicyDefinitions' -Filter '*.admx'
    }

    $filesImported = 0
    foreach ($file in $admxFiles) {
        $destPath = Join-Path $centralStorePath $file.Name
        Copy-Item -Path $file.FullName -Destination $destPath -Force
        $filesImported++
    }

    # Copy ADML subdirectories (en-US, etc.)
    $admlDirs = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
        Get-ChildItem -Path 'C:\Windows\PolicyDefinitions' -Directory
    }

    foreach ($dir in $admlDirs) {
        $destDir = Join-Path $centralStorePath $dir.Name
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        $admlFiles = Get-ChildItem -Path (Join-Path $sourcePath $dir.Name) -Filter '*.adml'
        foreach ($file in $admlFiles) {
            Copy-Item -Path $file.FullName -Destination $destDir -Force
            $filesImported++
        }
    }

    return $filesImported
}
```

### GPO Creation from JSON Template
```powershell
# Pattern from web search: GroupPolicy module usage
function New-LabGPOFromTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TemplatePath,

        [Parameter(Mandatory)]
        [string]$DomainDN
    )

    $template = Get-Content $TemplatePath -Raw | ConvertFrom-Json

    # Create GPO
    $gpo = New-GPO -Name $template.Name -ErrorAction Stop

    # Apply each registry setting
    foreach ($setting in $template.Settings) {
        $params = @{
            Name      = $template.Name
            Key       = $setting.Key
            ValueName = $setting.ValueName
            Value     = $setting.Value
            Type      = $setting.Type
        }

        # Handle both HKLM and HKCU keys
        if ($setting.Key -match '^HKLM\\') {
            # Computer Configuration
            $params.Key = $setting.Key -replace '^HKLM\\', ''
        }
        elseif ($setting.Key -match '^HKCU\\') {
            # User Configuration
            $params.Key = $setting.Key -replace '^HKCU\\', '
            # Add -KeyPrefix User if needed (Set-GPRegistryValue infers from Key)
        }

        Set-GPRegistryValue @params
    }

    # Link to domain root
    New-GPLink -Name $template.Name -Target $DomainDN

    return $gpo
}
```

### FQDN to DN Conversion
```powershell
# Helper for domain root DN format
function ConvertTo-DomainDN {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$DomainFQDN
    )

    $parts = $DomainFQDN -split '\.'
    $dnParts = $parts | ForEach-Object { "DC=$_" }
    return $dnParts -join ','
}

# Usage:
# ConvertTo-DomainDN -DomainFQDN 'simplelab.local'
# Returns: DC=simplelab,DC=local
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual GPO creation via GPMC | PowerShell GroupPolicy module automation | Windows Server 2008 R2 | Programmatic GPO management now possible |
| Local ADMX files per admin | Centralized ADMX Central Store | Windows Server 2008 | Consistent GPO editing across domain |
| GPO backup/restore via GPMC | Backup-GPO / Import-GPO cmdlets | Windows Server 2012 | Scriptable GPO migration |
| ADWS readiness polling | Get-ADDomain with retry loop | Windows Server 2016 | More reliable ADWS detection |

**Deprecated/outdated:**
- **LGPO.exe for domain GPOs**: LGPO.exe is designed for local GPOs only. Use GroupPolicy module for domain GPOs.
- **Direct ADSIScripter for GPOs**: The GroupPolicy module provides a cleaner abstraction. ADSIScripter is lower-level and error-prone.

## Open Questions

1. **GPO Registry Key Hive Prefix Handling**
   - What we know: `Set-GPRegistryValue` accepts registry keys in both `HKLM\Software\...` and `HKCU\Software\...` formats
   - What's unclear: Whether the hive prefix (`HKLM`/`HKCU`) is automatically inferred or needs explicit configuration switch
   - Recommendation: Test with both Computer Configuration (HKLM) and User Configuration (HKCU) settings during implementation. The cmdlet may automatically route to the correct GPO section based on hive prefix.

2. **GPO Link Order Enforcement**
   - What we know: `New-GPLink` accepts `-LinkOrder` parameter (0-99999) to control precedence
   - What's unclear: Whether link order matters for baseline GPOs all targeting domain root (same container)
   - Recommendation: Skip explicit `-LinkOrder` for initial implementation. All baseline GPOs apply to domain root; order is cosmetic for a lab environment. Add `-LinkOrder` parameter support if customer needs arise.

3. **ADML Language Directory Detection**
   - What we know: ADML files reside in subdirectories like `en-US`, `ko-KR`, etc.
   - What's unclear: Whether to copy all language directories or only detect/install OS language
   - Recommendation: Copy all ADML subdirectories found in `C:\Windows\PolicyDefinitions`. Storage is cheap, and this ensures language support for multi-language labs. Add language filtering optimization later if needed.

## Sources

### Primary (HIGH confidence)
- **Context7 - PowerShell GroupPolicy Module**: Available cmdlets, parameters, and usage patterns for GPO management
- **Project Codebase - DC.ps1** (lines 31-105): PostInstall pattern for STIG integration in DC role, demonstrating try-catch error handling and config gating
- **Project Codebase - Get-LabSTIGConfig.ps1**: ContainsKey guard pattern for safe GlobalLabConfig reading
- **Project Codebase - Invoke-LabSTIGBaselineCore.ps1** (lines 1-298): Result object pattern with audit fields (Success, VMsProcessed, Repairs, DurationSeconds)
- **Project Codebase - Lab-Config.ps1** (lines 219-229): STIG configuration block structure and default values

### Secondary (MEDIUM confidence)
- **WebSearch - PowerShell GroupPolicy Module 2025**: Verified `New-GPO`, `Set-GPRegistryValue`, `New-GPLink` cmdlets are current and supported. Documentation confirms -Key parameter accepts registry paths, -Type specifies RegistryValueKind (String, DWord, QWord, MultiString, ExpandString, Binary, None).
- **WebSearch - ADMX Central Store Best Practices**: Confirmed Central Store path `\\<domain>\SYSVOL\<domain>\Policies\PolicyDefinitions`, source location `C:\Windows\PolicyDefinitions`, and ADML subdirectory structure for language files.
- **WebSearch - ADWS Readiness Patterns**: Verified `Get-ADDomain` is the standard approach for ADWS readiness verification. ADWS runs on TCP port 9389 and depends on NTDS service being operational.

### Tertiary (LOW confidence)
- **WebSearch - GPO JSON Template Patterns**: No native JSON import capability in GroupPolicy module. Custom implementation required to parse JSON and call `Set-GPRegistryValue`. Considered LOW confidence because direct documentation is scarce; implementation should validate JSON schema empirically.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - GroupPolicy and ActiveDirectory modules are built-in Windows components with stable APIs
- Architecture: HIGH - Existing project patterns (STIG config, PostInstall integration, result objects) provide clear guidance
- Pitfalls: HIGH - ADWS startup race condition is well-documented; ContainsKey guards are proven pattern in Phase 27

**Research date:** 2026-02-20
**Valid until:** 2026-04-20 (60 days - PowerShell GroupPolicy module is stable, unlikely to change)

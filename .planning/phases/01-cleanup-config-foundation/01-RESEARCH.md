# Phase 1: Cleanup & Config Foundation - Research

**Researched:** 2026-02-16
**Domain:** PowerShell brownfield refactoring, configuration management, dead code removal
**Confidence:** HIGH

## Summary

Phase 1 addresses technical debt in a mature PowerShell codebase (107 functions, 11,000+ lines) with three distinct helper sourcing patterns, dual configuration systems (legacy variables + GlobalLabConfig hashtable), and archived/dead code accumulated during development. The codebase uses PowerShell 5.1+ with Pester 5.x testing (28 test files, 266 tests), pure PowerShell WPF GUI, and strict mode enforcement.

Research confirms that aggressive cleanup is safe (git history preserves deleted code), configuration unification is straightforward (consumers are localized), and helper sourcing can be standardized without breaking changes. The key technical challenge is maintaining PowerShell 5.1 compatibility while enforcing strict validation patterns.

**Primary recommendation:** Standardize on dynamic discovery helper sourcing (Lab-Common.ps1 pattern with Import-LabScriptTree), eliminate legacy variables immediately, validate configuration on load with loud failures, and delete dead code/archives without ceremony.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
**Dead code removal:**
- Delete `.archive/` directory entirely — it's in git history if needed
- Delete all leftover test/debug scripts (test-*.ps1, test.json) — they served their purpose
- `git rm` coverage.xml and .tools/powershell-lsp/ from tracking, update .gitignore to prevent re-addition
- Delete unreachable code paths aggressively — if it's not called, it's gone; git has history
- No reference copies, no "keep for later" — clean cut

**Config unification:**
- Kill legacy variables ($LabName, $LabSwitch, etc.) immediately — no deprecation period
- Update all consumers to use $GlobalLabConfig hashtable exclusively
- Config validation fails loudly — missing required fields = script stops with clear error message
- No fallback to defaults for required fields; script must tell user exactly what's missing

**Helper sourcing:**
- Fail fast on load errors — broken helper means broken app, surface it immediately
- No silent skipping of failed helpers

**Template/JSON validation:**
- Reject templates with invalid data (bad IP format, unknown role) — won't load until fixed
- Don't auto-correct; force the user to fix the source of truth

### Claude's Discretion
- Whether to split Lab-Config.ps1 into core + LabBuilder configs (evaluate coupling first)
- Which of the 3 helper sourcing patterns to standardize on (dynamic discovery vs explicit registration vs hybrid)
- How to replace $OrchestrationHelperPaths manual array (auto-discovery vs generated list)
- Template validation strictness level (schema vs field-level checks)
- Whether to use one shared JSON validator or separate validators per file type

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CLN-01 | .archive/ directory removed from main branch | Git history preservation confirmed; safe to delete |
| CLN-02 | Test coverage artifacts (coverage.xml) removed from tracked files | Already untracked; .gitignore entry prevents re-addition |
| CLN-03 | LSP tools removed from tracked files | Already in .gitignore; directory exists but untracked |
| CLN-04 | Leftover debug/test scripts removed | No test-*.ps1 or test.json found in repo root |
| CLN-05 | Dead or unreachable code paths identified and removed | Function call analysis pattern documented; grep-based detection feasible |
| CFG-01 | GlobalLabConfig hashtable is single source of truth — legacy variables removed | 20 files use legacy vars; localized updates required |
| CFG-02 | All entry points use consistent helper sourcing pattern | 3 patterns identified; Lab-Common.ps1 dynamic discovery recommended |
| CFG-03 | Lab-Config.ps1 validates configuration on load | PowerShell ValidateScript pattern and Test-Json for schema validation |
| CFG-04 | Template system reads/writes JSON correctly with schema validation | Save-LabTemplate validates fields; Test-Json provides schema validation |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| PowerShell | 5.1+ | Scripting runtime | Windows 10/11/Server 2016+ built-in; compatibility baseline |
| Pester | 5.x | Unit testing | De facto PowerShell testing framework; already in use (28 test files) |
| Set-StrictMode | Latest | Variable/syntax enforcement | Catches uninitialized variables, prevents silent failures |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Test-Json | PowerShell 6.2+ | JSON schema validation | Validating template files with .jsonschema |
| ConvertFrom-Json | PowerShell 5.1+ | JSON deserialization | Reading config/template files |
| ValidateScript | PowerShell 5.1+ | Parameter validation | Hashtable key validation, config field checks |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Test-Json (PowerShell 6.2+) | Custom regex validation | Test-Json unavailable in PS 5.1; custom validation simpler for basic checks |
| Dynamic discovery (Lab-Common.ps1) | Explicit manifest (SimpleLab.psd1) | Manifest requires manual updates but gives export control; dynamic is maintenance-free |
| Hashtable config | PSData file (.psd1) | Hashtable allows code execution (computed values); .psd1 is data-only |

**Installation:**
```powershell
# Pester 5.x (if not already installed)
Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck
```

## Architecture Patterns

### Recommended Project Structure
```
AutomatedLab/
├── Private/           # Internal helpers (53 files, ~4747 lines)
├── Public/            # Exported functions (38 files, ~6352 lines)
├── LabBuilder/        # Separate concern (4 scripts, reads $LabBuilderConfig)
├── GUI/               # WPF entry point (1 file, sources Private+Public via Get-ChildItem)
├── Tests/             # Pester tests (28 files, 266 tests)
├── Lab-Config.ps1     # Single config file (516 lines, hashtable + legacy vars)
└── Lab-Common.ps1     # Helper loader (33 lines, uses Import-LabScriptTree)
```

### Pattern 1: Dynamic Discovery Helper Sourcing (RECOMMENDED)

**What:** Scan Private/ and Public/ directories recursively, dot-source all .ps1 files in dependency-safe order.

**When to use:** Entry points that need all helpers loaded (Lab-Common.ps1, GUI, standalone scripts).

**Example:**
```powershell
# Source: /mnt/c/projects/AutomatedLab/Lab-Common.ps1 (lines 6-32)
$importHelperPath = Join-Path -Path $ScriptRoot -ChildPath 'Private\Import-LabScriptTree.ps1'
if (-not (Test-Path -Path $importHelperPath -PathType Leaf)) {
    throw "Required import helper not found: $importHelperPath"
}

. $importHelperPath

$privateFiles = Get-LabScriptFiles -RootPath $ScriptRoot -RelativePaths @('Private') -ExcludeFileNames @('Import-LabScriptTree.ps1')
foreach ($file in $privateFiles) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to import private helper '$($file.FullName)': $($_.Exception.Message)"
    }
}

$publicFiles = Get-LabScriptFiles -RootPath $ScriptRoot -RelativePaths @('Public')
foreach ($file in $publicFiles) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to import public helper '$($file.FullName)': $($_.Exception.Message)"
    }
}
```

**Why recommended:**
- Already proven in Lab-Common.ps1 (used by standalone scripts)
- Maintenance-free: new helpers auto-discovered
- Fail-fast error handling built in
- PowerShell 5.1 compatible

### Pattern 2: Explicit Registration (Current OpenCodeLab-App.ps1)

**What:** Manually list required helper paths in an array, dot-source each.

**When to use:** When you need precise control over load order or only a subset of helpers.

**Example:**
```powershell
# Source: /mnt/c/projects/AutomatedLab/OpenCodeLab-App.ps1 (lines 69-94)
$OrchestrationHelperPaths = @(
    (Join-Path $ScriptDir 'Private\Get-LabHostInventory.ps1'),
    (Join-Path $ScriptDir 'Private\Resolve-LabOperationIntent.ps1'),
    (Join-Path $ScriptDir 'Private\Invoke-LabRemoteProbe.ps1'),
    # ... 14 more paths
)

foreach ($helperPath in $OrchestrationHelperPaths) {
    if (Test-Path $helperPath) {
        . $helperPath
    }
}
```

**Tradeoff:** Requires manual updates when adding/removing helpers; prone to stale references.

### Pattern 3: Glob-Based Discovery (Current GUI)

**What:** Use Get-ChildItem with -Recurse to find .ps1 files, dot-source via ForEach-Object.

**When to use:** Simple entry points that need everything.

**Example:**
```powershell
# Source: /mnt/c/projects/AutomatedLab/GUI/Start-OpenCodeLabGUI.ps1 (lines 24-31)
foreach ($subDir in @('Private', 'Public')) {
    $dirPath = Join-Path $script:RepoRoot $subDir
    if (Test-Path $dirPath) {
        Get-ChildItem -Path $dirPath -Filter '*.ps1' -Recurse |
            ForEach-Object { . $_.FullName }
    }
}
```

**Tradeoff:** No error handling on individual file failures; silent skipping if dot-source fails.

### Pattern Recommendation: Standardize on Dynamic Discovery

**Rationale:**
1. Lab-Common.ps1 pattern already proven (used by multiple standalone scripts)
2. Fail-fast error handling aligns with user decision ("broken helper = broken app")
3. No maintenance burden when adding/removing helpers
4. Consistent with PowerShell community best practices ([Microsoft best practices](https://learn.microsoft.com/en-us/powershell/scripting/developer/module/how-to-write-a-powershell-module-manifest?view=powershell-7.5) recommend explicit exports, but dynamic loading is common for internal helpers)

**Migration path:**
- Replace OpenCodeLab-App.ps1 explicit array with Lab-Common.ps1 sourcing
- Add error handling to GUI's Get-ChildItem pattern (wrap in try-catch per file)
- Remove $OrchestrationHelperPaths array entirely

### Pattern 4: Configuration Validation (Fail-Fast)

**What:** Validate GlobalLabConfig hashtable keys/values on load; throw immediately on missing/invalid fields.

**When to use:** All entry points that rely on Lab-Config.ps1.

**Example:**
```powershell
# Proposed pattern for Lab-Config.ps1 footer
function Test-LabConfigRequired {
    param([hashtable]$Config)

    $required = @{
        'Lab.Name' = { $_ -match '^[a-zA-Z0-9_-]+$' }
        'Lab.DomainName' = { $_ -match '^[a-z0-9.-]+$' }
        'Network.SwitchName' = { $_ -match '^[a-zA-Z0-9_-]+$' }
        'Network.AddressSpace' = { $_ -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}$' }
    }

    foreach ($key in $required.Keys) {
        $parts = $key -split '\.'
        $value = $Config
        foreach ($part in $parts) {
            if (-not $value.ContainsKey($part)) {
                throw "Required config field missing: $key"
            }
            $value = $value[$part]
        }

        if (-not (& $required[$key] $value)) {
            throw "Invalid value for config field '$key': $value"
        }
    }
}

# Call at end of Lab-Config.ps1
Test-LabConfigRequired -Config $GlobalLabConfig
```

**Sources:**
- [PowerShell hashtable validation with ValidateScript](https://learn.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-hashtable?view=powershell-7.5)
- [Parameter validation patterns](https://powershellexplained.com/2017-02-20-Powershell-creating-parameter-validators-and-transforms/)

### Pattern 5: JSON Template Validation

**What:** Validate JSON structure and field values before accepting user templates.

**When to use:** Save-LabTemplate, Get-ActiveTemplateConfig.

**Example (already implemented):**
```powershell
# Source: /mnt/c/projects/AutomatedLab/Private/Save-LabTemplate.ps1 (lines 68-73)
# IP validation
if ($vm.ip -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
    return [pscustomobject]@{
        Success = $false
        Message = "Invalid IP address for VM '$($vm.name)': '$($vm.ip)'."
    }
}
```

**Enhancement for schema validation (PowerShell 6.2+):**
```powershell
# Requires PowerShell 6.2+ (unavailable in PS 5.1)
$schemaJson = Get-Content template-schema.json -Raw
$templateJson = Get-Content template.json -Raw
$valid = Test-Json -Json $templateJson -SchemaFile $schemaJson
```

**PowerShell 5.1 alternative (field-level validation):**
- Continue current pattern: explicit field checks with regex/type validation
- Source: [Test-Json cmdlet](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/test-json?view=powershell-7.5) unavailable in PS 5.1

### Anti-Patterns to Avoid

- **Silent helper load failures:** Current GUI pattern uses `ForEach-Object { . $_.FullName }` without error handling — if a helper fails to load, the error is lost
- **Fallback to defaults for required config:** Hides configuration issues; prefer loud failures
- **Set-StrictMode -Version Latest in reusable code:** "Latest" is non-deterministic across PowerShell versions; use specific version (e.g., `-Version 2.0`) or accept current pattern
  - **Source:** [Set-StrictMode caution](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/set-strictmode?view=powershell-7.5) warns that "Latest" meaning changes in new PowerShell releases
  - **Codebase reality:** All existing scripts use `-Version Latest`; changing now introduces risk
  - **Recommendation:** Keep `-Version Latest` pattern (already used consistently), document the trade-off

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON schema validation | Custom recursive object validation | Test-Json with .jsonschema (PS 6.2+) OR field-level regex (PS 5.1) | PowerShell 5.1 lacks Test-Json; regex validation sufficient for templates |
| Module helper loading | Custom dependency resolution | PowerShell module manifest FunctionsToExport OR dynamic Get-ChildItem | Module system handles dependencies; explicit exports give control |
| Configuration file parsing | String parsing | ConvertFrom-Json (JSON) or Import-PowerShellDataFile (.psd1) | Built-in cmdlets handle edge cases (encoding, escaping, depth) |
| Variable existence checking | $null comparisons | Test-Path variable: OR Get-Variable -ErrorAction | Set-StrictMode enforces best practices; Test-Path variable: is strict-mode-safe |

**Key insight:** PowerShell has strong built-in config/module patterns. Complexity comes from mixing three sourcing patterns and dual config systems (hashtable + legacy vars). Unification simplifies everything.

## Common Pitfalls

### Pitfall 1: Legacy Variable Creep

**What goes wrong:** New code references `$LabName` instead of `$GlobalLabConfig.Lab.Name`, perpetuating dual config system.

**Why it happens:** Lab-Config.ps1 exports legacy variables for backward compatibility; developers copy existing patterns.

**How to avoid:**
1. Remove legacy variable exports from Lab-Config.ps1 immediately (user decision: no deprecation period)
2. Update all consumers to `$GlobalLabConfig` hashtable in single pass
3. Add Pester test that fails if legacy variables exist in new code

**Warning signs:** Grep hits for `$LabName|$LabSwitch|$AdminPassword` outside Lab-Config.ps1 (currently 20 files).

### Pitfall 2: Silent Dot-Source Failures

**What goes wrong:** Helper file has syntax error or uses undefined variable; dot-source fails silently; calling code gets "command not found" error far from root cause.

**Why it happens:** PowerShell dot-sourcing doesn't throw on failure by default; error is captured but not re-thrown.

**How to avoid:**
```powershell
# BAD (current GUI pattern)
Get-ChildItem -Path $dirPath -Filter '*.ps1' -Recurse |
    ForEach-Object { . $_.FullName }

# GOOD (Lab-Common.ps1 pattern)
foreach ($file in $privateFiles) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to import private helper '$($file.FullName)': $($_.Exception.Message)"
    }
}
```

**Warning signs:**
- Error messages like "The term 'Get-LabConfig' is not recognized" when Lab-Config.ps1 was dot-sourced
- Intermittent function availability
- **Source:** [PowerShell dot-sourcing best practices](https://redmondmag.com/articles/2025/11/05/best-practices-for-powershell-dot-sourcing-1.aspx)

### Pitfall 3: Configuration Scope Blindness

**What goes wrong:** Assuming `$GlobalLabConfig` is truly global; script-scoped modifications don't persist across scripts.

**Why it happens:** PowerShell scoping rules: variables defined in dot-sourced scripts inherit caller's scope, but modifications are local unless explicitly `$script:` or `$global:`.

**How to avoid:**
1. Lab-Config.ps1 defines `$GlobalLabConfig` at script root (caller's scope)
2. Never modify config after load; treat as immutable
3. If runtime overrides needed, use parameters (e.g., `-AdminPassword` in OpenCodeLab-App.ps1)

**Warning signs:** Config changes in one script don't affect another; "config reset" bugs.

### Pitfall 4: .gitignore vs. git rm Confusion

**What goes wrong:** Adding `.tools/powershell-lsp/` to .gitignore doesn't remove already-tracked files; they remain in repository.

**Why it happens:** `.gitignore` prevents tracking new files, but doesn't affect already-tracked files.

**How to avoid:**
```powershell
# Remove from tracking (files stay on disk)
git rm -r --cached .tools/powershell-lsp/
git rm --cached coverage.xml

# Update .gitignore
# (already has entries: coverage.xml, .tools/powershell-lsp/)

# Commit removal
git commit -m "chore: untrack coverage.xml and LSP tools"
```

**Warning signs:** Files listed in `.gitignore` still appear in `git status` as modified.

### Pitfall 5: Dead Code Detection False Positives

**What goes wrong:** Grep-based call analysis misses dynamic invocations (e.g., `& $functionName`), incorrectly flags used code as dead.

**Why it happens:** PowerShell supports runtime function invocation; static analysis can't catch all references.

**How to avoid:**
1. Grep for function name in all .ps1 files (excluding function definition itself)
2. If no hits, check for splatting patterns: `@{FunctionName = 'Get-LabConfig'}`
3. Check exported functions in SimpleLab.psd1 (indicates external usage)
4. For borderline cases: add `# Called by: X, Y, Z` comment to function, revisit in Phase 3

**Warning signs:**
- Test-LabPrereqs, Write-ValidationReport: only called in their own examples, not in app code
- Test-LabCleanup: only referenced in its own synopsis

## Code Examples

Verified patterns from official sources and codebase analysis:

### Configuration Validation (Loud Failure)

```powershell
# Source: User decision + PowerShell best practices
# https://learn.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-hashtable

function Test-LabConfigField {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [string]$KeyPath,

        [Parameter(Mandatory)]
        [scriptblock]$Validator,

        [Parameter()]
        [string]$ErrorMessage
    )

    $keys = $KeyPath -split '\.'
    $value = $Config

    foreach ($key in $keys) {
        if (-not $value.ContainsKey($key)) {
            $msg = if ($ErrorMessage) { $ErrorMessage } else { "Required config field missing: $KeyPath" }
            throw $msg
        }
        $value = $value[$key]
    }

    if (-not (& $Validator $value)) {
        $msg = if ($ErrorMessage) { $ErrorMessage } else { "Invalid value for '$KeyPath': $value" }
        throw $msg
    }

    return $value
}

# Usage in Lab-Config.ps1 footer
$null = Test-LabConfigField -Config $GlobalLabConfig -KeyPath 'Lab.Name' -Validator { $_ -match '^[a-zA-Z0-9_-]+$' }
$null = Test-LabConfigField -Config $GlobalLabConfig -KeyPath 'Network.AddressSpace' -Validator { $_ -match '^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$' }
```

### Helper Sourcing with Fail-Fast

```powershell
# Source: /mnt/c/projects/AutomatedLab/Lab-Common.ps1 (modified for clarity)
function Import-LabHelpers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter(Mandatory)]
        [string[]]$RelativePaths
    )

    $importHelper = Join-Path $RootPath 'Private\Import-LabScriptTree.ps1'
    if (-not (Test-Path $importHelper)) {
        throw "Required helper loader not found: $importHelper"
    }
    . $importHelper

    $files = Get-LabScriptFiles -RootPath $RootPath -RelativePaths $RelativePaths -ExcludeFileNames @('Import-LabScriptTree.ps1')

    foreach ($file in $files) {
        try {
            Write-Verbose "Loading helper: $($file.Name)"
            . $file.FullName
        }
        catch {
            throw "Failed to load helper '$($file.FullName)': $($_.Exception.Message)"
        }
    }
}

# Usage
Import-LabHelpers -RootPath $PSScriptRoot -RelativePaths @('Private', 'Public') -Verbose
```

### JSON Template Validation (Field-Level, PS 5.1 Compatible)

```powershell
# Source: /mnt/c/projects/AutomatedLab/Private/Save-LabTemplate.ps1 (existing pattern)
function Test-LabTemplateVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$VM,

        [Parameter(Mandatory)]
        [string[]]$ExistingNames,

        [Parameter()]
        [string[]]$ValidRoles = @('DC', 'SQL', 'IIS', 'WSUS', 'DHCP', 'FileServer', 'PrintServer', 'DSC', 'Jumpbox', 'Client', 'Ubuntu')
    )

    # NetBIOS name validation (1-15 alphanumeric + hyphen)
    if ($VM.name -notmatch '^[a-zA-Z0-9-]{1,15}$') {
        throw "VM name '$($VM.name)' is invalid. Use 1-15 alphanumeric characters and hyphens."
    }

    # Unique name check
    if ($ExistingNames -contains $VM.name.ToLowerInvariant()) {
        throw "Duplicate VM name: '$($VM.name)'"
    }

    # IP validation (basic IPv4 pattern)
    if ($VM.ip -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
        throw "Invalid IP address for VM '$($VM.name)': '$($VM.ip)'"
    }

    # Role validation
    if ($VM.role -and $VM.role -notin $ValidRoles) {
        throw "Unknown role for VM '$($VM.name)': '$($VM.role)'. Valid roles: $($ValidRoles -join ', ')"
    }

    # Memory validation (1-64 GB realistic range)
    if ([int]$VM.memoryGB -lt 1 -or [int]$VM.memoryGB -gt 64) {
        throw "Memory for VM '$($VM.name)' must be 1-64 GB, got: $($VM.memoryGB)"
    }

    # Processor validation (1-16 realistic range)
    if ([int]$VM.processors -lt 1 -or [int]$VM.processors -gt 16) {
        throw "Processors for VM '$($VM.name)' must be 1-16, got: $($VM.processors)"
    }
}
```

### Dead Code Detection (Grep Pattern)

```bash
# Find function definitions
grep -r "^function \(\w\+-\w\+\)" Private/ Public/ | cut -d: -f1,2

# For each function, check if called elsewhere
FUNC="Test-LabPrereqs"
grep -r "$FUNC" --include="*.ps1" --exclude-dir=.archive | grep -v "^[^:]*:function $FUNC"

# If no results (except Tests/*.Tests.ps1), likely dead code
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Explicit helper arrays | Dynamic discovery with Get-LabScriptFiles | Lab-Common.ps1 (Feb 2025) | Maintenance-free; new helpers auto-loaded |
| Legacy variables only | Dual system (hashtable + legacy vars) | Lab-Config.ps1 v5.0 (Feb 2025) | Migration path; phase 1 completes transition |
| Silent dot-source failures | Try-catch with throw | Lab-Common.ps1 (Feb 2025) | Fail-fast on helper load errors |
| Manual template validation | Field-level validation in Save-LabTemplate | Feb 2025 | Prevents bad data at write time |
| Set-StrictMode -Version 2.0 | Set-StrictMode -Version Latest | Codebase standard | Catches more errors but non-deterministic across PS versions |

**Deprecated/outdated:**
- **Test-Json schema validation for PowerShell 5.1:** PowerShell 5.1 doesn't have Test-Json; field-level regex validation is current approach
- **SimpleLab.psd1 explicit exports:** Module manifest exists but isn't the primary loading mechanism; Lab-Common.ps1 dynamic discovery is standard
- **$OrchestrationHelperPaths manual array:** OpenCodeLab-App.ps1 pattern; should be replaced with Lab-Common.ps1 sourcing

## Research-Specific Findings

### Codebase Inventory

| Category | Count | Details |
|----------|-------|---------|
| Private helpers | 53 files | ~4747 lines; internal functions |
| Public functions | 38 files | ~6352 lines; exported via SimpleLab.psd1 |
| LabBuilder scripts | 4 files | Separate concern; reads $LabBuilderConfig |
| Test files | 28 files | Pester 5.x; 266 tests; ~3851 lines |
| Total functions | 107 | Includes nested helpers (ConvertTo-IPv4UInt32, etc.) |
| Legacy variable uses | 20 files | Grep hits for $LabName, $LabSwitch, $AdminPassword |

### Dead Code Candidates

**Already cleaned:**
- No `test-*.ps1` or `test.json` files in repo root
- `coverage.xml` already untracked (not in `git ls-files`)
- `.tools/powershell-lsp/` already in .gitignore but directory exists (20MB, untracked)

**Requires investigation:**
- Test-LabPrereqs (Public/Test-LabPrereqs.ps1): only referenced in Write-ValidationReport, not called by app
- Write-ValidationReport (Public/Write-ValidationReport.ps1): only referenced in own examples
- Test-LabCleanup (Public/Test-LabCleanup.ps1): only referenced in own synopsis

**Confirmed archives:**
- `.archive/` directory exists (3 subdirectories, old backups)
- `.archive/SimpleLab-20260210/` (old version snapshot)
- `.archive/deprecated-builders/` (legacy build scripts)

### Configuration Coupling Analysis

**Lab-Config.ps1 structure:**
- `$GlobalLabConfig` hashtable (primary, 187 lines)
- `$GlobalLabConfig.Builder` sub-hashtable (LabBuilder-specific, 210 lines)
- Legacy variable exports (119 lines, derives from hashtable)

**LabBuilder coupling:**
- LabBuilder scripts reference `$LabBuilderConfig` (exported at end of Lab-Config.ps1)
- Resolve-LabBuilderConfig.ps1 supports both `$LabBuilderConfig` and `$GlobalLabConfig.Builder`
- 11 LabBuilder references to `$LabBuilderConfig` across 4 files
- Zero direct references to `$GlobalLabConfig.Builder` (goes through `$LabBuilderConfig` alias)

**Recommendation:** Keep single Lab-Config.ps1 file
- LabBuilder config is tightly coupled (references same defaults: `$defaultLabName`, `$defaultDomainName`)
- Splitting would require import/dependency management
- Current structure is clear: `$GlobalLabConfig.Builder` is a top-level key, `$LabBuilderConfig` is an export alias

### Helper Sourcing Pattern Comparison

| Pattern | Files Using | Pros | Cons | Recommended? |
|---------|-------------|------|------|--------------|
| Dynamic discovery (Lab-Common.ps1) | 1 + standalone scripts | Maintenance-free, fail-fast | Loads all helpers | YES |
| Explicit array (OpenCodeLab-App.ps1) | 1 (17 helpers) | Precise control, load order | Manual updates, stale refs | NO |
| Glob-based (GUI) | 1 | Simple, loads all | No error handling | NO (needs error handling) |

**Migration impact:**
- OpenCodeLab-App.ps1: Replace $OrchestrationHelperPaths with `. Lab-Common.ps1`
- GUI: Add try-catch around dot-sourcing (keep Get-ChildItem pattern but add error handling)
- All standalone scripts: Already use Lab-Common.ps1 sourcing ✓

## Open Questions

1. **Should Lab-Config.ps1 split into core + LabBuilder files?**
   - What we know: LabBuilder is 210 lines nested under `$GlobalLabConfig.Builder`; shares default variables
   - What's unclear: Would split improve or harm maintainability?
   - Recommendation: **Keep single file**; coupling is intentional (shared defaults), splitting adds import complexity

2. **Which helper sourcing pattern should be standard?**
   - What we know: 3 patterns exist; Lab-Common.ps1 dynamic discovery has fail-fast built in
   - What's unclear: Performance impact of loading all 91 helpers vs. selective loading?
   - Recommendation: **Dynamic discovery (Lab-Common.ps1)**; performance impact negligible (~91 file dot-sources on modern hardware), maintenance benefit significant

3. **How to replace $OrchestrationHelperPaths in OpenCodeLab-App.ps1?**
   - What we know: Currently 17 helpers listed manually; Lab-Common.ps1 loads all helpers
   - What's unclear: Does OpenCodeLab-App.ps1 need selective loading?
   - Recommendation: **Replace with `. Lab-Common.ps1` sourcing**; app needs full helper set anyway, manual list is maintenance burden

4. **Should template validation use JSON schema or field-level checks?**
   - What we know: Test-Json available in PS 6.2+, not PS 5.1; current pattern is field-level regex
   - What's unclear: Future PowerShell 7+ migration plans?
   - Recommendation: **Field-level validation** for now (PS 5.1 compatibility required); add Test-Json schema validation when migrating to PS 7+

5. **Should there be one shared JSON validator or separate validators per file type?**
   - What we know: Two JSON file types (config.json, templates/*.json); different validation needs
   - What's unclear: Shared validator complexity vs. duplication?
   - Recommendation: **Separate validators**; template validation is domain-specific (VM name, IP, role), config validation is structure-focused (paths, thresholds)

6. **Are Test-LabPrereqs, Write-ValidationReport, Test-LabCleanup dead code?**
   - What we know: Not called by app; only referenced in own documentation/examples
   - What's unclear: External usage (e.g., user scripts, docs)?
   - Recommendation: **Investigate in Phase 3** (integration testing); if not called during full lifecycle tests, remove

## Sources

### Primary (HIGH confidence)
- **Codebase analysis:** /mnt/c/projects/AutomatedLab/ (direct file reads, grep analysis)
  - Lab-Config.ps1 (516 lines, hashtable + legacy vars)
  - Lab-Common.ps1 (33 lines, dynamic helper sourcing)
  - OpenCodeLab-App.ps1 (lines 69-94, explicit helper array)
  - GUI/Start-OpenCodeLabGUI.ps1 (lines 24-31, glob-based sourcing)
  - Private/Save-LabTemplate.ps1 (template validation pattern)
  - SimpleLab.psd1 (module manifest, 38 exported functions)
  - Tests/ directory (28 test files, 266 tests)

- **Microsoft official docs:**
  - [Set-StrictMode cmdlet](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/set-strictmode?view=powershell-7.5) - Variable checking, version caution
  - [Everything about hashtables](https://learn.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-hashtable?view=powershell-7.5) - Validation patterns
  - [Test-Json cmdlet](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/test-json?view=powershell-7.5) - Schema validation (PS 6.2+)
  - [Module manifest best practices](https://learn.microsoft.com/en-us/powershell/scripting/developer/module/how-to-write-a-powershell-module-manifest?view=powershell-7.5) - FunctionsToExport

### Secondary (MEDIUM confidence)
- [PowerShell creating parameter validators and transforms](https://powershellexplained.com/2017-02-20-Powershell-creating-parameter-validators-and-transforms/) - ValidateScript patterns
- [Best Practices for PowerShell Dot Sourcing, Part 1](https://redmondmag.com/articles/2025/11/05/best-practices-for-powershell-dot-sourcing-1.aspx) - Error handling patterns
- [Enforce Better Script Practices by Using Set-StrictMode](https://devblogs.microsoft.com/scripting/enforce-better-script-practices-by-using-set-strictmode/) - Strict mode benefits

### Tertiary (LOW confidence)
- [Azure PowerShell module best practices](https://github.com/Azure/azure-powershell/blob/main/documentation/development-docs/design-guidelines/module-best-practices.md) - Enterprise patterns (not directly applicable to single-dev project)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - PowerShell 5.1, Pester 5.x confirmed in use; Set-StrictMode pattern verified in codebase
- Architecture: HIGH - Three sourcing patterns identified via direct code analysis; Lab-Common.ps1 pattern proven
- Pitfalls: HIGH - Legacy variable usage confirmed (20 files); dot-source error handling patterns verified
- Dead code detection: MEDIUM - Grep analysis identifies candidates but can't catch dynamic invocation; requires runtime validation

**Research date:** 2026-02-16
**Valid until:** 2026-03-16 (30 days; stable PowerShell ecosystem, no rapid API changes expected)

**Codebase specifics validated:**
- 107 total functions (56 Private, 38 Public, 13 nested/helpers)
- 20 files using legacy variables ($LabName, $LabSwitch, $AdminPassword)
- 3 distinct helper sourcing patterns across 3 entry points
- 28 Pester test files covering orchestration, dispatch, state probes, GUI
- PowerShell 5.1 compatibility enforced (SimpleLab.psd1 line 32)
- Set-StrictMode -Version Latest used consistently across codebase

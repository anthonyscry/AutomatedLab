# Coding Conventions

**Analysis Date:** 2026-02-16

## Naming Patterns

**Files:**
- PascalCase with hyphens: `Get-LabConfig.ps1`, `Test-LabVM.ps1`
- PowerShell verb-noun pattern: `New-LabVM`, `Invoke-LabQuickModeHeal`
- Test files: `*.Tests.ps1` (e.g., `ActionRequest.Tests.ps1`)
- Role files: PascalCase without verbs (e.g., `DC.ps1`, `IIS.ps1`, `Jumpbox.ps1`)

**Functions:**
- PowerShell approved verbs: Get-, Set-, New-, Remove-, Test-, Invoke-, Resolve-
- Private functions: `Get-LabFleetStateProbe`, `Resolve-LabCoordinatorPolicy`
- Public functions: Same pattern but exported in module manifest
- Windows-specific: Prefix with `Lab` (e.g., `New-LabVM`, `Test-LabNetwork`)
- Linux-specific: Suffix or explicit name (e.g., `New-LinuxVM`, `Wait-LinuxVMReady`)

**Variables:**
- camelCase for local variables: `$vmNames`, `$switchName`, `$labRoot`
- PascalCase for parameters: `[Parameter()]$VMName`, `$MemoryGB`
- PascalCase for global config hashtables: `$GlobalLabConfig`, `$IPPlan`
- ALL_CAPS for environment variables: `OPENCODELAB_ADMIN_PASSWORD`, `LAB_ADMIN_PASSWORD`

**Types:**
- Native PS types: `[PSCustomObject]`, `[string]`, `[int]`, `[bool]`
- .NET types when needed: `[System.Collections.Generic.HashSet[string]]`
- Ordered hashtables for structured data: `[ordered]@{}`

## Code Style

**Formatting:**
- No automated formatter detected (no `.prettierrc` or `PSScriptAnalyzerSettings.psd1` in root)
- Indentation: 4 spaces (consistent across files)
- Braces: Opening brace on same line (K&R style)
- Line length: Generally ~120 characters, some lines extend to ~180

**Linting:**
- PSScriptAnalyzer available in `.tools/powershell-lsp/PSES/PSScriptAnalyzer/1.24.0/`
- Settings profiles available but not actively enforced in CI
- Manual validation recommended

**Strict Mode:**
- `Set-StrictMode -Version Latest` used in 8 entry-point scripts:
  - `OpenCodeLab-App.ps1`
  - `GUI/Start-OpenCodeLabGUI.ps1`
  - `Scripts/Run-OpenCodeLab.ps1`
  - `Scripts/Test-OpenCodeLabPreflight.ps1`
  - `Scripts/Test-OpenCodeLabHealth.ps1`
  - `Scripts/New-ScopedConfirmationToken.ps1`
  - `Scripts/Install-Ansible.ps1`
  - `SimpleLab.psm1`
- **Gap:** Private and Public functions do NOT set StrictMode internally (rely on module or caller)

## Import Organization

**Order:**
1. Module imports (if any)
2. Dot-source private helpers (in tests)
3. Function definitions
4. Script logic

**Module Pattern (`SimpleLab.psm1`):**
```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import helper that loads script trees
. (Join-Path $ModuleRoot 'Private\Import-LabScriptTree.ps1')

# Load all Private/*.ps1 files
$privateFiles = Get-LabScriptFiles -RootPath $ModuleRoot -RelativePaths @('Private')
foreach ($file in $privateFiles) { . $file.FullName }

# Load all Public/*.ps1 files
$publicFiles = Get-LabScriptFiles -RootPath $ModuleRoot -RelativePaths @('Public')
foreach ($file in $publicFiles) { . $file.FullName }

# Explicit export
Export-ModuleMember -Function @('Connect-LabVM', 'Get-LabStatus', ...)
```

**Test Pattern:**
```powershell
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Resolve-LabActionRequest.ps1')
    . (Join-Path $repoRoot 'Private/New-LabAppArgumentList.ps1')
}
```

**Path Aliases:**
- No TypeScript-style path aliases
- Explicit relative paths: `Join-Path $PSScriptRoot '..\Private\Get-LabConfig.ps1'`
- Tests use `$repoRoot = Split-Path -Parent $PSScriptRoot` for consistency

## Error Handling

**Patterns:**
- `throw` for fatal errors with descriptive messages
- `Write-Error` for recoverable errors (allows pipeline continuation)
- `Write-Warning` for non-blocking issues (e.g., auto-heal failures)
- Try-catch blocks wrap I/O and external commands

**Example from `Private/Get-LabHostInventory.ps1`:**
```powershell
try {
    $inventoryItem = Get-Item -LiteralPath $InventoryPath -ErrorAction Stop
}
catch {
    throw "Failed to read inventory file '$InventoryPath': $($_.Exception.Message)"
}

if ($inventoryItem.PSProvider.Name -ne 'FileSystem') {
    throw "InventoryPath must resolve to a filesystem file..."
}
```

**Result Objects Pattern:**
```powershell
$result = [PSCustomObject]@{
    VMName = $VMName
    Created = $false
    Status = "Failed"
    Message = ""
}

try {
    # ... operation ...
    $result.Created = $true
    $result.Status = "Success"
    return $result
}
catch {
    $result.Message = $_.Exception.Message
    return $result
}
```

## Logging

**Framework:** Native PowerShell cmdlets (no external logging framework)

**Patterns:**
- `Write-Host` for user-facing output (color-coded)
- `Write-Verbose` for detailed trace info (requires `-Verbose`)
- `Write-Warning` for issues that don't block execution
- `Write-Error` for failures
- Artifacts written to `run-logs/` directories as JSON and TXT

**Example from `OpenCodeLab-App.ps1`:**
```powershell
Write-Host "`n===== $Action Mode: $Mode =====" -ForegroundColor Cyan
Write-Host "Auto-heal: $($AutoHeal -and $healingEnabled)" -ForegroundColor Gray
```

## Comments

**When to Comment:**
- Function purpose: Full comment-based help with `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`
- Complex logic: Inline comments explaining "why" not "what"
- Configuration sections: Header comments describing setting impact
- Workarounds: Explain PS 5.1 compatibility issues

**Example from `Lab-Config.ps1`:**
```powershell
# Changing Name renames the core lab identity used by app actions.
Name = $defaultLabName

# Changing CoreVMNames alters which VMs are targeted by default for
# start/stop/status flows in scripts that operate on the "core lab".
CoreVMNames = @('dc1', 'svr1', 'ws1')
```

**Comment-Based Help:**
- Present in 46 of 50 Public functions (92% coverage)
- **Gap:** 4 Public functions lack help blocks
- Private functions: Minimal documentation (function-level purpose only)

**No TODO/FIXME markers:** Zero instances found in active code (excellent)

## Function Design

**Size:**
- Private functions: 34-278 lines (average ~120)
- Largest: `Test-LabDNS.ps1` (278 lines), `Test-LabDomainJoin.ps1` (265 lines)
- Public functions: Generally 50-200 lines with full help

**Parameters:**
- `[CmdletBinding()]` used in 187 of 213 functions (88% coverage)
- `[Parameter(Mandatory)]` for required inputs
- `[ValidateSet()]`, `[ValidateRange()]`, `[ValidatePattern()]` for input validation (111 occurrences)
- Default values for optional parameters
- Type hints on all parameters

**Return Values:**
- Private functions: Return `[PSCustomObject]` with structured data
- `[OutputType([PSCustomObject])]` declared in 19 Private functions
- Consistent property naming: `Status`, `Message`, `Success`, `Result`

**Example from `Private/Get-LabConfig.ps1`:**
```powershell
function Get-LabConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$ConfigPath = ".planning/config.json"
    )

    try {
        # ... load config ...
        return $config
    }
    catch {
        Write-Error "Failed to load config from '$ConfigPath': $($_.Exception.Message)"
        return $null
    }
}
```

## Module Design

**Exports:**
- Explicit `Export-ModuleMember -Function @(...)` in `SimpleLab.psm1`
- 57 exported functions (Public/)
- Private helpers (56 functions) are NOT exported

**Barrel Files:**
- Not used (PowerShell doesn't have this pattern)
- Module manifest (`SimpleLab.psd1`) lists metadata only

## PowerShell 5.1 Compatibility

**Critical Pattern:**
```powershell
# WRONG (PS 6+ only):
Join-Path 'C:\' 'Lab' 'VMs'

# CORRECT (PS 5.1 compatible):
Join-Path (Join-Path 'C:\' 'Lab') 'VMs'
```

**Documented in MEMORY.md:**
> Join-Path: Only accepts 2 args (Path + ChildPath). Use nested: `Join-Path (Join-Path A B) C`. PS 6+ supports 3+ args but Windows PowerShell 5.1 does not.

**Variable Existence Check:**
```powershell
# StrictMode-safe pattern (20+ occurrences):
if (Test-Path variable:GlobalLabConfig) { ... }

# Alternative:
if ((Test-Path variable:healResult) -and $null -ne $healResult) { ... }
```

## Architecture Patterns

**Orchestration Helpers Array:**
```powershell
# OpenCodeLab-App.ps1 sources 16+ Private helpers explicitly:
$OrchestrationHelperPaths = @(
    (Join-Path $ScriptDir 'Private\Get-LabHostInventory.ps1'),
    (Join-Path $ScriptDir 'Private\Resolve-LabOperationIntent.ps1'),
    (Join-Path $ScriptDir 'Private\Invoke-LabRemoteProbe.ps1'),
    # ... 13 more ...
)
```

**New Private helpers must be added to this array.**

**Result Object Convention:**
```powershell
# Consistent shape across coordinator functions:
[pscustomobject]@{
    Success = $true/$false
    Action = 'deploy'
    Mode = 'quick'
    Message = 'Descriptive status'
    Data = @{ ... }
}
```

## File Organization

**Private/ (56 files):**
- Helper functions, not exported
- Naming: Verb-Noun pattern
- Subdirectory: `Private/Linux/` for Linux-specific helpers

**Public/ (50 files):**
- Exported cmdlets
- Subdirectory: `Public/Linux/` for Linux VM management
- Full comment-based help required

**Tests/ (28 files):**
- Pester 5.x tests
- Pattern: `*.Tests.ps1`
- Co-located with source (not in separate tree)

**Scripts/ (multiple files):**
- Entry points and utilities
- Not part of module, called directly

**GUI/ (1 main file + XAML):**
- `Start-OpenCodeLabGUI.ps1` - WPF GUI launcher
- `MainWindow.xaml` - UI definition

---

*Convention analysis: 2026-02-16*

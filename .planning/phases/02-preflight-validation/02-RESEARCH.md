# Phase 2: Pre-flight Validation - Research

**Researched:** 2026-02-09
**Domain:** PowerShell file validation, ISO detection, configuration management
**Confidence:** HIGH

## Summary

Phase 2 implements pre-flight validation to verify ISOs and prerequisites exist before lab operations. The implementation uses native PowerShell cmdlets for file detection, configuration validation, and structured error reporting.

**Primary recommendation:** Use `Test-Path` for ISO validation with configurable paths stored in a JSON config file, implement a `Test-LabPrereqs` orchestrator function that runs all checks, and use structured output with PSCustomObject for clear pass/fail status.

## Standard Stack

### Core
| Library/Feature | Version | Purpose | Why Standard |
|-----------------|---------|---------|--------------|
| Test-Path | PowerShell 2.0+ | File existence validation | Native file system checking |
| Get-ChildItem | PowerShell 2.0+ | Directory enumeration | Built-in file listing |
| ConvertFrom-Json | PowerShell 3.0+ | Config file parsing | Native JSON deserialization |
| PSCustomObject | PowerShell 3.0+ | Structured check results | Clean object properties for output |

### Configuration Storage Options
| Approach | Pros | Cons | Recommendation |
|----------|------|------|----------------|
| JSON config file | Human-readable, easy to edit | Requires file I/O on every operation | **RECOMMENDED** |
| Environment variables | Built-in, no file dependency | Harder to edit, persists across sessions | Use for defaults only |
| Registry | Windows-native, persists | Harder to edit/migrate | Not recommended |
| PowerShell parameter files | Native to PS | Less common than JSON | Backup option |

### ISO Detection Patterns

**Pattern 1: Single Path Validation**
```powershell
function Test-IsoPath {
    param([string]$Path)
    $exists = Test-Path -Path $Path -PathType Leaf
    return [PSCustomObject]@{
        Path = $Path
        Exists = $exists
        IsValidIso = if ($exists) { $Path -match '\.iso$' } else { $false }
    }
}
```

**Pattern 2: Multiple ISO Locations**
```powershell
function Find-LabIso {
    param([string]$IsoName, [string[]]$SearchPaths)

    foreach ($path in $SearchPaths) {
        $fullPath = Join-Path $path $IsoName
        if (Test-Path $fullPath) {
            return $fullPath
        }
    }
    return $null
}
```

**Pattern 3: Config-Based Validation**
```powershell
# config.json
{
    "IsoPaths": {
        "Server2019": "C:\\ISOs\\Server2019.iso",
        "Windows11": "C:\\ISOs\\Windows11.iso"
    }
}

function Test-LabIsosConfig {
    $config = Get-Content "config.json" | ConvertFrom-Json
    $results = @()

    foreach ($iso in $config.IsoPaths.PSObject.Properties) {
        $exists = Test-Path $iso.Value
        $results += [PSCustomObject]@{
            Name = $iso.Name
            Path = $iso.Value
            Exists = $exists
        }
    }

    return $results
}
```

## Architecture Patterns

### Recommended: Config-Driven Pre-flight Checks

**Configuration File Structure:**
```
.planning/
└── config.json          # Lab configuration
    ├── IsoPaths          # ISO file locations
    ├── MinDiskSpace      # Minimum disk requirements
    └── MinMemory         # Minimum RAM requirements
```

**config.json Schema:**
```json
{
    "$schema": "https://simplelab.dev/schema/config.json",
    "IsoPaths": {
        "Server2019": "C:\\Lab\\ISOs\\17763.3650.240907-1235.fe_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso",
        "Windows11": "C:\\Lab\\ISOs\\Windows11.iso"
    },
    "IsoSearchPaths": [
        "C:\\Lab\\ISOs",
        "D:\\ISOs",
        ".\\ISOs"
    ],
    "Requirements": {
        "MinDiskSpaceGB": 100,
        "MinMemoryGB": 16
    }
}
```

### Check Results Output Format

**Recommended Output Structure:**
```powershell
[PSCustomObject]@{
    CheckType = "IsoValidation"
    Status = "Pass"  # or "Fail"
    Checks = @(
        [PSCustomObject]@{
            Name = "Server2019"
            Status = "Pass"
            Path = "C:\\Lab\\ISOs\\Server2019.iso"
        },
        [PSCustomObject]@{
            Name = "Windows11"
            Status = "Fail"
            Path = "C:\\Lab\\ISOs\\Windows11.iso"
            Error = "File not found"
        }
    )
    Overall = "Fail"
}
```

### Error Message Format

**Per Phase 1 UX-01 requirement:**
```powershell
if ($missingIsos.Count -gt 0) {
    $missingList = $missingIsos -join ", "
    Write-Error "Missing ISOs: $missingList"
    Write-Host "Expected locations:" -ForegroundColor Yellow
    $missingIsos | ForEach-Object {
        Write-Host "  - $_" -ForegroundColor Yellow
    }
}
```

## Implementation Plan

### Plan 02-01: ISO Detection and Validation
- Implement `Test-LabIso` function for single ISO validation
- Implement `Find-LabIso` function for searching multiple paths
- Support both absolute and relative paths
- Validate ISO file extension (.iso)

### Plan 02-02: Pre-flight Check Orchestration
- Implement `Test-LabPrereqs` orchestrator function
- Create config file loading/saving functions
- Implement disk space and memory checks
- Return structured PSCustomObject results

### Plan 02-03: Validation Error Reporting UX
- Format check results for console output
- Color-coded output (green=pass, red=fail, yellow=warning)
- Summary table with overall status
- Integration with SimpleLab.ps1 entry point

## Pitfalls to Avoid

### Pitfall 1: Path Separator Issues
**Problem:** Hard-coded backslashes fail on Linux/WSL
**Solution:** Use `Join-Path` cmdlet or `[IO.Path]::Combine()`

### Pitfall 2: Config File Not Found
**Problem:** First run has no config file
**Solution:** Create default config on first run, use `Initialize-LabConfig`

### Pitfall 3: ISO File Name Variations
**Problem:** ISO files have different names/versions
**Solution:** Search by pattern, accept multiple valid filenames

### Pitfall 4: Relative Path Resolution
**Problem:** Relative paths resolve differently depending on execution location
**Solution:** Resolve relative paths against repository root using `$PSScriptRoot`

## Key Decisions for Claude

### When Implementing

1. **Config Storage:** Use JSON at `.planning/config.json` - human-readable and easy to edit
2. **ISO Search:** Support multiple search paths with fallback
3. **Error Output:** Use Write-Error for failures, Write-Host with -ForegroundColor for user output
4. **Check Results:** Return PSCustomObject for programmatic consumption
5. **Config Initialization:** Auto-create default config if missing

### User Interface Decisions

1. **ISO Paths:** Allow user to configure via config file or environment variable
2. **Search Order:** Check exact path first, then search paths
3. **Output Format:** Table format for multiple checks, detailed info for failures
4. **Color Coding:** Green=pass, Red=fail, Yellow=warning per PowerShell conventions

## Requirements Mapping

| Requirement | Implementation |
|-------------|----------------|
| BUILD-03: Validate ISOs before build | `Test-LabPrereqs` checks ISOs before any build operation |
| VAL-02: Verify ISOs are present | ISO validation functions with specific error messages |
| UX-01: Clear error messages | Structured error output with missing ISO list |

## Dependencies

**From Phase 1:**
- `Write-RunArtifact` function for logging check results
- `Test-HyperVEnabled` function for Hyper-V validation (prerequisite check)
- Error handling pattern with try/catch/finally

**To Phase 3:**
- ISO validation required before network infrastructure setup
- Config file will be extended with network settings

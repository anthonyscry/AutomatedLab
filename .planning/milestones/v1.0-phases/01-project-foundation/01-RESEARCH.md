# Phase 1: Project Foundation - Research

**Researched:** 2025-02-09
**Domain:** PowerShell infrastructure, error handling, Hyper-V detection
**Confidence:** HIGH

## Summary

Phase 1 establishes project infrastructure for SimpleLab, focusing on Hyper-V detection, structured error handling, JSON run artifact generation, and project scaffolding. The implementation will use native PowerShell cmdlets and patterns without external dependencies.

**Primary recommendation:** Use `Get-ComputerInfo` with Hyper-V property filtering, combined error handling with `$ErrorActionPreference = 'Stop'` and `try/catch/finally` blocks, and standard `ConvertTo-Json` for run artifacts with a hashtable-based data structure.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Hyper-V Detection
- Use `Get-ComputerInfo` cmdlet to check Hyper-V status
- Check on every operation (not lazy evaluation)
- When Hyper-V is not enabled: Offer to enable with full command syntax
- Error message format: "Hyper-V is not enabled. Run: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All"

#### Error Handling
- Combined approach: `try/catch/finally` blocks + `$ErrorActionPreference = 'Stop'` globally
- Surface errors using `Write-Error` for errors, `Write-Host` for user output
- Granular exit codes: 1=general error, 2=validation failure, 3=network error, 4=VM error, 5=domain error

#### Run Artifacts
- Store as timestamped files (one per run): `run-YYYYMMDD-HHMMSS.json`
- Location: `.planning/runs/` directory
- Fields: Operation, Timestamp, Status, Duration, Error (if any), VM names, Phase info, Host info

#### Project Structure
- Add new `SimpleLab/` folder to existing repository
- Modules organized by feature: `Network/`, `VM/`, `Domain/`, etc.
- Main entry point: `SimpleLab.ps1`

### Claude's Discretion
- Exact JSON schema details
- Module import patterns
- Whether to use PowerShell classes vs hashtables for data structures

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

## Standard Stack

### Core
| Library/Feature | Version | Purpose | Why Standard |
|-----------------|---------|---------|--------------|
| PowerShell | 5.1+ | Script runtime | Built into Windows, Get-ComputerInfo requires Windows platform |
| Get-ComputerInfo | WinPS 5.1+ | Hyper-V detection | Consolidated system info cmdlet, Windows-only |
| ConvertTo-Json | WinPS 3.0+ | JSON artifact generation | Native JSON serialization, no dependencies |
| ErrorActionPreference | Built-in | Error handling control | Standard PowerShell error control mechanism |

### Supporting
| Feature | Purpose | When to Use |
|---------|---------|-------------|
| try/catch/finally blocks | Structured error handling | Wrap all operations that may fail |
| Export-ModuleMember | Module API control | Explicitly export public functions |
| PSCustomObject | Data structures | For structured data before JSON conversion |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Get-ComputerInfo | Get-CimInstance Win32_ComputerSystem.HypervisorPresent | Get-ComputerInfo is more comprehensive and newer (WinPS 5.1+) |
| Hashtable | PSCustomObject | Hashtables are faster for lookups; PSCustomObject better for properties |
| Native error handling | PSGallery logging modules | Native is sufficient; adds no dependencies |

**Installation:** No installation required - uses built-in PowerShell capabilities.

## Architecture Patterns

### Recommended Project Structure
```
SimpleLab/
├── SimpleLab.ps1           # Main entry point
├── SimpleLab.psm1          # Root module (exports public functions)
├── SimpleLab.psd1          # Module manifest
├── Public/                 # User-facing functions
│   ├── Invoke-LabOperation.ps1
│   ├── Test-HyperVEnabled.ps1
│   └── New-RunArtifact.ps1
├── Private/                # Internal helper functions
│   ├── Write-RunArtifact.ps1
│   └── Get-HostInfo.ps1
└── Classes/                # (Optional) PowerShell classes
    └── RunArtifact.psm1
```

### Pattern 1: Hyper-V Detection with Get-ComputerInfo
**What:** Use Get-ComputerInfo to retrieve system information and check Hyper-V related properties.

**When to use:** At the start of every operation that requires Hyper-V.

**Example:**
```powershell
# Source: Microsoft Get-ComputerInfo documentation
function Test-HyperVEnabled {
    [CmdletBinding()]
    param()

    try {
        $computerInfo = Get-ComputerInfo -Property "HyperV*"

        # Check for Hyper-V requirement properties (indicates not enabled)
        if ($computerInfo.HyperVRequirementVirtualizationFirmwareEnabled -eq $false) {
            throw "Hyper-V is not enabled. Run: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All"
        }

        # Alternative: Check if hypervisor is present (enabled state)
        # Note: HyperVisorPresent property may not be available via Get-ComputerInfo
        # Consider using Get-CimInstance for HypervisorPresent check
        $hypervisorPresent = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
        if (-not $hypervisorPresent) {
            throw "Hyper-V is not enabled. Run: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All"
        }

        return $true
    }
    catch {
        Write-Error $_.Exception.Message
        return $false
    }
}
```

### Pattern 2: Structured Error Handling
**What:** Combine `$ErrorActionPreference = 'Stop'` with try/catch/finally blocks for comprehensive error handling.

**When to use:** Wrap all operations that may fail.

**Example:**
```powershell
# Source: Microsoft "Everything about exceptions" documentation
function Invoke-LabOperation {
    [CmdletBinding()]
    param(
        [string]$Operation
    )

    $ErrorActionPreference = 'Stop'
    $startTime = Get-Date
    $exitCode = 0

    try {
        # Check Hyper-V first
        if (-not (Test-HyperVEnabled)) {
            $exitCode = 2  # Validation failure
            throw "Hyper-V validation failed"
        }

        # Perform operation
        Write-Host "Starting operation: $Operation"

        # ... operation logic here ...

        $status = "Success"
    }
    catch {
        # Surface the error
        Write-Error "Operation failed: $($_.Exception.Message)"

        # Set appropriate exit code based on error type
        if ($_.Exception.Message -match "network") { $exitCode = 3 }
        elseif ($_.Exception.Message -match "VM") { $exitCode = 4 }
        elseif ($_.Exception.Message -match "domain") { $exitCode = 5 }
        else { $exitCode = 1 }

        $status = "Failed"
    }
    finally {
        # Always generate run artifact
        $duration = (Get-Date) - $startTime
        New-RunArtifact -Operation $Operation -Status $status -Duration $duration -ExitCode $exitCode
    }

    exit $exitCode
}
```

### Pattern 3: JSON Run Artifact Generation
**What:** Create timestamped JSON files for each run with operation details.

**When to use:** After every operation (in finally block).

**Example:**
```powershell
# Source: Microsoft ConvertTo-Json documentation
function New-RunArtifact {
    [CmdletBinding()]
    param(
        [string]$Operation,
        [string]$Status,
        [TimeSpan]$Duration,
        [int]$ExitCode,
        [string[]]$VMNames = @(),
        [string]$Phase = "01-project-foundation",
        [Management.Automation.ErrorRecord]$ErrorRecord
    )

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $artifactPath = Join-Path $PSScriptRoot ".planning\runs\run-$timestamp.json"

    # Ensure directory exists
    $artifactDir = Split-Path $artifactPath -Parent
    if (-not (Test-Path $artifactDir)) {
        New-Item -Path $artifactDir -ItemType Directory -Force | Out-Null
    }

    # Create artifact object using hashtable
    $artifact = [ordered]@{
        Operation   = $Operation
        Timestamp   = (Get-Date).ToString("o")  # ISO 8601 format
        Status      = $Status
        Duration    = $Duration.TotalSeconds
        ExitCode    = $ExitCode
        VMNames     = $VMNames
        Phase       = $Phase
        HostInfo    = @{
            ComputerName = $env:COMPUTERNAME
            Username     = $env:USERNAME
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        }
    }

    # Add error info if present
    if ($ErrorRecord) {
        $artifact.Error = @{
            Message = $ErrorRecord.Exception.Message
            Type    = $ErrorRecord.Exception.GetType().Name
            ScriptStackTrace = $ErrorRecord.ScriptStackTrace
        }
    }

    # Convert to JSON and save
    $artifact | ConvertTo-Json -Depth 4 | Out-File -FilePath $artifactPath -Encoding utf8

    Write-Host "Run artifact saved to: $artifactPath"
    return $artifactPath
}
```

### Pattern 4: Module Import and Export
**What:** Use .psm1 module file with explicit exports.

**When to use:** Organizing functions into a reusable module.

**Example:**
```powershell
# SimpleLab.psm1
# Source: Microsoft "How to Write a PowerShell Script Module" documentation

# Import dependent modules (if any)
# Import-Module SomeDependency

# Dot-source private functions
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" | ForEach-Object {
    . $_.FullName
}

# Dot-source public functions
Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" | ForEach-Object {
    . $_.FullName
}

# Export public functions explicitly
Export-ModuleMember -Function @(
    'Invoke-LabOperation',
    'Test-HyperVEnabled',
    'New-RunArtifact'
)
```

### Anti-Patterns to Avoid

- **Silent error swallowing:** Never catch errors without proper handling or re-throwing
  - Bad: `catch { }` (empty catch)
  - Good: `catch { Write-Error $_; throw }` or `catch { $PSCmdlet.ThrowTerminatingError($PSItem) }`

- **Inconsistent error handling:** Don't mix Write-Error and throw without understanding the difference
  - Write-Error creates non-terminating errors by default
  - throw creates terminating errors
  - Use `-ErrorAction Stop` to convert Write-Error to terminating

- **Lazy Hyper-V checking:** Don't check Hyper-V only when needed
  - Check on every operation as specified in requirements
  - Hyper-V status can change between runs

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON serialization | Custom JSON string building | ConvertTo-Json | Handles escaping, nested objects, dates automatically |
| Error records | Custom error objects | PowerShell ErrorRecord | Rich context, stack traces, standard format |
| Module loading | Manual script dot-sourcing | Import-Module | Standard discovery, versioning, dependency management |
| Hyper-V detection | WMI queries, registry checks | Get-ComputerInfo | Consolidated API, handles edge cases |

**Key insight:** PowerShell's built-in capabilities cover all Phase 1 requirements without external dependencies. Custom solutions add maintenance burden and miss edge cases.

## Common Pitfalls

### Pitfall 1: Non-Terminating Errors in Try/Catch
**What goes wrong:** `Write-Error` and non-terminating errors don't trigger catch blocks.

**Why it happens:** PowerShell distinguishes between terminating and non-terminating errors. Only terminating errors are caught.

**How to avoid:**
- Use `$ErrorActionPreference = 'Stop'` globally
- Use `-ErrorAction Stop` on individual cmdlets
- Use `throw` or `$PSCmdlet.ThrowTerminatingError()` for custom errors

**Warning signs:** Errors that "should have been caught" but execution continues.

### Pitfall 2: Get-ComputerInfo Platform Limitations
**What goes wrong:** Script fails on non-Windows platforms.

**Why it happens:** Get-ComputerInfo is Windows-only (as noted in Microsoft documentation).

**How to avoid:** Check platform before calling:
```powershell
if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    $computerInfo = Get-ComputerInfo
} else {
    throw "Get-ComputerInfo is only available on Windows platforms"
}
```

**Warning signs:** "The term 'Get-ComputerInfo' is not recognized" errors.

### Pitfall 3: JSON Depth Limitations
**What goes wrong:** Complex objects truncated in JSON output.

**Why it happens:** ConvertTo-Json default depth is 2; deeper objects are truncated with "...". PowerShell 7.1+ warns about this.

**How to avoid:** Use `-Depth` parameter:
```powershell
$object | ConvertTo-Json -Depth 10
```

**Warning signs:** Objects with "..." in JSON output, incomplete data in artifacts.

### Pitfall 4: Module Path Issues
**What goes wrong:** Module not found when importing from different locations.

**Why it happens:** PowerShell module discovery requires specific paths or full paths.

**How to avoid:**
- Use `$PSScriptRoot` for relative paths
- Use `$Env:PSModulePath` for standard module locations
- Validate paths before Import-Module

**Warning signs:** "Module not found" errors when running from different directories.

### Pitfall 5: Hashtables vs PSCustomObject for JSON
**What goes wrong:** JSON output order inconsistent or wrong property types.

**Why it happens:** Regular hashtables don't guarantee order (though [ordered] does). PSCustomObject is more natural for JSON.

**How to avoid:** Use `[ordered]@{}` for hashtables when order matters, or use PSCustomObject:
```powershell
# Option 1: Ordered hashtable
[ordered]@{
    Property1 = 'Value1'
    Property2 = 'Value2'
}

# Option 2: PSCustomObject
[PSCustomObject]@{
    Property1 = 'Value1'
    Property2 = 'Value2'
}
```

**Warning signs:** JSON properties in unexpected order, wrong data types.

## Code Examples

Verified patterns from official sources:

### Hyper-V Detection
```powershell
# Source: Microsoft Scripting Blog - "Use PowerShell to Detect if Hypervisor is Present"
# URL: https://devblogs.microsoft.com/scripting/use-powershell-to-detect-if-hypervisor-is-present/

# Method 1: Check HypervisorPresent property
$hypervisorPresent = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent

if (-not $hypervisorPresent) {
    Write-Error "Hyper-V is not enabled. Run: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All"
    exit 2
}

# Method 2: Use Get-ComputerInfo with property filter
$computerInfo = Get-ComputerInfo -Property "HyperV*"
# Check HyperVRequirement properties (indicates Hyper-V is NOT enabled)
```

### Error Handling
```powershell
# Source: Microsoft "Everything about exceptions" documentation
# URL: https://learn.microsoft.com/en-us/powershell/scripting/learn/deep-dives/everything-about-exceptions

$ErrorActionPreference = 'Stop'

try {
    # Operation that might fail
    Start-Something -ErrorAction Stop
}
catch [System.IO.FileNotFoundException] {
    # Handle specific exception type
    Write-Error "File not found: $($_.Exception.Message)"
    exit 2
}
catch {
    # Handle all other exceptions
    Write-Error "Operation failed: $($_.Exception.Message)"
    exit 1
}
finally {
    # Cleanup or logging (always runs)
    Write-Host "Operation completed"
}
```

### JSON Artifact Creation
```powershell
# Source: Microsoft ConvertTo-Json documentation
# URL: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertto-json

# Create artifact object
$artifact = [ordered]@{
    Operation = "CreateVM"
    Timestamp = (Get-Date).ToString("o")
    Status = "Success"
    Duration = 45.2
    VMNames = @("VM01", "VM02")
}

# Convert to JSON with proper depth
$json = $artifact | ConvertTo-Json -Depth 4

# Save to file
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$jsonPath = ".planning/runs/run-$timestamp.json"
$json | Out-File -FilePath $jsonPath -Encoding utf8
```

### Module Structure
```powershell
# Source: Microsoft "How to Write a PowerShell Script Module" documentation
# URL: https://learn.microsoft.com/en-us/powershell/scripting/developer/module/how-to-write-a-powershell-script-module

# In SimpleLab.psm1

# Get public and private function files
$PublicFunctions = Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue
$PrivateFunctions = Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue

# Dot-source the files
foreach ($file in @($PublicFunctions + $PrivateFunctions)) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error "Failed to import function $($file.BaseName): $_"
        throw
    }
}

# Export public functions
Export-ModuleMember -Function $PublicFunctions.BaseName
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Get-WmiObject | Get-CimInstance | PowerShell 3.0 (2012) | Get-CimInstance uses WS-MAN, more portable |
| Write-Host for all output | Write-Error for errors, Write-Host for user output | Community best practice | Enables proper error handling pipelines |
| Global error variables | try/catch with $ErrorActionPreference | PowerShell evolution | Structured error handling is standard |
| Custom JSON serialization | ConvertTo-Json | PowerShell 3.0 (2012) | Built-in, handles edge cases |
| Manual script sourcing | Import-Module with manifest | PowerShell 2.0+ | Standard module system |

**Deprecated/outdated:**
- **Get-WmiObject:** Replaced by Get-CimInstance (still works but deprecated)
- **Trap statement:** Legacy error handling, use try/catch instead
- **.ps1xml files for simple types:** Use ConvertTo-Json for serialization

## Open Questions

1. **Hyper-V Detection Method**
   - What we know: Get-ComputerInfo returns Hyper-V related properties; Get-CimInstance Win32_ComputerSystem.HypervisorPresent directly reports hypervisor presence
   - What's unclear: Which specific Get-ComputerInfo property most reliably indicates Hyper-V is enabled
   - Recommendation: Use Get-CimInstance for HypervisorPresent check as it's more direct, or use Get-ComputerInfo with HyperVRequirement properties (when false, Hyper-V may not be available)

2. **Hashtable vs PSCustomObject for Run Artifacts**
   - What we know: Both work with ConvertTo-Json; [ordered] hashtables preserve order
   - What's unclear: Performance difference at artifact generation scale
   - Recommendation: Start with [ordered] hashtable for simplicity; switch to PSCustomObject if needed for type safety

## Sources

### Primary (HIGH confidence)
- **Microsoft Learn - Get-ComputerInfo** - Official cmdlet documentation, properties, Windows-only platform requirement
- **Microsoft Learn - Everything about exceptions** - Comprehensive error handling guide, try/catch/finally patterns
- **Microsoft Learn - ConvertTo-Json** - JSON serialization cmdlet, depth parameters, DateTime handling
- **Microsoft Learn - How to Write a PowerShell Script Module** - Module structure, Export-ModuleMember, .psm1/.psd1 files
- **Microsoft Scripting Blog - Detect Hypervisor Presence** - Get-CimInstance Win32_ComputerSystem.HypervisorPresent pattern

### Secondary (MEDIUM confidence)
- [Netwrix PowerShell Try-Catch Guide](https://netwrix.com/en/resources/blog/powershell-try-catch/) - Practical error handling examples
- [Fortra PowerShell Best Practices](https://automate.fortra.com/blog/powershell-error-handling) - Community best practices
- [Stack Overflow - PowerShell module structure](https://stackoverflow.com/questions/43032681/powershell-module-structure) - Module organization patterns
- [Inedo Blog - PowerShell modules in source control](https://blog.inedo.com/powershell/modules-in-source-control) - Organization strategies

### Tertiary (LOW confidence)
- Various community blog posts and Stack Overflow discussions - Used for supplementary patterns only, verified against official docs

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All built-in PowerShell features, official documentation available
- Architecture: HIGH - Based on Microsoft documentation and established PowerShell patterns
- Pitfalls: HIGH - All verified against official documentation or common community issues

**Research date:** 2025-02-09
**Valid until:** 2025-03-09 (30 days - PowerShell fundamentals are stable)

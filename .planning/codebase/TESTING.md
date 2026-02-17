# Testing Patterns

**Analysis Date:** 2026-02-16

## Test Framework

**Runner:**
- Pester 5.x (implicit from test syntax)
- No explicit `pester.config.ps1` or `.pester.ps1` file detected
- Tests assume Pester is installed in host environment

**Assertion Library:**
- Pester built-in assertions: `Should -Be`, `Should -Contain`, `Should -BeOfType`, `Should -Throw`

**Run Commands:**
```powershell
Invoke-Pester -Path .\Tests\           # Run all tests
Invoke-Pester -Path .\Tests\SimpleLab.Tests.ps1  # Run specific suite
Invoke-Pester -Path .\Tests\ -Output Detailed    # Verbose output
```

**No coverage command detected** - Manual coverage tracking required.

## Test File Organization

**Location:**
- All tests in `Tests/` directory (28 test files)
- NOT co-located with source files
- Separate from implementation code

**Naming:**
- Pattern: `<Feature>.Tests.ps1`
- Examples:
  - `ActionRequest.Tests.ps1` - Tests action normalization
  - `FleetStateProbe.Tests.ps1` - Tests multi-host probing
  - `QuickModeHeal.Tests.ps1` - Tests auto-heal logic
  - `SimpleLab.Tests.ps1` - Module integration tests
  - `Private.Tests.ps1` - Private helper tests

**Structure:**
```
Tests/
├── ActionRequest.Tests.ps1
├── CoordinatorDispatch.Tests.ps1
├── CoordinatorIntegration.Tests.ps1
├── CoordinatorPlan.Tests.ps1
├── CoordinatorPolicy.Tests.ps1
├── DeployModeHandoff.Tests.ps1
├── DispatchDocs.Tests.ps1
├── DispatchMode.Tests.ps1
├── DispatchPlan.Tests.ps1
├── ExecutionProfile.Tests.ps1
├── FleetStateProbe.Tests.ps1
├── HostInventory.Tests.ps1
├── ModeDecision.Tests.ps1
├── NewScopedConfirmationTokenScript.Tests.ps1
├── OpenCodeLabAppRouting.Tests.ps1
├── OpenCodeLabDispatchContract.Tests.ps1
├── OpenCodeLabGuiHelpers.Tests.ps1
├── OperationIntent.Tests.ps1
├── OrchestrationIntent.Tests.ps1
├── Private.Tests.ps1
├── QuickModeHeal.Tests.ps1
├── RunAlias.Tests.ps1
├── Run.Tests.ps1
├── ScopedConfirmationToken.Tests.ps1
├── SimpleLab.Tests.ps1
├── TransientTransportFailure.Tests.ps1
├── VirtualSwitchSubnetPreflight.Tests.ps1
└── WpfGui.Tests.ps1
```

**Total test count:** 28 test files, 322 test cases (`Describe`/`It`/`Context` blocks)

## Test Structure

**Suite Organization:**
```powershell
# Standard pattern from ActionRequest.Tests.ps1:
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Resolve-LabActionRequest.ps1')
    . (Join-Path $repoRoot 'Private/New-LabAppArgumentList.ps1')
}

Describe 'Resolve-LabActionRequest' {
    It 'preserves setup action and forces full mode' {
        $result = Resolve-LabActionRequest -Action 'setup'

        $result.Action | Should -Be 'setup'
        $result.Mode | Should -Be 'full'
    }

    It 'overrides provided mode for setup action' {
        $result = Resolve-LabActionRequest -Action 'setup' -Mode 'quick'

        $result.Action | Should -Be 'setup'
        $result.Mode | Should -Be 'full'
    }
}
```

**Patterns:**
- `BeforeAll {}` - Load functions under test (43 occurrences across 27 test files)
- `BeforeEach {}` - Setup mocks and state per test
- `Describe 'FunctionName'` - Group tests by function
- `It 'does something specific'` - Individual test case
- `Context 'when condition'` - Optional grouping within Describe

**Setup/Teardown:**
- Setup: `BeforeAll` for imports, `BeforeEach` for mocks
- Teardown: Implicit (Pester cleans up after each test)
- Temp files: Manual cleanup in try-finally blocks

## Mocking

**Framework:** Pester built-in mocking

**Patterns:**
```powershell
# From QuickModeHeal.Tests.ps1:
BeforeEach {
    $script:switchCalled = $false
    $script:natCalled = $false

    function New-LabSwitch { $script:switchCalled = $true }
    function New-LabNAT { $script:natCalled = $true }
    function Save-LabReadyCheckpoint { }
    function Start-LabVMs { }
    function Wait-LabVMReady { return $true }
    function Test-LabDomainHealth { return $true }
}

It 'heals missing switch' {
    # ... setup ...
    $result = Invoke-LabQuickModeHeal -StateProbe $probe ...

    $script:switchCalled | Should -BeTrue
}
```

**Mock-CommandName pattern (7 occurrences in FleetStateProbe.Tests.ps1):**
```powershell
Mock -CommandName Invoke-Command -MockWith { throw 'Should not be called for localhost' }

$result = Invoke-LabRemoteProbe -HostName 'localhost' -ScriptBlock { 'local-ok' }

Should -Invoke -CommandName Invoke-Command -Times 0 -Exactly
```

**What to Mock:**
- External commands: `Invoke-Command`, `Get-VM`, `Get-VMSnapshot`, `Get-VMSwitch`
- File I/O: When testing logic without filesystem dependencies
- Network calls: Hyper-V cmdlets, remoting operations
- Expensive operations: VM creation, domain joins

**What NOT to Mock:**
- Pure functions under test
- Simple data transformations
- Result object construction
- Configuration parsing (use real JSON/hashtables)

## Fixtures and Factories

**Test Data:**
```powershell
# Inline fixture pattern from SimpleLab.Tests.ps1:
Describe 'Get-LabVMConfig' {
    It 'Returns default configurations when no config file exists' {
        $result = Get-LabVMConfig
        $result | Should -Not -BeNullOrEmpty
        $result.Keys | Should -Contain 'dc1'
        $result.Keys | Should -Contain 'svr1'
        $result.Keys | Should -Contain 'ws1'
    }
}

# Structured test data from QuickModeHeal.Tests.ps1:
It 'returns no-op when probe is clean' {
    $probe = [pscustomobject]@{
        LabRegistered = $true
        MissingVMs = @()
        LabReadyAvailable = $true
        SwitchPresent = $true
        NatPresent = $true
    }

    $result = Invoke-LabQuickModeHeal -StateProbe $probe ...
}
```

**Location:**
- No separate fixtures directory
- Test data defined inline within test cases
- Factory pattern: PSCustomObject construction in BeforeEach or within It blocks

## Coverage

**Requirements:** None enforced

**Current State:**
- 28 test files covering orchestration, coordination, and core infrastructure
- Private functions: Partial coverage (19+ Private functions have tests)
- Public functions: Minimal direct unit tests (tested via integration tests)

**Coverage Gaps Identified:**
- Public VM management functions (`New-LabVM`, `Initialize-LabVMs`) - No unit tests
- Network setup functions (`New-LabSwitch`, `New-LabNAT`) - Integration only
- Linux VM helpers (`New-LinuxVM`, `Wait-LinuxVMReady`) - No unit tests
- GUI helpers (`Start-OpenCodeLabGUI.ps1`) - Minimal coverage (WpfGui.Tests.ps1 exists but limited)

**View Coverage:**
```powershell
# No built-in coverage command
# Manual: Review test file vs. source file list
```

## Test Types

**Unit Tests:**
- Scope: Individual Private helper functions
- Approach: Dot-source function, mock dependencies, assert result shape
- Examples:
  - `ActionRequest.Tests.ps1` - Tests `Resolve-LabActionRequest` logic
  - `ScopedConfirmationToken.Tests.ps1` - Tests token validation
  - `OperationIntent.Tests.ps1` - Tests intent resolution

**Integration Tests:**
- Scope: Multi-function workflows (e.g., coordinator dispatch)
- Approach: Mock external dependencies, test orchestration flow
- Examples:
  - `CoordinatorIntegration.Tests.ps1` - Tests full coordinator cycle
  - `SimpleLab.Tests.ps1` - Tests module loading and Public function contracts
  - `Private.Tests.ps1` - Tests Private helper interactions

**E2E Tests:**
- Framework: Not automated
- Approach: Manual via `OpenCodeLab-App.ps1 -Action deploy -DryRun`
- No dedicated E2E test suite detected

## Common Patterns

**Async Testing:**
```powershell
# Synchronous operations only in test suite
# Hyper-V operations are inherently blocking
# No async/await pattern in PowerShell 5.1 tests
```

**Error Testing:**
```powershell
# From FleetStateProbe.Tests.ps1:
It 'surfaces clear errors when remoting fails' {
    Mock -CommandName Invoke-Command -MockWith { throw 'WinRM unavailable' }

    {
        Invoke-LabRemoteProbe -HostName 'hv-03' -ScriptBlock { 'never-runs' }
    } | Should -Throw "Remote probe failed for host 'hv-03'*WinRM unavailable*"
}

# Pattern: Wrap call in scriptblock, assert with Should -Throw and wildcard message
```

**Platform Detection:**
```powershell
# From SimpleLab.Tests.ps1:
function Test-IsWindows {
    $platformIsWindows = if ($IsWindows -eq $null) { $env:OS -eq 'Windows_NT' } else { $IsWindows }
    return $platformIsWindows
}

Describe 'Test-HyperVEnabled' {
    BeforeEach {
        if (-not (Test-IsWindows)) {
            Set-ItResult -Skipped -Because 'Hyper-V is Windows-only'
        }
    }
}
```

**Isolated Runspace Pattern:**
```powershell
# From FleetStateProbe.Tests.ps1:
function Invoke-TestInIsolatedRunspace {
    param([scriptblock]$ScriptBlock, [object[]]$ArgumentList = @())

    $ps = [powershell]::Create()
    try {
        $null = $ps.AddScript($ScriptBlock.ToString(), $true)
        foreach ($argument in $ArgumentList) {
            $null = $ps.AddArgument($argument)
        }
        return $ps.Invoke()
    }
    finally {
        $ps.Dispose()
    }
}

# Used to test remote scriptblock execution without actual remoting
```

## Test Quality Metrics

**Test Files:** 28
**Test Cases (Describe/It/Context blocks):** 322
**BeforeAll/BeforeEach usage:** 43 occurrences (good setup hygiene)
**Mock usage:** 7 explicit Mock commands (light mocking, favors real execution where safe)

**Strengths:**
- Comprehensive orchestration logic coverage
- Isolated runspace pattern for remote execution testing
- Platform-aware test skipping
- Clear test names describing behavior

**Weaknesses:**
- No coverage metrics tooling
- Public VM management functions lack unit tests
- No E2E automation (manual only)
- No performance/load tests

## Running Tests

**Prerequisites:**
```powershell
# Install Pester 5.x if not present:
Install-Module -Name Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force

# Verify installation:
Get-Module -Name Pester -ListAvailable
```

**Run All Tests:**
```powershell
# From repository root:
Invoke-Pester -Path .\Tests\

# With detailed output:
Invoke-Pester -Path .\Tests\ -Output Detailed
```

**Run Specific Suite:**
```powershell
Invoke-Pester -Path .\Tests\QuickModeHeal.Tests.ps1
Invoke-Pester -Path .\Tests\SimpleLab.Tests.ps1
```

**Run by Tag (if implemented):**
```powershell
# No tag usage detected in test files
# To add tags: Describe 'Name' -Tag 'unit', 'integration'
```

## Test Development Guidelines

**When Adding New Private Function:**
1. Create corresponding test file: `Tests/<FunctionName>.Tests.ps1`
2. Use `BeforeAll` to dot-source the function
3. Mock external dependencies in `BeforeEach`
4. Test success path, error path, and edge cases
5. Assert result object shape and property values

**When Adding New Public Function:**
1. Add integration test to `Tests/SimpleLab.Tests.ps1` or separate file
2. Mock Hyper-V cmdlets if testing without VM infrastructure
3. Include platform detection if Windows-specific
4. Add parameter validation tests

**Pattern to Follow:**
```powershell
# Tests/MyNewFunction.Tests.ps1
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Get-MyNewFunction.ps1')
}

Describe 'Get-MyNewFunction' {
    BeforeEach {
        # Setup mocks
    }

    It 'returns expected result for valid input' {
        $result = Get-MyNewFunction -Param 'value'

        $result | Should -Not -BeNullOrEmpty
        $result.Status | Should -Be 'Success'
    }

    It 'handles missing input gracefully' {
        { Get-MyNewFunction -Param $null } | Should -Throw
    }
}
```

---

*Testing analysis: 2026-02-16*

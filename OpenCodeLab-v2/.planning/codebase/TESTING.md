# Testing Patterns

**Analysis Date:** 2025-02-21

## Test Framework

**Runner:**
- **C# / WPF Application**: No C# unit test projects found
- **PowerShell Integration Tests**: Pester 5.x (detected in project memory)
- PowerShell test files located in `/mnt/c/projects/AutomatedLab/OpenCodeLab-v2/tests/`

**Test Location:**
- Unit tests: `/mnt/c/projects/AutomatedLab/OpenCodeLab-v2/tests/unit/`
- Integration tests: `/mnt/c/projects/AutomatedLab/OpenCodeLab-v2/tests/integration/`
- Smoke tests: `/mnt/c/projects/AutomatedLab/OpenCodeLab-v2/tests/smoke/`

**Assertion Library:**
- Pester assertions (built-in): `Should -Be`, `Should -Throw`, etc.
- No C# test assertions for WPF code

**Run Commands:**
```bash
# Run PowerShell tests (Pester)
Invoke-Pester ./tests/unit -Output Detailed
Invoke-Pester ./tests/integration -Output Detailed
Invoke-Pester ./tests/smoke -Output Detailed

# Watch mode: Not applicable to Pester (test-and-exit model)

# Coverage: Pester code coverage
Invoke-Pester -CodeCoverage ./src/**/*.ps1
```

## Test File Organization

**Location:**
- **PowerShell Tests**: Separate directory structure (`tests/unit/`, `tests/integration/`, `tests/smoke/`)
- **C# Application**: No co-located unit tests for WPF code
- **Pattern**: Central test directories organized by test type (unit, integration, smoke)

**Naming:**
- PowerShell: `*.Tests.ps1` suffix (e.g., `Config.Tests.ps1`, `Dashboard.Tests.ps1`)
- Full path examples:
  - `/mnt/c/projects/AutomatedLab/OpenCodeLab-v2/tests/unit/App/CliRuntime.Tests.ps1`
  - `/mnt/c/projects/AutomatedLab/OpenCodeLab-v2/tests/integration/Actions/DeployAction.Tests.ps1`

**Directory Structure:**
```
tests/
├── unit/                          # Unit tests
│   ├── App/                       # Application layer
│   │   ├── CliRuntime.Tests.ps1
│   │   └── CommandRouter.Tests.ps1
│   ├── Core/                      # Core functionality
│   │   ├── Artifacts.Tests.ps1
│   │   ├── Config.Tests.ps1
│   │   └── RunLock.Tests.ps1
│   ├── Domain/                    # Domain models
│   │   └── ActionResult.Tests.ps1
│   └── Presentation/              # UI layer
│       └── Dashboard.Tests.ps1
├── integration/                   # Integration tests
│   └── Actions/
│       ├── DeployAction.Tests.ps1
│       ├── PreflightAction.Tests.ps1
│       ├── StatusHealth.Tests.ps1
│       └── TeardownPolicy.Tests.ps1
└── smoke/                         # End-to-end smoke tests
    └── LocalLifecycle.Smoke.Tests.ps1
```

## Test Structure

**C# WPF Code:**
- No formal unit tests for C# code (Services, ViewModels, Views)
- Application tested through PowerShell integration tests that invoke the CLI
- Defensive programming used instead: null checks, validation, broad exception handling

**PowerShell Tests (Pester 5.x):**

Test file structure from project memory:
```powershell
Describe 'Feature Name' {
    BeforeAll {
        # Dot-source helpers and modules
        . ./Private/HelperFunction.ps1
        Import-Module ./Module.psm1
    }

    BeforeEach {
        # Setup/reset state before each test
        $testData = @{}
    }

    Context 'Scenario Name' {
        It 'should do something' {
            # Arrange
            $input = 'test'

            # Act
            $result = Get-Something -Input $input

            # Assert
            $result | Should -Be 'expected'
        }
    }

    AfterAll {
        # Cleanup
    }
}
```

## Mocking

**Framework:**
- Pester's built-in mock functions: `Mock`, `InModuleScope`, `Should -Invoke`
- No explicit C# mocking framework (NUnit, xUnit, Moq) in use

**Patterns (PowerShell):**

```powershell
# Mock a command
Mock 'Get-VM' -MockWith { return @{ Name = 'TestVM' } }

# Verify mocks were called
Should -Invoke 'Get-VM' -Times 1

# Mock with parameters
Mock 'Test-Path' -ParameterFilter { $Path -eq 'C:\LabSources' } -MockWith { return $true }

# Invoke-Command mocking
InModuleScope 'ModuleName' {
    Mock 'Get-Something' { return 'mocked' }
    Test-Feature | Should -Be 'expected'
}
```

**What to Mock:**
- External commands: `Get-VM`, `New-VM`, `Remove-VM` (Hyper-V cmdlets)
- File system operations: `Test-Path`, `Get-Item` for path validation
- Network calls: Mock HTTP requests if any
- Environment variables: Mock via `$env:VAR_NAME` assignment

**What NOT to Mock:**
- Core PowerShell functions: `Write-Host`, `Write-Error` (test output handling)
- Helper functions from same module: Test actual implementations
- Data models and objects: Use real objects unless testing serialization
- Core language constructs: Use real conditionals, loops

## Fixtures and Factories

**Test Data:**
- JSON configuration files for lab scenarios
- Mock LabConfig objects constructed inline in tests
- Example from structure: Lab definitions stored as JSON in `C:\LabSources\LabConfig`

**Pattern (Typical):**
```powershell
# Inline fixture creation
$testLab = @{
    LabName     = 'TestLab'
    LabPath     = 'C:\LabSources\TestLab'
    Network     = @{ SwitchName = 'TestSwitch' }
    VMs         = @(
        @{ Name = 'DC01'; Role = 'DC'; Memory = 2 }
        @{ Name = 'WS01'; Role = 'Client'; Memory = 2 }
    )
}

# Convert to JSON for file-based tests
$testLab | ConvertTo-Json | Out-File 'test-config.json'
```

**Location:**
- Test data embedded in test files or in `test-fixtures/` directory
- Lab configuration examples in memory: Standard configs with DC, file servers, clients

## Coverage

**Requirements:**
- Not explicitly enforced (no code coverage thresholds in configuration)
- Pester supports code coverage analysis via `-CodeCoverage` parameter
- Coverage not integrated into CI pipeline (no automated enforcement)

**View Coverage:**
```bash
# Generate code coverage report
Invoke-Pester ./tests -CodeCoverage ./src/**/*.ps1 -PassThru |
    Select-Object -ExpandProperty CodeCoverage

# Coverage output: Line/function hit counts per file
```

## Test Types

**Unit Tests:**
- **Scope**: Individual functions, helpers, business logic
- **Location**: `/mnt/c/projects/AutomatedLab/OpenCodeLab-v2/tests/unit/`
- **Approach**:
  - Test small, isolated functions
  - Mock external dependencies (file system, cmdlets)
  - Verify output and side effects
  - Example test areas: Config parsing, artifact handling, runtime state

**Integration Tests:**
- **Scope**: Feature workflows, multi-component interactions
- **Location**: `/mnt/c/projects/AutomatedLab/OpenCodeLab-v2/tests/integration/`
- **Approach**:
  - Test actions: Deploy, Preflight, StatusHealth, Teardown
  - Verify service interactions
  - Test against actual Hyper-V (when available)
  - May require admin privileges or specific lab configuration
  - Example: `DeployAction.Tests.ps1` - full deployment workflow

**E2E Tests:**
- **Framework**: Smoke tests via Pester
- **Location**: `/mnt/c/projects/AutomatedLab/OpenCodeLab-v2/tests/smoke/`
- **Scope**: `LocalLifecycle.Smoke.Tests.ps1` - complete lab lifecycle
- **Approach**:
  - Create lab → Deploy → Validate → Destroy
  - Minimal assertions, focus on workflow completion
  - Longer runtime, tests actual system behavior

**C# WPF Tests:**
- **Not formalized**: No unit test project exists
- **Manual testing**: GUI tested through user interaction
- **Implicit testing**: Business logic tested indirectly via PowerShell integration tests
- **Coverage**: MVVM logic (ViewModels) tested through PowerShell scenarios

## Common Patterns

**Setup/Teardown:**

```powershell
Describe 'Lab Deployment' {
    BeforeAll {
        # Initialize test environment
        $script:testLabPath = 'C:\LabSources\UnitTest'
        New-Item -Path $script:testLabPath -ItemType Directory -Force
    }

    BeforeEach {
        # Reset state before each test
        Remove-Item "$script:testLabPath\*" -Force -Recurse -ErrorAction SilentlyContinue
    }

    AfterEach {
        # Cleanup after each test
        # (optional, if expensive)
    }

    AfterAll {
        # Final cleanup
        Remove-Item $script:testLabPath -Force -Recurse -ErrorAction SilentlyContinue
    }
}
```

**Assertion Pattern (Pester 5.x):**

```powershell
# Basic assertions
$result | Should -Be 'expected'
$count | Should -Be 5
$object.Property | Should -Not -BeNullOrEmpty

# Collection assertions
$results | Should -HaveCount 3
$results[0].Name | Should -BeIn @('Option1', 'Option2')

# Exception assertions
{ Invoke-Command } | Should -Throw 'ErrorMessage'

# Mock verification
Should -Invoke 'Get-VM' -Times 2 -Exactly
```

**Async/Task Testing (PowerShell):**
- PowerShell is single-threaded
- Async operations tested through Job polling
- Example pattern:
```powershell
$job = Start-Job -ScriptBlock { Invoke-LongRunningTask }
$job | Wait-Job -Timeout 30 | Should -Not -BeNullOrEmpty
$result = $job | Receive-Job
$result | Should -Be 'expected'
```

**Error Testing (Pester):**

```powershell
# Test error handling
Context 'Error Cases' {
    It 'should handle missing VM' {
        Mock 'Get-VM' {
            throw [System.Management.Automation.ItemNotFoundException]'VM not found'
        }

        { Start-VM -Name 'NonExistent' } | Should -Throw
    }

    It 'should log validation errors' {
        $result = Invoke-LabValidation -BadConfig $null
        $result.Errors | Should -Not -BeNullOrEmpty
    }
}
```

**C# Service Testing (Implicit via PowerShell):**

Services like `HyperVService.cs` (line 1-178) are tested through PowerShell integration tests that:
1. Call the C# application with parameters
2. Verify return codes and output
3. Check system state (VMs created/removed)
4. Validate logs for error messages

Example test scenario:
```powershell
# Test VM enumeration
$vms = @(HyperVService).GetVirtualMachinesAsync().Result
$vms | Should -HaveCount -GreaterThan 0
```

---

*Testing analysis: 2025-02-21*

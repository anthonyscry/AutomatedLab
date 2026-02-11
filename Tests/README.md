# SimpleLab Tests

This directory contains Pester tests for the SimpleLab module.

## Running Tests

### Quick Start

From the SimpleLab module root:

```powershell
# Run all tests
Invoke-Pester -Path .\Tests\

# Run with detailed output
Invoke-Pester -Path .\Tests\ -Verbose

# Run specific test file
Invoke-Pester -Path .\Tests\SimpleLab.Tests.ps1
```

### Using the Test Runner

```powershell
# Run tests with results output
.\Tests\Run.Tests.ps1

# Run with detailed verbosity
.\Tests\Run.Tests.ps1 -Verbosity Detailed

# Specify custom output path
.\Tests\Run.Tests.ps1 -OutputPath .\Tests\MyResults.xml
```

## Test Files

| File | Description |
|------|-------------|
| `SimpleLab.Tests.ps1` | Tests for public API functions |
| `Private.Tests.ps1` | Tests for internal helper functions |
| `Run.Tests.ps1` | Test runner with code coverage |

## Test Structure

Tests are organized by function:

- **Unit Tests**: Test individual functions in isolation
- **Integration Tests**: Test multiple functions working together
- **Platform Tests**: Handle Windows vs Linux differences

## Code Coverage

The test runner generates code coverage reports in JaCoCo format.
View coverage using compatible tools or editors that support JaCoCo.

## Writing New Tests

When adding new functions:

1. Create a `Describe` block for the function
2. Add `It` blocks for each behavior/edge case
3. Use `BeforeAll`/`BeforeEach` for setup
4. Use `AfterAll`/`AfterEach` for cleanup
5. Mock Windows-specific functionality for cross-platform tests

Example:

```powershell
Describe 'New-MyFunction' {
    BeforeEach {
        if (-not (Test-IsWindows)) {
            Set-ItResult -Skipped -Because 'Windows-only feature'
        }
    }

    It 'Returns expected result' {
        $result = New-MyFunction -Param 'Value'
        $result | Should -Be 'Expected'
    }

    It 'Handles null input' {
        { New-MyFunction -Param $null } | Should -Throw
    }
}
```

## CI/CD Integration

Tests can be integrated into CI/CD pipelines:

```yaml
# GitHub Actions example
- name: Run Pester Tests
  shell: pwsh
  run: |
    ./Tests/Run.Tests.ps1 -OutputPath TestResults.xml

- name: Upload Test Results
  uses: actions/upload-artifact@v3
  with:
    name: test-results
    path: TestResults.xml
```

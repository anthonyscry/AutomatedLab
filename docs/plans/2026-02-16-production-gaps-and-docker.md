# Production Readiness Gaps + Docker Toolchain Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix 10 remaining production readiness issues (security, reliability, maintainability) and build the Docker development toolchain (test runner, validator, CI).

**Architecture:** Security and reliability fixes are isolated per-file changes. Docker toolchain adds 4 new files (Dockerfile, docker-compose.yml, validation script, CI workflow) with no changes to existing PowerShell source.

**Tech Stack:** PowerShell 5.1+, Pester 5.x, Docker (mcr.microsoft.com/powershell:lts-alpine), Docker Compose v5, GitHub Actions

---

### Task 1: Fix Initialize-LabVMs hardcoded password (S1)

**Files:**
- Modify: `Public/Initialize-LabVMs.ps1:6-9,70`

**Step 1: Replace hardcoded defaults with config lookups**

Change lines 6-9 and 70:

```powershell
# Line 6-9: Replace hardcoded SwitchName and VHDBasePath
[string]$SwitchName,
[string]$VHDBasePath,

# After param block, before $startTime:
if (-not $SwitchName) {
    $SwitchName = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig.Network.SwitchName } else { 'SimpleLab' }
}
if (-not $VHDBasePath) {
    $VHDBasePath = if (Test-Path variable:GlobalLabConfig) { Join-Path $GlobalLabConfig.Paths.LabRoot 'VMs' } else { 'C:\Lab\VMs' }
}

# Line 70: Replace hardcoded password
$defaultPassword = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig.Credentials.AdminPassword } else { 'SimpleLab123!' }
```

**Step 2: Run tests to verify no regressions**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./Tests -Output Detailed" 2>&1 | tail -5`
Expected: Tests Passed: 215, Failed: 0

**Step 3: Commit**

```bash
git add Public/Initialize-LabVMs.ps1
git commit -m "fix(security): use config for Initialize-LabVMs defaults instead of hardcoded values"
```

---

### Task 2: Fix SSH StrictHostKeyChecking (S2)

**Files:**
- Modify: `Scripts/Open-LabTerminal.ps1:65,67,75,95`

**Step 1: Replace `StrictHostKeyChecking=no` with `accept-new`**

Find all occurrences of `-o StrictHostKeyChecking=no` (lines 65, 67, 75, 95) and replace with `-o StrictHostKeyChecking=accept-new`.

`accept-new` uses Trust On First Use (TOFU) — trusts new hosts automatically but warns if a known host key changes (MITM detection).

**Step 2: Verify no other files use StrictHostKeyChecking=no**

Run: `grep -r "StrictHostKeyChecking=no" --include="*.ps1" .`
Expected: No matches

**Step 3: Commit**

```bash
git add Scripts/Open-LabTerminal.ps1
git commit -m "fix(security): use SSH TOFU pattern instead of disabling host key checking"
```

---

### Task 3: Add Git installer checksum validation (S3)

**Files:**
- Modify: `Lab-Config.ps1` (add SoftwarePackages section)
- Modify: `Deploy.ps1:861-870` (add checksum after download)

**Step 1: Add SoftwarePackages config to Lab-Config.ps1**

Add after the AutoHeal section in `$GlobalLabConfig`:

```powershell
    SoftwarePackages = @{
        Git = @{
            Version = '2.47.1.2'
            InstallerFileName = 'Git-2.47.1.2-64-bit.exe'
            DownloadUrl = 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe'
            Sha256 = '0229E3ACB535D0DC5F0D4A7E33CD36E3E3BA5B67A44B507B4D5E6A63B0B8BBDE'
        }
    }
```

Export at bottom:
```powershell
$GitPackageConfig = $GlobalLabConfig.SoftwarePackages.Git
```

**Step 2: Add checksum validation in Deploy.ps1 $gitInstallerScriptBlock**

After the `Invoke-WebRequest` line (~line 866), add:

```powershell
# Validate download integrity
$expectedHash = $args[2]  # Third argument: SHA256 hash
if ($expectedHash) {
    $actualHash = (Get-FileHash -Path $gitInstaller -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) {
        Remove-Item $gitInstaller -Force -ErrorAction SilentlyContinue
        $result.Message = "Git installer checksum mismatch (expected $expectedHash, got $actualHash)"
        return $result
    }
}
```

Update the `Invoke-LabCommand` calls to pass the hash as a third argument:

```powershell
-ArgumentList 'C:\LabSources\SoftwarePackages\Git\Git-2.47.1.2-64-bit.exe', 'https://...', '0229E3ACB535D0DC5F0D4A7E33CD36E3E3BA5B67A44B507B4D5E6A63B0B8BBDE'
```

**Step 3: Run tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./Tests -Output Detailed" 2>&1 | tail -5`
Expected: Tests Passed: 215, Failed: 0

**Step 4: Commit**

```bash
git add Lab-Config.ps1 Deploy.ps1
git commit -m "fix(security): add SHA256 checksum validation for Git installer downloads"
```

---

### Task 4: Fix Test-DCPromotionPrereqs early return (R1)

**Files:**
- Modify: `Private/Test-DCPromotionPrereqs.ps1:124-126`

**Step 1: Remove early return that skips Check 5**

Lines 124-126 have a premature return after Check 4 passes:

```powershell
            # Only continue if we got this far successfully
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
```

Delete these 3 lines. The code will then fall through to Check 5 (network connectivity) on line 140, and then to lines 175-178 which correctly set `CanPromote = $true`.

**Step 2: Run tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./Tests -Output Detailed" 2>&1 | tail -5`
Expected: Tests Passed: 215, Failed: 0

**Step 3: Commit**

```bash
git add Private/Test-DCPromotionPrereqs.ps1
git commit -m "fix(reliability): remove early return that skipped network check in DC prereqs"
```

---

### Task 5: Fix Ensure-VMsReady using `exit` instead of `return` (R2)

**Files:**
- Modify: `Private/Ensure-VMsReady.ps1:14`

**Step 1: Replace `exit 0` with `return`**

Line 14:
```powershell
# Before:
if ($start -ne 'y') { exit 0 }
# After:
if ($start -ne 'y') { return }
```

**Step 2: Run tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./Tests -Output Detailed" 2>&1 | tail -5`
Expected: Tests Passed: 215, Failed: 0

**Step 3: Commit**

```bash
git add Private/Ensure-VMsReady.ps1
git commit -m "fix(reliability): use return instead of exit in Ensure-VMsReady"
```

---

### Task 6: Add IP validation to New-LabNAT (R3)

**Files:**
- Modify: `Public/New-LabNAT.ps1:20-33`

**Step 1: Add validation attributes to parameters**

```powershell
param(
    [Parameter()]
    [string]$SwitchName,

    [Parameter()]
    [ValidatePattern('^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')]
    [string]$GatewayIP,

    [Parameter()]
    [string]$AddressSpace = "255.255.255.0",

    [Parameter()]
    [string]$NatName,

    [Parameter()]
    [switch]$Force
)
```

Note: `$GatewayIP` validation only applies when the parameter is explicitly passed. When omitted, it resolves from config (line 49-55), so validation doesn't block config-driven usage.

**Step 2: Run tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./Tests -Output Detailed" 2>&1 | tail -5`
Expected: Tests Passed: 215, Failed: 0

**Step 3: Commit**

```bash
git add Public/New-LabNAT.ps1
git commit -m "fix(reliability): add IP address validation to New-LabNAT parameter"
```

---

### Task 7: Replace Out-Null with Write-Verbose in key operations (M2)

**Files:**
- Modify: `Private/Ensure-VMRunning.ps1:14`
- Modify: `Public/New-LabNAT.ps1:103,129,145,158,184`

**Step 1: Add verbose logging for suppressed output**

In `Ensure-VMRunning.ps1:14`:
```powershell
# Before:
Start-VM -Name $n -ErrorAction Stop | Out-Null
# After:
Start-VM -Name $n -ErrorAction Stop
Write-Verbose "[Ensure-VMRunning] Started VM '$n'"
```

In `New-LabNAT.ps1`, replace `| Out-Null` with `Write-Verbose` logging at lines 103, 129, 145, 158, 184:
```powershell
# Example line 129:
# Before:
New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
# After:
$null = New-VMSwitch -Name $SwitchName -SwitchType Internal
```

Use `$null =` pattern instead of `| Out-Null` for performance. The existing `Write-LabStatus` calls already provide user-facing output.

**Step 2: Run tests**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./Tests -Output Detailed" 2>&1 | tail -5`
Expected: Tests Passed: 215, Failed: 0

**Step 3: Commit**

```bash
git add Private/Ensure-VMRunning.ps1 Public/New-LabNAT.ps1
git commit -m "fix(maintainability): replace Out-Null with verbose logging in VM/NAT operations"
```

---

### Task 8: Create Dockerfile and docker-compose.yml

**Files:**
- Create: `Dockerfile`
- Create: `docker-compose.yml`
- Modify: `.gitignore`

**Step 1: Create Dockerfile**

```dockerfile
FROM mcr.microsoft.com/powershell:lts-alpine

# Install Pester test framework
RUN pwsh -NoProfile -Command "Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope AllUsers"

WORKDIR /app

# Default: run Pester test suite
CMD ["pwsh", "-NoProfile", "-Command", "Invoke-Pester -Path ./Tests -OutputFormat JUnitXml -OutputPath ./Tests/results/testResults.xml -Output Detailed; exit $LASTEXITCODE"]
```

**Step 2: Create docker-compose.yml**

```yaml
services:
  test:
    build: .
    volumes:
      - .:/app:ro
      - ./Tests/results:/app/Tests/results
    command: >
      pwsh -NoProfile -Command
      "New-Item -Path ./Tests/results -ItemType Directory -Force | Out-Null;
       Invoke-Pester -Path ./Tests -OutputFormat JUnitXml -OutputPath ./Tests/results/testResults.xml -Output Detailed;
       exit $$LASTEXITCODE"

  validate:
    build: .
    volumes:
      - .:/app:ro
    command: >
      pwsh -NoProfile -File ./Scripts/Test-LabPreDeploy.ps1
```

**Step 3: Update .gitignore**

Add to `.gitignore`:
```
# Docker
docker-compose.override.yml

# Test results (generated by container)
Tests/results/
```

**Step 4: Build and verify image builds**

Run: `docker compose build`
Expected: Successfully builds image

**Step 5: Commit**

```bash
git add Dockerfile docker-compose.yml .gitignore
git commit -m "feat: add Docker image and compose for test runner and validator"
```

---

### Task 9: Create pre-deploy validation script

**Files:**
- Create: `Scripts/Test-LabPreDeploy.ps1`

**Step 1: Write the validation script**

```powershell
# Test-LabPreDeploy.ps1 -- Pre-deploy validation checks
# Run inside Docker: docker compose run validate
# Exit 0 = all clear, Exit 1 = issues found

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = Split-Path -Parent $scriptDir

$checks = @()
$failed = 0

# Check 1: PowerShell syntax validation
Write-Host "`n[CHECK 1] PowerShell syntax validation..." -ForegroundColor Cyan
$syntaxErrors = @()
Get-ChildItem -Path $repoRoot -Filter '*.ps1' -Recurse |
    Where-Object { $_.FullName -notlike '*\.archive\*' } |
    ForEach-Object {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) {
            $syntaxErrors += [pscustomobject]@{
                File = $_.FullName.Replace($repoRoot, '.')
                Errors = $errors.Count
                First = $errors[0].Message
            }
        }
    }

if ($syntaxErrors.Count -eq 0) {
    Write-Host "  PASS: All .ps1 files parse without errors" -ForegroundColor Green
    $checks += [pscustomobject]@{ Name = 'Syntax'; Status = 'Pass'; Message = 'All files clean' }
} else {
    Write-Host "  FAIL: $($syntaxErrors.Count) file(s) have syntax errors:" -ForegroundColor Red
    foreach ($err in $syntaxErrors) {
        Write-Host "    $($err.File): $($err.First)" -ForegroundColor Yellow
    }
    $checks += [pscustomobject]@{ Name = 'Syntax'; Status = 'Fail'; Message = "$($syntaxErrors.Count) files with errors" }
    $failed++
}

# Check 2: Lab-Config.ps1 loads without error
Write-Host "`n[CHECK 2] Lab-Config.ps1 loading..." -ForegroundColor Cyan
$configPath = Join-Path $repoRoot 'Lab-Config.ps1'
try {
    . $configPath
    $requiredKeys = @('Lab', 'Network', 'Credentials', 'VMSizing')
    $missingKeys = $requiredKeys | Where-Object { -not $GlobalLabConfig.ContainsKey($_) }
    if ($missingKeys.Count -eq 0) {
        Write-Host "  PASS: GlobalLabConfig has all required sections" -ForegroundColor Green
        $checks += [pscustomobject]@{ Name = 'Config'; Status = 'Pass'; Message = 'Config valid' }
    } else {
        Write-Host "  FAIL: Missing config sections: $($missingKeys -join ', ')" -ForegroundColor Red
        $checks += [pscustomobject]@{ Name = 'Config'; Status = 'Fail'; Message = "Missing: $($missingKeys -join ', ')" }
        $failed++
    }
} catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $checks += [pscustomobject]@{ Name = 'Config'; Status = 'Fail'; Message = $_.Exception.Message }
    $failed++
}

# Check 3: Module manifest validity
Write-Host "`n[CHECK 3] Module manifest..." -ForegroundColor Cyan
$manifestPath = Join-Path $repoRoot 'SimpleLab.psd1'
try {
    $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
    Write-Host "  PASS: SimpleLab v$($manifest.Version) manifest valid" -ForegroundColor Green
    $checks += [pscustomobject]@{ Name = 'Manifest'; Status = 'Pass'; Message = "v$($manifest.Version)" }
} catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $checks += [pscustomobject]@{ Name = 'Manifest'; Status = 'Fail'; Message = $_.Exception.Message }
    $failed++
}

# Check 4: VM naming consistency
Write-Host "`n[CHECK 4] VM naming consistency..." -ForegroundColor Cyan
$deployPath = Join-Path $repoRoot 'Deploy.ps1'
$deployContent = Get-Content $deployPath -Raw
$deployVMNames = @()
[regex]::Matches($deployContent, "Add-LabMachineDefinition\s+-Name\s+'([^']+)'") | ForEach-Object {
    $deployVMNames += $_.Groups[1].Value
}
$configVMNames = @($GlobalLabConfig.Lab.CoreVMNames)
$missingInConfig = $deployVMNames | Where-Object { $_ -notin $configVMNames }
$missingInDeploy = $configVMNames | Where-Object { $_ -notin $deployVMNames }

if ($missingInConfig.Count -eq 0 -and $missingInDeploy.Count -eq 0) {
    Write-Host "  PASS: Deploy.ps1 VM names match CoreVMNames" -ForegroundColor Green
    $checks += [pscustomobject]@{ Name = 'VMNaming'; Status = 'Pass'; Message = 'Names consistent' }
} else {
    $msg = @()
    if ($missingInConfig.Count -gt 0) { $msg += "In Deploy but not config: $($missingInConfig -join ', ')" }
    if ($missingInDeploy.Count -gt 0) { $msg += "In config but not Deploy: $($missingInDeploy -join ', ')" }
    Write-Host "  WARN: $($msg -join '; ')" -ForegroundColor Yellow
    $checks += [pscustomobject]@{ Name = 'VMNaming'; Status = 'Warn'; Message = ($msg -join '; ') }
}

# Check 5: Default password detection
Write-Host "`n[CHECK 5] Default password check..." -ForegroundColor Cyan
if ($GlobalLabConfig.Credentials.AdminPassword -eq 'SimpleLab123!') {
    Write-Host "  WARN: AdminPassword is set to the default value" -ForegroundColor Yellow
    $checks += [pscustomobject]@{ Name = 'Password'; Status = 'Warn'; Message = 'Default password in use' }
} else {
    Write-Host "  PASS: AdminPassword is not the default" -ForegroundColor Green
    $checks += [pscustomobject]@{ Name = 'Password'; Status = 'Pass'; Message = 'Custom password set' }
}

# Summary
Write-Host "`n" + ("=" * 50) -ForegroundColor Gray
$passCount = ($checks | Where-Object Status -eq 'Pass').Count
$failCount = ($checks | Where-Object Status -eq 'Fail').Count
$warnCount = ($checks | Where-Object Status -eq 'Warn').Count
Write-Host "Results: $passCount passed, $failCount failed, $warnCount warnings" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Green' })

exit $failed
```

**Step 2: Test locally**

Run: `pwsh -NoProfile -File Scripts/Test-LabPreDeploy.ps1`
Expected: All checks pass or warn (no failures)

**Step 3: Test in Docker**

Run: `docker compose run validate`
Expected: Same results as local

**Step 4: Commit**

```bash
git add Scripts/Test-LabPreDeploy.ps1
git commit -m "feat: add pre-deploy validation script for Docker and CI"
```

---

### Task 10: Create GitHub Actions CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Step 1: Write the CI workflow**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  validate:
    name: Pre-deploy validation
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build Docker image
        run: docker compose build
      - name: Run validation
        run: docker compose run validate

  test:
    name: Pester tests
    needs: validate
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build Docker image
        run: docker compose build
      - name: Create results directory
        run: mkdir -p Tests/results
      - name: Run tests
        run: docker compose run test
      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-results
          path: Tests/results/testResults.xml
      - name: Publish test summary
        if: always()
        uses: dorny/test-reporter@v1
        with:
          name: Pester Results
          path: Tests/results/testResults.xml
          reporter: java-junit
```

**Step 2: Commit**

```bash
mkdir -p .github/workflows
git add .github/workflows/ci.yml
git commit -m "feat: add GitHub Actions CI pipeline with Docker-based test runner"
```

---

### Task 11: Run full test suite and push

**Step 1: Run full test suite locally**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path ./Tests -Output Detailed" 2>&1 | tail -5`
Expected: Tests Passed: 215, Failed: 0

**Step 2: Run Docker test suite**

Run: `docker compose run test`
Expected: Tests Passed: 215, Failed: 0

**Step 3: Push all changes**

```bash
git push
```

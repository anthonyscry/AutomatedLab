# Quick-Mode Auto-Heal Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Auto-repair healable infrastructure gaps (vSwitch, NAT, LabReady snapshot) before falling back from quick to full deploy mode, reducing full deploy frequency.

**Architecture:** New `Invoke-LabQuickModeHeal` helper sits between `Get-LabStateProbe` and `Resolve-LabModeDecision`. It receives the probe result, attempts targeted repairs for healable conditions, then re-probes so the mode decision uses fresh state. Unhealable conditions (missing VMs, unregistered lab) pass through unchanged.

**Tech Stack:** PowerShell 5.1+, Pester 5.x, existing SimpleLab module helpers

---

### Task 1: Add Lab-Config AutoHeal section

**Files:**
- Modify: `Lab-Config.ps1:164-167` (between Timeouts and RequiredISOs)

**Step 1: Write the failing test**

No test needed for config — this is a static hashtable. Verified by later tasks that consume the config.

**Step 2: Write minimal implementation**

In `Lab-Config.ps1`, add after the `Timeouts` block (line 164) and before `RequiredISOs` (line 166):

```powershell
    AutoHeal = @{
        # Changing Enabled toggles whether quick-mode auto-heal runs before fallback.
        Enabled = $true
        # Changing TimeoutSeconds caps total heal duration before aborting.
        TimeoutSeconds = 120
        # Changing HealthCheckTimeoutSeconds caps VM health verification for LabReady healing.
        HealthCheckTimeoutSeconds = 60
    }
```

**Step 3: Commit**

```bash
git add Lab-Config.ps1
git commit -m "feat: add AutoHeal config section to Lab-Config"
```

---

### Task 2: Create Invoke-LabQuickModeHeal with infra repair tests

**Files:**
- Create: `Private/Invoke-LabQuickModeHeal.ps1`
- Create: `Tests/QuickModeHeal.Tests.ps1`

**Step 1: Write the failing tests**

Create `Tests/QuickModeHeal.Tests.ps1`:

```powershell
# Invoke-LabQuickModeHeal tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Invoke-LabQuickModeHeal.ps1')
}

Describe 'Invoke-LabQuickModeHeal' {
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

    It 'returns no-op when probe is clean' {
        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $true
            SwitchPresent = $true
            NatPresent = $true
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24'

        $result.HealAttempted | Should -BeFalse
        $result.HealSucceeded | Should -BeFalse
        $result.RepairsApplied | Should -HaveCount 0
        $result.RemainingIssues | Should -HaveCount 0
    }

    It 'skips heal when lab not registered' {
        $probe = [pscustomobject]@{
            LabRegistered = $false
            MissingVMs = @()
            LabReadyAvailable = $false
            SwitchPresent = $false
            NatPresent = $false
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24'

        $result.HealAttempted | Should -BeFalse
    }

    It 'skips heal when VMs are missing' {
        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @('svr1')
            LabReadyAvailable = $true
            SwitchPresent = $true
            NatPresent = $true
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24'

        $result.HealAttempted | Should -BeFalse
    }

    It 'heals missing switch' {
        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $true
            SwitchPresent = $false
            NatPresent = $true
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24'

        $result.HealAttempted | Should -BeTrue
        $result.HealSucceeded | Should -BeTrue
        $result.RepairsApplied | Should -Contain 'switch_recreated'
        $script:switchCalled | Should -BeTrue
    }

    It 'heals missing NAT' {
        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $true
            SwitchPresent = $true
            NatPresent = $false
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24'

        $result.HealAttempted | Should -BeTrue
        $result.HealSucceeded | Should -BeTrue
        $result.RepairsApplied | Should -Contain 'nat_recreated'
        $script:natCalled | Should -BeTrue
    }

    It 'heals both switch and NAT in one pass' {
        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $true
            SwitchPresent = $false
            NatPresent = $false
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24'

        $result.HealAttempted | Should -BeTrue
        $result.HealSucceeded | Should -BeTrue
        $result.RepairsApplied | Should -HaveCount 2
        $result.RepairsApplied | Should -Contain 'switch_recreated'
        $result.RepairsApplied | Should -Contain 'nat_recreated'
    }

    It 'skips heal when disabled via config' {
        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $false
            SwitchPresent = $false
            NatPresent = $false
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24' -Enabled:$false

        $result.HealAttempted | Should -BeFalse
    }

    It 'reports remaining issues when switch repair throws' {
        function New-LabSwitch { throw 'Access denied' }

        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $true
            SwitchPresent = $false
            NatPresent = $true
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24'

        $result.HealAttempted | Should -BeTrue
        $result.HealSucceeded | Should -BeFalse
        $result.RemainingIssues | Should -Contain 'switch_repair_failed'
    }
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path .\Tests\QuickModeHeal.Tests.ps1 -Output Detailed`

Expected: FAIL because `Invoke-LabQuickModeHeal` does not exist.

**Step 3: Write minimal implementation**

Create `Private/Invoke-LabQuickModeHeal.ps1`:

```powershell
function Invoke-LabQuickModeHeal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$StateProbe,

        [Parameter(Mandatory)]
        [string]$SwitchName,

        [Parameter(Mandatory)]
        [string]$NatName,

        [Parameter(Mandatory)]
        [string]$AddressSpace,

        [string[]]$VMNames = @(),

        [int]$TimeoutSeconds = 120,

        [int]$HealthCheckTimeoutSeconds = 60,

        [bool]$Enabled = $true
    )

    $noOp = [pscustomobject]@{
        HealAttempted = $false
        HealSucceeded = $false
        RepairsApplied = @()
        RemainingIssues = @()
        DurationSeconds = 0
    }

    if (-not $Enabled) { return $noOp }

    $props = @($StateProbe.PSObject.Properties.Name)
    $labRegistered = if ($props -contains 'LabRegistered') { [bool]$StateProbe.LabRegistered } else { $false }
    $missingVMs = if ($props -contains 'MissingVMs') { @($StateProbe.MissingVMs) } else { @('unknown') }
    $labReadyAvailable = if ($props -contains 'LabReadyAvailable') { [bool]$StateProbe.LabReadyAvailable } else { $false }
    $switchPresent = if ($props -contains 'SwitchPresent') { [bool]$StateProbe.SwitchPresent } else { $false }
    $natPresent = if ($props -contains 'NatPresent') { [bool]$StateProbe.NatPresent } else { $false }

    if (-not $labRegistered) { return $noOp }
    if ($missingVMs.Count -gt 0) { return $noOp }

    $needsSwitch = -not $switchPresent
    $needsNat = -not $natPresent
    $needsLabReady = -not $labReadyAvailable

    if (-not $needsSwitch -and -not $needsNat -and -not $needsLabReady) { return $noOp }

    $healStart = Get-Date
    $repairs = [System.Collections.Generic.List[string]]::new()
    $remaining = [System.Collections.Generic.List[string]]::new()

    if ($needsSwitch) {
        try {
            New-LabSwitch -Name $SwitchName
            $repairs.Add('switch_recreated')
        }
        catch {
            $remaining.Add('switch_repair_failed')
        }
    }

    if ($needsNat) {
        try {
            New-LabNAT -Name $NatName -AddressSpace $AddressSpace
            $repairs.Add('nat_recreated')
        }
        catch {
            $remaining.Add('nat_repair_failed')
        }
    }

    if ($needsLabReady) {
        try {
            $healthy = $false
            if ($VMNames.Count -gt 0) {
                Start-LabVMs -VMNames $VMNames -ErrorAction SilentlyContinue
                $ready = Wait-LabVMReady -VMNames $VMNames -TimeoutSeconds $HealthCheckTimeoutSeconds -ErrorAction Stop
                if ($ready) {
                    $healthy = Test-LabDomainHealth -ErrorAction Stop
                }
            }

            if ($healthy) {
                Save-LabReadyCheckpoint
                $repairs.Add('labready_created')
            }
            else {
                $remaining.Add('labready_unhealable')
            }
        }
        catch {
            $remaining.Add('labready_unhealable')
        }
    }

    $duration = [int]((Get-Date) - $healStart).TotalSeconds

    return [pscustomobject]@{
        HealAttempted = $true
        HealSucceeded = ($remaining.Count -eq 0)
        RepairsApplied = @($repairs)
        RemainingIssues = @($remaining)
        DurationSeconds = $duration
    }
}
```

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path .\Tests\QuickModeHeal.Tests.ps1 -Output Detailed`

Expected: PASS for all 8 tests.

**Step 5: Commit**

```bash
git add Private/Invoke-LabQuickModeHeal.ps1 Tests/QuickModeHeal.Tests.ps1
git commit -m "feat: add Invoke-LabQuickModeHeal with infra repair tests"
```

---

### Task 3: Add LabReady snapshot healing tests

**Files:**
- Modify: `Tests/QuickModeHeal.Tests.ps1`

**Step 1: Write the failing tests**

Add to the existing `Describe 'Invoke-LabQuickModeHeal'` block in `Tests/QuickModeHeal.Tests.ps1`:

```powershell
    It 'heals missing LabReady when VMs are healthy' {
        $script:snapshotCalled = $false
        function Save-LabReadyCheckpoint { $script:snapshotCalled = $true }

        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $false
            SwitchPresent = $true
            NatPresent = $true
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24' -VMNames @('dc1', 'svr1', 'ws1')

        $result.HealAttempted | Should -BeTrue
        $result.HealSucceeded | Should -BeTrue
        $result.RepairsApplied | Should -Contain 'labready_created'
        $script:snapshotCalled | Should -BeTrue
    }

    It 'refuses LabReady when VM health check fails' {
        function Test-LabDomainHealth { return $false }

        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $false
            SwitchPresent = $true
            NatPresent = $true
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24' -VMNames @('dc1', 'svr1', 'ws1')

        $result.HealAttempted | Should -BeTrue
        $result.HealSucceeded | Should -BeFalse
        $result.RemainingIssues | Should -Contain 'labready_unhealable'
    }

    It 'skips LabReady heal when no VMNames provided' {
        $probe = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $false
            SwitchPresent = $true
            NatPresent = $true
        }

        $result = Invoke-LabQuickModeHeal -StateProbe $probe -SwitchName 'LabSwitch' -NatName 'LabNAT' -AddressSpace '10.0.10.0/24'

        $result.HealAttempted | Should -BeTrue
        $result.HealSucceeded | Should -BeFalse
        $result.RemainingIssues | Should -Contain 'labready_unhealable'
    }
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path .\Tests\QuickModeHeal.Tests.ps1 -Output Detailed`

Expected: FAIL for new LabReady tests (implementation may need adjustment for VMNames-empty case).

**Step 3: Adjust implementation if needed**

The `$VMNames.Count -gt 0` guard in `Invoke-LabQuickModeHeal` already handles the empty VMNames case by falling into `$healthy = $false`, which adds `labready_unhealable`. Verify this passes.

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path .\Tests\QuickModeHeal.Tests.ps1 -Output Detailed`

Expected: PASS for all 11 tests.

**Step 5: Commit**

```bash
git add Tests/QuickModeHeal.Tests.ps1
git commit -m "test: add LabReady snapshot healing coverage"
```

---

### Task 4: Add -AutoHeal parameter and wire heal into deploy flow

**Files:**
- Modify: `OpenCodeLab-App.ps1:45` (add parameter)
- Modify: `OpenCodeLab-App.ps1:1516-1518` (insert heal call before mode decision)

**Step 1: Write the failing test**

Add to `Tests/OpenCodeLabAppRouting.Tests.ps1` — find the `Invoke-AppNoExecute` helper and add `AutoHeal` parameter support, then add test:

In the `Invoke-AppNoExecute` parameter block, add:
```powershell
[switch]$AutoHeal
```

In the splat building section, add:
```powershell
if ($AutoHeal) { $invokeSplat.AutoHeal = $true }
```

Then add test case:
```powershell
It 'passes AutoHeal switch to app execution' {
    $state = [pscustomobject]@{
        LabRegistered = $true
        MissingVMs = @()
        LabReadyAvailable = $true
        SwitchPresent = $true
        NatPresent = $true
    }

    $result = Invoke-AppNoExecute -Action 'deploy' -Mode 'quick' -State $state -AutoHeal

    $result | Should -Not -BeNullOrEmpty
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path .\Tests\OpenCodeLabAppRouting.Tests.ps1 -Output Detailed`

Expected: FAIL because `-AutoHeal` is not a recognized parameter.

**Step 3: Write minimal implementation**

In `OpenCodeLab-App.ps1`:

1. Add `-AutoHeal` switch after line 45 (`[switch]$AutoFixSubnetConflict,`):
```powershell
    [switch]$AutoHeal,
```

2. After the state probe extraction (line 1516) and before the mode decision call (line 1518), insert the heal call:
```powershell
        $healResult = $null
        $autoHealEnabled = if ($null -ne $GlobalLabConfig -and $GlobalLabConfig.ContainsKey('AutoHeal')) {
            [bool]$GlobalLabConfig.AutoHeal.Enabled -and [bool]$AutoHeal
        } else { [bool]$AutoHeal }
        if ($autoHealEnabled -and $RequestedMode -eq 'quick') {
            $healSplat = @{
                StateProbe = $stateProbe
                SwitchName = $SwitchName
                NatName = $NatName
                AddressSpace = $AddressSpace
                VMNames = @(Get-ExpectedVMs)
            }
            if ($null -ne $GlobalLabConfig -and $GlobalLabConfig.ContainsKey('AutoHeal')) {
                if ($GlobalLabConfig.AutoHeal.ContainsKey('TimeoutSeconds')) {
                    $healSplat.TimeoutSeconds = $GlobalLabConfig.AutoHeal.TimeoutSeconds
                }
                if ($GlobalLabConfig.AutoHeal.ContainsKey('HealthCheckTimeoutSeconds')) {
                    $healSplat.HealthCheckTimeoutSeconds = $GlobalLabConfig.AutoHeal.HealthCheckTimeoutSeconds
                }
            }
            $healResult = Invoke-LabQuickModeHeal @healSplat

            if ($healResult.HealAttempted) {
                foreach ($repair in $healResult.RepairsApplied) {
                    Add-RunEvent -Step 'auto_heal' -Status 'ok' -Message "repaired: $repair"
                }
                foreach ($issue in $healResult.RemainingIssues) {
                    Add-RunEvent -Step 'auto_heal' -Status 'warn' -Message "unresolved: $issue"
                }

                if ($healResult.RepairsApplied.Count -gt 0) {
                    $stateProbe = Get-LabStateProbe -LabName $LabName -VMNames (Get-ExpectedVMs) -SwitchName $SwitchName -NatName $NatName
                }
            }
        }
```

3. In `Write-RunArtifacts`, add `auto_heal` to the report hashtable after `dry_run` (line 172):
```powershell
        auto_heal = if ($null -ne $healResult) { $healResult } else { $null }
```

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path .\Tests\OpenCodeLabAppRouting.Tests.ps1 -Output Detailed`

Expected: PASS.

**Step 5: Commit**

```bash
git add OpenCodeLab-App.ps1 Tests/OpenCodeLabAppRouting.Tests.ps1
git commit -m "feat: wire AutoHeal into deploy flow with re-probe"
```

---

### Task 5: Add console output for heal operations

**Files:**
- Modify: `OpenCodeLab-App.ps1` (add Write-Host output around heal calls)

**Step 1: Write the failing test**

No separate test — console output is verified by manual smoke check. The run event tests from Task 4 verify the data flow.

**Step 2: Write minimal implementation**

In `OpenCodeLab-App.ps1`, wrap the heal call section with console output. Replace the heal block's event logging with:

```powershell
            if ($healResult.HealAttempted) {
                foreach ($repair in $healResult.RepairsApplied) {
                    Write-Host "[AutoHeal] Repaired: $repair" -ForegroundColor Green
                    Add-RunEvent -Step 'auto_heal' -Status 'ok' -Message "repaired: $repair"
                }
                foreach ($issue in $healResult.RemainingIssues) {
                    Write-Host "[AutoHeal] Unresolved: $issue" -ForegroundColor Yellow
                    Add-RunEvent -Step 'auto_heal' -Status 'warn' -Message "unresolved: $issue"
                }

                if ($healResult.HealSucceeded) {
                    Write-Host "[AutoHeal] All issues healed. Continuing with quick mode." -ForegroundColor Green
                }
                else {
                    Write-Host "[AutoHeal] Some issues could not be healed. Falling back to full mode." -ForegroundColor Yellow
                }

                if ($healResult.RepairsApplied.Count -gt 0) {
                    $stateProbe = Get-LabStateProbe -LabName $LabName -VMNames (Get-ExpectedVMs) -SwitchName $SwitchName -NatName $NatName
                }
            }
```

**Step 3: Run tests to verify nothing broke**

Run: `Invoke-Pester -Path .\Tests\OpenCodeLabAppRouting.Tests.ps1 -Output Detailed`

Expected: PASS.

**Step 4: Commit**

```bash
git add OpenCodeLab-App.ps1
git commit -m "feat: add console output for auto-heal operations"
```

---

### Task 6: Add mode decision integration test for healed state

**Files:**
- Modify: `Tests/ModeDecision.Tests.ps1`

**Step 1: Write the failing test**

Add to the existing `Describe 'Resolve-LabModeDecision'` block:

```powershell
    It 'quick deploy stays quick after healed infra drift' {
        # Simulates state after auto-heal repaired switch and NAT
        $healedState = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $true
            SwitchPresent = $true
            NatPresent = $true
        }

        $result = Resolve-LabModeDecision -Operation deploy -RequestedMode quick -State $healedState

        $result.EffectiveMode | Should -Be 'quick'
        $result.FallbackReason | Should -BeNullOrEmpty
    }

    It 'quick deploy falls back after failed heal leaves missing LabReady' {
        # Simulates state after auto-heal repaired switch but LabReady is still missing
        $partialHealState = [pscustomobject]@{
            LabRegistered = $true
            MissingVMs = @()
            LabReadyAvailable = $false
            SwitchPresent = $true
            NatPresent = $true
        }

        $result = Resolve-LabModeDecision -Operation deploy -RequestedMode quick -State $partialHealState

        $result.EffectiveMode | Should -Be 'full'
        $result.FallbackReason | Should -Be 'missing_labready'
    }
```

**Step 2: Run test to verify it passes**

Run: `Invoke-Pester -Path .\Tests\ModeDecision.Tests.ps1 -Output Detailed`

Expected: PASS (these test existing logic with post-heal scenarios — they should pass immediately since `Resolve-LabModeDecision` already handles these states).

**Step 3: Commit**

```bash
git add Tests/ModeDecision.Tests.ps1
git commit -m "test: add mode decision integration tests for healed state"
```

---

### Task 7: Run full verification

**Files:**
- Read-only verification

**Step 1: Run focused QuickModeHeal tests**

Run: `Invoke-Pester -Path .\Tests\QuickModeHeal.Tests.ps1 -Output Detailed`

Expected: All 11 tests PASS.

**Step 2: Run ModeDecision tests**

Run: `Invoke-Pester -Path .\Tests\ModeDecision.Tests.ps1 -Output Detailed`

Expected: All tests PASS (existing + 2 new).

**Step 3: Run app routing tests**

Run: `Invoke-Pester -Path .\Tests\OpenCodeLabAppRouting.Tests.ps1 -Output Detailed`

Expected: All tests PASS (existing + 1 new).

**Step 4: Run full test suite**

Run: `Invoke-Pester -Path .\Tests\ -Output Detailed`

Expected: All tests PASS, 0 failures.

**Step 5: Commit (if any fixups needed)**

```bash
git add -A
git commit -m "fix: address verification issues from auto-heal integration"
```

---

Execution handoff summary: 7 tasks, TDD flow throughout. Tasks 1-3 build the core helper with tests. Task 4 wires it into the app. Task 5 adds console UX. Task 6 validates mode decision integration. Task 7 runs full verification.

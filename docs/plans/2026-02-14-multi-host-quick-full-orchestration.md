# Multi-Host Safety-First Quick/Full Orchestration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a coordinator-driven multi-host orchestration flow for `deploy` and `teardown` that keeps safety guarantees strict while supporting 2-5 remote hosts via PowerShell Remoting.

**Architecture:** Build a coordinator pipeline (`intent -> inventory -> fleet probe -> policy -> plan -> dispatch`) and route app entrypoints through it. Keep quick/full as policy outcomes over one lifecycle model and enforce fail-closed destructive controls with scoped confirmation tokens. Preserve thin CLI/GUI layers and strengthen run artifacts for auditability.

**Tech Stack:** PowerShell 5.1+, Hyper-V cmdlets, PowerShell Remoting (WinRM), Pester, existing module helper pattern in `Private/`.

---

### Task 1: Add operation intent + host inventory contracts

**Files:**
- Create: `Private/Get-LabHostInventory.ps1`
- Create: `Private/Resolve-LabOperationIntent.ps1`
- Test: `Tests/HostInventory.Tests.ps1`
- Test: `Tests/OperationIntent.Tests.ps1`

**Step 1: Write the failing test**

```powershell
Describe 'Get-LabHostInventory' {
    It 'returns default local host when inventory is not provided' {
        $result = Get-LabHostInventory
        $result.Source | Should -Be 'default-local'
        $result.Hosts.Count | Should -Be 1
        $result.Hosts[0].Name | Should -Be $env:COMPUTERNAME
    }
}

Describe 'Resolve-LabOperationIntent' {
    It 'normalizes action mode and host targets' {
        $intent = Resolve-LabOperationIntent -Action deploy -Mode quick -TargetHosts @('HV-01')
        $intent.Action | Should -Be 'deploy'
        $intent.RequestedMode | Should -Be 'quick'
        $intent.TargetHosts | Should -Be @('HV-01')
    }
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path .\Tests\HostInventory.Tests.ps1, .\Tests\OperationIntent.Tests.ps1 -Output Detailed`
Expected: FAIL because functions do not exist yet.

**Step 3: Write minimal implementation**

```powershell
function Get-LabHostInventory {
    [CmdletBinding()]
    param(
        [string]$InventoryPath,
        [string[]]$TargetHosts = @()
    )

    if (-not [string]::IsNullOrWhiteSpace($InventoryPath)) {
        $raw = Get-Content -LiteralPath $InventoryPath -Raw -ErrorAction Stop
        $inventory = $raw | ConvertFrom-Json -ErrorAction Stop
        $hosts = @($inventory.hosts)
        if ($TargetHosts.Count -gt 0) {
            $hosts = @($hosts | Where-Object { $_.name -in $TargetHosts })
        }

        return [pscustomobject]@{
            Source = 'file'
            Hosts = @($hosts | ForEach-Object {
                [pscustomobject]@{ Name = [string]$_.name; Role = [string]$_.role; Connection = [string]$_.connection }
            })
        }
    }

    return [pscustomobject]@{
        Source = 'default-local'
        Hosts = @([pscustomobject]@{ Name = $env:COMPUTERNAME; Role = 'primary'; Connection = 'local' })
    }
}
```

```powershell
function Resolve-LabOperationIntent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Action,
        [ValidateSet('quick','full')][string]$Mode = 'full',
        [string[]]$TargetHosts = @(),
        [string]$InventoryPath
    )

    $inventory = Get-LabHostInventory -InventoryPath $InventoryPath -TargetHosts $TargetHosts
    [pscustomobject]@{
        Action = $Action.Trim().ToLowerInvariant()
        RequestedMode = $Mode
        TargetHosts = @($inventory.Hosts | ForEach-Object { $_.Name })
        InventorySource = $inventory.Source
    }
}
```

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path .\Tests\HostInventory.Tests.ps1, .\Tests\OperationIntent.Tests.ps1 -Output Detailed`
Expected: PASS.

**Step 5: Commit**

```bash
git add Private/Get-LabHostInventory.ps1 Private/Resolve-LabOperationIntent.ps1 Tests/HostInventory.Tests.ps1 Tests/OperationIntent.Tests.ps1
git commit -m "feat: add host inventory and operation intent contracts"
```

### Task 2: Add multi-host probe adapter and fleet probe helper

**Files:**
- Create: `Private/Invoke-LabRemoteProbe.ps1`
- Create: `Private/Get-LabFleetStateProbe.ps1`
- Test: `Tests/FleetStateProbe.Tests.ps1`

**Step 1: Write the failing test**

```powershell
Describe 'Get-LabFleetStateProbe' {
    It 'returns one result per host with structured reachability' {
        Mock Invoke-LabRemoteProbe {
            [pscustomobject]@{ LabRegistered = $true; MissingVMs = @(); LabReadyAvailable = $true; SwitchPresent = $true; NatPresent = $true }
        }

        $result = Get-LabFleetStateProbe -HostNames @('HV-01', 'HV-02') -LabName 'AutomatedLab' -VMNames @('dc1', 'svr1', 'ws1')
        $result.Count | Should -Be 2
        $result[0].HostName | Should -Be 'HV-01'
        $result[0].Reachable | Should -BeTrue
    }
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path .\Tests\FleetStateProbe.Tests.ps1 -Output Detailed`
Expected: FAIL because probe helpers do not exist yet.

**Step 3: Write minimal implementation**

```powershell
function Invoke-LabRemoteProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )

    if ($HostName -eq $env:COMPUTERNAME -or $HostName -eq 'localhost') {
        return & $ScriptBlock
    }

    return Invoke-Command -ComputerName $HostName -ScriptBlock $ScriptBlock -ErrorAction Stop
}
```

```powershell
function Get-LabFleetStateProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$HostNames,
        [Parameter(Mandatory)][string]$LabName,
        [Parameter(Mandatory)][string[]]$VMNames,
        [string]$SwitchName = 'AutomatedLab',
        [string]$NatName = 'AutomatedLabNAT'
    )

    $fleet = New-Object System.Collections.Generic.List[object]

    foreach ($host in $HostNames) {
        try {
            $probe = Invoke-LabRemoteProbe -HostName $host -ScriptBlock {
                Get-LabStateProbe -LabName $using:LabName -VMNames $using:VMNames -SwitchName $using:SwitchName -NatName $using:NatName
            }

            $fleet.Add([pscustomobject]@{ HostName = $host; Reachable = $true; Probe = $probe; Failure = $null }) | Out-Null
        }
        catch {
            $fleet.Add([pscustomobject]@{ HostName = $host; Reachable = $false; Probe = $null; Failure = $_.Exception.Message }) | Out-Null
        }
    }

    return $fleet.ToArray()
}
```

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path .\Tests\FleetStateProbe.Tests.ps1 -Output Detailed`
Expected: PASS.

**Step 5: Commit**

```bash
git add Private/Invoke-LabRemoteProbe.ps1 Private/Get-LabFleetStateProbe.ps1 Tests/FleetStateProbe.Tests.ps1
git commit -m "feat: add fleet state probe over powershell remoting"
```

### Task 3: Add coordinator policy engine (fail-closed + escalation-required)

**Files:**
- Create: `Private/Resolve-LabCoordinatorPolicy.ps1`
- Test: `Tests/CoordinatorPolicy.Tests.ps1`

**Step 1: Write the failing test**

```powershell
Describe 'Resolve-LabCoordinatorPolicy' {
    It 'fails closed when any host probe is unreachable' {
        $intent = [pscustomobject]@{ Action = 'teardown'; RequestedMode = 'full'; TargetHosts = @('HV-01') }
        $fleet = @([pscustomobject]@{ HostName = 'HV-01'; Reachable = $false; Probe = $null; Failure = 'timeout' })

        $result = Resolve-LabCoordinatorPolicy -Intent $intent -FleetProbe $fleet
        $result.Allowed | Should -BeFalse
        $result.Outcome | Should -Be 'PolicyBlocked'
        $result.Reason | Should -Be 'probe_uncertain'
    }

    It 'returns escalation required for quick teardown when full is required' {
        $intent = [pscustomobject]@{ Action = 'teardown'; RequestedMode = 'quick'; TargetHosts = @('HV-01') }
        $fleet = @([pscustomobject]@{ HostName = 'HV-01'; Reachable = $true; Probe = [pscustomobject]@{ LabReadyAvailable = $false } })

        $result = Resolve-LabCoordinatorPolicy -Intent $intent -FleetProbe $fleet
        $result.Allowed | Should -BeFalse
        $result.Outcome | Should -Be 'EscalationRequired'
    }
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path .\Tests\CoordinatorPolicy.Tests.ps1 -Output Detailed`
Expected: FAIL.

**Step 3: Write minimal implementation**

```powershell
function Resolve-LabCoordinatorPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Intent,
        [Parameter(Mandatory)][object[]]$FleetProbe,
        [switch]$HasScopedConfirmation
    )

    if (@($FleetProbe | Where-Object { -not $_.Reachable }).Count -gt 0) {
        return [pscustomobject]@{ Allowed = $false; Outcome = 'PolicyBlocked'; Reason = 'probe_uncertain'; EffectiveMode = $Intent.RequestedMode }
    }

    if ($Intent.Action -eq 'teardown' -and $Intent.RequestedMode -eq 'quick') {
        $missingLabReady = @($FleetProbe | Where-Object { -not $_.Probe.LabReadyAvailable }).Count -gt 0
        if ($missingLabReady) {
            return [pscustomobject]@{ Allowed = $false; Outcome = 'EscalationRequired'; Reason = 'quick_teardown_requires_full'; EffectiveMode = 'full' }
        }
    }

    if ($Intent.Action -eq 'teardown' -and $Intent.RequestedMode -eq 'full' -and -not $HasScopedConfirmation) {
        return [pscustomobject]@{ Allowed = $false; Outcome = 'PolicyBlocked'; Reason = 'missing_confirmation_token'; EffectiveMode = 'full' }
    }

    return [pscustomobject]@{ Allowed = $true; Outcome = 'Approved'; Reason = 'ok'; EffectiveMode = $Intent.RequestedMode }
}
```

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path .\Tests\CoordinatorPolicy.Tests.ps1 -Output Detailed`
Expected: PASS.

**Step 5: Commit**

```bash
git add Private/Resolve-LabCoordinatorPolicy.ps1 Tests/CoordinatorPolicy.Tests.ps1
git commit -m "feat: enforce fail-closed coordinator policy outcomes"
```

### Task 4: Add scoped destructive confirmation token helpers

**Files:**
- Create: `Private/New-LabScopedConfirmationToken.ps1`
- Create: `Private/Test-LabScopedConfirmationToken.ps1`
- Test: `Tests/ScopedConfirmationToken.Tests.ps1`

**Step 1: Write the failing test**

```powershell
Describe 'Scoped confirmation token' {
    It 'validates token only for matching run, hosts, and operation hash' {
        $token = New-LabScopedConfirmationToken -RunId 'run-1' -TargetHosts @('HV-01') -OperationHash 'abc' -Secret 'test-secret'
        (Test-LabScopedConfirmationToken -Token $token -RunId 'run-1' -TargetHosts @('HV-01') -OperationHash 'abc' -Secret 'test-secret').Valid | Should -BeTrue
        (Test-LabScopedConfirmationToken -Token $token -RunId 'run-2' -TargetHosts @('HV-01') -OperationHash 'abc' -Secret 'test-secret').Valid | Should -BeFalse
    }
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path .\Tests\ScopedConfirmationToken.Tests.ps1 -Output Detailed`
Expected: FAIL.

**Step 3: Write minimal implementation**

```powershell
function New-LabScopedConfirmationToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string[]]$TargetHosts,
        [Parameter(Mandatory)][string]$OperationHash,
        [Parameter(Mandatory)][string]$Secret,
        [int]$TtlMinutes = 10
    )

    $payload = [ordered]@{
        run_id = $RunId
        target_hosts = @($TargetHosts | Sort-Object)
        operation_hash = $OperationHash
        expires_utc = (Get-Date).ToUniversalTime().AddMinutes($TtlMinutes).ToString('o')
    } | ConvertTo-Json -Compress

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $key = [System.Text.Encoding]::UTF8.GetBytes($Secret)
    $hmac = New-Object System.Security.Cryptography.HMACSHA256($key)
    $sig = [Convert]::ToBase64String($hmac.ComputeHash($bytes))

    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payload)) + '.' + $sig
}
```

```powershell
function Test-LabScopedConfirmationToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string[]]$TargetHosts,
        [Parameter(Mandatory)][string]$OperationHash,
        [Parameter(Mandatory)][string]$Secret
    )

    # Parse + verify signature + expiry + scope.
    # Return [pscustomobject]@{ Valid = $true/$false; Reason = '...' }
}
```

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path .\Tests\ScopedConfirmationToken.Tests.ps1 -Output Detailed`
Expected: PASS.

**Step 5: Commit**

```bash
git add Private/New-LabScopedConfirmationToken.ps1 Private/Test-LabScopedConfirmationToken.ps1 Tests/ScopedConfirmationToken.Tests.ps1
git commit -m "feat: add run-scoped destructive confirmation token validation"
```

### Task 5: Build coordinator execution plan + dispatcher shell

**Files:**
- Create: `Private/New-LabCoordinatorPlan.ps1`
- Create: `Private/Invoke-LabCoordinatorPlan.ps1`
- Test: `Tests/CoordinatorPlan.Tests.ps1`

**Step 1: Write the failing test**

```powershell
Describe 'New-LabCoordinatorPlan' {
    It 'adds destructive barrier for full teardown' {
        $intent = [pscustomobject]@{ Action = 'teardown'; RequestedMode = 'full'; TargetHosts = @('HV-01') }
        $plan = New-LabCoordinatorPlan -Intent $intent
        ($plan.Steps.Id -contains 'destructive-barrier') | Should -BeTrue
        ($plan.Steps.Id -contains 'execute-destructive') | Should -BeTrue
    }
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path .\Tests\CoordinatorPlan.Tests.ps1 -Output Detailed`
Expected: FAIL.

**Step 3: Write minimal implementation**

```powershell
function New-LabCoordinatorPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject]$Intent)

    $steps = @(
        [pscustomobject]@{ Id = 'preflight-probe'; DependsOn = @(); Kind = 'preflight' },
        [pscustomobject]@{ Id = 'policy-check'; DependsOn = @('preflight-probe'); Kind = 'barrier' },
        [pscustomobject]@{ Id = 'execute-nondestructive'; DependsOn = @('policy-check'); Kind = 'execute' }
    )

    if ($Intent.Action -eq 'teardown' -and $Intent.RequestedMode -eq 'full') {
        $steps += [pscustomobject]@{ Id = 'destructive-barrier'; DependsOn = @('execute-nondestructive'); Kind = 'barrier' }
        $steps += [pscustomobject]@{ Id = 'execute-destructive'; DependsOn = @('destructive-barrier'); Kind = 'execute' }
    }

    [pscustomobject]@{ Steps = $steps }
}
```

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path .\Tests\CoordinatorPlan.Tests.ps1 -Output Detailed`
Expected: PASS.

**Step 5: Commit**

```bash
git add Private/New-LabCoordinatorPlan.ps1 Private/Invoke-LabCoordinatorPlan.ps1 Tests/CoordinatorPlan.Tests.ps1
git commit -m "feat: add coordinator execution plan with destructive barriers"
```

### Task 6: Integrate coordinator pipeline into app routing

**Files:**
- Modify: `OpenCodeLab-App.ps1`
- Modify: `Private/Resolve-LabDispatchPlan.ps1`
- Modify: `Private/Resolve-LabExecutionProfile.ps1`
- Test: `Tests/OpenCodeLabAppRouting.Tests.ps1`
- Test: `Tests/CoordinatorIntegration.Tests.ps1`

**Step 1: Write the failing test**

```powershell
Describe 'OpenCodeLab-App coordinator integration' {
    It 'returns escalation required rather than silent full destructive fallback' {
        $state = [pscustomobject]@{ HostName = 'HV-01'; Reachable = $true; Probe = [pscustomobject]@{ LabReadyAvailable = $false } }
        $result = & .\OpenCodeLab-App.ps1 -Action teardown -Mode quick -NoExecute -NoExecuteStateJson ($state | ConvertTo-Json -Depth 10 -Compress)
        $result.PolicyOutcome | Should -Be 'EscalationRequired'
    }
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path .\Tests\OpenCodeLabAppRouting.Tests.ps1, .\Tests\CoordinatorIntegration.Tests.ps1 -Output Detailed`
Expected: FAIL.

**Step 3: Write minimal implementation**

```powershell
# OpenCodeLab-App.ps1 additions
param(
    [string[]]$TargetHosts,
    [string]$InventoryPath,
    [string]$ConfirmationToken
)

# 1) Resolve intent
$intent = Resolve-LabOperationIntent -Action $Action -Mode $Mode -TargetHosts $TargetHosts -InventoryPath $InventoryPath

# 2) Probe fleet
$fleet = Get-LabFleetStateProbe -HostNames $intent.TargetHosts -LabName $LabName -VMNames (Get-ExpectedVMs) -SwitchName $SwitchName -NatName $NatName

# 3) Policy
$policy = Resolve-LabCoordinatorPolicy -Intent $intent -FleetProbe $fleet -HasScopedConfirmation:([string]::IsNullOrWhiteSpace($ConfirmationToken) -eq $false)

# 4) Route only if approved
if (-not $policy.Allowed) {
    Add-RunEvent -Step 'policy' -Status 'blocked' -Message $policy.Reason
    if ($NoExecute) {
        return [pscustomobject]@{ PolicyOutcome = $policy.Outcome; PolicyReason = $policy.Reason; EffectiveMode = $policy.EffectiveMode }
    }
    throw "Policy blocked execution: $($policy.Reason)"
}
```

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path .\Tests\OpenCodeLabAppRouting.Tests.ps1, .\Tests\CoordinatorIntegration.Tests.ps1 -Output Detailed`
Expected: PASS.

**Step 5: Commit**

```bash
git add OpenCodeLab-App.ps1 Private/Resolve-LabDispatchPlan.ps1 Private/Resolve-LabExecutionProfile.ps1 Tests/OpenCodeLabAppRouting.Tests.ps1 Tests/CoordinatorIntegration.Tests.ps1
git commit -m "feat: integrate coordinator policy pipeline into app routing"
```

### Task 7: Integrate GUI inputs for multi-host and destructive authorization

**Files:**
- Modify: `OpenCodeLab-GUI.ps1`
- Modify: `Private/New-LabAppArgumentList.ps1`
- Modify: `Private/Get-LabGuiDestructiveGuard.ps1`
- Modify: `Private/Get-LabRunArtifactSummary.ps1`
- Test: `Tests/OpenCodeLabGuiHelpers.Tests.ps1`

**Step 1: Write the failing test**

```powershell
Describe 'GUI argument list' {
    It 'includes TargetHosts and ConfirmationToken when provided' {
        $args = New-LabAppArgumentList -Options @{ Action = 'teardown'; Mode = 'full'; TargetHosts = 'HV-01,HV-02'; ConfirmationToken = 'abc' }
        $args | Should -Contain '-TargetHosts'
        $args | Should -Contain 'HV-01,HV-02'
        $args | Should -Contain '-ConfirmationToken'
    }
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path .\Tests\OpenCodeLabGuiHelpers.Tests.ps1 -Output Detailed`
Expected: FAIL.

**Step 3: Write minimal implementation**

```powershell
# OpenCodeLab-GUI.ps1
# Add text fields for TargetHosts and ConfirmationToken
# Include both values in options hashtable when non-empty

# Private/New-LabAppArgumentList.ps1
if ($safeOptions.ContainsKey('TargetHosts') -and -not [string]::IsNullOrWhiteSpace([string]$safeOptions.TargetHosts)) {
    $argumentList.Add('-TargetHosts') | Out-Null
    $argumentList.Add([string]$safeOptions.TargetHosts) | Out-Null
}
if ($safeOptions.ContainsKey('ConfirmationToken') -and -not [string]::IsNullOrWhiteSpace([string]$safeOptions.ConfirmationToken)) {
    $argumentList.Add('-ConfirmationToken') | Out-Null
    $argumentList.Add([string]$safeOptions.ConfirmationToken) | Out-Null
}
```

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path .\Tests\OpenCodeLabGuiHelpers.Tests.ps1 -Output Detailed`
Expected: PASS.

**Step 5: Commit**

```bash
git add OpenCodeLab-GUI.ps1 Private/New-LabAppArgumentList.ps1 Private/Get-LabGuiDestructiveGuard.ps1 Private/Get-LabRunArtifactSummary.ps1 Tests/OpenCodeLabGuiHelpers.Tests.ps1
git commit -m "feat: add gui support for multi-host targets and scoped confirmation"
```

### Task 8: Add artifacts, docs, and full verification gates

**Files:**
- Modify: `README.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/REPOSITORY-STRUCTURE.md`
- Modify: `CHANGELOG.md`
- Modify: `OpenCodeLab-App.ps1`

**Step 1: Write the failing test (artifact shape)**

```powershell
Describe 'Run artifacts include coordinator fields' {
    It 'writes policy and host outcome metadata' {
        # Validate artifact includes policy_outcome, policy_reason, host_outcomes, blast_radius
    }
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path .\Tests\OpenCodeLabAppRouting.Tests.ps1 -Output Detailed`
Expected: FAIL on missing artifact fields.

**Step 3: Write minimal implementation + docs**

```powershell
# OpenCodeLab-App.ps1 artifact payload additions
policy_outcome = $policy.Outcome
policy_reason = $policy.Reason
host_outcomes = $fleet
blast_radius = @($intent.TargetHosts)
```

Update docs with operator guidance for:
- `-TargetHosts`
- `-InventoryPath`
- `-ConfirmationToken`
- `EscalationRequired` behavior
- safety-first fail-closed policy outcomes

**Step 4: Run full verification**

Run: `Invoke-Pester -Path .\Tests\ -Output Detailed`
Expected: PASS.

Run: `Select-String -Path .\OpenCodeLab-App.ps1, .\OpenCodeLab-GUI.ps1 -Pattern "TargetHosts|InventoryPath|ConfirmationToken|policy_outcome|host_outcomes|blast_radius|EscalationRequired"`
Expected: Matches for each required integration field/keyword.

**Step 5: Commit**

```bash
git add OpenCodeLab-App.ps1 README.md docs/ARCHITECTURE.md docs/REPOSITORY-STRUCTURE.md CHANGELOG.md
git commit -m "docs: publish multi-host safety-first orchestration behavior"
```

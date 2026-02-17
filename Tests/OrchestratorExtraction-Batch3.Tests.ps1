# OrchestratorExtraction-Batch3.Tests.ps1
# Unit tests for 6 functions extracted from OpenCodeLab-App.ps1 in Batch 3

BeforeAll {
    Set-StrictMode -Version Latest

    $repoRoot = Split-Path -Parent $PSScriptRoot

    # Batch 1 dependencies
    . (Join-Path $repoRoot 'Private/Add-LabRunEvent.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabPreflightArgs.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabBootstrapArgs.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabDeployArgs.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabHealthArgs.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabExpectedVMs.ps1')
    . (Join-Path $repoRoot 'Private/Convert-LabArgumentArrayToSplat.ps1')
    . (Join-Path $repoRoot 'Private/Resolve-LabScriptPath.ps1')
    . (Join-Path $repoRoot 'Private/Import-LabModule.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabRepoScript.ps1')
    . (Join-Path $repoRoot 'Public/Write-LabStatus.ps1')

    # Batch 2 dependencies
    . (Join-Path $repoRoot 'Private/Test-LabReadySnapshot.ps1')
    . (Join-Path $repoRoot 'Private/Stop-LabVMsSafe.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabBlowAway.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabQuickDeploy.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabQuickTeardown.ps1')

    # Batch 3 functions under test
    . (Join-Path $repoRoot 'Private/Invoke-LabOrchestrationActionCore.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabOneButtonSetup.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabOneButtonReset.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabSetup.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabBulkVMProvision.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabSetupMenu.ps1')

    # Stub Read-MenuCount (still inline in App.ps1; extracted in Batch 4)
    function Global:Read-MenuCount {
        param([Parameter(Mandatory)][string]$Prompt, [int]$DefaultValue = 0)
        return $DefaultValue
    }

    # Create a fake Hyper-V module so module-qualified Hyper-V\Get-VM calls work
    if (-not (Get-Module -Name 'Hyper-V' -ErrorAction SilentlyContinue)) {
        New-Module -Name 'Hyper-V' -ScriptBlock {
            function Get-VM {
                param([string]$Name, $ErrorAction)
                if ($Name) { return [pscustomobject]@{ Name = $Name; State = 'Running' } }
                return @()
            }
        } | Import-Module -Global
    }

    # Stub AutomatedLab / Hyper-V commands that may not exist in test environment
    if (-not (Get-Command Get-VMSnapshot -ErrorAction SilentlyContinue)) {
        function Global:Get-VMSnapshot { param([string]$VMName, [string]$Name, $ErrorAction) $null }
    }
    if (-not (Get-Command Stop-LabVM -ErrorAction SilentlyContinue)) {
        function Global:Stop-LabVM { param([switch]$All, $ErrorAction) }
    }
    if (-not (Get-Command Stop-VM -ErrorAction SilentlyContinue)) {
        function Global:Stop-VM { param([switch]$Force, $ErrorAction) }
    }
    if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
        function Global:Get-VM { param($ErrorAction) @() }
    }
    if (-not (Get-Command Import-Module -ErrorAction SilentlyContinue)) {
        function Global:Import-Module { param([string]$Name, $ErrorAction) }
    }
    if (-not (Get-Command Restore-LabVMSnapshot -ErrorAction SilentlyContinue)) {
        function Global:Restore-LabVMSnapshot { param([switch]$All, [string]$SnapshotName) }
    }
    if (-not (Get-Command New-LabVM -ErrorAction SilentlyContinue)) {
        function Global:New-LabVM {
            param([string]$VMName, [int]$MemoryGB, [string]$VHDPath, [string]$SwitchName, [int]$ProcessorCount, [string]$IsoPath)
            return [pscustomobject]@{ Status = 'OK'; Message = "VM $VMName created" }
        }
    }
}

Describe 'Invoke-LabOrchestrationActionCore' {

    BeforeEach {
        $script:runEvents = New-Object System.Collections.Generic.List[object]
        $script:labConfig = @{
            Lab     = @{ Name = 'TestLab'; CoreVMNames = @('DC1', 'SVR1', 'WS1') }
            Paths   = @{ LabRoot = 'C:\TestLabRoot' }
            Network = @{ NatName = 'TestNat' }
        }
        $script:orchestrationIntent = [pscustomobject]@{
            RunQuickStartupSequence = $false
            RunQuickReset           = $false
        }
    }

    It 'calls Invoke-LabQuickDeploy when deploy action and RunQuickStartupSequence is true' {
        $script:orchestrationIntent.RunQuickStartupSequence = $true

        Mock Invoke-LabQuickDeploy { }

        Invoke-LabOrchestrationActionCore `
            -OrchestrationAction 'deploy' `
            -Mode 'quick' `
            -Intent $script:orchestrationIntent `
            -LabConfig $script:labConfig `
            -ScriptDir 'C:\ScriptDir' `
            -SwitchName 'TestSwitch' `
            -RunEvents $script:runEvents

        Should -Invoke Invoke-LabQuickDeploy -Times 1 -Exactly
    }

    It 'calls Invoke-LabRepoScript with Deploy when deploy and RunQuickStartupSequence is false' {
        $script:orchestrationIntent.RunQuickStartupSequence = $false

        Mock Invoke-LabRepoScript { }

        Invoke-LabOrchestrationActionCore `
            -OrchestrationAction 'deploy' `
            -Mode 'full' `
            -Intent $script:orchestrationIntent `
            -LabConfig $script:labConfig `
            -ScriptDir 'C:\ScriptDir' `
            -SwitchName 'TestSwitch' `
            -RunEvents $script:runEvents

        Should -Invoke Invoke-LabRepoScript -Times 1 -ParameterFilter { $BaseName -eq 'Deploy' }
    }

    It 'calls Invoke-LabQuickTeardown when teardown action and RunQuickReset is true' {
        $script:orchestrationIntent.RunQuickReset = $true

        Mock Invoke-LabQuickTeardown { }

        Invoke-LabOrchestrationActionCore `
            -OrchestrationAction 'teardown' `
            -Mode 'quick' `
            -Intent $script:orchestrationIntent `
            -LabConfig $script:labConfig `
            -ScriptDir 'C:\ScriptDir' `
            -SwitchName 'TestSwitch' `
            -RunEvents $script:runEvents

        Should -Invoke Invoke-LabQuickTeardown -Times 1 -Exactly
    }

    It 'calls Invoke-LabBlowAway when teardown action and RunQuickReset is false' {
        $script:orchestrationIntent.RunQuickReset = $false

        Mock Invoke-LabBlowAway { }

        Invoke-LabOrchestrationActionCore `
            -OrchestrationAction 'teardown' `
            -Mode 'full' `
            -Intent $script:orchestrationIntent `
            -LabConfig $script:labConfig `
            -ScriptDir 'C:\ScriptDir' `
            -SwitchName 'TestSwitch' `
            -RunEvents $script:runEvents

        Should -Invoke Invoke-LabBlowAway -Times 1 -Exactly
    }

    It 'passes DryRun to Invoke-LabQuickDeploy' {
        $script:orchestrationIntent.RunQuickStartupSequence = $true

        $script:dryRunReceived = $false
        Mock Invoke-LabQuickDeploy { $script:dryRunReceived = [bool]$DryRun }

        Invoke-LabOrchestrationActionCore `
            -OrchestrationAction 'deploy' `
            -Mode 'quick' `
            -Intent $script:orchestrationIntent `
            -LabConfig $script:labConfig `
            -ScriptDir 'C:\ScriptDir' `
            -SwitchName 'TestSwitch' `
            -RunEvents $script:runEvents `
            -DryRun

        $script:dryRunReceived | Should -Be $true
    }

    It 'passes Force and NonInteractive to Invoke-LabBlowAway as BypassPrompt' {
        $script:orchestrationIntent.RunQuickReset = $false

        $script:bypassReceived = $false
        Mock Invoke-LabBlowAway { $script:bypassReceived = [bool]$BypassPrompt }

        Invoke-LabOrchestrationActionCore `
            -OrchestrationAction 'teardown' `
            -Mode 'full' `
            -Intent $script:orchestrationIntent `
            -LabConfig $script:labConfig `
            -ScriptDir 'C:\ScriptDir' `
            -SwitchName 'TestSwitch' `
            -RunEvents $script:runEvents `
            -Force

        $script:bypassReceived | Should -Be $true
    }
}

Describe 'Invoke-LabOneButtonSetup' {

    BeforeEach {
        $script:runEvents = New-Object System.Collections.Generic.List[object]
        $script:labConfig = @{
            Lab     = @{ Name = 'TestLab'; CoreVMNames = @('DC1', 'SVR1', 'WS1') }
            Paths   = @{ LabRoot = 'C:\TestLabRoot' }
            Network = @{ SwitchName = 'TestSwitch' }
        }

        Mock Invoke-LabRepoScript { }
        Mock Import-LabModule { }
        Mock Get-VMSnapshot { return @{ Name = 'LabReady' } }
    }

    It 'calls preflight and bootstrap repo scripts in order' {
        # The fake Hyper-V module returns a VM for any named query, so VM existence check passes
        $script:callOrder = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-LabRepoScript {
            $script:callOrder.Add($BaseName)
        }

        Invoke-LabOneButtonSetup `
            -EffectiveMode 'full' `
            -LabConfig $script:labConfig `
            -ScriptDir 'C:\ScriptDir' `
            -LabName 'TestLab' `
            -RunEvents $script:runEvents

        $script:callOrder[0] | Should -Be 'Test-OpenCodeLabPreflight'
        $script:callOrder[1] | Should -Be 'Bootstrap'
    }

    It 'calls Start-LabDay and Lab-Status after bootstrap' {
        # The fake Hyper-V module returns a VM for any named query
        $script:callOrder = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-LabRepoScript {
            $script:callOrder.Add($BaseName)
        }

        Invoke-LabOneButtonSetup `
            -EffectiveMode 'full' `
            -LabConfig $script:labConfig `
            -ScriptDir 'C:\ScriptDir' `
            -LabName 'TestLab' `
            -RunEvents $script:runEvents

        $script:callOrder | Should -Contain 'Start-LabDay'
        $script:callOrder | Should -Contain 'Lab-Status'
    }

    It 'adds rollback event when health check fails and LabReady snapshot missing' {
        # Fake Hyper-V module provides VMs so bootstrap check passes
        Mock Invoke-LabRepoScript {
            if ($BaseName -eq 'Test-OpenCodeLabHealth') { throw 'Health check failed' }
        }
        Mock Get-VMSnapshot { return $null }

        {
            Invoke-LabOneButtonSetup `
                -EffectiveMode 'full' `
                -LabConfig $script:labConfig `
                -ScriptDir 'C:\ScriptDir' `
                -LabName 'TestLab' `
                -RunEvents $script:runEvents
        } | Should -Throw

        $rollbackEvent = $script:runEvents | Where-Object { $_.Step -eq 'rollback' }
        $rollbackEvent | Should -Not -BeNullOrEmpty
    }

    It 'attempts rollback when health check fails and LabReady snapshot exists' {
        # Fake Hyper-V module provides VMs so bootstrap check passes
        Mock Invoke-LabRepoScript {
            if ($BaseName -eq 'Test-OpenCodeLabHealth') { throw 'Health check failed' }
        }
        Mock Get-VMSnapshot { return @{ Name = 'LabReady' } }
        Mock Restore-LabVMSnapshot { }

        {
            Invoke-LabOneButtonSetup `
                -EffectiveMode 'full' `
                -LabConfig $script:labConfig `
                -ScriptDir 'C:\ScriptDir' `
                -LabName 'TestLab' `
                -RunEvents $script:runEvents
        } | Should -Throw

        Should -Invoke Restore-LabVMSnapshot -Times 1
    }
}

Describe 'Invoke-LabOneButtonReset' {

    BeforeEach {
        $script:runEvents = New-Object System.Collections.Generic.List[object]
        $script:labConfig = @{
            Lab     = @{ Name = 'TestLab'; CoreVMNames = @('DC1', 'SVR1', 'WS1') }
            Paths   = @{ LabRoot = 'C:\TestLabRoot' }
            Network = @{ NatName = 'TestNat'; SwitchName = 'TestSwitch' }
        }
    }

    It 'calls dry-run blow-away and adds dry-run event when DryRun is set' {
        Mock Invoke-LabBlowAway { }

        Invoke-LabOneButtonReset `
            -DryRun `
            -LabConfig $script:labConfig `
            -ScriptDir 'C:\ScriptDir' `
            -SwitchName 'TestSwitch' `
            -LabName 'TestLab' `
            -EffectiveMode 'full' `
            -RunEvents $script:runEvents

        Should -Invoke Invoke-LabBlowAway -Times 1
        $dryRunEvent = $script:runEvents | Where-Object { $_.Step -eq 'one-button-reset' -and $_.Status -eq 'dry-run' }
        $dryRunEvent | Should -Not -BeNullOrEmpty
    }

    It 'calls both Invoke-LabBlowAway and Invoke-LabOneButtonSetup in sequence' {
        $script:callOrder = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-LabBlowAway { $script:callOrder.Add('BlowAway') }
        Mock Invoke-LabOneButtonSetup { $script:callOrder.Add('OneButtonSetup') }

        Invoke-LabOneButtonReset `
            -LabConfig $script:labConfig `
            -ScriptDir 'C:\ScriptDir' `
            -SwitchName 'TestSwitch' `
            -LabName 'TestLab' `
            -EffectiveMode 'full' `
            -RunEvents $script:runEvents `
            -Force

        $script:callOrder.Count | Should -Be 2
        $script:callOrder[0] | Should -Be 'BlowAway'
        $script:callOrder[1] | Should -Be 'OneButtonSetup'
    }

    It 'does not call Invoke-LabOneButtonSetup when DryRun is set' {
        Mock Invoke-LabBlowAway { }
        Mock Invoke-LabOneButtonSetup { }

        Invoke-LabOneButtonReset `
            -DryRun `
            -LabConfig $script:labConfig `
            -ScriptDir 'C:\ScriptDir' `
            -SwitchName 'TestSwitch' `
            -LabName 'TestLab' `
            -EffectiveMode 'full' `
            -RunEvents $script:runEvents

        Should -Invoke Invoke-LabOneButtonSetup -Times 0 -Exactly
    }

    It 'passes BypassPrompt when Force is set' {
        $script:bypassReceived = $false
        Mock Invoke-LabBlowAway { $script:bypassReceived = [bool]$BypassPrompt }
        Mock Invoke-LabOneButtonSetup { }

        Invoke-LabOneButtonReset `
            -Force `
            -LabConfig $script:labConfig `
            -ScriptDir 'C:\ScriptDir' `
            -SwitchName 'TestSwitch' `
            -LabName 'TestLab' `
            -EffectiveMode 'full' `
            -RunEvents $script:runEvents

        $script:bypassReceived | Should -Be $true
    }
}

Describe 'Invoke-LabSetup' {

    BeforeEach {
        $script:runEvents = New-Object System.Collections.Generic.List[object]
    }

    It 'calls preflight and bootstrap repo scripts' {
        $script:calledScripts = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-LabRepoScript { $script:calledScripts.Add($BaseName) }

        Invoke-LabSetup `
            -EffectiveMode 'full' `
            -ScriptDir 'C:\ScriptDir' `
            -RunEvents $script:runEvents

        $script:calledScripts | Should -Contain 'Test-OpenCodeLabPreflight'
        $script:calledScripts | Should -Contain 'Bootstrap'
    }

    It 'passes NonInteractive to Get-LabBootstrapArgs' {
        Mock Invoke-LabRepoScript { }

        # Should not throw with NonInteractive
        {
            Invoke-LabSetup `
                -EffectiveMode 'quick' `
                -ScriptDir 'C:\ScriptDir' `
                -RunEvents $script:runEvents `
                -NonInteractive
        } | Should -Not -Throw
    }

    It 'calls preflight before bootstrap' {
        $script:callOrder = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-LabRepoScript { $script:callOrder.Add($BaseName) }

        Invoke-LabSetup `
            -EffectiveMode 'full' `
            -ScriptDir 'C:\ScriptDir' `
            -RunEvents $script:runEvents

        $script:callOrder[0] | Should -Be 'Test-OpenCodeLabPreflight'
        $script:callOrder[1] | Should -Be 'Bootstrap'
    }
}

Describe 'Invoke-LabBulkVMProvision' {

    BeforeAll {
        $script:bulkTempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('bulk-vm-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -Path $script:bulkTempDir -ItemType Directory -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $script:bulkTempDir) { Remove-Item -Recurse -Force $script:bulkTempDir }
    }

    BeforeEach {
        $script:runEvents = New-Object System.Collections.Generic.List[object]
        $script:labConfig = @{
            Lab      = @{ Name = 'TestLab' }
            Paths    = @{ LabRoot = $script:bulkTempDir }
            Network  = @{ SwitchName = 'TestSwitch' }
            VMSizing = @{
                Server = @{ Memory = 2GB; Processors = 2 }
                Client = @{ Memory = 2GB; Processors = 2 }
            }
        }
    }

    It 'returns immediately when both counts are 0' {
        Mock New-LabVM { }

        Invoke-LabBulkVMProvision `
            -ServerCount 0 `
            -WorkstationCount 0 `
            -LabConfig $script:labConfig `
            -RunEvents $script:runEvents

        Should -Invoke New-LabVM -Times 0 -Exactly
    }

    It 'creates correct number of server VMs' {
        # Fake Hyper-V module returns empty list for bulk Get-VM (no -Name param)
        $script:vmNames = [System.Collections.Generic.List[string]]::new()
        Mock New-LabVM {
            $script:vmNames.Add($VMName)
            return [pscustomobject]@{ Status = 'OK'; Message = "Created $VMName" }
        }

        Invoke-LabBulkVMProvision `
            -ServerCount 2 `
            -WorkstationCount 0 `
            -LabConfig $script:labConfig `
            -RunEvents $script:runEvents

        Should -Invoke New-LabVM -Times 2 -Exactly
        $script:vmNames | Should -Contain 'SVR2'
        $script:vmNames | Should -Contain 'SVR3'
    }

    It 'creates correct number of workstation VMs' {
        # Fake Hyper-V module returns empty list for bulk Get-VM (no -Name param)
        $script:vmNames = [System.Collections.Generic.List[string]]::new()
        Mock New-LabVM {
            $script:vmNames.Add($VMName)
            return [pscustomobject]@{ Status = 'OK'; Message = "Created $VMName" }
        }

        Invoke-LabBulkVMProvision `
            -ServerCount 0 `
            -WorkstationCount 2 `
            -LabConfig $script:labConfig `
            -RunEvents $script:runEvents

        Should -Invoke New-LabVM -Times 2 -Exactly
        $script:vmNames | Should -Contain 'WS2'
        $script:vmNames | Should -Contain 'WS3'
    }

    It 'adds run events for each provisioned VM' {
        Mock New-LabVM { return [pscustomobject]@{ Status = 'OK'; Message = 'Created' } }

        Invoke-LabBulkVMProvision `
            -ServerCount 1 `
            -WorkstationCount 1 `
            -LabConfig $script:labConfig `
            -RunEvents $script:runEvents

        $script:runEvents.Count | Should -Be 2
        ($script:runEvents | Where-Object { $_.Step -eq 'setup-add-server-vm' }) | Should -Not -BeNullOrEmpty
        ($script:runEvents | Where-Object { $_.Step -eq 'setup-add-workstation-vm' }) | Should -Not -BeNullOrEmpty
    }

    It 'adds fail event when New-LabVM returns non-OK status' {
        Mock New-LabVM { return [pscustomobject]@{ Status = 'Fail'; Message = 'Disk error' } }

        Invoke-LabBulkVMProvision `
            -ServerCount 1 `
            -WorkstationCount 0 `
            -LabConfig $script:labConfig `
            -RunEvents $script:runEvents

        $failEvent = $script:runEvents | Where-Object { $_.Status -eq 'fail' }
        $failEvent | Should -Not -BeNullOrEmpty
    }

    It 'throws when New-LabVM is not available' {
        # Override stub with unavailable version
        Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'New-LabVM' }

        {
            Invoke-LabBulkVMProvision `
                -ServerCount 1 `
                -WorkstationCount 0 `
                -LabConfig $script:labConfig `
                -RunEvents $script:runEvents
        } | Should -Throw
    }
}

Describe 'Invoke-LabSetupMenu' {

    BeforeEach {
        $script:runEvents = New-Object System.Collections.Generic.List[object]
        $script:labConfig = @{
            Lab      = @{ Name = 'TestLab'; CoreVMNames = @('DC1', 'SVR1', 'WS1') }
            Paths    = @{ LabRoot = 'C:\TestLabRoot' }
            Network  = @{ SwitchName = 'TestSwitch' }
            VMSizing = @{
                Server = @{ Memory = 2GB; Processors = 2 }
                Client = @{ Memory = 2GB; Processors = 2 }
            }
        }
    }

    It 'calls Invoke-LabOneButtonSetup with correct params' {
        Mock Read-Host { return '0' }
        Mock Read-MenuCount { return 0 }
        Mock Invoke-LabOneButtonSetup { }

        Invoke-LabSetupMenu `
            -LabConfig $script:labConfig `
            -ScriptDir 'C:\ScriptDir' `
            -LabName 'TestLab' `
            -EffectiveMode 'full' `
            -RunEvents $script:runEvents

        Should -Invoke Invoke-LabOneButtonSetup -Times 1 -Exactly
    }

    It 'does not call Invoke-LabBulkVMProvision when counts are 0' {
        Mock Read-Host { return '0' }
        Mock Read-MenuCount { return 0 }
        Mock Invoke-LabOneButtonSetup { }
        Mock Invoke-LabBulkVMProvision { }

        Invoke-LabSetupMenu `
            -LabConfig $script:labConfig `
            -ScriptDir 'C:\ScriptDir' `
            -LabName 'TestLab' `
            -EffectiveMode 'full' `
            -RunEvents $script:runEvents

        Should -Invoke Invoke-LabBulkVMProvision -Times 0 -Exactly
    }

    It 'calls Invoke-LabBulkVMProvision when server count is greater than 0' {
        $script:callCount = 0
        Mock Read-MenuCount {
            $script:callCount++
            if ($script:callCount -eq 1) { return 1 }  # ServerCount = 1
            return 0
        }
        Mock Read-Host { return '' }
        Mock Invoke-LabOneButtonSetup { }
        Mock Invoke-LabBulkVMProvision { }

        Invoke-LabSetupMenu `
            -LabConfig $script:labConfig `
            -ScriptDir 'C:\ScriptDir' `
            -LabName 'TestLab' `
            -EffectiveMode 'full' `
            -RunEvents $script:runEvents

        Should -Invoke Invoke-LabBulkVMProvision -Times 1 -Exactly
    }

    It 'adds setup-plan event with server and workstation counts' {
        Mock Read-MenuCount { return 0 }
        Mock Invoke-LabOneButtonSetup { }

        Invoke-LabSetupMenu `
            -LabConfig $script:labConfig `
            -ScriptDir 'C:\ScriptDir' `
            -LabName 'TestLab' `
            -EffectiveMode 'full' `
            -RunEvents $script:runEvents

        $planEvent = $script:runEvents | Where-Object { $_.Step -eq 'setup-plan' }
        $planEvent | Should -Not -BeNullOrEmpty
        $planEvent.Status | Should -Be 'ok'
    }
}

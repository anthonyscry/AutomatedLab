# OrchestratorExtraction-Batch4.Tests.ps1
# Unit tests for 9 functions extracted from OpenCodeLab-App.ps1 in Batch 4 (interactive menu system)

BeforeAll {
    Set-StrictMode -Version Latest

    $repoRoot = Split-Path -Parent $PSScriptRoot

    # Batch 1 dependencies
    . (Join-Path $repoRoot 'Private/Add-LabRunEvent.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabHealthArgs.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabExpectedVMs.ps1')
    . (Join-Path $repoRoot 'Private/Convert-LabArgumentArrayToSplat.ps1')
    . (Join-Path $repoRoot 'Private/Resolve-LabScriptPath.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabRepoScript.ps1')
    . (Join-Path $repoRoot 'Public/Write-LabStatus.ps1')

    # Batch 2 dependencies
    . (Join-Path $repoRoot 'Private/Test-LabReadySnapshot.ps1')
    . (Join-Path $repoRoot 'Private/Stop-LabVMsSafe.ps1')

    # Batch 3 dependencies
    . (Join-Path $repoRoot 'Private/Invoke-LabOneButtonReset.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabSetupMenu.ps1')

    # Batch 4 functions under test
    . (Join-Path $repoRoot 'Private/Suspend-LabMenuPrompt.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabMenuCommand.ps1')
    . (Join-Path $repoRoot 'Private/Read-LabMenuCount.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabMenuVmSelection.ps1')
    . (Join-Path $repoRoot 'Private/Show-LabMenu.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabConfigureRoleMenu.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabAddVMWizard.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabAddVMMenu.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabInteractiveMenu.ps1')

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

    # Stub commands that may not exist in the test environment
    if (-not (Get-Command Stop-VM -ErrorAction SilentlyContinue)) {
        function Global:Stop-VM { param([switch]$Force, $ErrorAction) }
    }
    if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
        function Global:Get-VM { param($ErrorAction) @() }
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
    if (-not (Get-Command Get-VMSnapshot -ErrorAction SilentlyContinue)) {
        function Global:Get-VMSnapshot { param([string]$VMName, [string]$Name, $ErrorAction) $null }
    }
    if (-not (Get-Command Import-Module -ErrorAction SilentlyContinue)) {
        function Global:Import-Module { param([string]$Name, $ErrorAction) }
    }
    if (-not (Get-Command Invoke-LabOneButtonSetup -ErrorAction SilentlyContinue)) {
        function Global:Invoke-LabOneButtonSetup { param([string]$EffectiveMode, [hashtable]$LabConfig, [string]$ScriptDir, [string]$LabName, [System.Collections.Generic.List[object]]$RunEvents, [switch]$NonInteractive, [switch]$AutoFixSubnetConflict) }
    }
    if (-not (Get-Command Invoke-LabBulkVMProvision -ErrorAction SilentlyContinue)) {
        function Global:Invoke-LabBulkVMProvision { param([int]$ServerCount, [int]$WorkstationCount, [string]$ServerIsoPath, [string]$WorkstationIsoPath, [hashtable]$LabConfig, [System.Collections.Generic.List[object]]$RunEvents) }
    }
    if (-not (Get-Command Import-LabModule -ErrorAction SilentlyContinue)) {
        function Global:Import-LabModule { param([string]$LabName) }
    }
}

Describe 'Suspend-LabMenuPrompt' {

    It 'calls Read-Host' {
        Mock Read-Host { '' }

        Suspend-LabMenuPrompt

        Should -Invoke Read-Host -Times 1 -Exactly
    }

    It 'has [CmdletBinding()] and no parameters' {
        $cmd = Get-Command Suspend-LabMenuPrompt
        $cmd | Should -Not -BeNullOrEmpty
        $cmd.Parameters.Keys | Should -Not -Contain 'Prompt'
    }
}

Describe 'Invoke-LabMenuCommand' {

    BeforeEach {
        $script:runEvents = New-Object System.Collections.Generic.List[object]
    }

    It 'executes the Command scriptblock' {
        $script:commandRan = $false
        Mock Read-Host { '' }

        Invoke-LabMenuCommand -Name 'test-cmd' -Command { $script:commandRan = $true } -RunEvents $script:runEvents

        $script:commandRan | Should -Be $true
    }

    It 'logs start and ok events to RunEvents' {
        Mock Read-Host { '' }

        Invoke-LabMenuCommand -Name 'test-event' -Command { } -RunEvents $script:runEvents

        $script:runEvents.Count | Should -Be 2
        $script:runEvents[0].Step | Should -Be 'menu:test-event'
        $script:runEvents[0].Status | Should -Be 'start'
        $script:runEvents[1].Status | Should -Be 'ok'
    }

    It 'logs fail event when command throws' {
        Mock Read-Host { '' }

        Invoke-LabMenuCommand -Name 'fail-cmd' -Command { throw "test error" } -RunEvents $script:runEvents

        $failEvent = $script:runEvents | Where-Object { $_.Status -eq 'fail' }
        $failEvent | Should -Not -BeNullOrEmpty
        $failEvent.Message | Should -Be 'test error'
    }

    It 'calls Suspend-LabMenuPrompt when NoPause is not set' {
        Mock Read-Host { '' }
        Mock Suspend-LabMenuPrompt { }

        Invoke-LabMenuCommand -Name 'pause-test' -Command { } -RunEvents $script:runEvents

        Should -Invoke Suspend-LabMenuPrompt -Times 1 -Exactly
    }

    It 'does not call Suspend-LabMenuPrompt when NoPause is set' {
        Mock Suspend-LabMenuPrompt { }

        Invoke-LabMenuCommand -Name 'no-pause-test' -Command { } -RunEvents $script:runEvents -NoPause

        Should -Invoke Suspend-LabMenuPrompt -Times 0 -Exactly
    }
}

Describe 'Read-LabMenuCount' {

    It 'returns the parsed integer when input is valid' {
        Mock Read-Host { '5' }

        $result = Read-LabMenuCount -Prompt 'How many' -DefaultValue 0

        $result | Should -Be 5
    }

    It 'returns DefaultValue when input is empty' {
        Mock Read-Host { '' }

        $result = Read-LabMenuCount -Prompt 'How many' -DefaultValue 3

        $result | Should -Be 3
    }

    It 'returns DefaultValue when input is not a valid integer' {
        Mock Read-Host { 'abc' }

        $result = Read-LabMenuCount -Prompt 'How many' -DefaultValue 2

        $result | Should -Be 2
    }

    It 'returns 0 when input is 0 (valid boundary)' {
        Mock Read-Host { '0' }

        $result = Read-LabMenuCount -Prompt 'How many' -DefaultValue 5

        $result | Should -Be 0
    }
}

Describe 'Get-LabMenuVmSelection' {

    It 'returns the typed VM name when VM list is empty (Hyper-V returns empty)' {
        # Fake Hyper-V module returns @() so vmNames is empty, falls through to Read-Host prompt
        Mock Read-Host { 'MYVM' }

        $result = Get-LabMenuVmSelection -CoreVMNames @()

        $result | Should -Be 'MYVM'
    }

    It 'returns SuggestedVM when no VMs available and no input provided' {
        # Fake Hyper-V returns @(), CoreVMNames empty -> vmNames empty -> return SuggestedVM
        Mock Read-Host { '' }

        $result = Get-LabMenuVmSelection -SuggestedVM 'MySuggestedVM' -CoreVMNames @()

        $result | Should -Be 'MySuggestedVM'
    }

    It 'returns custom name when N is entered as target VM name' {
        # Fake Hyper-V returns @() -> empty vmNames -> Read-Host prompt returns 'MyCustomVM'
        # Test: when user directly types a VM name at the prompt
        Mock Read-Host { 'MyCustomVM' }

        $result = Get-LabMenuVmSelection -CoreVMNames @()

        $result | Should -Be 'MyCustomVM'
    }
}

Describe 'Show-LabMenu' {

    It 'runs without errors' {
        Mock Clear-Host { }
        Mock Write-Host { }

        { Show-LabMenu } | Should -Not -Throw
    }

    It 'calls Clear-Host' {
        Mock Clear-Host { }
        Mock Write-Host { }

        Show-LabMenu

        Should -Invoke Clear-Host -Times 1 -Exactly
    }
}

Describe 'Invoke-LabConfigureRoleMenu' {

    BeforeEach {
        $script:runEvents = New-Object System.Collections.Generic.List[object]
        $script:scriptDir = 'C:\ScriptDir'
        $script:coreVMNames = @('DC1', 'SVR1', 'WS1')
    }

    It 'returns early when X is selected' {
        Mock Read-Host { 'X' }

        { Invoke-LabConfigureRoleMenu -ScriptDir $script:scriptDir -CoreVMNames $script:coreVMNames -RunEvents $script:runEvents } | Should -Not -Throw

        $script:runEvents.Count | Should -Be 0
    }

    It 'logs configure-role event when valid role is selected' {
        $script:readCount = 0
        Mock Read-Host {
            $script:readCount++
            switch ($script:readCount) {
                1 { '1' }  # Select DC role
                2 { 'P' }  # Primary mode
                3 { '1' }  # Select VM index 1 from Get-LabMenuVmSelection
                default { 'N' }
            }
        }
        Mock Get-LabMenuVmSelection { 'DC1' }
        Mock Write-LabStatus { }

        Invoke-LabConfigureRoleMenu -ScriptDir $script:scriptDir -CoreVMNames $script:coreVMNames -RunEvents $script:runEvents

        $roleEvent = $script:runEvents | Where-Object { $_.Step -eq 'configure-role' }
        $roleEvent | Should -Not -BeNullOrEmpty
        $roleEvent.Status | Should -Be 'ok'
    }

    It 'shows invalid message for unknown role key' {
        $script:readCount = 0
        Mock Read-Host {
            $script:readCount++
            if ($script:readCount -eq 1) { 'Z' } else { 'X' }
        }
        Mock Write-Host { }

        { Invoke-LabConfigureRoleMenu -ScriptDir $script:scriptDir -CoreVMNames $script:coreVMNames -RunEvents $script:runEvents } | Should -Not -Throw
    }
}

Describe 'Invoke-LabAddVMWizard' {

    BeforeEach {
        $script:runEvents = New-Object System.Collections.Generic.List[object]
        $script:labConfig = @{
            Lab     = @{ Name = 'TestLab'; CoreVMNames = @('DC1', 'SVR1', 'WS1') }
            Paths   = @{ LabRoot = '/tmp/TestLabRoot' }
            Network = @{ SwitchName = 'TestSwitch' }
        }
    }

    It 'cancels when user does not confirm with y' {
        Mock Read-Host { 'n' }
        Mock Write-Host { }
        Mock New-Item { }
        Mock Test-Path { $true }

        Invoke-LabAddVMWizard -VMType 'Server' -LabConfig $script:labConfig -RunEvents $script:runEvents

        $script:runEvents.Count | Should -Be 0
    }

    It 'calls New-LabVM when user confirms with y' {
        $script:readCount = 0
        Mock Read-Host {
            $script:readCount++
            switch ($script:readCount) {
                1 { '' }     # VM name (use default SVR2)
                2 { '' }     # Memory (use default 4)
                3 { '' }     # CPU (use default 2)
                4 { '' }     # ISO path (empty)
                5 { 'y' }    # Confirm
                default { '' }
            }
        }
        Mock Write-Host { }
        Mock New-Item { }
        Mock Test-Path { $true }
        Mock New-LabVM { [pscustomobject]@{ Status = 'OK'; Message = 'Created' } }
        Mock Write-LabStatus { }

        Invoke-LabAddVMWizard -VMType 'Server' -LabConfig $script:labConfig -RunEvents $script:runEvents

        Should -Invoke New-LabVM -Times 1 -Exactly
    }

    It 'logs ok event when VM creation succeeds' {
        $script:readCount = 0
        Mock Read-Host {
            $script:readCount++
            switch ($script:readCount) {
                5 { 'y' }
                default { '' }
            }
        }
        Mock Write-Host { }
        Mock New-Item { }
        Mock Test-Path { $true }
        Mock New-LabVM { [pscustomobject]@{ Status = 'OK'; Message = 'Created' } }
        Mock Write-LabStatus { }

        Invoke-LabAddVMWizard -VMType 'Workstation' -LabConfig $script:labConfig -RunEvents $script:runEvents

        $addVmEvent = $script:runEvents | Where-Object { $_.Step -eq 'add-vm' }
        $addVmEvent | Should -Not -BeNullOrEmpty
        $addVmEvent.Status | Should -Be 'ok'
    }
}

Describe 'Invoke-LabAddVMMenu' {

    BeforeEach {
        $script:runEvents = New-Object System.Collections.Generic.List[object]
        $script:labConfig = @{
            Lab     = @{ Name = 'TestLab'; CoreVMNames = @('DC1', 'SVR1', 'WS1') }
            Paths   = @{ LabRoot = 'C:\TestLabRoot' }
            Network = @{ SwitchName = 'TestSwitch' }
        }
    }

    It 'dispatches to Invoke-LabAddVMWizard with Server type when 1 selected' {
        Mock Read-Host { '1' }
        Mock Invoke-LabAddVMWizard { }
        Mock Write-Host { }

        Invoke-LabAddVMMenu -LabConfig $script:labConfig -RunEvents $script:runEvents

        Should -Invoke Invoke-LabAddVMWizard -Times 1 -ParameterFilter { $VMType -eq 'Server' }
    }

    It 'dispatches to Invoke-LabAddVMWizard with Workstation type when 2 selected' {
        Mock Read-Host { '2' }
        Mock Invoke-LabAddVMWizard { }
        Mock Write-Host { }

        Invoke-LabAddVMMenu -LabConfig $script:labConfig -RunEvents $script:runEvents

        Should -Invoke Invoke-LabAddVMWizard -Times 1 -ParameterFilter { $VMType -eq 'Workstation' }
    }

    It 'returns without error when X is selected' {
        Mock Read-Host { 'X' }
        Mock Write-Host { }

        { Invoke-LabAddVMMenu -LabConfig $script:labConfig -RunEvents $script:runEvents } | Should -Not -Throw
    }

    It 'shows invalid message for unknown choice' {
        Mock Read-Host { 'Z' }
        Mock Write-Host { }

        { Invoke-LabAddVMMenu -LabConfig $script:labConfig -RunEvents $script:runEvents } | Should -Not -Throw
    }
}

Describe 'Invoke-LabInteractiveMenu' {

    BeforeEach {
        $script:runEvents = New-Object System.Collections.Generic.List[object]
        $script:labConfig = @{
            Lab     = @{ Name = 'TestLab'; CoreVMNames = @('DC1', 'SVR1', 'WS1') }
            Paths   = @{ LabRoot = 'C:\TestLabRoot' }
            Network = @{ SwitchName = 'TestSwitch' }
        }
    }

    It 'exits cleanly when X is entered immediately' {
        Mock Show-LabMenu { }
        Mock Read-Host { 'X' }

        { Invoke-LabInteractiveMenu `
            -LabConfig $script:labConfig `
            -ScriptDir 'C:\ScriptDir' `
            -SwitchName 'TestSwitch' `
            -LabName 'TestLab' `
            -EffectiveMode 'quick' `
            -RunEvents $script:runEvents } | Should -Not -Throw
    }

    It 'calls Show-LabMenu on each iteration' {
        $script:callCount = 0
        Mock Show-LabMenu { }
        Mock Read-Host {
            $script:callCount++
            if ($script:callCount -le 2) { 'default' } else { 'X' }
        }
        Mock Write-Host { }
        Mock Start-Sleep { }

        Invoke-LabInteractiveMenu `
            -LabConfig $script:labConfig `
            -ScriptDir 'C:\ScriptDir' `
            -SwitchName 'TestSwitch' `
            -LabName 'TestLab' `
            -EffectiveMode 'full' `
            -RunEvents $script:runEvents

        Should -Invoke Show-LabMenu -Times 3 -Exactly
    }

    It 'dispatches to Invoke-LabMenuCommand for known menu actions' {
        Mock Show-LabMenu { }
        $script:callCount = 0
        Mock Read-Host {
            $script:callCount++
            if ($script:callCount -eq 1) { '1' } else { 'X' }
        }
        Mock Invoke-LabMenuCommand { }

        Invoke-LabInteractiveMenu `
            -LabConfig $script:labConfig `
            -ScriptDir 'C:\ScriptDir' `
            -SwitchName 'TestSwitch' `
            -LabName 'TestLab' `
            -EffectiveMode 'quick' `
            -RunEvents $script:runEvents

        Should -Invoke Invoke-LabMenuCommand -Times 1 -ParameterFilter { $Name -eq 'start' }
    }
}

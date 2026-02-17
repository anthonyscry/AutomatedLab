# OrchestratorExtraction-Batch2.Tests.ps1
# Unit tests for 8 functions extracted from OpenCodeLab-App.ps1 in Batch 2

BeforeAll {
    Set-StrictMode -Version Latest

    $repoRoot = Split-Path -Parent $PSScriptRoot

    # Batch 1 dependencies (needed by Batch 2 functions)
    . (Join-Path $repoRoot 'Private/Add-LabRunEvent.ps1')
    . (Join-Path $repoRoot 'Private/Convert-LabArgumentArrayToSplat.ps1')
    . (Join-Path $repoRoot 'Private/Resolve-LabScriptPath.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabExpectedVMs.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabHealthArgs.ps1')
    . (Join-Path $repoRoot 'Private/Import-LabModule.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabRepoScript.ps1')
    . (Join-Path $repoRoot 'Public/Write-LabStatus.ps1')

    # Batch 2 functions under test
    . (Join-Path $repoRoot 'Private/Resolve-LabNoExecuteStateOverride.ps1')
    . (Join-Path $repoRoot 'Private/Resolve-LabRuntimeStateOverride.ps1')
    . (Join-Path $repoRoot 'Private/Test-LabReadySnapshot.ps1')
    . (Join-Path $repoRoot 'Private/Stop-LabVMsSafe.ps1')
    . (Join-Path $repoRoot 'Private/Write-LabRunArtifacts.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabBlowAway.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabQuickDeploy.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabQuickTeardown.ps1')

    # Stub Hyper-V / AutomatedLab commands that may not exist in test environment
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
}

Describe 'Resolve-LabNoExecuteStateOverride' {

    It 'returns null when NoExecute is false' {
        $result = Resolve-LabNoExecuteStateOverride -NoExecute:$false
        $result | Should -BeNullOrEmpty
    }

    It 'returns null when NoExecute is true and no JSON or path provided' {
        $result = Resolve-LabNoExecuteStateOverride -NoExecute
        $result | Should -BeNullOrEmpty
    }

    It 'parses JSON string when NoExecuteStateJson is provided' {
        $json = '[{"HostName":"host1","Reachable":true}]'
        $result = Resolve-LabNoExecuteStateOverride -NoExecute -NoExecuteStateJson $json
        $result | Should -Not -BeNullOrEmpty
        $result[0].HostName | Should -Be 'host1'
    }

    It 'returns array when JSON is an array of host probes' {
        $json = '[{"HostName":"h1","Reachable":true},{"HostName":"h2","Reachable":false}]'
        $result = Resolve-LabNoExecuteStateOverride -NoExecute -NoExecuteStateJson $json
        $result.Count | Should -Be 2
    }

    It 'loads state from file path when NoExecuteStatePath is provided' {
        $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) ('noexec-' + [guid]::NewGuid().ToString('N') + '.json')
        try {
            '[{"HostName":"filehost","Reachable":true}]' | Set-Content $tmpFile -Encoding UTF8
            $result = Resolve-LabNoExecuteStateOverride -NoExecute -NoExecuteStatePath $tmpFile
            $result | Should -Not -BeNullOrEmpty
            $result[0].HostName | Should -Be 'filehost'
        }
        finally {
            if (Test-Path $tmpFile) { Remove-Item $tmpFile }
        }
    }

    It 'throws when NoExecuteStatePath does not exist' {
        { Resolve-LabNoExecuteStateOverride -NoExecute -NoExecuteStatePath 'C:\nonexistent\state.json' } | Should -Throw
    }

    It 'extracts HostProbes array from state object' {
        $json = '{"HostProbes":[{"HostName":"probe1"},{"HostName":"probe2"}]}'
        $result = Resolve-LabNoExecuteStateOverride -NoExecute -NoExecuteStateJson $json
        $result.Count | Should -Be 2
        $result[0].HostName | Should -Be 'probe1'
    }

    It 'adds MissingVMs property when not present in state object' {
        $json = '{"LabRegistered":true,"LabReadyAvailable":false}'
        $result = Resolve-LabNoExecuteStateOverride -NoExecute -NoExecuteStateJson $json
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'MissingVMs'
    }
}

Describe 'Resolve-LabRuntimeStateOverride' {

    BeforeEach {
        $env:OPENCODELAB_RUNTIME_STATE_JSON = $null
    }

    AfterEach {
        $env:OPENCODELAB_RUNTIME_STATE_JSON = $null
    }

    It 'returns null when SkipRuntimeBootstrap is false' {
        $result = Resolve-LabRuntimeStateOverride -SkipRuntimeBootstrap:$false
        $result | Should -BeNullOrEmpty
    }

    It 'returns null when SkipRuntimeBootstrap is true but env var is empty' {
        $result = Resolve-LabRuntimeStateOverride -SkipRuntimeBootstrap
        $result | Should -BeNullOrEmpty
    }

    It 'parses env var JSON when SkipRuntimeBootstrap is true' {
        $env:OPENCODELAB_RUNTIME_STATE_JSON = '[{"HostName":"runtime1","Reachable":true}]'
        $result = Resolve-LabRuntimeStateOverride -SkipRuntimeBootstrap
        $result | Should -Not -BeNullOrEmpty
        $result[0].HostName | Should -Be 'runtime1'
    }

    It 'throws when env var contains invalid JSON' {
        $env:OPENCODELAB_RUNTIME_STATE_JSON = 'this is not json'
        { Resolve-LabRuntimeStateOverride -SkipRuntimeBootstrap } | Should -Throw
    }

    It 'returns array for array JSON input' {
        $env:OPENCODELAB_RUNTIME_STATE_JSON = '[{"HostName":"h1"},{"HostName":"h2"}]'
        $result = Resolve-LabRuntimeStateOverride -SkipRuntimeBootstrap
        $result.Count | Should -Be 2
    }

    It 'extracts HostProbes from state object' {
        $env:OPENCODELAB_RUNTIME_STATE_JSON = '{"HostProbes":[{"HostName":"rp1"},{"HostName":"rp2"}]}'
        $result = Resolve-LabRuntimeStateOverride -SkipRuntimeBootstrap
        $result.Count | Should -Be 2
    }
}

Describe 'Test-LabReadySnapshot' {

    BeforeEach {
        Mock Import-LabModule { }
    }

    It 'returns true when all VMs have LabReady snapshot' {
        Mock Get-VMSnapshot { return @{ Name = 'LabReady' } }

        $result = Test-LabReadySnapshot -LabName 'TestLab' -VMNames @('DC1', 'SVR1')
        $result | Should -Be $true
    }

    It 'returns false when a VM is missing LabReady snapshot' {
        Mock Get-VMSnapshot { return $null }

        $result = Test-LabReadySnapshot -LabName 'TestLab' -VMNames @('DC1', 'SVR1')
        $result | Should -Be $false
    }

    It 'returns false when Get-VMSnapshot throws' {
        Mock Get-VMSnapshot { throw 'Hyper-V not available' }

        $result = Test-LabReadySnapshot -LabName 'TestLab' -VMNames @('DC1')
        $result | Should -Be $false
    }

    It 'uses CoreVMNames fallback when VMNames not provided' {
        $script:snapCallCount = 0
        Mock Get-VMSnapshot {
            $script:snapCallCount++
            return @{ Name = 'LabReady' }
        }

        $result = Test-LabReadySnapshot -LabName 'TestLab' -CoreVMNames @('DC1', 'SVR1', 'WS1')
        $result | Should -Be $true
        $script:snapCallCount | Should -Be 3
    }

    It 'returns true when VMNames is empty and CoreVMNames is empty (no VMs to check)' {
        $result = Test-LabReadySnapshot -LabName 'TestLab'
        $result | Should -Be $true
    }
}

Describe 'Stop-LabVMsSafe' {

    BeforeEach {
        Mock Import-LabModule { }
    }

    It 'calls Stop-LabVM when available' {
        Mock Stop-LabVM { }

        { Stop-LabVMsSafe -LabName 'TestLab' -CoreVMNames @('DC1', 'SVR1') } | Should -Not -Throw
        Should -Invoke Stop-LabVM -Times 1 -Exactly
    }

    It 'falls back to Get-VM and Stop-VM when Stop-LabVM throws' {
        Mock Stop-LabVM { throw 'AutomatedLab not available' }
        Mock Get-VM {
            return @(
                [pscustomobject]@{ Name = 'DC1'; State = 'Running' },
                [pscustomobject]@{ Name = 'SVR1'; State = 'Off' },
                [pscustomobject]@{ Name = 'OtherVM'; State = 'Running' }
            )
        }
        Mock Stop-VM { }

        Stop-LabVMsSafe -LabName 'TestLab' -CoreVMNames @('DC1', 'SVR1')

        # Should Stop-VM only for DC1 (Running and in CoreVMNames), not SVR1 (Off) or OtherVM (not in list)
        Should -Invoke Stop-VM -Times 1
    }
}

Describe 'Write-LabRunArtifacts' {

    BeforeAll {
        $script:artifactDir = Join-Path ([System.IO.Path]::GetTempPath()) ('write-artifacts-' + [guid]::NewGuid().ToString('N'))
        New-Item -Path $script:artifactDir -ItemType Directory | Out-Null
    }

    AfterAll {
        if (Test-Path $script:artifactDir) {
            Remove-Item -Recurse -Force $script:artifactDir
        }
    }

    It 'creates JSON and TXT files in RunLogRoot' {
        $runId = 'testrun-001'
        $reportData = @{
            RunId                = $runId
            Action               = 'test'
            ResolvedDispatchMode = 'off'
            ExecutionOutcome     = 'succeeded'
            ExecutionStartedAt   = $null
            ExecutionCompletedAt = $null
            RequestedMode        = 'quick'
            EffectiveMode        = 'quick'
            FallbackReason       = $null
            ProfileSource        = 'default'
            NonInteractive       = $false
            CoreOnly             = $true
            Force                = $false
            RemoveNetwork        = $false
            DryRun               = $false
            AutoHeal             = $null
            DefaultsFile         = $null
            RunStart             = (Get-Date)
            RunLogRoot           = $script:artifactDir
            PolicyOutcome        = $null
            PolicyReason         = $null
            HostOutcomes         = @()
            BlastRadius          = @()
            RunEvents            = (New-Object System.Collections.Generic.List[object])
        }

        Write-LabRunArtifacts -ReportData $reportData -Success $true

        $jsonPath = Join-Path $script:artifactDir "OpenCodeLab-Run-$runId.json"
        $txtPath = Join-Path $script:artifactDir "OpenCodeLab-Run-$runId.txt"

        $jsonPath | Should -Exist
        $txtPath | Should -Exist
    }

    It 'writes correct success value to JSON' {
        $runId = 'testrun-success'
        $reportData = @{
            RunId                = $runId
            Action               = 'health'
            ResolvedDispatchMode = 'off'
            ExecutionOutcome     = 'succeeded'
            ExecutionStartedAt   = $null
            ExecutionCompletedAt = $null
            RequestedMode        = 'full'
            EffectiveMode        = 'full'
            FallbackReason       = $null
            ProfileSource        = 'default'
            NonInteractive       = $false
            CoreOnly             = $true
            Force                = $false
            RemoveNetwork        = $false
            DryRun               = $false
            AutoHeal             = $null
            DefaultsFile         = $null
            RunStart             = (Get-Date)
            RunLogRoot           = $script:artifactDir
            PolicyOutcome        = $null
            PolicyReason         = $null
            HostOutcomes         = @()
            BlastRadius          = @()
            RunEvents            = (New-Object System.Collections.Generic.List[object])
        }

        Write-LabRunArtifacts -ReportData $reportData -Success $true

        $jsonPath = Join-Path $script:artifactDir "OpenCodeLab-Run-$runId.json"
        $json = Get-Content $jsonPath -Raw | ConvertFrom-Json

        $json.success | Should -Be $true
        $json.action | Should -Be 'health'
        $json.run_id | Should -Be $runId
    }

    It 'writes error message to JSON when success is false' {
        $runId = 'testrun-fail'
        $reportData = @{
            RunId                = $runId
            Action               = 'deploy'
            ResolvedDispatchMode = 'off'
            ExecutionOutcome     = 'failed'
            ExecutionStartedAt   = $null
            ExecutionCompletedAt = $null
            RequestedMode        = 'full'
            EffectiveMode        = 'full'
            FallbackReason       = $null
            ProfileSource        = 'default'
            NonInteractive       = $false
            CoreOnly             = $true
            Force                = $false
            RemoveNetwork        = $false
            DryRun               = $false
            AutoHeal             = $null
            DefaultsFile         = $null
            RunStart             = (Get-Date)
            RunLogRoot           = $script:artifactDir
            PolicyOutcome        = $null
            PolicyReason         = $null
            HostOutcomes         = @()
            BlastRadius          = @()
            RunEvents            = (New-Object System.Collections.Generic.List[object])
        }

        Write-LabRunArtifacts -ReportData $reportData -Success $false -ErrorMessage 'Something went wrong'

        $jsonPath = Join-Path $script:artifactDir "OpenCodeLab-Run-$runId.json"
        $json = Get-Content $jsonPath -Raw | ConvertFrom-Json

        $json.success | Should -Be $false
        $json.error | Should -Be 'Something went wrong'
    }

    It 'creates RunLogRoot directory if it does not exist' {
        $newDir = Join-Path $script:artifactDir 'newsubdir'
        $runId = 'testrun-newdir'
        $reportData = @{
            RunId                = $runId
            Action               = 'test'
            ResolvedDispatchMode = 'off'
            ExecutionOutcome     = 'succeeded'
            ExecutionStartedAt   = $null
            ExecutionCompletedAt = $null
            RequestedMode        = 'quick'
            EffectiveMode        = 'quick'
            FallbackReason       = $null
            ProfileSource        = 'default'
            NonInteractive       = $false
            CoreOnly             = $true
            Force                = $false
            RemoveNetwork        = $false
            DryRun               = $false
            AutoHeal             = $null
            DefaultsFile         = $null
            RunStart             = (Get-Date)
            RunLogRoot           = $newDir
            PolicyOutcome        = $null
            PolicyReason         = $null
            HostOutcomes         = @()
            BlastRadius          = @()
            RunEvents            = (New-Object System.Collections.Generic.List[object])
        }

        Write-LabRunArtifacts -ReportData $reportData -Success $true

        $newDir | Should -Exist
    }
}

Describe 'Invoke-LabBlowAway' {

    It 'outputs dry-run message and adds event when Simulate is set' {
        $runEvents = New-Object System.Collections.Generic.List[object]
        $labConfig = @{
            Lab = @{ Name = 'TestLab'; CoreVMNames = @('DC1', 'SVR1') }
            Paths = @{ LabRoot = 'C:\TestLabRoot' }
            Network = @{ NatName = 'TestNat' }
        }

        Invoke-LabBlowAway -Simulate -BypassPrompt -LabConfig $labConfig -SwitchName 'TestSwitch' -RunEvents $runEvents

        $runEvents.Count | Should -Be 1
        $runEvents[0].Step | Should -Be 'blow-away'
        $runEvents[0].Status | Should -Be 'dry-run'
    }

    It 'aborts when prompt is not confirmed' {
        $runEvents = New-Object System.Collections.Generic.List[object]
        $labConfig = @{
            Lab = @{ Name = 'TestLab'; CoreVMNames = @('DC1') }
            Paths = @{ LabRoot = 'C:\TestLabRoot' }
            Network = @{ NatName = 'TestNat' }
        }

        Mock Read-Host { return 'no' }
        Mock Stop-LabVMsSafe { }

        Invoke-LabBlowAway -LabConfig $labConfig -SwitchName 'TestSwitch' -RunEvents $runEvents

        # Should not have called Stop-LabVMsSafe (aborted before step 1)
        Should -Invoke Stop-LabVMsSafe -Times 0 -Exactly
    }
}

Describe 'Invoke-LabQuickDeploy' {

    It 'outputs dry-run message and adds event when DryRun is set' {
        $runEvents = New-Object System.Collections.Generic.List[object]

        Invoke-LabQuickDeploy -DryRun -ScriptDir 'C:\TestDir' -RunEvents $runEvents

        $runEvents.Count | Should -Be 1
        $runEvents[0].Step | Should -Be 'deploy-quick'
        $runEvents[0].Status | Should -Be 'dry-run'
    }

    It 'calls Invoke-LabRepoScript when not in DryRun mode' {
        $runEvents = New-Object System.Collections.Generic.List[object]

        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('quick-deploy-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempDir -ItemType Directory | Out-Null

        try {
            # Create stub scripts
            Set-Content (Join-Path $tempDir 'Start-LabDay.ps1') ''
            Set-Content (Join-Path $tempDir 'Lab-Status.ps1') ''
            Set-Content (Join-Path $tempDir 'Test-OpenCodeLabHealth.ps1') ''

            { Invoke-LabQuickDeploy -ScriptDir $tempDir -RunEvents $runEvents } | Should -Not -Throw

            ($runEvents | Where-Object { $_.Step -eq 'Start-LabDay' }) | Should -Not -BeNullOrEmpty
        }
        finally {
            Remove-Item -Recurse -Force $tempDir
        }
    }
}

Describe 'Invoke-LabQuickTeardown' {

    BeforeEach {
        Mock Import-LabModule { }
        Mock Stop-LabVM { }
        Mock Get-VM { return @() }
    }

    It 'outputs dry-run message and adds event when DryRun is set' {
        $runEvents = New-Object System.Collections.Generic.List[object]
        $labConfig = @{
            Lab = @{ Name = 'TestLab'; CoreVMNames = @('DC1') }
        }

        Invoke-LabQuickTeardown -DryRun -LabName 'TestLab' -CoreVMNames @('DC1') -LabConfig $labConfig -RunEvents $runEvents

        $runEvents.Count | Should -Be 1
        $runEvents[0].Step | Should -Be 'teardown-quick'
        $runEvents[0].Status | Should -Be 'dry-run'
    }

    It 'stops VMs and emits warning event when LabReady snapshot not found' {
        $runEvents = New-Object System.Collections.Generic.List[object]
        $labConfig = @{
            Lab = @{ Name = 'TestLab'; CoreVMNames = @('DC1', 'SVR1') }
        }

        Mock Get-LabExpectedVMs { return @('DC1', 'SVR1') }
        Mock Get-VMSnapshot { return $null }

        Invoke-LabQuickTeardown -LabName 'TestLab' -CoreVMNames @('DC1', 'SVR1') -LabConfig $labConfig -RunEvents $runEvents

        $warnEvent = $runEvents | Where-Object { $_.Status -eq 'warn' -or $_.Status -eq 'fail' }
        $warnEvent | Should -Not -BeNullOrEmpty
    }
}

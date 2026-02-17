# OrchestratorExtraction-Batch1.Tests.ps1
# Unit tests for 11 functions extracted from OpenCodeLab-App.ps1 in Batch 1

BeforeAll {
    Set-StrictMode -Version Latest

    $repoRoot = Split-Path -Parent $PSScriptRoot

    . (Join-Path $repoRoot 'Private/Convert-LabArgumentArrayToSplat.ps1')
    . (Join-Path $repoRoot 'Private/Resolve-LabScriptPath.ps1')
    . (Join-Path $repoRoot 'Private/Add-LabRunEvent.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabRepoScript.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabExpectedVMs.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabPreflightArgs.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabBootstrapArgs.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabDeployArgs.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabHealthArgs.ps1')
    . (Join-Path $repoRoot 'Private/Import-LabModule.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabLogRetention.ps1')
}

Describe 'Convert-LabArgumentArrayToSplat' {

    It 'converts switch arguments to true' {
        $result = Convert-LabArgumentArrayToSplat -ArgumentList @('-NonInteractive')
        $result['NonInteractive'] | Should -Be $true
    }

    It 'converts key-value arguments' {
        $result = Convert-LabArgumentArrayToSplat -ArgumentList @('-Mode', 'full')
        $result['Mode'] | Should -Be 'full'
    }

    It 'handles mixed switch and key-value arguments' {
        $result = Convert-LabArgumentArrayToSplat -ArgumentList @('-Mode', 'full', '-NonInteractive')
        $result['Mode'] | Should -Be 'full'
        $result['NonInteractive'] | Should -Be $true
    }

    It 'returns empty hashtable for empty array' {
        $result = Convert-LabArgumentArrayToSplat -ArgumentList @()
        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 0
    }

    It 'throws on bare positional value' {
        { Convert-LabArgumentArrayToSplat -ArgumentList @('barevalue') } | Should -Throw
    }

    It 'throws on empty dash token' {
        { Convert-LabArgumentArrayToSplat -ArgumentList @('-') } | Should -Throw
    }

    It 'handles multiple key-value pairs' {
        $result = Convert-LabArgumentArrayToSplat -ArgumentList @('-Mode', 'quick', '-AutoFixSubnetConflict')
        $result['Mode'] | Should -Be 'quick'
        $result['AutoFixSubnetConflict'] | Should -Be $true
    }
}

Describe 'Resolve-LabScriptPath' {

    It 'finds script in root directory' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('resolve-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempDir -ItemType Directory | Out-Null
        $scriptPath = Join-Path $tempDir 'TestScript.ps1'
        Set-Content $scriptPath '# test'

        try {
            $result = Resolve-LabScriptPath -BaseName 'TestScript' -ScriptDir $tempDir
            $result | Should -Be $scriptPath
        } finally {
            Remove-Item -Recurse -Force $tempDir
        }
    }

    It 'finds script in Scripts/ subdirectory' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('resolve-test-' + [guid]::NewGuid().ToString('N'))
        $scriptsDir = Join-Path $tempDir 'Scripts'
        New-Item -Path $scriptsDir -ItemType Directory -Force | Out-Null
        $scriptPath = Join-Path $scriptsDir 'TestScript.ps1'
        Set-Content $scriptPath '# test'

        try {
            $result = Resolve-LabScriptPath -BaseName 'TestScript' -ScriptDir $tempDir
            $result | Should -Be $scriptPath
        } finally {
            Remove-Item -Recurse -Force $tempDir
        }
    }

    It 'throws when script not found' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('resolve-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempDir -ItemType Directory | Out-Null

        try {
            { Resolve-LabScriptPath -BaseName 'NonExistentScript' -ScriptDir $tempDir } | Should -Throw
        } finally {
            Remove-Item -Recurse -Force $tempDir
        }
    }
}

Describe 'Add-LabRunEvent' {

    It 'adds event to the list with correct properties' {
        $list = New-Object System.Collections.Generic.List[object]
        Add-LabRunEvent -Step 'test-step' -Status 'ok' -Message 'hello' -RunEvents $list

        $list.Count | Should -Be 1
        $list[0].Step | Should -Be 'test-step'
        $list[0].Status | Should -Be 'ok'
        $list[0].Message | Should -Be 'hello'
    }

    It 'sets Time property in ISO 8601 format' {
        $list = New-Object System.Collections.Generic.List[object]
        Add-LabRunEvent -Step 'step' -Status 'start' -RunEvents $list

        $list[0].Time | Should -Not -BeNullOrEmpty
        { [datetime]::Parse($list[0].Time) } | Should -Not -Throw
    }

    It 'defaults Message to empty string' {
        $list = New-Object System.Collections.Generic.List[object]
        Add-LabRunEvent -Step 'step' -Status 'ok' -RunEvents $list

        $list[0].Message | Should -Be ''
    }

    It 'accumulates multiple events' {
        $list = New-Object System.Collections.Generic.List[object]
        Add-LabRunEvent -Step 'step1' -Status 'start' -RunEvents $list
        Add-LabRunEvent -Step 'step2' -Status 'ok' -RunEvents $list
        Add-LabRunEvent -Step 'step3' -Status 'fail' -RunEvents $list

        $list.Count | Should -Be 3
    }

    It 'works with empty list' {
        $list = New-Object System.Collections.Generic.List[object]
        { Add-LabRunEvent -Step 'step' -Status 'ok' -RunEvents $list } | Should -Not -Throw
    }
}

Describe 'Invoke-LabRepoScript' {

    BeforeAll {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('repo-script-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -Path $script:tempDir -ItemType Directory | Out-Null

        # Create a test script that writes output
        $script:testScriptPath = Join-Path $script:tempDir 'TestRepo.ps1'
        Set-Content $script:testScriptPath 'param([string]$Mode) Write-Output "ran:$Mode"'
    }

    AfterAll {
        if (Test-Path $script:tempDir) {
            Remove-Item -Recurse -Force $script:tempDir
        }
    }

    It 'calls the downstream script and logs start/ok events' {
        $list = New-Object System.Collections.Generic.List[object]

        Invoke-LabRepoScript -BaseName 'TestRepo' -ScriptDir $script:tempDir -RunEvents $list

        $list.Count | Should -BeGreaterOrEqual 2
        $list[0].Step | Should -Be 'TestRepo'
        $list[0].Status | Should -Be 'start'
        ($list | Where-Object { $_.Status -eq 'ok' }) | Should -Not -BeNullOrEmpty
    }

    It 'passes Arguments as splat to the script' {
        $list = New-Object System.Collections.Generic.List[object]

        $output = Invoke-LabRepoScript -BaseName 'TestRepo' -Arguments @('-Mode', 'quick') -ScriptDir $script:tempDir -RunEvents $list

        # The script should have received Mode=quick
        # Check start event includes argument text
        $list[0].Message | Should -Match 'Mode'
    }

    It 'logs fail event and rethrows on script error' {
        # Create a failing script
        $failScript = Join-Path $script:tempDir 'FailingScript.ps1'
        Set-Content $failScript 'throw "intentional failure"'

        $list = New-Object System.Collections.Generic.List[object]

        { Invoke-LabRepoScript -BaseName 'FailingScript' -ScriptDir $script:tempDir -RunEvents $list } | Should -Throw

        ($list | Where-Object { $_.Status -eq 'fail' }) | Should -Not -BeNullOrEmpty
    }

    It 'throws when script not found' {
        $list = New-Object System.Collections.Generic.List[object]

        { Invoke-LabRepoScript -BaseName 'NonExistent' -ScriptDir $script:tempDir -RunEvents $list } | Should -Throw
    }
}

Describe 'Get-LabExpectedVMs' {

    It 'returns CoreVMNames from config' {
        $config = @{ Lab = @{ CoreVMNames = @('dc1', 'svr1', 'ws1') } }
        $result = Get-LabExpectedVMs -LabConfig $config

        $result | Should -HaveCount 3
        $result | Should -Contain 'dc1'
        $result | Should -Contain 'svr1'
        $result | Should -Contain 'ws1'
    }

    It 'returns array even for single VM' {
        $config = @{ Lab = @{ CoreVMNames = @('dc1') } }
        $result = Get-LabExpectedVMs -LabConfig $config

        @($result).Count | Should -Be 1
    }

    It 'returns empty array when no VMs configured' {
        $config = @{ Lab = @{ CoreVMNames = @() } }
        $result = Get-LabExpectedVMs -LabConfig $config

        @($result).Count | Should -Be 0
    }
}

Describe 'Get-LabPreflightArgs' {

    It 'returns empty array' {
        $result = Get-LabPreflightArgs
        @($result).Count | Should -Be 0
    }

}

Describe 'Get-LabBootstrapArgs' {

    It 'includes Mode in result' {
        $result = Get-LabBootstrapArgs -Mode 'full'
        $result | Should -Contain '-Mode'
        $result | Should -Contain 'full'
    }

    It 'uses quick mode when specified' {
        $result = Get-LabBootstrapArgs -Mode 'quick'
        $result | Should -Contain 'quick'
    }

    It 'includes -NonInteractive switch when passed' {
        $result = Get-LabBootstrapArgs -Mode 'full' -NonInteractive
        $result | Should -Contain '-NonInteractive'
    }

    It 'includes -AutoFixSubnetConflict switch when passed' {
        $result = Get-LabBootstrapArgs -Mode 'full' -AutoFixSubnetConflict
        $result | Should -Contain '-AutoFixSubnetConflict'
    }

    It 'omits switches when not passed' {
        $result = Get-LabBootstrapArgs -Mode 'full'
        $result | Should -Not -Contain '-NonInteractive'
        $result | Should -Not -Contain '-AutoFixSubnetConflict'
    }

    It 'defaults to full mode' {
        $result = Get-LabBootstrapArgs
        $result | Should -Contain 'full'
    }
}

Describe 'Get-LabDeployArgs' {

    It 'includes Mode in result' {
        $result = Get-LabDeployArgs -Mode 'full'
        $result | Should -Contain '-Mode'
        $result | Should -Contain 'full'
    }

    It 'uses quick mode when specified' {
        $result = Get-LabDeployArgs -Mode 'quick'
        $result | Should -Contain 'quick'
    }

    It 'includes -NonInteractive switch when passed' {
        $result = Get-LabDeployArgs -Mode 'full' -NonInteractive
        $result | Should -Contain '-NonInteractive'
    }

    It 'includes -AutoFixSubnetConflict switch when passed' {
        $result = Get-LabDeployArgs -Mode 'full' -AutoFixSubnetConflict
        $result | Should -Contain '-AutoFixSubnetConflict'
    }

    It 'omits switches when not passed' {
        $result = Get-LabDeployArgs -Mode 'full'
        $result | Should -Not -Contain '-NonInteractive'
        $result | Should -Not -Contain '-AutoFixSubnetConflict'
    }

    It 'defaults to full mode' {
        $result = Get-LabDeployArgs
        $result | Should -Contain 'full'
    }
}

Describe 'Get-LabHealthArgs' {

    It 'returns empty array' {
        $result = Get-LabHealthArgs
        @($result).Count | Should -Be 0
    }

}

Describe 'Import-LabModule' {

    It 'has LabName parameter' {
        $fn = Get-Command Import-LabModule
        $fn.Parameters.ContainsKey('LabName') | Should -Be $true
    }

    It 'imports module and lab when both succeed' {
        $script:moduleCalled = $false
        $script:labImportCalled = $false
        $script:labName = $null

        function Get-Module { param($Name) return $null }
        function Import-Module { param($Name) $script:moduleCalled = $true }
        function Import-Lab { param($Name) $script:labImportCalled = $true; $script:labName = $Name }
        function Get-Lab { return $null }

        Import-LabModule -LabName 'TestLab'

        $script:moduleCalled | Should -Be $true
        $script:labImportCalled | Should -Be $true
        $script:labName | Should -Be 'TestLab'
    }

    It 'throws descriptive error when AutomatedLab module missing' {
        function Get-Module { param($Name) return $null }
        function Import-Module { param($Name) throw 'module not found' }
        function Get-Lab { return $null }

        { Import-LabModule -LabName 'TestLab' } | Should -Throw -ExpectedMessage '*AutomatedLab module is not installed*'
    }

    It 'throws descriptive error when lab not registered' {
        function Get-Module { param($Name) return $null }
        function Import-Module { param($Name) }
        function Import-Lab { param($Name) throw 'lab not found' }
        function Get-Lab { return $null }

        { Import-LabModule -LabName 'TestLab' } | Should -Throw -ExpectedMessage "*TestLab*is not registered*"
    }

    It 'skips re-import when module is loaded and lab matches' {
        $script:importLabCalled = $false

        function Get-Module { param($Name) return [pscustomobject]@{ Name = $Name } }
        function Get-Lab { return [pscustomobject]@{ Name = 'TestLab' } }
        function Import-Lab { $script:importLabCalled = $true }
        function Import-Module { }

        Import-LabModule -LabName 'TestLab'

        $script:importLabCalled | Should -Be $false
    }
}

Describe 'Invoke-LabLogRetention' {

    It 'deletes files older than retention days' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('retention-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempDir -ItemType Directory | Out-Null

        $oldFile = Join-Path $tempDir 'old-log.txt'
        Set-Content $oldFile 'old content'
        (Get-Item $oldFile).LastWriteTime = (Get-Date).AddDays(-30)

        try {
            Invoke-LabLogRetention -RetentionDays 14 -LogRoot $tempDir
            Test-Path $oldFile | Should -Be $false
        } finally {
            if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
        }
    }

    It 'preserves files within retention window' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('retention-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempDir -ItemType Directory | Out-Null

        $recentFile = Join-Path $tempDir 'recent-log.txt'
        Set-Content $recentFile 'recent content'

        try {
            Invoke-LabLogRetention -RetentionDays 14 -LogRoot $tempDir
            Test-Path $recentFile | Should -Be $true
        } finally {
            if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
        }
    }

    It 'does nothing when RetentionDays is 0' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('retention-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -Path $tempDir -ItemType Directory | Out-Null

        $oldFile = Join-Path $tempDir 'old-log.txt'
        Set-Content $oldFile 'old content'
        (Get-Item $oldFile).LastWriteTime = (Get-Date).AddDays(-30)

        try {
            Invoke-LabLogRetention -RetentionDays 0 -LogRoot $tempDir
            Test-Path $oldFile | Should -Be $true
        } finally {
            if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
        }
    }

    It 'does nothing when log root does not exist' {
        $nonExistentDir = Join-Path ([System.IO.Path]::GetTempPath()) ('nonexistent-' + [guid]::NewGuid().ToString('N'))
        { Invoke-LabLogRetention -RetentionDays 14 -LogRoot $nonExistentDir } | Should -Not -Throw
    }

    It 'does nothing when LogRoot is empty' {
        { Invoke-LabLogRetention -RetentionDays 14 -LogRoot '' } | Should -Not -Throw
    }
}

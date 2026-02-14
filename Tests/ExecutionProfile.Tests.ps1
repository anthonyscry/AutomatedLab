# Resolve-LabExecutionProfile tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'Private/Resolve-LabExecutionProfile.ps1'
    . $scriptPath
}

Describe 'Resolve-LabExecutionProfile' {
    It 'uses quick deploy defaults' {
        $result = Resolve-LabExecutionProfile -Operation deploy -Mode quick

        $result.Mode | Should -Be 'quick'
        $result.ReuseLabDefinition | Should -BeTrue
        $result.ReuseInfra | Should -BeTrue
        $result.SkipHeavyValidation | Should -BeTrue
        $result.ParallelChecks | Should -BeTrue
        $result.DestructiveCleanup | Should -BeFalse
    }

    It 'uses full teardown defaults with destructive cleanup' {
        $result = Resolve-LabExecutionProfile -Operation teardown -Mode full

        $result.Mode | Should -Be 'full'
        $result.ReuseLabDefinition | Should -BeFalse
        $result.ReuseInfra | Should -BeFalse
        $result.SkipHeavyValidation | Should -BeFalse
        $result.ParallelChecks | Should -BeTrue
        $result.DestructiveCleanup | Should -BeTrue
    }

    It 'applies precedence defaults then profile then overrides' {
        $tempPath = Join-Path $TestDrive 'execution-profile.json'
        $profileObject = [pscustomobject]@{
            ReuseLabDefinition = $false
            ReuseInfra = $false
            SkipHeavyValidation = $false
            ParallelChecks = $false
            DestructiveCleanup = $true
        }
        $profileObject | ConvertTo-Json | Set-Content -Path $tempPath -Encoding UTF8

        $result = Resolve-LabExecutionProfile -Operation deploy -Mode quick -ProfilePath $tempPath -Overrides @{
            ReuseInfra = $true
            ParallelChecks = $true
        }

        $result.Mode | Should -Be 'quick'
        $result.ReuseLabDefinition | Should -BeFalse
        $result.ReuseInfra | Should -BeTrue
        $result.SkipHeavyValidation | Should -BeFalse
        $result.ParallelChecks | Should -BeTrue
        $result.DestructiveCleanup | Should -BeTrue
    }

    It 'throws when profile path is missing' {
        $missingPath = Join-Path $TestDrive 'missing-profile.json'

        {
            Resolve-LabExecutionProfile -Operation deploy -Mode quick -ProfilePath $missingPath
        } | Should -Throw '*Profile path does not exist*'
    }
}

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
        } | Should -Throw '*Profile file could not be read*'
    }

    It 'reads profile files with literal wildcard characters in filename' {
        $profilePath = Join-Path $TestDrive 'execution-profile[1].json'
        $profileObject = [pscustomobject]@{
            ReuseInfra = $false
        }
        [System.IO.File]::WriteAllText($profilePath, ($profileObject | ConvertTo-Json))

        $result = Resolve-LabExecutionProfile -Operation deploy -Mode quick -ProfilePath $profilePath

        $result.ReuseInfra | Should -BeFalse
    }

    It 'throws a JSON-specific error when profile content is invalid JSON' {
        $profilePath = Join-Path $TestDrive 'invalid-profile.json'
        [System.IO.File]::WriteAllText($profilePath, '{ invalid json }')

        {
            Resolve-LabExecutionProfile -Operation deploy -Mode quick -ProfilePath $profilePath
        } | Should -Throw '*Profile file contains invalid JSON*'
    }

    It 'throws a read-specific error when profile file cannot be read' {
        $profilePath = Join-Path $TestDrive 'unreadable-profile.json'
        [System.IO.File]::WriteAllText($profilePath, '{"ReuseInfra":true}')

        Mock Get-Content {
            throw [System.UnauthorizedAccessException]::new('Access to the path is denied.')
        } -ParameterFilter { $LiteralPath -eq $profilePath }

        {
            Resolve-LabExecutionProfile -Operation deploy -Mode quick -ProfilePath $profilePath
        } | Should -Throw '*Profile file could not be read*'
    }
}

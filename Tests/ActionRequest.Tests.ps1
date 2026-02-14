# Action request normalization and app argument list tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Resolve-LabActionRequest.ps1')
    . (Join-Path $repoRoot 'Private/New-LabAppArgumentList.ps1')
}

Describe 'Resolve-LabActionRequest' {
    It 'preserves setup action and forces full mode' {
        $result = Resolve-LabActionRequest -Action 'setup'

        $result.Action | Should -Be 'setup'
        $result.Mode | Should -Be 'full'
    }

    It 'preserves one-button-setup action and forces full mode' {
        $result = Resolve-LabActionRequest -Action 'one-button-setup'

        $result.Action | Should -Be 'one-button-setup'
        $result.Mode | Should -Be 'full'
    }

    It 'preserves one-button-reset action and forces full mode' {
        $result = Resolve-LabActionRequest -Action 'one-button-reset'

        $result.Action | Should -Be 'one-button-reset'
        $result.Mode | Should -Be 'full'
    }

    It 'preserves blow-away action and forces full mode' {
        $result = Resolve-LabActionRequest -Action 'blow-away'

        $result.Action | Should -Be 'blow-away'
        $result.Mode | Should -Be 'full'
    }

    It 'overrides provided mode for setup action' {
        $result = Resolve-LabActionRequest -Action 'setup' -Mode 'quick'

        $result.Action | Should -Be 'setup'
        $result.Mode | Should -Be 'full'
    }

    It 'keeps deploy with provided quick mode' {
        $result = Resolve-LabActionRequest -Action 'deploy' -Mode 'quick'

        $result.Action | Should -Be 'deploy'
        $result.Mode | Should -Be 'quick'
    }

    It 'passes unknown action through unchanged' {
        $result = Resolve-LabActionRequest -Action 'custom-action' -Mode 'quick'

        $result.Action | Should -Be 'custom-action'
        $result.Mode | Should -Be 'quick'
    }
}

Describe 'New-LabAppArgumentList' {
    It 'builds deterministic argument list including advanced options' {
        $options = @{
            Action = 'deploy'
            Mode = 'quick'
            NonInteractive = $true
            Force = $true
            RemoveNetwork = $true
            DryRun = $true
            ProfilePath = 'C:\Profiles\lab-profile.json'
            DefaultsFile = 'C:\Profiles\defaults.json'
            CoreOnly = $true
        }

        $result = New-LabAppArgumentList -Options $options

        $result | Should -Be @(
            '-Action', 'deploy',
            '-Mode', 'quick',
            '-NonInteractive',
            '-Force',
            '-RemoveNetwork',
            '-DryRun',
            '-ProfilePath', 'C:\Profiles\lab-profile.json',
            '-DefaultsFile', 'C:\Profiles\defaults.json',
            '-CoreOnly'
        )
    }

    It 'omits false switches' {
        $options = @{
            Action = 'teardown'
            Mode = 'full'
            NonInteractive = $false
            Force = $false
            RemoveNetwork = $false
            DryRun = $false
            CoreOnly = $false
        }

        $result = New-LabAppArgumentList -Options $options

        $result | Should -Be @('-Action', 'teardown', '-Mode', 'full')
    }

    It 'treats string false values as false for switches' {
        $options = @{
            Action = 'deploy'
            Mode = 'quick'
            NonInteractive = 'false'
            Force = 'FALSE'
            RemoveNetwork = '0'
            DryRun = 'no'
            CoreOnly = 'off'
        }

        $result = New-LabAppArgumentList -Options $options

        $result | Should -Be @('-Action', 'deploy', '-Mode', 'quick')
    }

    It 'treats string true values as true for switches' {
        $options = @{
            Action = 'deploy'
            Mode = 'quick'
            NonInteractive = 'true'
            Force = 'TRUE'
            RemoveNetwork = '1'
            DryRun = 'yes'
            CoreOnly = 'on'
        }

        $result = New-LabAppArgumentList -Options $options

        $result | Should -Be @(
            '-Action', 'deploy',
            '-Mode', 'quick',
            '-NonInteractive',
            '-Force',
            '-RemoveNetwork',
            '-DryRun',
            '-CoreOnly'
        )
    }
}

Set-StrictMode -Version Latest

Describe 'WPF UI regression guardrails' {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
        $actionsViewModelPath = Join-Path $repoRoot 'ViewModels/ActionsViewModel.cs'
        $settingsViewPath = Join-Path $repoRoot 'Views/SettingsView.xaml'

        $actionsViewModelSource = Get-Content -Path $actionsViewModelPath -Raw
        $settingsViewSource = Get-Content -Path $settingsViewPath -Raw
    }

    It 'keeps deployment state active when cancellation is requested' {
        $cancelMethod = [regex]::Match(
            $actionsViewModelSource,
            'private\s+Task\s+CancelDeploymentAsync\(\)\s*\{(?<body>[\s\S]*?)\n\s*\}',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )

        $cancelMethod.Success | Should -BeTrue
        $cancelMethod.Groups['body'].Value | Should -Not -Match 'IsDeploying\s*=\s*false\s*;'
    }

    It 'disables cancel command after cancellation is requested' {
        $actionsViewModelSource | Should -Match 'CancelDeployCommand\s*=\s*new\s+AsyncCommand\(CancelDeploymentAsync,\s*\(\)\s*=>\s*IsDeploying\s*&&\s*!IsCancellationRequested\)'
    }

    It 'adds deployment lifecycle telemetry markers for triage' {
        $actionsViewModelSource | Should -Match 'TrackDeploymentEvent\("deploy_start"'
        $actionsViewModelSource | Should -Match 'TrackDeploymentEvent\("cancel_requested"'
        $actionsViewModelSource | Should -Match 'TrackDeploymentEvent\("deploy_completed"'
    }

    It 'loads settings for new lab dialog defaults' {
        $actionsViewModelSource | Should -Match 'new\s+NewLabDialog\(AppSettingsStore\.LoadOrDefault\(\)\)'
    }

    It 'binds switch type with SelectedValue round-trip' {
        $settingsViewSource | Should -Match 'SelectedValuePath="Content"'
        $settingsViewSource | Should -Match 'SelectedValue="\{Binding\s+DefaultSwitchType\}"'
    }
}

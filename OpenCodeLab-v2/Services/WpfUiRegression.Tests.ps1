Set-StrictMode -Version Latest

Describe 'WPF UI regression guardrails' {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
        $actionsViewModelPath = Join-Path $repoRoot 'ViewModels/ActionsViewModel.cs'
        $dashboardViewModelPath = Join-Path $repoRoot 'ViewModels/DashboardViewModel.cs'
        $dashboardViewPath = Join-Path $repoRoot 'Views/DashboardView.xaml'
        $settingsViewPath = Join-Path $repoRoot 'Views/SettingsView.xaml'
        $newLabDialogPath = Join-Path $repoRoot 'Views/NewLabDialog.xaml.cs'

        $actionsViewModelSource = Get-Content -Path $actionsViewModelPath -Raw
        $dashboardViewModelSource = Get-Content -Path $dashboardViewModelPath -Raw
        $dashboardViewSource = Get-Content -Path $dashboardViewPath -Raw
        $settingsViewSource = Get-Content -Path $settingsViewPath -Raw
        $newLabDialogSource = Get-Content -Path $newLabDialogPath -Raw
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

    It 'wraps deployment credential helper text to avoid clipping' {
        $newLabDialogSource | Should -Match 'var policyHint = new TextBlock\s*\{[\s\S]*?TextWrapping\s*=\s*TextWrapping\.Wrap'
        $newLabDialogSource | Should -Match 'var envHint = new TextBlock\s*\{[\s\S]*?TextWrapping\s*=\s*TextWrapping\.Wrap'
    }

    It 'adds dashboard action for removing selected VM only' {
        $dashboardViewModelSource | Should -Match 'public\s+AsyncCommand\s+RemoveSelectedVMCommand\s*\{\s*get;\s*\}'
        $dashboardViewModelSource | Should -Match 'RemoveSelectedVMCommand\s*=\s*new\s+AsyncCommand\(RemoveSelectedVMAsync,\s*\(\)\s*=>\s*SelectedVM\s*!\=\s*null\)'
        $dashboardViewModelSource | Should -Match '_hvService\.RemoveVMAsync\(vmName,\s*deleteDisk:\s*true\)'
        $dashboardViewSource | Should -Match 'Command="\{Binding\s+RemoveSelectedVMCommand\}"'
    }
}

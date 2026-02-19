Set-StrictMode -Version Latest

Describe 'Dashboard frame' {
    BeforeAll {
        $formatterPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Presentation.Console/Public/Format-LabDashboardFrame.ps1'
        . $formatterPath
    }

    It 'renders required sections' {
        $frame = Format-LabDashboardFrame -Status @{ Lock = 'free'; Profile = 'default' } -Events @() -Diagnostics @()

        $frame | Should -Match 'LOCK'
        $frame | Should -Match 'CORE STATUS'
        $frame | Should -Match 'EVENT STREAM'
        $frame | Should -Match 'DIAGNOSTICS'
    }

    It 'falls back to unknown for missing lock and profile values' {
        $frame = Format-LabDashboardFrame -Status @{} -Events @() -Diagnostics @()

        $frame | Should -Match '(?m)^LOCK: unknown$'
        $frame | Should -Match '(?m)^PROFILE: unknown$'
    }

    It 'falls back to unknown for blank lock and profile values' {
        $frame = Format-LabDashboardFrame -Status @{ Lock = ' '; Profile = '' } -Events @() -Diagnostics @()

        $frame | Should -Match '(?m)^LOCK: unknown$'
        $frame | Should -Match '(?m)^PROFILE: unknown$'
    }

    It 'handles null status events and diagnostics' {
        $frame = Format-LabDashboardFrame -Status $null -Events $null -Diagnostics $null

        $frame | Should -Match '(?m)^LOCK: unknown$'
        $frame | Should -Match '(?m)^PROFILE: unknown$'
        $frame | Should -Match '(?m)^EVENT STREAM \(0\)$'
        $frame | Should -Match '(?m)^DIAGNOSTICS \(0\)$'
    }

    It 'shows explicit lock profile and non-empty counts' {
        $events = @('event-1', 'event-2', 'event-3')
        $diagnostics = @('diag-1', 'diag-2')

        $frame = Format-LabDashboardFrame -Status @{ Lock = 'locked'; Profile = 'safe-mode' } -Events $events -Diagnostics $diagnostics

        $frame | Should -Match '(?m)^LOCK: locked$'
        $frame | Should -Match '(?m)^PROFILE: safe-mode$'
        $frame | Should -Match '(?m)^EVENT STREAM \(3\)$'
        $frame | Should -Match '(?m)^DIAGNOSTICS \(2\)$'
    }
}

Describe 'Show dashboard action' {
    BeforeAll {
        $formatterPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Presentation.Console/Public/Format-LabDashboardFrame.ps1'
        $actionPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Presentation.Console/Public/Show-LabDashboardAction.ps1'

        . $formatterPath
        . $actionPath
    }

    It 'returns formatter output and does not render by default' {
        Mock -CommandName Format-LabDashboardFrame -MockWith { return 'frame-from-formatter' }
        Mock -CommandName Write-Host

        $result = Show-LabDashboardAction -Status @{ Lock = 'free'; Profile = 'default' } -Events @() -Diagnostics @()

        $result | Should -Be 'frame-from-formatter'
        Assert-MockCalled -CommandName Format-LabDashboardFrame -Times 1 -Exactly
        Assert-MockCalled -CommandName Write-Host -Times 0 -Exactly
    }

    It 'returns formatter output unchanged and renders when requested' {
        Mock -CommandName Format-LabDashboardFrame -MockWith { return 'frame-for-render' }
        Mock -CommandName Write-Host

        $result = Show-LabDashboardAction -Status @{ Lock = 'free'; Profile = 'default' } -Events @() -Diagnostics @() -Render

        $result | Should -Be 'frame-for-render'
        Assert-MockCalled -CommandName Format-LabDashboardFrame -Times 1 -Exactly
        Assert-MockCalled -CommandName Write-Host -Times 1 -Exactly -ParameterFilter { $Object -eq 'frame-for-render' }
    }
}

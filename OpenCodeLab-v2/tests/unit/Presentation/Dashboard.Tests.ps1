Set-StrictMode -Version Latest

Describe 'Dashboard frame' {
    BeforeAll {
        $formatterPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Presentation.Console/Public/Format-LabDashboardFrame.ps1'

        if (Test-Path -Path $formatterPath) {
            . $formatterPath
        }
    }

    It 'renders required sections' {
        $frame = Format-LabDashboardFrame -Status @{ Lock = 'free'; Profile = 'default' } -Events @() -Diagnostics @()

        $frame | Should -Match 'LOCK'
        $frame | Should -Match 'CORE STATUS'
        $frame | Should -Match 'EVENT STREAM'
        $frame | Should -Match 'DIAGNOSTICS'
    }
}

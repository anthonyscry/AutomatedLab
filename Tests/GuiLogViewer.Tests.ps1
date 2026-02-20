# Pester tests for GUI Log Viewer (LOGV-01, LOGV-02, LOGV-03)
# Covers run history XAML elements, session log preservation, DataGrid columns,
# run history wiring, filter logic, and export logic.

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $logsViewXamlPath = Join-Path $repoRoot 'GUI/Views/LogsView.xaml'
    $guiScriptPath    = Join-Path $repoRoot 'GUI/Start-OpenCodeLabGUI.ps1'

    # Read source files once as raw strings for structural tests
    $LogsViewXaml = Get-Content -Path $logsViewXamlPath -Raw
    $GuiSource    = Get-Content -Path $guiScriptPath -Raw
}

Describe 'LogsView.xaml - Run History Elements (LOGV-01)' {

    It 'contains runHistoryGrid DataGrid element' {
        $LogsViewXaml | Should -Match 'x:Name="runHistoryGrid"'
    }

    It 'contains cmbRunHistoryFilter ComboBox element' {
        $LogsViewXaml | Should -Match 'x:Name="cmbRunHistoryFilter"'
    }

    It 'contains btnRefreshHistory Button element' {
        $LogsViewXaml | Should -Match 'x:Name="btnRefreshHistory"'
    }

    It 'contains btnExportHistory Button element' {
        $LogsViewXaml | Should -Match 'x:Name="btnExportHistory"'
    }

    It 'contains txtNoHistory empty state TextBlock' {
        $LogsViewXaml | Should -Match 'x:Name="txtNoHistory"'
    }

    It 'contains a DataGrid element tag' {
        $LogsViewXaml | Should -Match '<DataGrid\s'
    }

    It 'contains Run History header text' {
        $LogsViewXaml | Should -Match 'Run History'
    }
}

Describe 'LogsView.xaml - Session Log Elements Preserved' {

    It 'contains cmbLogFilter ComboBox element' {
        $LogsViewXaml | Should -Match 'x:Name="cmbLogFilter"'
    }

    It 'contains btnClearLogs Button element' {
        $LogsViewXaml | Should -Match 'x:Name="btnClearLogs"'
    }

    It 'contains logScroller ScrollViewer element' {
        $LogsViewXaml | Should -Match 'x:Name="logScroller"'
    }

    It 'contains txtLogOutput TextBlock element' {
        $LogsViewXaml | Should -Match 'x:Name="txtLogOutput"'
    }

    It 'contains Session Log header text' {
        $LogsViewXaml | Should -Match 'Session Log'
    }
}

Describe 'LogsView.xaml - DataGrid Columns (LOGV-01)' {

    It 'contains RunId column header' {
        $LogsViewXaml | Should -Match 'Header="RunId"'
    }

    It 'contains Action column header' {
        $LogsViewXaml | Should -Match 'Header="Action"'
    }

    It 'contains Success column header' {
        $LogsViewXaml | Should -Match 'Header="Success"'
    }

    It 'contains Ended UTC column header' {
        $LogsViewXaml | Should -Match 'Header="Ended \(UTC\)"'
    }

    It 'contains Mode column header' {
        $LogsViewXaml | Should -Match 'Header="Mode"'
    }

    It 'contains Error column header' {
        $LogsViewXaml | Should -Match 'Header="Error"'
    }
}

Describe 'Initialize-LogsView - Run History Wiring (LOGV-01)' {

    It 'source calls Get-LabRunHistory' {
        $GuiSource | Should -Match 'Get-LabRunHistory'
    }

    It 'source resolves runHistoryGrid via FindName' {
        $GuiSource | Should -Match "FindName\(.+runHistoryGrid.+\)"
    }

    It 'source resolves cmbRunHistoryFilter via FindName' {
        $GuiSource | Should -Match "FindName\(.+cmbRunHistoryFilter.+\)"
    }

    It 'source resolves btnExportHistory via FindName' {
        $GuiSource | Should -Match "FindName\(.+btnExportHistory.+\)"
    }

    It 'source resolves txtNoHistory via FindName' {
        $GuiSource | Should -Match "FindName\(.+txtNoHistory.+\)"
    }
}

Describe 'Initialize-LogsView - Filter Logic (LOGV-02)' {

    It 'source wires cmbRunHistoryFilter with SelectionChanged event' {
        $GuiSource | Should -Match 'cmbRunHistoryFilter\.Add_SelectionChanged'
    }

    It 'source contains deploy filter value' {
        $GuiSource | Should -Match "'deploy'"
    }

    It 'source contains teardown filter value' {
        $GuiSource | Should -Match "'teardown'"
    }

    It 'source contains snapshot filter value' {
        $GuiSource | Should -Match "'snapshot'"
    }

    It 'source references .Action property for filter comparison' {
        $GuiSource | Should -Match '\.Action'
    }
}

Describe 'Initialize-LogsView - Export Logic (LOGV-03)' {

    It 'source references SaveFileDialog for export' {
        $GuiSource | Should -Match 'SaveFileDialog'
    }

    It 'source uses Set-Content to write export file' {
        $GuiSource | Should -Match 'Set-Content'
    }

    It 'source wires btnExportHistory with Add_Click handler' {
        $GuiSource | Should -Match '\$btnExportHistory\.Add_Click'
    }

    It 'source uses tab delimiter in export format' {
        $GuiSource | Should -Match '`t'
    }

    It 'source references .txt file filter for export dialog' {
        $GuiSource | Should -Match '\*\.txt'
    }
}

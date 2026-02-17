# Pester tests for WPF GUI XAML files and theme resource dictionaries

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $guiRoot  = Join-Path $repoRoot 'GUI'
}

Describe 'WPF GUI XAML Files' {

    $xamlFiles = @(
        'MainWindow.xaml'
        'Themes/Dark.xaml'
        'Themes/Light.xaml'
        'Views/DashboardView.xaml'
        'Views/ActionsView.xaml'
        'Views/CustomizeView.xaml'
        'Views/LogsView.xaml'
        'Views/SettingsView.xaml'
        'Components/VMCard.xaml'
    )

    foreach ($relativePath in $xamlFiles) {
        It "<relativePath> exists and is valid XML" -TestCases @{ relativePath = $relativePath } {
            $fullPath = Join-Path $guiRoot $relativePath
            $fullPath | Should -Exist
            { [xml](Get-Content -Raw -Path $fullPath) } | Should -Not -Throw
        }
    }

    It 'Start-OpenCodeLabGUI.ps1 exists and has no syntax errors' {
        $scriptPath = Join-Path $guiRoot 'Start-OpenCodeLabGUI.ps1'
        $scriptPath | Should -Exist

        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }
}

Describe 'Theme Resource Dictionaries' {

    $requiredColorKeys = @(
        'BackgroundColor'
        'CardBackgroundColor'
        'AccentColor'
        'TextPrimaryColor'
        'TextSecondaryColor'
        'BorderColor'
        'SuccessColor'
        'ErrorColor'
        'WarningColor'
    )

    BeforeAll {
        $ns = @{ x = 'http://schemas.microsoft.com/winfx/2006/xaml' }

        $darkPath  = Join-Path $guiRoot 'Themes/Dark.xaml'
        $lightPath = Join-Path $guiRoot 'Themes/Light.xaml'

        # Helper: extract all x:Key values from a XAML resource dictionary
        function Get-XamlKeys {
            param([string]$Path)
            [xml]$doc = Get-Content -Raw -Path $Path
            $nsMgr = [System.Xml.XmlNamespaceManager]::new($doc.NameTable)
            $nsMgr.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
            $nodes = $doc.SelectNodes('//*[@x:Key]', $nsMgr)
            $nodes | ForEach-Object { $_.GetAttribute('Key', 'http://schemas.microsoft.com/winfx/2006/xaml') }
        }

        $darkKeys  = @(Get-XamlKeys -Path $darkPath)
        $lightKeys = @(Get-XamlKeys -Path $lightPath)
    }

    foreach ($key in $requiredColorKeys) {
        It "Dark theme defines required key '$key'" -TestCases @{ key = $key } {
            $darkKeys | Should -Contain $key
        }
    }

    foreach ($key in $requiredColorKeys) {
        It "Light theme defines required key '$key'" -TestCases @{ key = $key } {
            $lightKeys | Should -Contain $key
        }
    }

    It 'Both themes define the same set of x:Key names' {
        $sortedDark  = $darkKeys  | Sort-Object
        $sortedLight = $lightKeys | Sort-Object
        $sortedDark | Should -Be $sortedLight
    }
}

Describe 'GUI Entry Point Syntax' {

    It 'Start-OpenCodeLabGUI.ps1 has no parse errors' {
        $scriptPath = Join-Path $guiRoot 'Start-OpenCodeLabGUI.ps1'
        $scriptPath | Should -Exist

        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }
}

Describe 'GUI Log Management' {

    BeforeAll {
        $scriptPath = Join-Path $guiRoot 'Start-OpenCodeLabGUI.ps1'
        $scriptContent = Get-Content -Raw -Path $scriptPath
    }

    It 'Declares LogEntriesMaxCount constant' {
        $scriptContent | Should -Match '\$script:LogEntriesMaxCount\s*=\s*\d+'
    }

    It 'LogEntriesMaxCount is set to 2000' {
        $scriptContent | Should -Match '\$script:LogEntriesMaxCount\s*=\s*2000'
    }

    It 'Add-LogEntry function trims entries when cap exceeded' {
        $scriptContent | Should -Match 'while\s*\(\s*\$script:LogEntries\.Count\s*-gt\s*\$script:LogEntriesMaxCount\s*\)'
        $scriptContent | Should -Match '\$script:LogEntries\.RemoveAt\(0\)'
    }

    It 'Render-LogEntries uses Application.Current.FindResource instead of mainWindow.FindResource' {
        $scriptContent | Should -Match '\[System\.Windows\.Application\]::Current\.FindResource\(\$brushKey\)'
        $scriptContent | Should -Not -Match '\$mainWindow\.FindResource\(\$brushKey\)'
    }
}

Describe 'GUI Settings Persistence' {

    BeforeAll {
        $scriptPath = Join-Path $guiRoot 'Start-OpenCodeLabGUI.ps1'
        $scriptContent = Get-Content -Raw -Path $scriptPath
    }

    It 'Settings Save handler validates subnet format' {
        $scriptContent | Should -Match 'Invalid subnet format.*CIDR notation'
    }

    It 'Settings Save handler persists Network settings to config.json' {
        $scriptContent | Should -Match '\$networkSettings\s*=\s*\[PSCustomObject\]@\{'
        $scriptContent | Should -Match 'SwitchName\s*='
        $scriptContent | Should -Match 'Subnet\s*='
        $scriptContent | Should -Match 'GatewayIP\s*='
    }

    It 'Settings Save handler persists AdminUsername to config.json' {
        $scriptContent | Should -Match '\$configJson\.AdminUsername\s*=\s*\$adminUser'
    }

    It 'Settings Save handler persists AdminUsername to gui-settings.json' {
        $scriptContent | Should -Match "Save-GuiSettings"
        $scriptContent | Should -Match "\`$guiSettings\['AdminUsername'\]"
    }

    It 'Initialize-SettingsView loads from config.json when GlobalLabConfig unavailable' {
        $scriptContent | Should -Match 'if\s*\(-not\s*\(Test-Path\s+variable:GlobalLabConfig\)\)'
        $scriptContent | Should -Match '\$configJson\.Network'
        $scriptContent | Should -Match '\$configJson\.AdminUsername'
    }

    It 'Save-GuiSettings wraps Set-Content in try/catch' {
        $scriptContent | Should -Match 'catch\s*\{\s*Write-Warning.*Failed to save GUI settings'
    }

    It 'Get-GuiSettings returns empty hashtable on corrupt JSON' {
        $scriptContent | Should -Match 'catch\s*\{\s*Write-Warning.*Failed to read GUI settings'
    }
}

Describe 'GUI-CLI Action Parity' {

    BeforeAll {
        $guiScript = Join-Path $guiRoot 'Start-OpenCodeLabGUI.ps1'
        $cliScript = Join-Path (Split-Path -Parent $guiRoot) 'OpenCodeLab-App.ps1'
    }

    It 'WPF GUI actions list matches CLI ValidateSet (excluding menu)' {
        # Extract CLI actions from ValidateSet
        $cliContent = Get-Content -Raw -Path $cliScript
        $cliActions = @()
        if ($cliContent -match "ValidateSet\(([\s\S]*?)\)") {
            $cliActions = @([regex]::Matches($matches[1], "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }) |
                Where-Object { $_ -ne 'menu' } | Sort-Object
        }

        # Extract GUI actions from Initialize-ActionsView
        $guiContent = Get-Content -Raw -Path $guiScript
        $guiActions = @()
        if ($guiContent -match '\$actions\s*=\s*@\(([\s\S]*?)\)') {
            $guiActions = @([regex]::Matches($matches[1], "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }) |
                Sort-Object
        }

        $cliActions.Count | Should -BeGreaterThan 0 -Because 'CLI should have action list'
        $guiActions.Count | Should -BeGreaterThan 0 -Because 'GUI should have action list'
        $guiActions | Should -Be $cliActions -Because 'GUI and CLI action lists should match'
    }

    It 'GUI defines descriptions for all actions' {
        $guiContent = Get-Content -Raw -Path $guiScript

        # Extract action list
        $guiActions = @()
        if ($guiContent -match '\$actions\s*=\s*@\(([\s\S]*?)\)') {
            $guiActions = @([regex]::Matches($matches[1], "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        }

        # Extract actionDescriptions hashtable
        $descriptionBlock = ''
        if ($guiContent -match '\$actionDescriptions\s*=\s*@\{([\s\S]*?)\n\s*\}') {
            $descriptionBlock = $matches[1]
        }

        $guiActions.Count | Should -BeGreaterThan 0
        $descriptionBlock | Should -Not -BeNullOrEmpty

        foreach ($action in $guiActions) {
            $descriptionBlock | Should -Match "'$action'\s*=" -Because "Action '$action' should have a description"
        }
    }
}

Describe 'Timer Lifecycle' {

    BeforeAll {
        $guiContent = Get-Content -Raw -Path (Join-Path $guiRoot 'Start-OpenCodeLabGUI.ps1')
    }

    It 'VMPollTimer is stopped when leaving Dashboard view' {
        $guiContent | Should -Match 'VMPollTimer.*Stop'
    }

    It 'Window Closing handler is registered' {
        $guiContent | Should -Match 'Add_Closing'
    }
}

Describe 'Customize View Hardening' {

    BeforeAll {
        $guiContent = Get-Content -Raw -Path (Join-Path $guiRoot 'Start-OpenCodeLabGUI.ps1')
    }

    It 'validates VM names are non-empty before template save' {
        $guiContent | Should -Match 'All VMs must have a name'
    }

    It 'Initialize-CustomizeView has error handling' {
        $guiContent | Should -Match 'Customize view failed to initialize'
    }
}

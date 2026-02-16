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

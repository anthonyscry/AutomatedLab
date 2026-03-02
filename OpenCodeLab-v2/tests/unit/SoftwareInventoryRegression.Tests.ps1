Set-StrictMode -Version Latest

Describe 'Software Inventory - Model Structure' {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
        $modelPath = Join-Path $repoRoot 'Models\InstalledSoftware.cs'
        $script:modelSource = Get-Content -Path $modelPath -Raw
    }

    It 'has InstalledSoftware class with Name property' {
        $script:modelSource | Should -Match 'public\s+string\s+Name\s*\{'
    }

    It 'has Version property' {
        $script:modelSource | Should -Match 'public\s+string\??\s+Version\s*\{'
    }

    It 'has Publisher property' {
        $script:modelSource | Should -Match 'public\s+string\??\s+Publisher\s*\{'
    }

    It 'has InstallDate property' {
        $script:modelSource | Should -Match 'public\s+DateTime\??\s+InstallDate\s*\{'
    }

    It 'has ScanResult.VMName property' {
        $script:modelSource | Should -Match 'public\s+string\s+VMName\s*\{'
    }

    It 'has ScanResult.Software list' {
        $script:modelSource | Should -Match 'public\s+List<InstalledSoftware>\s+Software\s*\{'
    }

    It 'has ScanResult.ScannedAt property' {
        $script:modelSource | Should -Match 'public\s+DateTime\s+ScannedAt\s*\{'
    }

    It 'has ScanResult.Success property' {
        $script:modelSource | Should -Match 'public\s+bool\s+Success\s*\{'
    }

    It 'uses OpenCodeLab.Models namespace' {
        $script:modelSource | Should -Match 'namespace\s+OpenCodeLab\.Models'
    }
}

Describe 'Software Inventory - ViewModel Commands' {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
        $vmPath = Join-Path $repoRoot 'ViewModels\SoftwareInventoryViewModel.cs'
        $script:vmSource = Get-Content -Path $vmPath -Raw
    }

    It 'has ScanAllCommand' {
        $script:vmSource | Should -Match 'ScanAllCommand'
    }

    It 'has ScanSelectedCommand' {
        $script:vmSource | Should -Match 'ScanSelectedCommand'
    }

    It 'has CancelScanCommand' {
        $script:vmSource | Should -Match 'CancelScanCommand'
    }

    It 'has ExportCsvCommand' {
        $script:vmSource | Should -Match 'ExportCsvCommand'
    }

    It 'has ExportJsonCommand' {
        $script:vmSource | Should -Match 'ExportJsonCommand'
    }

    It 'has ClearCommand' {
        $script:vmSource | Should -Match 'ClearCommand'
    }

    It 'inherits from ObservableObject' {
        $script:vmSource | Should -Match 'class\s+SoftwareInventoryViewModel\s*:\s*ObservableObject'
    }

    It 'has CancellationTokenSource field' {
        $script:vmSource | Should -Match 'CancellationTokenSource'
    }
}

Describe 'Software Inventory - View Bindings' {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
        $viewPath = Join-Path $repoRoot 'Views\SoftwareInventoryView.xaml'
        $script:viewSource = Get-Content -Path $viewPath -Raw
    }

    It 'binds ScanAllCommand' {
        $script:viewSource | Should -Match 'ScanAllCommand'
    }

    It 'binds ScanSelectedCommand' {
        $script:viewSource | Should -Match 'ScanSelectedCommand'
    }

    It 'binds CancelScanCommand' {
        $script:viewSource | Should -Match 'CancelScanCommand'
    }

    It 'binds ExportCsvCommand' {
        $script:viewSource | Should -Match 'ExportCsvCommand'
    }

    It 'binds ExportJsonCommand' {
        $script:viewSource | Should -Match 'ExportJsonCommand'
    }

    It 'binds ClearCommand' {
        $script:viewSource | Should -Match 'ClearCommand'
    }

    It 'binds SearchText' {
        $script:viewSource | Should -Match 'SearchText'
    }

    It 'binds IsGroupedView' {
        $script:viewSource | Should -Match 'IsGroupedView'
    }

    It 'uses StaticResource brushes' {
        $script:viewSource | Should -Match 'StaticResource'
    }
}


Describe 'Software Inventory - Navigation Integration' {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
        $mainXamlPath = Join-Path $repoRoot 'Views\MainWindow.xaml'
        $mainCsPath = Join-Path $repoRoot 'Views\MainWindow.xaml.cs'
        $script:mainXamlSource = Get-Content -Path $mainXamlPath -Raw
        $script:mainCsSource = Get-Content -Path $mainCsPath -Raw
    }

    It 'has SoftwareInventory tag on sidebar button' {
        $script:mainXamlSource | Should -Match 'Tag="SoftwareInventory"'
    }

    It 'has SoftwareInventoryView element in content area' {
        $script:mainXamlSource | Should -Match 'x:Name="SoftwareInventoryView"'
    }

    It 'has NavigateTo case for SoftwareInventory' {
        $script:mainCsSource | Should -Match 'case "SoftwareInventory"'
    }

    It 'instantiates SoftwareInventoryViewModel' {
        $script:mainCsSource | Should -Match 'new\s+SoftwareInventoryViewModel\(\)'
    }

    It 'sets SoftwareInventoryView DataContext' {
        $script:mainCsSource | Should -Match 'SoftwareInventoryView\.DataContext\s*=\s*SoftwareInventoryVM'
    }

    It 'resets SoftwareInventoryButton style' {
        $script:mainCsSource | Should -Match 'SoftwareInventoryButton\.Background\s*=\s*Brushes\.Transparent'
    }
}

Describe 'Software Inventory - Service Patterns' {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
        $servicePath = Join-Path $repoRoot 'Services\SoftwareInventoryService.cs'
        $script:serviceSource = Get-Content -Path $servicePath -Raw
    }

    It 'uses ProcessStartInfo for PowerShell execution' {
        $script:serviceSource | Should -Match 'ProcessStartInfo'
    }

    It 'does NOT reference System.Management.Automation' {
        $script:serviceSource | Should -Not -Match 'System\.Management\.Automation'
    }

    It 'has SaveResultsAsync method' {
        $script:serviceSource | Should -Match 'SaveResultsAsync'
    }

    It 'has LoadResultsAsync method' {
        $script:serviceSource | Should -Match 'LoadResultsAsync'
    }
}

Describe 'Software Inventory - Export Service' {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
        $exportPath = Join-Path $repoRoot 'Services\ExportService.cs'
        $script:exportSource = Get-Content -Path $exportPath -Raw
    }

    It 'has ExportToCsvAsync method' {
        $script:exportSource | Should -Match 'ExportToCsvAsync'
    }

    It 'has ExportToJsonAsync method' {
        $script:exportSource | Should -Match 'ExportToJsonAsync'
    }

    It 'uses System.Text.Json' {
        $script:exportSource | Should -Match 'System\.Text\.Json'
    }
}

Describe 'Software Inventory - PowerShell Script' {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
        $scriptPath = Join-Path $repoRoot 'Get-VMSoftwareInventory.ps1'
        $script:scriptSource = Get-Content -Path $scriptPath -Raw
    }

    It 'has param block with VMName' {
        $script:scriptSource | Should -Match 'param\s*\('
        $script:scriptSource | Should -Match 'VMName'
    }

    It 'has LabName parameter' {
        $script:scriptSource | Should -Match 'LabName'
    }

    It 'queries 64-bit registry path' {
        $script:scriptSource | Should -BeLike '*SOFTWARE*Microsoft*Windows*CurrentVersion*Uninstall*'
    }

    It 'queries Wow6432Node registry path' {
        $script:scriptSource | Should -Match 'Wow6432Node'
    }

    It 'outputs JSON via ConvertTo-Json' {
        $script:scriptSource | Should -Match 'ConvertTo-Json'
    }

    It 'has zero parse errors' {
        $sp = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'Get-VMSoftwareInventory.ps1'
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($sp, [ref]$null, [ref]$errors) | Out-Null
        $errors.Count | Should -Be 0
    }
}

Describe 'Software Inventory - Forbidden Patterns' {
    BeforeAll {
        $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
        $newFiles = @(
            'Models\InstalledSoftware.cs',
            'Services\SoftwareInventoryService.cs',
            'Services\ExportService.cs',
            'ViewModels\SoftwareInventoryViewModel.cs',
            'Views\SoftwareInventoryView.xaml',
            'Views\SoftwareInventoryView.xaml.cs'
        )
        $script:allNewSource = ($newFiles | ForEach-Object {
            $filePath = Join-Path $repoRoot $_
            if (Test-Path $filePath) { Get-Content -Path $filePath -Raw }
        }) -join [System.Environment]::NewLine

        $csprojPath = Join-Path $repoRoot 'OpenCodeLab-V2.csproj'
        $script:csprojSource = Get-Content -Path $csprojPath -Raw
    }

    It 'does NOT use Newtonsoft.Json in any new file' {
        $script:allNewSource | Should -Not -Match 'Newtonsoft\.Json'
    }

    It 'does NOT reference System.Management.Automation in csproj' {
        $script:csprojSource | Should -Not -Match 'System\.Management\.Automation'
    }

    It 'does NOT use hardcoded Foreground/Background hex colors in View' {
        $viewPath = Join-Path $repoRoot 'Views\SoftwareInventoryView.xaml'
        $viewSource = Get-Content -Path $viewPath -Raw
        $hexColors = [regex]::Matches($viewSource, 'Foreground="#[0-9A-Fa-f]+"|Background="#[0-9A-Fa-f]+"')
        $hexColors.Count | Should -Be 0
    }
}

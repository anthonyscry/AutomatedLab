# WPF GUI Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the WinForms launcher GUI with a full WPF management dashboard featuring VM cards, network topology, actions panel, log viewer, settings editor, and switchable dark/light themes.

**Architecture:** PowerShell + WPF with external `.xaml` files loaded via `[System.Windows.Markup.XamlReader]`. All logic stays in `.ps1` files. Background runspaces handle Hyper-V polling and action execution to keep the UI responsive. Existing `Private/` helpers and `Public/` functions are reused unchanged.

**Tech Stack:** PowerShell 5.1+, WPF (PresentationFramework), XAML, DispatcherTimer, PowerShell Runspaces

---

### Task 1: Entry Point and XAML Loader

**Files:**
- Create: `GUI/Start-OpenCodeLabGUI.ps1`

**Step 1: Create the entry point script**

Create `GUI/Start-OpenCodeLabGUI.ps1` with WPF assembly loading, function sourcing, and a reusable XAML loader function:

```powershell
#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load WPF assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$script:GuiRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:RepoRoot = Split-Path -Parent $script:GuiRoot

# Source all Private and Public functions (same pattern as OpenCodeLab-App.ps1)
$privateFunctions = Get-ChildItem -Path (Join-Path $script:RepoRoot 'Private') -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue
$publicFunctions = Get-ChildItem -Path (Join-Path $script:RepoRoot 'Public') -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue

foreach ($func in @($privateFunctions) + @($publicFunctions)) {
    . $func.FullName
}

# Source Lab-Config.ps1 for $GlobalLabConfig
$configPath = Join-Path $script:RepoRoot 'Lab-Config.ps1'
if (Test-Path $configPath) {
    try { . $configPath } catch {
        if (-not (Test-Path variable:GlobalLabConfig)) { throw $_ }
    }
    $ErrorActionPreference = 'Stop'
}

function Import-XamlFile {
    <#
    .SYNOPSIS
        Loads a XAML file and returns the parsed WPF element.
    .PARAMETER Path
        Full path to the .xaml file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "XAML file not found: $Path"
    }

    $xamlContent = Get-Content -Path $Path -Raw
    # Remove x:Class attribute if present (not supported in XamlReader)
    $xamlContent = $xamlContent -replace 'x:Class="[^"]*"', ''
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xamlContent))
    $element = [System.Windows.Markup.XamlReader]::Load($reader)
    return $element
}

# GUI settings persistence
$script:GuiSettingsPath = Join-Path $script:RepoRoot '.planning' 'gui-settings.json'

function Get-GuiSettings {
    if (Test-Path $script:GuiSettingsPath) {
        try {
            return Get-Content -Raw -Path $script:GuiSettingsPath | ConvertFrom-Json
        }
        catch { }
    }
    return [PSCustomObject]@{ Theme = 'Dark' }
}

function Save-GuiSettings {
    param([PSCustomObject]$Settings)
    $dir = Split-Path -Parent $script:GuiSettingsPath
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    $Settings | ConvertTo-Json | Set-Content -Path $script:GuiSettingsPath -Encoding UTF8
}
```

**Step 2: Verify the script loads without errors**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& 'C:\projects\AutomatedLab\GUI\Start-OpenCodeLabGUI.ps1'"`
Expected: Script loads and exits (no window yet, no errors)

**Step 3: Commit**

```bash
git add GUI/Start-OpenCodeLabGUI.ps1
git commit -m "feat(gui): add WPF entry point with XAML loader"
```

---

### Task 2: Theme Resource Dictionaries

**Files:**
- Create: `GUI/Themes/Dark.xaml`
- Create: `GUI/Themes/Light.xaml`

**Step 1: Create the Dark theme**

Create `GUI/Themes/Dark.xaml`:

```xml
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

    <!-- Colors -->
    <Color x:Key="BackgroundColor">#1E1E2E</Color>
    <Color x:Key="CardBackgroundColor">#2A2A3C</Color>
    <Color x:Key="SidebarColor">#16161E</Color>
    <Color x:Key="AccentColor">#7C3AED</Color>
    <Color x:Key="AccentHoverColor">#9B5BFF</Color>
    <Color x:Key="TextPrimaryColor">#E0E0E0</Color>
    <Color x:Key="TextSecondaryColor">#A0A0B0</Color>
    <Color x:Key="BorderColor">#3A3A4C</Color>
    <Color x:Key="SuccessColor">#22C55E</Color>
    <Color x:Key="ErrorColor">#EF4444</Color>
    <Color x:Key="WarningColor">#EAB308</Color>
    <Color x:Key="InputBackgroundColor">#252536</Color>

    <!-- Brushes -->
    <SolidColorBrush x:Key="BackgroundBrush" Color="{StaticResource BackgroundColor}" />
    <SolidColorBrush x:Key="CardBackgroundBrush" Color="{StaticResource CardBackgroundColor}" />
    <SolidColorBrush x:Key="SidebarBrush" Color="{StaticResource SidebarColor}" />
    <SolidColorBrush x:Key="AccentBrush" Color="{StaticResource AccentColor}" />
    <SolidColorBrush x:Key="AccentHoverBrush" Color="{StaticResource AccentHoverColor}" />
    <SolidColorBrush x:Key="TextPrimaryBrush" Color="{StaticResource TextPrimaryColor}" />
    <SolidColorBrush x:Key="TextSecondaryBrush" Color="{StaticResource TextSecondaryColor}" />
    <SolidColorBrush x:Key="BorderBrush" Color="{StaticResource BorderColor}" />
    <SolidColorBrush x:Key="SuccessBrush" Color="{StaticResource SuccessColor}" />
    <SolidColorBrush x:Key="ErrorBrush" Color="{StaticResource ErrorColor}" />
    <SolidColorBrush x:Key="WarningBrush" Color="{StaticResource WarningColor}" />
    <SolidColorBrush x:Key="InputBackgroundBrush" Color="{StaticResource InputBackgroundColor}" />

    <!-- Button Style -->
    <Style x:Key="ModernButton" TargetType="Button">
        <Setter Property="Background" Value="{StaticResource AccentBrush}" />
        <Setter Property="Foreground" Value="White" />
        <Setter Property="BorderThickness" Value="0" />
        <Setter Property="Padding" Value="16,8" />
        <Setter Property="FontSize" Value="13" />
        <Setter Property="Cursor" Value="Hand" />
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border Background="{TemplateBinding Background}"
                            CornerRadius="6"
                            Padding="{TemplateBinding Padding}">
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" />
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter Property="Background" Value="{StaticResource AccentHoverBrush}" />
                        </Trigger>
                        <Trigger Property="IsEnabled" Value="False">
                            <Setter Property="Opacity" Value="0.5" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <!-- Sidebar Button Style -->
    <Style x:Key="SidebarButton" TargetType="Button">
        <Setter Property="Background" Value="Transparent" />
        <Setter Property="Foreground" Value="{StaticResource TextSecondaryBrush}" />
        <Setter Property="BorderThickness" Value="0" />
        <Setter Property="Padding" Value="16,12" />
        <Setter Property="FontSize" Value="13" />
        <Setter Property="HorizontalContentAlignment" Value="Left" />
        <Setter Property="Cursor" Value="Hand" />
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border x:Name="border" Background="{TemplateBinding Background}"
                            Padding="{TemplateBinding Padding}">
                        <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center" />
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="border" Property="Background" Value="{StaticResource CardBackgroundBrush}" />
                            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <!-- TextBox Style -->
    <Style x:Key="ModernTextBox" TargetType="TextBox">
        <Setter Property="Background" Value="{StaticResource InputBackgroundBrush}" />
        <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}" />
        <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}" />
        <Setter Property="BorderThickness" Value="1" />
        <Setter Property="Padding" Value="8,6" />
        <Setter Property="FontSize" Value="13" />
        <Setter Property="CaretBrush" Value="{StaticResource TextPrimaryBrush}" />
    </Style>

    <!-- ComboBox Style -->
    <Style x:Key="ModernComboBox" TargetType="ComboBox">
        <Setter Property="Background" Value="{StaticResource InputBackgroundBrush}" />
        <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}" />
        <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}" />
        <Setter Property="BorderThickness" Value="1" />
        <Setter Property="Padding" Value="8,6" />
        <Setter Property="FontSize" Value="13" />
    </Style>

    <!-- Card Style -->
    <Style x:Key="CardBorder" TargetType="Border">
        <Setter Property="Background" Value="{StaticResource CardBackgroundBrush}" />
        <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}" />
        <Setter Property="BorderThickness" Value="1" />
        <Setter Property="CornerRadius" Value="8" />
        <Setter Property="Padding" Value="16" />
    </Style>

    <!-- Label Style -->
    <Style x:Key="HeaderLabel" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}" />
        <Setter Property="FontSize" Value="18" />
        <Setter Property="FontWeight" Value="SemiBold" />
    </Style>

    <Style x:Key="SubLabel" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{StaticResource TextSecondaryBrush}" />
        <Setter Property="FontSize" Value="12" />
    </Style>

    <!-- ToggleButton (Switch) Style -->
    <Style x:Key="ToggleSwitch" TargetType="ToggleButton">
        <Setter Property="Width" Value="44" />
        <Setter Property="Height" Value="22" />
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="ToggleButton">
                    <Grid>
                        <Border x:Name="track" Background="{StaticResource BorderBrush}"
                                CornerRadius="11" />
                        <Border x:Name="thumb" Background="White"
                                CornerRadius="9" Width="18" Height="18"
                                HorizontalAlignment="Left" Margin="2,0,0,0" />
                    </Grid>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsChecked" Value="True">
                            <Setter TargetName="track" Property="Background" Value="{StaticResource AccentBrush}" />
                            <Setter TargetName="thumb" Property="HorizontalAlignment" Value="Right" />
                            <Setter TargetName="thumb" Property="Margin" Value="0,0,2,0" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

</ResourceDictionary>
```

**Step 2: Create the Light theme**

Create `GUI/Themes/Light.xaml` — identical structure but with light colors:

```xml
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

    <!-- Colors -->
    <Color x:Key="BackgroundColor">#F5F5F5</Color>
    <Color x:Key="CardBackgroundColor">#FFFFFF</Color>
    <Color x:Key="SidebarColor">#E8E8EC</Color>
    <Color x:Key="AccentColor">#6D28D9</Color>
    <Color x:Key="AccentHoverColor">#7C3AED</Color>
    <Color x:Key="TextPrimaryColor">#1A1A1A</Color>
    <Color x:Key="TextSecondaryColor">#6B7280</Color>
    <Color x:Key="BorderColor">#D1D5DB</Color>
    <Color x:Key="SuccessColor">#16A34A</Color>
    <Color x:Key="ErrorColor">#DC2626</Color>
    <Color x:Key="WarningColor">#CA8A04</Color>
    <Color x:Key="InputBackgroundColor">#FFFFFF</Color>

    <!-- Brushes — same keys, light values -->
    <SolidColorBrush x:Key="BackgroundBrush" Color="{StaticResource BackgroundColor}" />
    <SolidColorBrush x:Key="CardBackgroundBrush" Color="{StaticResource CardBackgroundColor}" />
    <SolidColorBrush x:Key="SidebarBrush" Color="{StaticResource SidebarColor}" />
    <SolidColorBrush x:Key="AccentBrush" Color="{StaticResource AccentColor}" />
    <SolidColorBrush x:Key="AccentHoverBrush" Color="{StaticResource AccentHoverColor}" />
    <SolidColorBrush x:Key="TextPrimaryBrush" Color="{StaticResource TextPrimaryColor}" />
    <SolidColorBrush x:Key="TextSecondaryBrush" Color="{StaticResource TextSecondaryColor}" />
    <SolidColorBrush x:Key="BorderBrush" Color="{StaticResource BorderColor}" />
    <SolidColorBrush x:Key="SuccessBrush" Color="{StaticResource SuccessColor}" />
    <SolidColorBrush x:Key="ErrorBrush" Color="{StaticResource ErrorColor}" />
    <SolidColorBrush x:Key="WarningBrush" Color="{StaticResource WarningColor}" />
    <SolidColorBrush x:Key="InputBackgroundBrush" Color="{StaticResource InputBackgroundColor}" />

    <!-- Styles — identical templates, same resource key references resolve to light colors -->
    <Style x:Key="ModernButton" TargetType="Button">
        <Setter Property="Background" Value="{StaticResource AccentBrush}" />
        <Setter Property="Foreground" Value="White" />
        <Setter Property="BorderThickness" Value="0" />
        <Setter Property="Padding" Value="16,8" />
        <Setter Property="FontSize" Value="13" />
        <Setter Property="Cursor" Value="Hand" />
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border Background="{TemplateBinding Background}"
                            CornerRadius="6"
                            Padding="{TemplateBinding Padding}">
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" />
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter Property="Background" Value="{StaticResource AccentHoverBrush}" />
                        </Trigger>
                        <Trigger Property="IsEnabled" Value="False">
                            <Setter Property="Opacity" Value="0.5" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <Style x:Key="SidebarButton" TargetType="Button">
        <Setter Property="Background" Value="Transparent" />
        <Setter Property="Foreground" Value="{StaticResource TextSecondaryBrush}" />
        <Setter Property="BorderThickness" Value="0" />
        <Setter Property="Padding" Value="16,12" />
        <Setter Property="FontSize" Value="13" />
        <Setter Property="HorizontalContentAlignment" Value="Left" />
        <Setter Property="Cursor" Value="Hand" />
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border x:Name="border" Background="{TemplateBinding Background}"
                            Padding="{TemplateBinding Padding}">
                        <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center" />
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter TargetName="border" Property="Background" Value="{StaticResource CardBackgroundBrush}" />
                            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <Style x:Key="ModernTextBox" TargetType="TextBox">
        <Setter Property="Background" Value="{StaticResource InputBackgroundBrush}" />
        <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}" />
        <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}" />
        <Setter Property="BorderThickness" Value="1" />
        <Setter Property="Padding" Value="8,6" />
        <Setter Property="FontSize" Value="13" />
        <Setter Property="CaretBrush" Value="{StaticResource TextPrimaryBrush}" />
    </Style>

    <Style x:Key="ModernComboBox" TargetType="ComboBox">
        <Setter Property="Background" Value="{StaticResource InputBackgroundBrush}" />
        <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}" />
        <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}" />
        <Setter Property="BorderThickness" Value="1" />
        <Setter Property="Padding" Value="8,6" />
        <Setter Property="FontSize" Value="13" />
    </Style>

    <Style x:Key="CardBorder" TargetType="Border">
        <Setter Property="Background" Value="{StaticResource CardBackgroundBrush}" />
        <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}" />
        <Setter Property="BorderThickness" Value="1" />
        <Setter Property="CornerRadius" Value="8" />
        <Setter Property="Padding" Value="16" />
    </Style>

    <Style x:Key="HeaderLabel" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}" />
        <Setter Property="FontSize" Value="18" />
        <Setter Property="FontWeight" Value="SemiBold" />
    </Style>

    <Style x:Key="SubLabel" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{StaticResource TextSecondaryBrush}" />
        <Setter Property="FontSize" Value="12" />
    </Style>

    <Style x:Key="ToggleSwitch" TargetType="ToggleButton">
        <Setter Property="Width" Value="44" />
        <Setter Property="Height" Value="22" />
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="ToggleButton">
                    <Grid>
                        <Border x:Name="track" Background="{StaticResource BorderBrush}"
                                CornerRadius="11" />
                        <Border x:Name="thumb" Background="White"
                                CornerRadius="9" Width="18" Height="18"
                                HorizontalAlignment="Left" Margin="2,0,0,0" />
                    </Grid>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsChecked" Value="True">
                            <Setter TargetName="track" Property="Background" Value="{StaticResource AccentBrush}" />
                            <Setter TargetName="thumb" Property="HorizontalAlignment" Value="Right" />
                            <Setter TargetName="thumb" Property="Margin" Value="0,0,2,0" />
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

</ResourceDictionary>
```

**Step 3: Verify XAML parses correctly**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -AssemblyName PresentationFramework; [System.Windows.Markup.XamlReader]::Parse((Get-Content 'C:\projects\AutomatedLab\GUI\Themes\Dark.xaml' -Raw)); Write-Host 'Dark OK'; [System.Windows.Markup.XamlReader]::Parse((Get-Content 'C:\projects\AutomatedLab\GUI\Themes\Light.xaml' -Raw)); Write-Host 'Light OK'"`
Expected: `Dark OK` and `Light OK` with no errors

**Step 4: Commit**

```bash
git add GUI/Themes/Dark.xaml GUI/Themes/Light.xaml
git commit -m "feat(gui): add dark and light WPF theme resource dictionaries"
```

---

### Task 3: Main Window Shell with Sidebar Navigation

**Files:**
- Create: `GUI/MainWindow.xaml`
- Modify: `GUI/Start-OpenCodeLabGUI.ps1`

**Step 1: Create the main window XAML**

Create `GUI/MainWindow.xaml` with a sidebar + content area layout:

```xml
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="OpenCodeLab"
        Width="1200" Height="800"
        MinWidth="900" MinHeight="600"
        WindowStartupLocation="CenterScreen">

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="200" />
            <ColumnDefinition Width="*" />
        </Grid.ColumnDefinitions>

        <!-- Sidebar -->
        <Border Grid.Column="0" Background="{DynamicResource SidebarBrush}">
            <DockPanel>
                <!-- App Title -->
                <TextBlock DockPanel.Dock="Top"
                           Text="OpenCodeLab"
                           FontSize="16" FontWeight="Bold"
                           Foreground="{DynamicResource TextPrimaryBrush}"
                           Margin="16,20,16,24" />

                <!-- Theme Toggle at bottom -->
                <StackPanel DockPanel.Dock="Bottom" Margin="16,0,16,16">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="&#x2600;" FontSize="14"
                                   Foreground="{DynamicResource TextSecondaryBrush}"
                                   VerticalAlignment="Center" Margin="0,0,8,0" />
                        <ToggleButton x:Name="btnThemeToggle"
                                      Style="{DynamicResource ToggleSwitch}" />
                        <TextBlock Text="&#x263D;" FontSize="14"
                                   Foreground="{DynamicResource TextSecondaryBrush}"
                                   VerticalAlignment="Center" Margin="8,0,0,0" />
                    </StackPanel>
                </StackPanel>

                <!-- Nav Buttons -->
                <StackPanel>
                    <Button x:Name="btnNavDashboard" Content="&#x25A0;  Dashboard"
                            Style="{DynamicResource SidebarButton}" />
                    <Button x:Name="btnNavActions" Content="&#x25B6;  Actions"
                            Style="{DynamicResource SidebarButton}" />
                    <Button x:Name="btnNavLogs" Content="&#x2261;  Logs"
                            Style="{DynamicResource SidebarButton}" />
                    <Button x:Name="btnNavSettings" Content="&#x2699;  Settings"
                            Style="{DynamicResource SidebarButton}" />
                </StackPanel>
            </DockPanel>
        </Border>

        <!-- Content Area -->
        <Border Grid.Column="1" Background="{DynamicResource BackgroundBrush}">
            <Grid x:Name="contentArea" Margin="24">
                <!-- Views are loaded here dynamically -->
                <TextBlock x:Name="txtPlaceholder"
                           Text="Loading..."
                           Style="{DynamicResource HeaderLabel}"
                           HorizontalAlignment="Center"
                           VerticalAlignment="Center" />
            </Grid>
        </Border>
    </Grid>
</Window>
```

**Step 2: Add window logic and theme switching to Start-OpenCodeLabGUI.ps1**

Append to `GUI/Start-OpenCodeLabGUI.ps1`:

```powershell
# Theme management
function Set-AppTheme {
    param([ValidateSet('Dark','Light')][string]$Theme)

    $themePath = Join-Path $script:GuiRoot "Themes\$Theme.xaml"
    $themeDict = Import-XamlFile -Path $themePath

    $app = [System.Windows.Application]::Current
    if ($null -eq $app) {
        $app = [System.Windows.Application]::new()
    }

    # Clear existing theme dictionaries and apply new one
    $app.Resources.MergedDictionaries.Clear()
    $app.Resources.MergedDictionaries.Add($themeDict)

    $script:CurrentTheme = $Theme
}

# Load main window
$mainWindow = Import-XamlFile -Path (Join-Path $script:GuiRoot 'MainWindow.xaml')

# Find named elements
$btnNavDashboard = $mainWindow.FindName('btnNavDashboard')
$btnNavActions = $mainWindow.FindName('btnNavActions')
$btnNavLogs = $mainWindow.FindName('btnNavLogs')
$btnNavSettings = $mainWindow.FindName('btnNavSettings')
$btnThemeToggle = $mainWindow.FindName('btnThemeToggle')
$contentArea = $mainWindow.FindName('contentArea')
$txtPlaceholder = $mainWindow.FindName('txtPlaceholder')

# Apply saved theme
$guiSettings = Get-GuiSettings
$initialTheme = if ($guiSettings.Theme -eq 'Light') { 'Light' } else { 'Dark' }
Set-AppTheme -Theme $initialTheme
$btnThemeToggle.IsChecked = ($initialTheme -eq 'Dark')

# Theme toggle handler
$btnThemeToggle.Add_Click({
    $newTheme = if ($script:CurrentTheme -eq 'Dark') { 'Light' } else { 'Dark' }
    Set-AppTheme -Theme $newTheme
    $settings = Get-GuiSettings
    $settings.Theme = $newTheme
    Save-GuiSettings -Settings $settings
})

# Navigation handler — loads view XAML into content area
$script:CurrentView = $null

function Switch-View {
    param([string]$ViewName)

    if ($script:CurrentView -eq $ViewName) { return }

    $viewPath = Join-Path $script:GuiRoot "Views\${ViewName}View.xaml"
    if (-not (Test-Path $viewPath)) {
        $txtPlaceholder.Text = "$ViewName (coming soon)"
        $txtPlaceholder.Visibility = 'Visible'
        return
    }

    $viewElement = Import-XamlFile -Path $viewPath
    $contentArea.Children.Clear()
    $contentArea.Children.Add($viewElement) | Out-Null
    $script:CurrentView = $ViewName
}

$btnNavDashboard.Add_Click({ Switch-View -ViewName 'Dashboard' })
$btnNavActions.Add_Click({ Switch-View -ViewName 'Actions' })
$btnNavLogs.Add_Click({ Switch-View -ViewName 'Logs' })
$btnNavSettings.Add_Click({ Switch-View -ViewName 'Settings' })

# Default to Dashboard view
$txtPlaceholder.Text = 'Dashboard'

# Show the window
$mainWindow.ShowDialog() | Out-Null
```

**Step 3: Test that the window opens with themed sidebar**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\projects\AutomatedLab\GUI\Start-OpenCodeLabGUI.ps1"`
Expected: Window opens at 1200x800 with dark sidebar, nav buttons, theme toggle. Clicking nav buttons shows view name. Theme toggle switches colors.

**Step 4: Commit**

```bash
git add GUI/MainWindow.xaml GUI/Start-OpenCodeLabGUI.ps1
git commit -m "feat(gui): add main window shell with sidebar nav and theme switching"
```

---

### Task 4: Dashboard View — VM Cards

**Files:**
- Create: `GUI/Views/DashboardView.xaml`
- Create: `GUI/Components/VMCard.xaml`
- Modify: `GUI/Start-OpenCodeLabGUI.ps1` — add VM polling logic

**Step 1: Create the VM card component XAML**

Create `GUI/Components/VMCard.xaml`:

```xml
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Style="{DynamicResource CardBorder}" Margin="0,0,0,12">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>

        <!-- Row 0: Name + Status Dot -->
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,4">
            <Ellipse x:Name="statusDot" Width="10" Height="10"
                     Fill="{DynamicResource TextSecondaryBrush}"
                     VerticalAlignment="Center" Margin="0,0,8,0" />
            <TextBlock x:Name="txtVMName" Text="vm-name"
                       FontSize="15" FontWeight="SemiBold"
                       Foreground="{DynamicResource TextPrimaryBrush}" />
        </StackPanel>

        <!-- Row 1: Role label -->
        <TextBlock Grid.Row="1" x:Name="txtRole" Text="Role"
                   Style="{DynamicResource SubLabel}" Margin="18,0,0,8" />

        <!-- Row 2: IP Address -->
        <TextBlock Grid.Row="2" x:Name="txtIP" Text="IP: --"
                   Foreground="{DynamicResource TextSecondaryBrush}"
                   FontSize="12" Margin="18,0,0,4" />

        <!-- Row 3: CPU / Memory -->
        <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="18,0,0,8">
            <TextBlock x:Name="txtCPU" Text="CPU: --"
                       Foreground="{DynamicResource TextSecondaryBrush}"
                       FontSize="12" Margin="0,0,16,0" />
            <TextBlock x:Name="txtMemory" Text="Mem: --"
                       Foreground="{DynamicResource TextSecondaryBrush}"
                       FontSize="12" />
        </StackPanel>

        <!-- Row 4: Action Buttons -->
        <StackPanel Grid.Row="4" Orientation="Horizontal" Margin="18,0,0,0">
            <Button x:Name="btnStart" Content="Start"
                    Style="{DynamicResource ModernButton}"
                    Padding="10,4" FontSize="11" Margin="0,0,6,0" />
            <Button x:Name="btnStop" Content="Stop"
                    Style="{DynamicResource ModernButton}"
                    Padding="10,4" FontSize="11" Margin="0,0,6,0" />
            <Button x:Name="btnConnect" Content="Connect"
                    Style="{DynamicResource ModernButton}"
                    Padding="10,4" FontSize="11" />
        </StackPanel>
    </Grid>
</Border>
```

**Step 2: Create the Dashboard view XAML**

Create `GUI/Views/DashboardView.xaml`:

```xml
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Grid.ColumnDefinitions>
        <ColumnDefinition Width="2*" MinWidth="280" />
        <ColumnDefinition Width="3*" MinWidth="400" />
    </Grid.ColumnDefinitions>

    <!-- Left: VM Cards -->
    <DockPanel Grid.Column="0" Margin="0,0,16,0">
        <TextBlock DockPanel.Dock="Top" Text="Virtual Machines"
                   Style="{DynamicResource HeaderLabel}" Margin="0,0,0,16" />
        <ScrollViewer VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="vmCardContainer">
                <!-- VM cards are added here dynamically -->
                <TextBlock x:Name="txtNoVMs" Text="Polling VM status..."
                           Foreground="{DynamicResource TextSecondaryBrush}"
                           FontSize="13" />
            </StackPanel>
        </ScrollViewer>
    </DockPanel>

    <!-- Right: Network Topology -->
    <DockPanel Grid.Column="1">
        <TextBlock DockPanel.Dock="Top" Text="Network Topology"
                   Style="{DynamicResource HeaderLabel}" Margin="0,0,0,16" />
        <Border Style="{DynamicResource CardBorder}">
            <Canvas x:Name="topologyCanvas" ClipToBounds="True" />
        </Border>
    </DockPanel>
</Grid>
```

**Step 3: Add VM polling and card rendering logic to Start-OpenCodeLabGUI.ps1**

Append to `GUI/Start-OpenCodeLabGUI.ps1` (before `$mainWindow.ShowDialog()`):

```powershell
# VM role mapping
$script:VMRoles = @{
    'dc1'  = 'Domain Controller'
    'svr1' = 'Member Server'
    'ws1'  = 'Windows 11 Client'
    'lin1' = 'Ubuntu Linux'
}

# Status color mapping
function Get-StatusColor {
    param([string]$State)
    switch ($State) {
        'Running'  { return [System.Windows.Media.Brushes]::LimeGreen }
        'Off'      { return [System.Windows.Media.Brushes]::Red }
        'Paused'   { return [System.Windows.Media.Brushes]::Yellow }
        'Saved'    { return [System.Windows.Media.Brushes]::Orange }
        default    { return [System.Windows.Media.Brushes]::Gray }
    }
}

# Create a VM card from the component XAML
function New-VMCardElement {
    param([string]$VMName, [string]$Role)
    $cardPath = Join-Path $script:GuiRoot 'Components\VMCard.xaml'
    $card = Import-XamlFile -Path $cardPath
    $card.FindName('txtVMName').Text = $VMName.ToUpper()
    $card.FindName('txtRole').Text = $Role
    return $card
}

# Update card data from VM status
function Update-VMCard {
    param($Card, $VMData)
    $dot = $Card.FindName('statusDot')
    $ip = $Card.FindName('txtIP')
    $cpu = $Card.FindName('txtCPU')
    $mem = $Card.FindName('txtMemory')
    $btnStart = $Card.FindName('btnStart')
    $btnStop = $Card.FindName('btnStop')

    if ($null -eq $VMData -or $VMData.State -eq 'NotCreated') {
        $dot.Fill = [System.Windows.Media.Brushes]::Gray
        $ip.Text = 'Not created'
        $cpu.Text = 'CPU: --'
        $mem.Text = 'Mem: --'
        $btnStart.IsEnabled = $false
        $btnStop.IsEnabled = $false
        return
    }

    $dot.Fill = Get-StatusColor -State $VMData.State
    $ip.Text = "IP: $($VMData.NetworkStatus)"
    $cpu.Text = "CPU: $($VMData.CPUUsage)%"
    $mem.Text = "Mem: $($VMData.MemoryGB) GB"
    $btnStart.IsEnabled = ($VMData.State -ne 'Running')
    $btnStop.IsEnabled = ($VMData.State -eq 'Running')
}

# Dashboard initialization (called when switching to Dashboard view)
$script:DashboardInitialized = $false
$script:VMCards = @{}
$script:VMPollTimer = $null

function Initialize-DashboardView {
    param($DashboardElement)

    if ($script:DashboardInitialized) { return }

    $container = $DashboardElement.FindName('vmCardContainer')
    $noVMsLabel = $DashboardElement.FindName('txtNoVMs')
    $canvas = $DashboardElement.FindName('topologyCanvas')

    # Store references for polling
    $script:DashboardContainer = $container
    $script:DashboardNoVMsLabel = $noVMsLabel
    $script:TopologyCanvas = $canvas

    # Create cards for known VMs
    $vmNames = @('dc1', 'svr1', 'ws1')
    if (Test-Path variable:GlobalLabConfig) {
        $vmNames = $GlobalLabConfig.Lab.CoreVMNames
    }

    $noVMsLabel.Visibility = 'Collapsed'
    foreach ($vmName in $vmNames) {
        $role = if ($script:VMRoles.ContainsKey($vmName)) { $script:VMRoles[$vmName] } else { 'VM' }
        $card = New-VMCardElement -VMName $vmName -Role $role
        $container.Children.Add($card) | Out-Null
        $script:VMCards[$vmName] = $card

        # Wire up action buttons
        $thisVMName = $vmName
        $card.FindName('btnStart').Add_Click({
            try { Start-VM -Name $thisVMName -ErrorAction Stop }
            catch { [System.Windows.MessageBox]::Show("Failed to start ${thisVMName}: $($_.Exception.Message)") }
        }.GetNewClosure())
        $card.FindName('btnStop').Add_Click({
            try { Stop-VM -Name $thisVMName -Force -ErrorAction Stop }
            catch { [System.Windows.MessageBox]::Show("Failed to stop ${thisVMName}: $($_.Exception.Message)") }
        }.GetNewClosure())
        $card.FindName('btnConnect').Add_Click({
            try { vmconnect.exe localhost $thisVMName }
            catch { [System.Windows.MessageBox]::Show("Failed to connect to ${thisVMName}: $($_.Exception.Message)") }
        }.GetNewClosure())
    }

    # Start polling timer
    $script:VMPollTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:VMPollTimer.Interval = [TimeSpan]::FromSeconds(5)
    $script:VMPollTimer.Add_Tick({
        try {
            $statuses = Get-LabStatus -ErrorAction SilentlyContinue
            if ($null -ne $statuses) {
                foreach ($vmStatus in $statuses) {
                    if ($script:VMCards.ContainsKey($vmStatus.VMName)) {
                        Update-VMCard -Card $script:VMCards[$vmStatus.VMName] -VMData $vmStatus
                    }
                }
                Update-TopologyCanvas -Canvas $script:TopologyCanvas -VMStatuses $statuses
            }
        }
        catch { }
    })
    $script:VMPollTimer.Start()

    $script:DashboardInitialized = $true
}
```

**Step 4: Wire up Dashboard initialization in Switch-View**

Update the `Switch-View` function in `Start-OpenCodeLabGUI.ps1` so that after loading the Dashboard view, it calls `Initialize-DashboardView`:

```powershell
# Replace the existing Switch-View function:
function Switch-View {
    param([string]$ViewName)

    if ($script:CurrentView -eq $ViewName) { return }

    $viewPath = Join-Path $script:GuiRoot "Views\${ViewName}View.xaml"
    if (-not (Test-Path $viewPath)) {
        $contentArea.Children.Clear()
        $placeholder = [System.Windows.Controls.TextBlock]::new()
        $placeholder.Text = "$ViewName (coming soon)"
        $placeholder.Style = $mainWindow.FindResource('HeaderLabel')
        $placeholder.HorizontalAlignment = 'Center'
        $placeholder.VerticalAlignment = 'Center'
        $contentArea.Children.Add($placeholder) | Out-Null
        $script:CurrentView = $ViewName
        return
    }

    $viewElement = Import-XamlFile -Path $viewPath
    $contentArea.Children.Clear()
    $contentArea.Children.Add($viewElement) | Out-Null
    $script:CurrentView = $ViewName

    # Post-load initialization
    if ($ViewName -eq 'Dashboard') {
        Initialize-DashboardView -DashboardElement $viewElement
    }
}
```

**Step 5: Test that dashboard loads with VM cards**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\projects\AutomatedLab\GUI\Start-OpenCodeLabGUI.ps1"`
Expected: Dashboard shows 3 VM cards (dc1, svr1, ws1) with status dots, role labels, and action buttons. Cards update every 5 seconds.

**Step 6: Commit**

```bash
git add GUI/Views/DashboardView.xaml GUI/Components/VMCard.xaml GUI/Start-OpenCodeLabGUI.ps1
git commit -m "feat(gui): add dashboard view with VM status cards and polling"
```

---

### Task 5: Dashboard View — Network Topology Canvas

**Files:**
- Modify: `GUI/Start-OpenCodeLabGUI.ps1` — add topology drawing function

**Step 1: Add topology drawing function**

Add to `Start-OpenCodeLabGUI.ps1` (before `$mainWindow.ShowDialog()`):

```powershell
function Update-TopologyCanvas {
    param(
        [System.Windows.Controls.Canvas]$Canvas,
        $VMStatuses
    )

    $Canvas.Children.Clear()

    $canvasWidth = if ($Canvas.ActualWidth -gt 0) { $Canvas.ActualWidth } else { 500 }
    $canvasHeight = if ($Canvas.ActualHeight -gt 0) { $Canvas.ActualHeight } else { 400 }

    # NAT Gateway box at top center
    $gatewayIP = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig.Network.GatewayIp } else { '10.0.10.1' }
    $switchName = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig.Network.SwitchName } else { 'AutomatedLab' }

    $gwWidth = 140
    $gwHeight = 40
    $gwX = ($canvasWidth - $gwWidth) / 2
    $gwY = 20

    # Draw gateway box
    $gwBorder = [System.Windows.Shapes.Rectangle]::new()
    $gwBorder.Width = $gwWidth
    $gwBorder.Height = $gwHeight
    $gwBorder.RadiusX = 6
    $gwBorder.RadiusY = 6
    $gwBorder.Stroke = $Canvas.FindResource('AccentBrush')
    $gwBorder.StrokeThickness = 2
    $gwBorder.Fill = $Canvas.FindResource('CardBackgroundBrush')
    [System.Windows.Controls.Canvas]::SetLeft($gwBorder, $gwX)
    [System.Windows.Controls.Canvas]::SetTop($gwBorder, $gwY)
    $Canvas.Children.Add($gwBorder) | Out-Null

    $gwLabel = [System.Windows.Controls.TextBlock]::new()
    $gwLabel.Text = "NAT Gateway`n$gatewayIP"
    $gwLabel.TextAlignment = 'Center'
    $gwLabel.FontSize = 11
    $gwLabel.Foreground = $Canvas.FindResource('TextPrimaryBrush')
    [System.Windows.Controls.Canvas]::SetLeft($gwLabel, $gwX + 10)
    [System.Windows.Controls.Canvas]::SetTop($gwLabel, $gwY + 4)
    $Canvas.Children.Add($gwLabel) | Out-Null

    # Virtual switch bar in middle
    $switchY = $gwY + $gwHeight + 40
    $switchWidth = $canvasWidth - 60
    $switchX = 30

    $switchLine = [System.Windows.Shapes.Rectangle]::new()
    $switchLine.Width = $switchWidth
    $switchLine.Height = 30
    $switchLine.RadiusX = 4
    $switchLine.RadiusY = 4
    $switchLine.Fill = $Canvas.FindResource('CardBackgroundBrush')
    $switchLine.Stroke = $Canvas.FindResource('BorderBrush')
    $switchLine.StrokeThickness = 1
    [System.Windows.Controls.Canvas]::SetLeft($switchLine, $switchX)
    [System.Windows.Controls.Canvas]::SetTop($switchLine, $switchY)
    $Canvas.Children.Add($switchLine) | Out-Null

    $switchLabel = [System.Windows.Controls.TextBlock]::new()
    $switchLabel.Text = "vSwitch: $switchName"
    $switchLabel.FontSize = 11
    $switchLabel.Foreground = $Canvas.FindResource('TextSecondaryBrush')
    [System.Windows.Controls.Canvas]::SetLeft($switchLabel, $switchX + 8)
    [System.Windows.Controls.Canvas]::SetTop($switchLabel, $switchY + 6)
    $Canvas.Children.Add($switchLabel) | Out-Null

    # Line from gateway to switch
    $gwLine = [System.Windows.Shapes.Line]::new()
    $gwLine.X1 = $canvasWidth / 2
    $gwLine.Y1 = $gwY + $gwHeight
    $gwLine.X2 = $canvasWidth / 2
    $gwLine.Y2 = $switchY
    $gwLine.Stroke = $Canvas.FindResource('BorderBrush')
    $gwLine.StrokeThickness = 2
    $Canvas.Children.Add($gwLine) | Out-Null

    # VM nodes below switch
    if ($null -eq $VMStatuses) { return }

    $vmArray = @($VMStatuses)
    $vmCount = $vmArray.Count
    if ($vmCount -eq 0) { return }

    $nodeY = $switchY + 30 + 40
    $nodeWidth = 120
    $nodeHeight = 50
    $spacing = ($canvasWidth - 60) / $vmCount

    for ($i = 0; $i -lt $vmCount; $i++) {
        $vm = $vmArray[$i]
        $nodeX = $switchX + ($spacing * $i) + (($spacing - $nodeWidth) / 2)

        # Line from switch to node
        $connLine = [System.Windows.Shapes.Line]::new()
        $connLine.X1 = $nodeX + $nodeWidth / 2
        $connLine.Y1 = $switchY + 30
        $connLine.X2 = $nodeX + $nodeWidth / 2
        $connLine.Y2 = $nodeY
        $connLine.Stroke = Get-StatusColor -State $vm.State
        $connLine.StrokeThickness = 2
        $Canvas.Children.Add($connLine) | Out-Null

        # Node box
        $nodeRect = [System.Windows.Shapes.Rectangle]::new()
        $nodeRect.Width = $nodeWidth
        $nodeRect.Height = $nodeHeight
        $nodeRect.RadiusX = 6
        $nodeRect.RadiusY = 6
        $nodeRect.Fill = $Canvas.FindResource('CardBackgroundBrush')
        $nodeRect.Stroke = Get-StatusColor -State $vm.State
        $nodeRect.StrokeThickness = 2
        [System.Windows.Controls.Canvas]::SetLeft($nodeRect, $nodeX)
        [System.Windows.Controls.Canvas]::SetTop($nodeRect, $nodeY)
        $Canvas.Children.Add($nodeRect) | Out-Null

        # Node label
        $ipText = if ($vm.NetworkStatus) { $vm.NetworkStatus } else { '--' }
        $nodeLabel = [System.Windows.Controls.TextBlock]::new()
        $nodeLabel.Text = "$($vm.VMName.ToUpper())`n$ipText"
        $nodeLabel.TextAlignment = 'Center'
        $nodeLabel.FontSize = 11
        $nodeLabel.Foreground = $Canvas.FindResource('TextPrimaryBrush')
        [System.Windows.Controls.Canvas]::SetLeft($nodeLabel, $nodeX + 8)
        [System.Windows.Controls.Canvas]::SetTop($nodeLabel, $nodeY + 8)
        $Canvas.Children.Add($nodeLabel) | Out-Null
    }
}
```

**Step 2: Test topology renders**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\projects\AutomatedLab\GUI\Start-OpenCodeLabGUI.ps1"`
Expected: Right side of dashboard shows NAT gateway box, switch bar, and VM nodes connected with colored lines. Colors reflect VM states.

**Step 3: Commit**

```bash
git add GUI/Start-OpenCodeLabGUI.ps1
git commit -m "feat(gui): add network topology canvas to dashboard"
```

---

### Task 6: Actions View

**Files:**
- Create: `GUI/Views/ActionsView.xaml`
- Modify: `GUI/Start-OpenCodeLabGUI.ps1` — add actions view logic

**Step 1: Create the Actions view XAML**

Create `GUI/Views/ActionsView.xaml`:

```xml
<ScrollViewer xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
              xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
              VerticalScrollBarVisibility="Auto">
    <StackPanel Margin="0,0,16,0" MaxWidth="700">

        <TextBlock Text="Actions" Style="{DynamicResource HeaderLabel}" Margin="0,0,0,20" />

        <!-- Action + Mode Row -->
        <Grid Margin="0,0,0,12">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*" />
                <ColumnDefinition Width="16" />
                <ColumnDefinition Width="*" />
            </Grid.ColumnDefinitions>

            <StackPanel Grid.Column="0">
                <TextBlock Text="Action" Foreground="{DynamicResource TextSecondaryBrush}"
                           FontSize="12" Margin="0,0,0,4" />
                <ComboBox x:Name="cmbAction" Style="{DynamicResource ModernComboBox}" />
            </StackPanel>

            <StackPanel Grid.Column="2">
                <TextBlock Text="Mode" Foreground="{DynamicResource TextSecondaryBrush}"
                           FontSize="12" Margin="0,0,0,4" />
                <ComboBox x:Name="cmbMode" Style="{DynamicResource ModernComboBox}" />
            </StackPanel>
        </Grid>

        <!-- Toggle Switches -->
        <Border Style="{DynamicResource CardBorder}" Margin="0,0,0,12">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="*" />
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0" Orientation="Horizontal">
                    <ToggleButton x:Name="tglNonInteractive" Style="{DynamicResource ToggleSwitch}" IsChecked="True" />
                    <TextBlock Text="  NonInteractive" Foreground="{DynamicResource TextPrimaryBrush}"
                               FontSize="12" VerticalAlignment="Center" />
                </StackPanel>

                <StackPanel Grid.Column="1" Orientation="Horizontal">
                    <ToggleButton x:Name="tglForce" Style="{DynamicResource ToggleSwitch}" />
                    <TextBlock Text="  Force" Foreground="{DynamicResource TextPrimaryBrush}"
                               FontSize="12" VerticalAlignment="Center" />
                </StackPanel>

                <StackPanel Grid.Column="2" Orientation="Horizontal">
                    <ToggleButton x:Name="tglDryRun" Style="{DynamicResource ToggleSwitch}" />
                    <TextBlock Text="  DryRun" Foreground="{DynamicResource TextPrimaryBrush}"
                               FontSize="12" VerticalAlignment="Center" />
                </StackPanel>
            </Grid>
        </Border>

        <!-- Advanced Options Expander -->
        <Expander x:Name="expAdvanced" Header="Advanced Options"
                  Foreground="{DynamicResource TextPrimaryBrush}" Margin="0,0,0,12">
            <Border Style="{DynamicResource CardBorder}" Margin="0,8,0,0">
                <StackPanel>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                        <ToggleButton x:Name="tglRemoveNetwork" Style="{DynamicResource ToggleSwitch}" />
                        <TextBlock Text="  RemoveNetwork" Foreground="{DynamicResource TextPrimaryBrush}"
                                   FontSize="12" VerticalAlignment="Center" Margin="0,0,24,0" />
                        <ToggleButton x:Name="tglCoreOnly" Style="{DynamicResource ToggleSwitch}" IsChecked="True" />
                        <TextBlock Text="  CoreOnly" Foreground="{DynamicResource TextPrimaryBrush}"
                                   FontSize="12" VerticalAlignment="Center" />
                    </StackPanel>

                    <TextBlock Text="Profile Path" Foreground="{DynamicResource TextSecondaryBrush}"
                               FontSize="12" Margin="0,0,0,4" />
                    <TextBox x:Name="txtProfilePath" Style="{DynamicResource ModernTextBox}" Margin="0,0,0,8" />

                    <TextBlock Text="Defaults File" Foreground="{DynamicResource TextSecondaryBrush}"
                               FontSize="12" Margin="0,0,0,4" />
                    <TextBox x:Name="txtDefaultsFile" Style="{DynamicResource ModernTextBox}" Margin="0,0,0,8" />

                    <TextBlock Text="Target Hosts (comma / space / semicolon)" Foreground="{DynamicResource TextSecondaryBrush}"
                               FontSize="12" Margin="0,0,0,4" />
                    <TextBox x:Name="txtTargetHosts" Style="{DynamicResource ModernTextBox}" Margin="0,0,0,8" />

                    <TextBlock Text="Confirmation Token" Foreground="{DynamicResource TextSecondaryBrush}"
                               FontSize="12" Margin="0,0,0,4" />
                    <TextBox x:Name="txtConfirmationToken" Style="{DynamicResource ModernTextBox}" />
                </StackPanel>
            </Border>
        </Expander>

        <!-- Command Preview -->
        <TextBlock Text="Command Preview" Foreground="{DynamicResource TextSecondaryBrush}"
                   FontSize="12" Margin="0,0,0,4" />
        <TextBox x:Name="txtCommandPreview" Style="{DynamicResource ModernTextBox}"
                 IsReadOnly="True" TextWrapping="Wrap" MinHeight="60" Margin="0,0,0,16" />

        <!-- Run Button -->
        <Button x:Name="btnRunAction" Content="Run" Width="160" Height="40"
                Style="{DynamicResource ModernButton}" FontSize="15"
                HorizontalAlignment="Left" />

    </StackPanel>
</ScrollViewer>
```

**Step 2: Add actions view initialization logic to Start-OpenCodeLabGUI.ps1**

Append to `Start-OpenCodeLabGUI.ps1` (before `$mainWindow.ShowDialog()`):

```powershell
$script:ActionsInitialized = $false

function Initialize-ActionsView {
    param($ActionsElement)

    if ($script:ActionsInitialized) { return }

    $cmbAction = $ActionsElement.FindName('cmbAction')
    $cmbMode = $ActionsElement.FindName('cmbMode')
    $tglNonInteractive = $ActionsElement.FindName('tglNonInteractive')
    $tglForce = $ActionsElement.FindName('tglForce')
    $tglDryRun = $ActionsElement.FindName('tglDryRun')
    $tglRemoveNetwork = $ActionsElement.FindName('tglRemoveNetwork')
    $tglCoreOnly = $ActionsElement.FindName('tglCoreOnly')
    $txtProfilePath = $ActionsElement.FindName('txtProfilePath')
    $txtDefaultsFile = $ActionsElement.FindName('txtDefaultsFile')
    $txtTargetHosts = $ActionsElement.FindName('txtTargetHosts')
    $txtConfirmationToken = $ActionsElement.FindName('txtConfirmationToken')
    $txtCommandPreview = $ActionsElement.FindName('txtCommandPreview')
    $btnRunAction = $ActionsElement.FindName('btnRunAction')
    $expAdvanced = $ActionsElement.FindName('expAdvanced')

    # Populate dropdowns
    $actions = @('deploy', 'teardown', 'status', 'health', 'setup', 'one-button-setup', 'one-button-reset', 'blow-away')
    foreach ($a in $actions) { $cmbAction.Items.Add($a) | Out-Null }
    $cmbAction.SelectedIndex = 0

    $modes = @('quick', 'full')
    foreach ($m in $modes) { $cmbMode.Items.Add($m) | Out-Null }
    $cmbMode.SelectedIndex = 0

    $appPath = Join-Path $script:RepoRoot 'OpenCodeLab-App.ps1'

    # Build options from controls
    $getOptions = {
        $targetHosts = @($txtTargetHosts.Text | ConvertTo-LabTargetHostList)
        $opts = @{
            Action = [string]$cmbAction.SelectedItem
            Mode = [string]$cmbMode.SelectedItem
            NonInteractive = [bool]$tglNonInteractive.IsChecked
            Force = [bool]$tglForce.IsChecked
            DryRun = [bool]$tglDryRun.IsChecked
            RemoveNetwork = [bool]$tglRemoveNetwork.IsChecked
            CoreOnly = [bool]$tglCoreOnly.IsChecked
        }
        if (-not [string]::IsNullOrWhiteSpace($txtProfilePath.Text)) { $opts.ProfilePath = $txtProfilePath.Text.Trim() }
        if (-not [string]::IsNullOrWhiteSpace($txtDefaultsFile.Text)) { $opts.DefaultsFile = $txtDefaultsFile.Text.Trim() }
        if ($targetHosts.Count -gt 0) { $opts.TargetHosts = $targetHosts }
        if (-not [string]::IsNullOrWhiteSpace($txtConfirmationToken.Text)) { $opts.ConfirmationToken = $txtConfirmationToken.Text.Trim() }
        return $opts
    }

    $updatePreview = {
        try {
            $opts = & $getOptions
            $txtCommandPreview.Text = New-LabGuiCommandPreview -AppScriptPath $appPath -Options $opts
        }
        catch { $txtCommandPreview.Text = '<preview unavailable>' }
    }

    $updateLayout = {
        $targetHosts = @($txtTargetHosts.Text | ConvertTo-LabTargetHostList)
        $layoutState = Get-LabGuiLayoutState -Action ([string]$cmbAction.SelectedItem) -Mode ([string]$cmbMode.SelectedItem) -ProfilePath $txtProfilePath.Text -TargetHosts $targetHosts
        $tglNonInteractive.IsChecked = $layoutState.RecommendedNonInteractiveDefault
        if ($layoutState.ShowAdvanced) { $expAdvanced.IsExpanded = $true }
        & $updatePreview
    }

    # Wire events
    $cmbAction.Add_SelectionChanged($updateLayout)
    $cmbMode.Add_SelectionChanged($updateLayout)
    $tglNonInteractive.Add_Click($updatePreview)
    $tglForce.Add_Click($updatePreview)
    $tglDryRun.Add_Click($updatePreview)
    $tglRemoveNetwork.Add_Click($updatePreview)
    $tglCoreOnly.Add_Click($updatePreview)
    $txtProfilePath.Add_TextChanged($updateLayout)
    $txtDefaultsFile.Add_TextChanged($updatePreview)
    $txtTargetHosts.Add_TextChanged($updateLayout)
    $txtConfirmationToken.Add_TextChanged($updatePreview)

    # Run button
    $btnRunAction.Add_Click({
        $opts = & $getOptions
        $guard = Get-LabGuiDestructiveGuard -Action $opts.Action -Mode $opts.Mode -ProfilePath ($opts.ProfilePath ?? '')
        if ($guard.RequiresConfirmation) {
            $result = [System.Windows.MessageBox]::Show(
                "This will run $($guard.ConfirmationLabel). Continue?",
                'Confirm destructive action',
                'YesNo', 'Warning')
            if ($result -ne 'Yes') { return }
        }

        $argList = New-LabAppArgumentList -Options $opts
        $hostPath = (Get-Command 'powershell.exe' -ErrorAction SilentlyContinue).Source
        $processArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $appPath) + $argList
        Start-Process -FilePath $hostPath -ArgumentList $processArgs -Verb RunAs

        # Switch to Logs view
        Add-LogEntry -Message "Started: $($opts.Action) ($($opts.Mode))" -Level 'Info'
        Switch-View -ViewName 'Logs'
    })

    & $updatePreview
    $script:ActionsInitialized = $true
}
```

**Step 3: Update Switch-View to initialize Actions view**

In the `Switch-View` function, add after the Dashboard check:

```powershell
    elseif ($ViewName -eq 'Actions') {
        Initialize-ActionsView -ActionsElement $viewElement
    }
```

**Step 4: Test Actions view**

Run the GUI, click Actions in sidebar. Verify dropdowns populate, toggles work, command preview updates, Run button launches with UAC.

**Step 5: Commit**

```bash
git add GUI/Views/ActionsView.xaml GUI/Start-OpenCodeLabGUI.ps1
git commit -m "feat(gui): add actions view with command builder and safety gates"
```

---

### Task 7: Logs View

**Files:**
- Create: `GUI/Views/LogsView.xaml`
- Modify: `GUI/Start-OpenCodeLabGUI.ps1` — add log management

**Step 1: Create the Logs view XAML**

Create `GUI/Views/LogsView.xaml`:

```xml
<DockPanel xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
           xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

    <!-- Header + Controls -->
    <Grid DockPanel.Dock="Top" Margin="0,0,0,12">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto" />
            <ColumnDefinition Width="*" />
            <ColumnDefinition Width="Auto" />
            <ColumnDefinition Width="Auto" />
        </Grid.ColumnDefinitions>

        <TextBlock Grid.Column="0" Text="Logs"
                   Style="{DynamicResource HeaderLabel}" VerticalAlignment="Center" />

        <ComboBox Grid.Column="2" x:Name="cmbLogFilter"
                  Style="{DynamicResource ModernComboBox}"
                  Width="120" Margin="0,0,8,0" />

        <Button Grid.Column="3" x:Name="btnClearLogs" Content="Clear"
                Style="{DynamicResource ModernButton}" Padding="12,6" />
    </Grid>

    <!-- Log Output -->
    <Border Style="{DynamicResource CardBorder}">
        <ScrollViewer x:Name="logScroller" VerticalScrollBarVisibility="Auto">
            <TextBlock x:Name="txtLogOutput"
                       FontFamily="Cascadia Code,Consolas,Courier New"
                       FontSize="12"
                       Foreground="{DynamicResource TextPrimaryBrush}"
                       TextWrapping="Wrap" />
        </ScrollViewer>
    </Border>
</DockPanel>
```

**Step 2: Add log management to Start-OpenCodeLabGUI.ps1**

Append to `Start-OpenCodeLabGUI.ps1` (before `$mainWindow.ShowDialog()`):

```powershell
# Global log buffer (persists across view switches)
$script:LogEntries = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:LogsViewInitialized = $false
$script:LogFilter = 'All'
$script:LogOutputElement = $null
$script:LogScrollerElement = $null

function Add-LogEntry {
    param(
        [string]$Message,
        [ValidateSet('Info','Warning','Error','Success')]
        [string]$Level = 'Info'
    )
    $entry = [PSCustomObject]@{
        Timestamp = Get-Date -Format 'HH:mm:ss'
        Level = $Level
        Message = $Message
    }
    $script:LogEntries.Add($entry)

    # Update UI if logs view is active
    if ($null -ne $script:LogOutputElement) {
        Render-LogEntries
    }
}

function Render-LogEntries {
    if ($null -eq $script:LogOutputElement) { return }

    $script:LogOutputElement.Inlines.Clear()

    foreach ($entry in $script:LogEntries) {
        if ($script:LogFilter -ne 'All' -and $entry.Level -ne $script:LogFilter) { continue }

        $color = switch ($entry.Level) {
            'Error'   { $mainWindow.FindResource('ErrorBrush') }
            'Warning' { $mainWindow.FindResource('WarningBrush') }
            'Success' { $mainWindow.FindResource('SuccessBrush') }
            default   { $mainWindow.FindResource('TextPrimaryBrush') }
        }

        $run = [System.Windows.Documents.Run]::new("[$($entry.Timestamp)] [$($entry.Level.ToUpper())] $($entry.Message)`n")
        $run.Foreground = $color
        $script:LogOutputElement.Inlines.Add($run)
    }

    # Auto-scroll to bottom
    if ($null -ne $script:LogScrollerElement) {
        $script:LogScrollerElement.ScrollToEnd()
    }
}

function Initialize-LogsView {
    param($LogsElement)

    $script:LogOutputElement = $LogsElement.FindName('txtLogOutput')
    $script:LogScrollerElement = $LogsElement.FindName('logScroller')
    $cmbFilter = $LogsElement.FindName('cmbLogFilter')
    $btnClear = $LogsElement.FindName('btnClearLogs')

    # Populate filter
    if ($cmbFilter.Items.Count -eq 0) {
        foreach ($f in @('All', 'Info', 'Warning', 'Error', 'Success')) {
            $cmbFilter.Items.Add($f) | Out-Null
        }
        $cmbFilter.SelectedIndex = 0
    }

    $cmbFilter.Add_SelectionChanged({
        $script:LogFilter = [string]$cmbFilter.SelectedItem
        Render-LogEntries
    })

    $btnClear.Add_Click({
        $script:LogEntries.Clear()
        Render-LogEntries
    })

    Render-LogEntries
    $script:LogsViewInitialized = $true
}
```

**Step 3: Update Switch-View to initialize Logs view**

Add to `Switch-View`:

```powershell
    elseif ($ViewName -eq 'Logs') {
        Initialize-LogsView -LogsElement $viewElement
    }
```

Also, when switching away from Logs, clear the element references so they don't go stale. Add at the top of `Switch-View`:

```powershell
    # Clear stale references when leaving Logs view
    if ($script:CurrentView -eq 'Logs') {
        $script:LogOutputElement = $null
        $script:LogScrollerElement = $null
    }
```

**Step 4: Test Logs view**

Run: Open GUI, click Actions, run a "status" action, verify it auto-switches to Logs view showing the action entry. Verify filter dropdown and clear button work.

**Step 5: Commit**

```bash
git add GUI/Views/LogsView.xaml GUI/Start-OpenCodeLabGUI.ps1
git commit -m "feat(gui): add logs view with color-coded output and filtering"
```

---

### Task 8: Settings View

**Files:**
- Create: `GUI/Views/SettingsView.xaml`
- Modify: `GUI/Start-OpenCodeLabGUI.ps1` — add settings view logic

**Step 1: Create the Settings view XAML**

Create `GUI/Views/SettingsView.xaml`:

```xml
<ScrollViewer xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
              xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
              VerticalScrollBarVisibility="Auto">
    <StackPanel Margin="0,0,16,0" MaxWidth="700">

        <TextBlock Text="Settings" Style="{DynamicResource HeaderLabel}" Margin="0,0,0,20" />

        <!-- Paths Section -->
        <TextBlock Text="PATHS" Foreground="{DynamicResource AccentBrush}"
                   FontSize="12" FontWeight="Bold" Margin="0,0,0,8" />
        <Border Style="{DynamicResource CardBorder}" Margin="0,0,0,16">
            <StackPanel>
                <TextBlock Text="Lab Root" Style="{DynamicResource SubLabel}" Margin="0,0,0,4" />
                <TextBox x:Name="txtLabRoot" Style="{DynamicResource ModernTextBox}" Margin="0,0,0,12" />

                <TextBlock Text="Server 2019 ISO" Style="{DynamicResource SubLabel}" Margin="0,0,0,4" />
                <Grid Margin="0,0,0,12">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*" />
                        <ColumnDefinition Width="Auto" />
                    </Grid.ColumnDefinitions>
                    <TextBox x:Name="txtIsoServer" Style="{DynamicResource ModernTextBox}" Grid.Column="0" />
                    <Button x:Name="btnBrowseServer" Content="Browse" Grid.Column="1"
                            Style="{DynamicResource ModernButton}" Padding="12,6" Margin="8,0,0,0" />
                </Grid>

                <TextBlock Text="Windows 11 ISO" Style="{DynamicResource SubLabel}" Margin="0,0,0,4" />
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*" />
                        <ColumnDefinition Width="Auto" />
                    </Grid.ColumnDefinitions>
                    <TextBox x:Name="txtIsoWin11" Style="{DynamicResource ModernTextBox}" Grid.Column="0" />
                    <Button x:Name="btnBrowseWin11" Content="Browse" Grid.Column="1"
                            Style="{DynamicResource ModernButton}" Padding="12,6" Margin="8,0,0,0" />
                </Grid>
            </StackPanel>
        </Border>

        <!-- Network Section -->
        <TextBlock Text="NETWORK" Foreground="{DynamicResource AccentBrush}"
                   FontSize="12" FontWeight="Bold" Margin="0,0,0,8" />
        <Border Style="{DynamicResource CardBorder}" Margin="0,0,0,16">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="16" />
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="16" />
                    <ColumnDefinition Width="*" />
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto" />
                    <RowDefinition Height="Auto" />
                </Grid.RowDefinitions>

                <TextBlock Grid.Row="0" Grid.Column="0" Text="Switch Name" Style="{DynamicResource SubLabel}" Margin="0,0,0,4" />
                <TextBox Grid.Row="1" Grid.Column="0" x:Name="txtSwitchName" Style="{DynamicResource ModernTextBox}" />

                <TextBlock Grid.Row="0" Grid.Column="2" Text="Subnet" Style="{DynamicResource SubLabel}" Margin="0,0,0,4" />
                <TextBox Grid.Row="1" Grid.Column="2" x:Name="txtSubnet" Style="{DynamicResource ModernTextBox}" />

                <TextBlock Grid.Row="0" Grid.Column="4" Text="Gateway IP" Style="{DynamicResource SubLabel}" Margin="0,0,0,4" />
                <TextBox Grid.Row="1" Grid.Column="4" x:Name="txtGatewayIP" Style="{DynamicResource ModernTextBox}" />
            </Grid>
        </Border>

        <!-- Credentials Section -->
        <TextBlock Text="CREDENTIALS" Foreground="{DynamicResource AccentBrush}"
                   FontSize="12" FontWeight="Bold" Margin="0,0,0,8" />
        <Border Style="{DynamicResource CardBorder}" Margin="0,0,0,16">
            <StackPanel>
                <TextBlock Text="Admin Password" Style="{DynamicResource SubLabel}" Margin="0,0,0,4" />
                <PasswordBox x:Name="txtAdminPassword" FontSize="13" Padding="8,6"
                             Background="{DynamicResource InputBackgroundBrush}"
                             Foreground="{DynamicResource TextPrimaryBrush}"
                             BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" />
            </StackPanel>
        </Border>

        <!-- Theme Section -->
        <TextBlock Text="APPEARANCE" Foreground="{DynamicResource AccentBrush}"
                   FontSize="12" FontWeight="Bold" Margin="0,0,0,8" />
        <Border Style="{DynamicResource CardBorder}" Margin="0,0,0,16">
            <StackPanel Orientation="Horizontal">
                <TextBlock Text="Dark Mode" Foreground="{DynamicResource TextPrimaryBrush}"
                           FontSize="13" VerticalAlignment="Center" Margin="0,0,12,0" />
                <ToggleButton x:Name="tglSettingsTheme" Style="{DynamicResource ToggleSwitch}" />
            </StackPanel>
        </Border>

        <!-- Save Button -->
        <Button x:Name="btnSaveSettings" Content="Save Settings" Width="160" Height="40"
                Style="{DynamicResource ModernButton}" FontSize="15"
                HorizontalAlignment="Left" />

    </StackPanel>
</ScrollViewer>
```

**Step 2: Add settings view initialization logic to Start-OpenCodeLabGUI.ps1**

Append to `Start-OpenCodeLabGUI.ps1` (before `$mainWindow.ShowDialog()`):

```powershell
$script:SettingsInitialized = $false

function Initialize-SettingsView {
    param($SettingsElement)

    $txtLabRoot = $SettingsElement.FindName('txtLabRoot')
    $txtIsoServer = $SettingsElement.FindName('txtIsoServer')
    $txtIsoWin11 = $SettingsElement.FindName('txtIsoWin11')
    $btnBrowseServer = $SettingsElement.FindName('btnBrowseServer')
    $btnBrowseWin11 = $SettingsElement.FindName('btnBrowseWin11')
    $txtSwitchName = $SettingsElement.FindName('txtSwitchName')
    $txtSubnet = $SettingsElement.FindName('txtSubnet')
    $txtGatewayIP = $SettingsElement.FindName('txtGatewayIP')
    $txtAdminPassword = $SettingsElement.FindName('txtAdminPassword')
    $tglSettingsTheme = $SettingsElement.FindName('tglSettingsTheme')
    $btnSave = $SettingsElement.FindName('btnSaveSettings')

    # Populate from GlobalLabConfig
    if (Test-Path variable:GlobalLabConfig) {
        $txtLabRoot.Text = $GlobalLabConfig.Paths.LabRoot
        $txtSwitchName.Text = $GlobalLabConfig.Network.SwitchName
        $txtSubnet.Text = $GlobalLabConfig.Network.AddressSpace
        $txtGatewayIP.Text = $GlobalLabConfig.Network.GatewayIp
        $txtAdminPassword.Password = $GlobalLabConfig.Credentials.AdminPassword
    }

    # Populate ISO paths from .planning/config.json
    $configJsonPath = Join-Path $script:RepoRoot '.planning' 'config.json'
    if (Test-Path $configJsonPath) {
        try {
            $planningConfig = Get-Content -Raw -Path $configJsonPath | ConvertFrom-Json
            $txtIsoServer.Text = $planningConfig.IsoPaths.Server2019
            $txtIsoWin11.Text = $planningConfig.IsoPaths.Windows11
        }
        catch { }
    }

    # Theme toggle
    $tglSettingsTheme.IsChecked = ($script:CurrentTheme -eq 'Dark')
    $tglSettingsTheme.Add_Click({
        $newTheme = if ($tglSettingsTheme.IsChecked) { 'Dark' } else { 'Light' }
        Set-AppTheme -Theme $newTheme
        $btnThemeToggle.IsChecked = ($newTheme -eq 'Dark')
        $settings = Get-GuiSettings
        $settings.Theme = $newTheme
        Save-GuiSettings -Settings $settings
    })

    # Browse buttons
    $browseIso = {
        param($TargetTextBox)
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = [System.Windows.Forms.OpenFileDialog]::new()
        $dialog.Filter = 'ISO files (*.iso)|*.iso|All files (*.*)|*.*'
        $dialog.Title = 'Select ISO File'
        if ($dialog.ShowDialog() -eq 'OK') {
            $TargetTextBox.Text = $dialog.FileName
        }
    }

    $btnBrowseServer.Add_Click({ & $browseIso $txtIsoServer })
    $btnBrowseWin11.Add_Click({ & $browseIso $txtIsoWin11 })

    # Save button
    $btnSave.Add_Click({
        try {
            # Validate IP format
            if (-not [string]::IsNullOrWhiteSpace($txtGatewayIP.Text) -and
                $txtGatewayIP.Text -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
                [System.Windows.MessageBox]::Show('Invalid Gateway IP format.', 'Validation Error', 'OK', 'Warning')
                return
            }

            # Update .planning/config.json ISO paths
            $configJsonPath = Join-Path $script:RepoRoot '.planning' 'config.json'
            if (Test-Path $configJsonPath) {
                $planningConfig = Get-Content -Raw -Path $configJsonPath | ConvertFrom-Json
                $planningConfig.IsoPaths.Server2019 = $txtIsoServer.Text
                $planningConfig.IsoPaths.Windows11 = $txtIsoWin11.Text
                $planningConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configJsonPath -Encoding UTF8
            }

            [System.Windows.MessageBox]::Show('Settings saved successfully.', 'Settings', 'OK', 'Information')
            Add-LogEntry -Message 'Settings saved' -Level 'Success'
        }
        catch {
            [System.Windows.MessageBox]::Show("Failed to save: $($_.Exception.Message)", 'Error', 'OK', 'Error')
            Add-LogEntry -Message "Settings save failed: $($_.Exception.Message)" -Level 'Error'
        }
    })

    $script:SettingsInitialized = $true
}
```

**Step 3: Update Switch-View to initialize Settings view**

Add to `Switch-View`:

```powershell
    elseif ($ViewName -eq 'Settings') {
        Initialize-SettingsView -SettingsElement $viewElement
    }
```

**Step 4: Test Settings view**

Run the GUI, navigate to Settings. Verify fields populated from config, browse buttons open file picker, theme toggle works, save button updates config.json.

**Step 5: Commit**

```bash
git add GUI/Views/SettingsView.xaml GUI/Start-OpenCodeLabGUI.ps1
git commit -m "feat(gui): add settings view with config editing and ISO browser"
```

---

### Task 9: Update Launcher and Syntax Validation

**Files:**
- Modify: `Scripts/Run-OpenCodeLab.ps1` — add GUI launch option and syntax validation for new files

**Step 1: Update Run-OpenCodeLab.ps1 to support --gui flag**

Edit `Scripts/Run-OpenCodeLab.ps1` to add a `-GUI` switch that launches the WPF GUI instead:

Add `-GUI` switch to the param block and add GUI launch logic before the existing app launch:

```powershell
# After the existing param block, add:
[switch]$GUI
```

Add before the existing `& $appScriptPath @effectiveArguments` line:

```powershell
# Launch WPF GUI if requested
if ($GUI) {
    $guiScriptPath = Join-Path $repoRoot 'GUI' 'Start-OpenCodeLabGUI.ps1'
    if (-not (Test-Path -Path $guiScriptPath -PathType Leaf)) {
        throw "GUI entry point not found at path: $guiScriptPath"
    }
    & $guiScriptPath
    return
}
```

Also update the syntax validation `$buildTargets` array to include the new GUI entry point:

```powershell
$buildTargets = @(
    $appScriptPath,
    (Join-Path $repoRoot 'Bootstrap.ps1'),
    (Join-Path $repoRoot 'Deploy.ps1'),
    (Join-Path $repoRoot 'OpenCodeLab-GUI.ps1'),
    (Join-Path $repoRoot 'GUI' 'Start-OpenCodeLabGUI.ps1')
)
```

**Step 2: Test that -GUI launches the WPF window**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\projects\AutomatedLab\Scripts\Run-OpenCodeLab.ps1" -GUI`
Expected: WPF window opens instead of CLI menu

**Step 3: Commit**

```bash
git add Scripts/Run-OpenCodeLab.ps1
git commit -m "feat(gui): add -GUI switch to launcher for WPF mode"
```

---

### Task 10: Pester Tests for XAML Loading and Theme Switching

**Files:**
- Create: `Tests/WpfGui.Tests.ps1`

**Step 1: Write tests for XAML loading and theme infrastructure**

Create `Tests/WpfGui.Tests.ps1`:

```powershell
BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $guiRoot = Join-Path $repoRoot 'GUI'
}

Describe 'WPF GUI XAML Files' {

    It 'GUI directory exists' {
        Test-Path $guiRoot | Should -Be $true
    }

    It 'MainWindow.xaml exists and is valid XML' {
        $path = Join-Path $guiRoot 'MainWindow.xaml'
        Test-Path $path | Should -Be $true
        { [xml](Get-Content -Raw -Path $path) } | Should -Not -Throw
    }

    It 'Dark.xaml exists and is valid XML' {
        $path = Join-Path $guiRoot 'Themes' 'Dark.xaml'
        Test-Path $path | Should -Be $true
        { [xml](Get-Content -Raw -Path $path) } | Should -Not -Throw
    }

    It 'Light.xaml exists and is valid XML' {
        $path = Join-Path $guiRoot 'Themes' 'Light.xaml'
        Test-Path $path | Should -Be $true
        { [xml](Get-Content -Raw -Path $path) } | Should -Not -Throw
    }

    It 'DashboardView.xaml exists and is valid XML' {
        $path = Join-Path $guiRoot 'Views' 'DashboardView.xaml'
        Test-Path $path | Should -Be $true
        { [xml](Get-Content -Raw -Path $path) } | Should -Not -Throw
    }

    It 'ActionsView.xaml exists and is valid XML' {
        $path = Join-Path $guiRoot 'Views' 'ActionsView.xaml'
        Test-Path $path | Should -Be $true
        { [xml](Get-Content -Raw -Path $path) } | Should -Not -Throw
    }

    It 'LogsView.xaml exists and is valid XML' {
        $path = Join-Path $guiRoot 'Views' 'LogsView.xaml'
        Test-Path $path | Should -Be $true
        { [xml](Get-Content -Raw -Path $path) } | Should -Not -Throw
    }

    It 'SettingsView.xaml exists and is valid XML' {
        $path = Join-Path $guiRoot 'Views' 'SettingsView.xaml'
        Test-Path $path | Should -Be $true
        { [xml](Get-Content -Raw -Path $path) } | Should -Not -Throw
    }

    It 'VMCard.xaml exists and is valid XML' {
        $path = Join-Path $guiRoot 'Components' 'VMCard.xaml'
        Test-Path $path | Should -Be $true
        { [xml](Get-Content -Raw -Path $path) } | Should -Not -Throw
    }

    It 'Start-OpenCodeLabGUI.ps1 exists and has no syntax errors' {
        $path = Join-Path $guiRoot 'Start-OpenCodeLabGUI.ps1'
        Test-Path $path | Should -Be $true
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
    }
}

Describe 'Theme Resource Dictionaries' {

    It 'Dark theme defines all required color keys' {
        $path = Join-Path $guiRoot 'Themes' 'Dark.xaml'
        $xml = [xml](Get-Content -Raw -Path $path)
        $ns = @{ x = 'http://schemas.microsoft.com/winfx/2006/xaml' }
        $requiredKeys = @('BackgroundColor', 'CardBackgroundColor', 'AccentColor', 'TextPrimaryColor', 'TextSecondaryColor', 'BorderColor', 'SuccessColor', 'ErrorColor', 'WarningColor')

        foreach ($key in $requiredKeys) {
            $node = $xml.ResourceDictionary.ChildNodes | Where-Object {
                $_.GetAttribute('Key', 'http://schemas.microsoft.com/winfx/2006/xaml') -eq $key
            }
            $node | Should -Not -BeNullOrEmpty -Because "Dark theme should define '$key'"
        }
    }

    It 'Light theme defines all required color keys' {
        $path = Join-Path $guiRoot 'Themes' 'Light.xaml'
        $xml = [xml](Get-Content -Raw -Path $path)
        $requiredKeys = @('BackgroundColor', 'CardBackgroundColor', 'AccentColor', 'TextPrimaryColor', 'TextSecondaryColor', 'BorderColor', 'SuccessColor', 'ErrorColor', 'WarningColor')

        foreach ($key in $requiredKeys) {
            $node = $xml.ResourceDictionary.ChildNodes | Where-Object {
                $_.GetAttribute('Key', 'http://schemas.microsoft.com/winfx/2006/xaml') -eq $key
            }
            $node | Should -Not -BeNullOrEmpty -Because "Light theme should define '$key'"
        }
    }

    It 'Both themes define same set of style keys' {
        $darkPath = Join-Path $guiRoot 'Themes' 'Dark.xaml'
        $lightPath = Join-Path $guiRoot 'Themes' 'Light.xaml'
        $darkXml = [xml](Get-Content -Raw -Path $darkPath)
        $lightXml = [xml](Get-Content -Raw -Path $lightPath)

        $getKeys = {
            param($xml)
            $xml.ResourceDictionary.ChildNodes | ForEach-Object {
                $_.GetAttribute('Key', 'http://schemas.microsoft.com/winfx/2006/xaml')
            } | Where-Object { $_ } | Sort-Object
        }

        $darkKeys = & $getKeys $darkXml
        $lightKeys = & $getKeys $lightXml
        $darkKeys | Should -Be $lightKeys
    }
}

Describe 'GUI Settings Persistence' {

    It 'Get-GuiSettings returns default Dark theme when file does not exist' {
        # Source the entry point to get the function
        $entryPoint = Join-Path $guiRoot 'Start-OpenCodeLabGUI.ps1'

        # Parse just the function definitions (don't execute the whole script)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($entryPoint, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0 -Because 'GUI entry point should parse without errors'
    }
}
```

**Step 2: Run the tests**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester 'C:\projects\AutomatedLab\Tests\WpfGui.Tests.ps1' -Verbose"`
Expected: All tests pass

**Step 3: Commit**

```bash
git add Tests/WpfGui.Tests.ps1
git commit -m "test(gui): add Pester tests for WPF XAML files and theme dictionaries"
```

---

### Task 11: Final Integration and Verification

**Files:**
- No new files — verification only

**Step 1: Run all Pester tests**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$c = New-PesterConfiguration; $c.Run.Path = 'C:\projects\AutomatedLab\Tests'; $c.Output.Verbosity = 'Detailed'; Invoke-Pester -Configuration $c"`
Expected: All tests pass (existing 215 + new GUI tests)

**Step 2: Run Docker test suite**

Run: `docker compose -f C:\projects\AutomatedLab\docker-compose.yml run --rm test`
Expected: All tests pass in container

**Step 3: Run pre-deploy validator**

Run: `docker compose -f C:\projects\AutomatedLab\docker-compose.yml run --rm validate`
Expected: All 5 checks pass

**Step 4: Manually test the full GUI**

Run: `powershell.exe -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"C:\projects\AutomatedLab\Scripts\Run-OpenCodeLab.ps1\" -GUI'"`

Verify:
- Window opens with dark theme
- Sidebar navigation works (Dashboard, Actions, Logs, Settings)
- Theme toggle switches between dark and light
- Dashboard shows VM cards (may show "Not created" if no VMs exist)
- Topology canvas renders gateway, switch, and VM nodes
- Actions view has working dropdowns, toggles, command preview
- Logs view shows entries and supports filtering
- Settings view loads config values, browse buttons work, save persists

**Step 5: Commit any final fixes, then push**

```bash
git push origin main
```

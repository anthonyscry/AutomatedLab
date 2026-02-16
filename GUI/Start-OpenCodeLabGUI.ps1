#Requires -Version 5.1

<#
.SYNOPSIS
    WPF GUI entry point for OpenCodeLab (AutomatedLab).
.DESCRIPTION
    Loads WPF assemblies, sources shared lab functions, and provides XAML
    loading and GUI settings persistence utilities.  Does NOT create a window
    -- that responsibility belongs to the main window view loaded later.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── WPF assemblies ──────────────────────────────────────────────────────────
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# ── Path roots ──────────────────────────────────────────────────────────────
$script:GuiRoot  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$script:RepoRoot = Split-Path -Parent $script:GuiRoot

# ── Source shared Private / Public helpers from the repo root ───────────────
foreach ($subDir in @('Private', 'Public')) {
    $dirPath = Join-Path $script:RepoRoot $subDir
    if (Test-Path $dirPath) {
        Get-ChildItem -Path $dirPath -Filter '*.ps1' -Recurse |
            ForEach-Object { . $_.FullName }
    }
}

# ── Source Lab-Config.ps1 (may fail on non-Windows path resolution) ─────────
$script:LabConfigPath = Join-Path $script:RepoRoot 'Lab-Config.ps1'
if (Test-Path $script:LabConfigPath) {
    try { . $script:LabConfigPath } catch {
        # Path-resolution errors (e.g. C:\ on Linux) are expected in some
        # environments.  If GlobalLabConfig was still populated, carry on.
        if (-not (Test-Path variable:GlobalLabConfig)) { throw $_ }
    }
    # Lab-Config.ps1 may set ErrorActionPreference to Stop internally;
    # reset to our own preference after sourcing.
    $ErrorActionPreference = 'Stop'
}

# ── XAML loader ─────────────────────────────────────────────────────────────
function Import-XamlFile {
    <#
    .SYNOPSIS
        Loads a .xaml file and returns the parsed WPF object tree.
    .DESCRIPTION
        Reads the XAML content, strips the x:Class attribute (which is only
        needed by the VS designer and causes XamlReader to fail), then parses
        through System.Windows.Markup.XamlReader.
    .PARAMETER Path
        Absolute or relative path to the .xaml file.
    .OUTPUTS
        The root WPF element defined in the XAML.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "XAML file not found: $Path"
    }

    $rawXaml = Get-Content -Path $Path -Raw
    # Remove x:Class="..." which is a designer-only attribute
    $rawXaml = $rawXaml -replace 'x:Class="[^"]*"', ''

    $reader  = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($rawXaml))
    try {
        [System.Windows.Markup.XamlReader]::Load($reader)
    }
    finally {
        $reader.Close()
        $reader.Dispose()
    }
}

# ── GUI settings persistence ───────────────────────────────────────────────
$script:GuiSettingsPath = Join-Path $script:RepoRoot '.planning' 'gui-settings.json'

function Get-GuiSettings {
    <#
    .SYNOPSIS
        Reads persisted GUI preferences from .planning/gui-settings.json.
    .OUTPUTS
        A hashtable of settings, or an empty hashtable if the file is missing
        or unreadable.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:GuiSettingsPath)) {
        return @{}
    }

    try {
        $json = Get-Content -Path $script:GuiSettingsPath -Raw | ConvertFrom-Json
        # Convert the PSCustomObject to a hashtable for easier consumption.
        $ht = @{}
        foreach ($prop in $json.PSObject.Properties) {
            $ht[$prop.Name] = $prop.Value
        }
        return $ht
    }
    catch {
        Write-Warning "Failed to read GUI settings: $_"
        return @{}
    }
}

function Save-GuiSettings {
    <#
    .SYNOPSIS
        Persists a hashtable of GUI preferences to .planning/gui-settings.json.
    .PARAMETER Settings
        Hashtable of key/value pairs to store.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings
    )

    $parentDir = Split-Path -Parent $script:GuiSettingsPath
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    $Settings | ConvertTo-Json -Depth 10 | Set-Content -Path $script:GuiSettingsPath -Encoding UTF8
}

# ── Theme switching ──────────────────────────────────────────────────────
$script:CurrentTheme = $null

function Set-AppTheme {
    <#
    .SYNOPSIS
        Loads a theme ResourceDictionary and applies it to the WPF Application.
    .PARAMETER Theme
        'Dark' or 'Light'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Dark','Light')]
        [string]$Theme
    )

    $themePath = Join-Path $script:GuiRoot 'Themes' "$Theme.xaml"
    $themeDict = Import-XamlFile -Path $themePath

    # Ensure there is a WPF Application instance (needed for merged dictionaries).
    if (-not [System.Windows.Application]::Current) {
        [void][System.Windows.Application]::new()
    }

    $app = [System.Windows.Application]::Current
    $app.Resources.MergedDictionaries.Clear()
    $app.Resources.MergedDictionaries.Add($themeDict)

    $script:CurrentTheme = $Theme
}

# ── View switching ───────────────────────────────────────────────────────
$script:CurrentView = $null

function Switch-View {
    <#
    .SYNOPSIS
        Loads a view XAML into the content area, replacing the current content.
    .PARAMETER ViewName
        The view name (e.g. 'Dashboard'), maps to GUI/Views/{ViewName}View.xaml.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ViewName
    )

    if ($script:CurrentView -eq $ViewName) { return }

    $viewPath = Join-Path $script:GuiRoot 'Views' "${ViewName}View.xaml"

    $script:contentArea.Children.Clear()

    if (Test-Path $viewPath) {
        $viewElement = Import-XamlFile -Path $viewPath
        $script:contentArea.Children.Add($viewElement) | Out-Null
    }
    else {
        $script:txtPlaceholder.Text = "$ViewName view coming soon..."
        $script:contentArea.Children.Add($script:txtPlaceholder) | Out-Null
    }

    $script:CurrentView = $ViewName

    # ── Post-load initialisation stubs ──────────────────────────────
    switch ($ViewName) {
        'Dashboard' { <# Initialize-DashboardView when ready #> }
        'Actions'   { <# Initialize-ActionsView when ready #> }
        'Logs'      { <# Initialize-LogsView when ready #> }
        'Settings'  { <# Initialize-SettingsView when ready #> }
    }
}

# ── Load main window ────────────────────────────────────────────────────
$mainWindowPath = Join-Path $script:GuiRoot 'MainWindow.xaml'

# Apply saved theme (or default to Dark) BEFORE loading the window so that
# DynamicResource references pick up the correct brushes immediately.
$guiSettings  = Get-GuiSettings
$initialTheme = if ($guiSettings['Theme']) { $guiSettings['Theme'] } else { 'Dark' }
Set-AppTheme -Theme $initialTheme

$mainWindow = Import-XamlFile -Path $mainWindowPath

# ── Resolve named elements ──────────────────────────────────────────────
$script:btnNavDashboard = $mainWindow.FindName('btnNavDashboard')
$script:btnNavActions   = $mainWindow.FindName('btnNavActions')
$script:btnNavLogs      = $mainWindow.FindName('btnNavLogs')
$script:btnNavSettings  = $mainWindow.FindName('btnNavSettings')
$script:btnThemeToggle  = $mainWindow.FindName('btnThemeToggle')
$script:contentArea     = $mainWindow.FindName('contentArea')
$script:txtPlaceholder  = $mainWindow.FindName('txtPlaceholder')

# ── Set initial toggle state (Checked = Dark) ───────────────────────────
$script:btnThemeToggle.IsChecked = ($initialTheme -eq 'Dark')

# ── Theme toggle handler ────────────────────────────────────────────────
$script:btnThemeToggle.Add_Click({
    $newTheme = if ($script:btnThemeToggle.IsChecked) { 'Dark' } else { 'Light' }
    Set-AppTheme -Theme $newTheme

    $settings = Get-GuiSettings
    $settings['Theme'] = $newTheme
    Save-GuiSettings -Settings $settings
})

# ── Wire navigation buttons ─────────────────────────────────────────────
$script:btnNavDashboard.Add_Click({ Switch-View -ViewName 'Dashboard' })
$script:btnNavActions.Add_Click({   Switch-View -ViewName 'Actions' })
$script:btnNavLogs.Add_Click({      Switch-View -ViewName 'Logs' })
$script:btnNavSettings.Add_Click({  Switch-View -ViewName 'Settings' })

# ── Default view ────────────────────────────────────────────────────────
Switch-View -ViewName 'Dashboard'

# ── Show window (blocks until closed) ───────────────────────────────────
$mainWindow.ShowDialog() | Out-Null

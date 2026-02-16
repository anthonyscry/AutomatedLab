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

    # ── Clear stale element refs when leaving a view ────────────────
    if ($script:CurrentView -eq 'Logs') {
        $script:LogOutputElement  = $null
        $script:LogScrollerElement = $null
    }

    $script:CurrentView = $ViewName

    # ── Post-load initialisation stubs ──────────────────────────────
    switch ($ViewName) {
        'Dashboard' { Initialize-DashboardView }
        'Actions'   { Initialize-ActionsView }
        'Logs'      { Initialize-LogsView }
        'Settings'  { Initialize-SettingsView }
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

# ── VM role display names ──────────────────────────────────────────────
$script:VMRoles = @{
    dc1  = 'Domain Controller'
    svr1 = 'Member Server'
    ws1  = 'Windows 11 Client'
    lin1 = 'Ubuntu Linux'
}

# ── VM status colour mapping ──────────────────────────────────────────
function Get-StatusColor {
    <#
    .SYNOPSIS
        Maps a Hyper-V VM state string to a WPF SolidColorBrush.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$State
    )

    switch ($State) {
        'Running' { [System.Windows.Media.Brushes]::LimeGreen }
        'Off'     { [System.Windows.Media.Brushes]::Red }
        'Paused'  { [System.Windows.Media.Brushes]::Yellow }
        'Saved'   { [System.Windows.Media.Brushes]::Orange }
        default   { [System.Windows.Media.Brushes]::Gray }
    }
}

# ── Create a single VM card element from XAML ─────────────────────────
function New-VMCardElement {
    <#
    .SYNOPSIS
        Loads VMCard.xaml and sets the VM name and role labels.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VMName
    )

    $cardPath = Join-Path $script:GuiRoot 'Components' 'VMCard.xaml'
    $card     = Import-XamlFile -Path $cardPath

    $card.FindName('txtVMName').Text = $VMName
    $roleName = if ($script:VMRoles.ContainsKey($VMName.ToLowerInvariant())) {
        $script:VMRoles[$VMName.ToLowerInvariant()]
    } else {
        'Virtual Machine'
    }
    $card.FindName('txtRole').Text = $roleName

    return $card
}

# ── Update an existing card with live VM data ─────────────────────────
function Update-VMCard {
    <#
    .SYNOPSIS
        Refreshes a VM card's status dot, IP, CPU/memory text, and button states.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.FrameworkElement]$Card,

        [Parameter(Mandatory)]
        [PSCustomObject]$VMData
    )

    $state = $VMData.State
    $Card.FindName('statusDot').Fill = Get-StatusColor -State $state

    # IP text — use NetworkStatus if available, otherwise '--'
    $ipText = if ($VMData.NetworkStatus -and $VMData.NetworkStatus -ne 'N/A') {
        "IP: $($VMData.NetworkStatus)"
    } else {
        'IP: --'
    }
    $Card.FindName('txtIP').Text = $ipText

    # CPU and memory
    $cpuText = if ($VMData.CPUUsage -and $VMData.CPUUsage -ne 'N/A') {
        "CPU: $($VMData.CPUUsage)"
    } else {
        'CPU: --'
    }
    $memText = if ($VMData.MemoryGB -and $VMData.MemoryGB -ne 'N/A') {
        "Mem: $($VMData.MemoryGB)"
    } else {
        'Mem: --'
    }
    $Card.FindName('txtCPU').Text    = $cpuText
    $Card.FindName('txtMemory').Text = $memText

    # Button enabled states
    $isRunning = ($state -eq 'Running')
    $Card.FindName('btnStart').IsEnabled   = -not $isRunning
    $Card.FindName('btnStop').IsEnabled    = $isRunning
    $Card.FindName('btnConnect').IsEnabled = $isRunning
}

# ── Network topology canvas drawing ───────────────────────────────────
function Update-TopologyCanvas {
    <#
    .SYNOPSIS
        Draws a network diagram (NAT gateway, virtual switch, VM nodes) on a
        WPF Canvas element using theme-aware brushes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.Canvas]$Canvas,

        [Parameter()]
        $VMStatuses
    )

    $Canvas.Children.Clear()

    # ── Canvas dimensions (fall back if not yet laid out) ────────
    $cw = if ($Canvas.ActualWidth  -gt 0) { $Canvas.ActualWidth  } else { 500 }
    $ch = if ($Canvas.ActualHeight -gt 0) { $Canvas.ActualHeight } else { 400 }

    # ── Theme brushes (inherited through the visual tree) ────────
    $accentBrush  = $Canvas.FindResource('AccentBrush')
    $cardBgBrush  = $Canvas.FindResource('CardBackgroundBrush')
    $borderBrush  = $Canvas.FindResource('BorderBrush')
    $textBrush    = $Canvas.FindResource('TextPrimaryBrush')
    $subTextBrush = $Canvas.FindResource('TextSecondaryBrush')

    # ── NAT Gateway box (top center) ────────────────────────────
    $gwWidth  = 140
    $gwHeight = 40
    $gwX = ($cw - $gwWidth) / 2
    $gwY = 20

    $gwRect = New-Object System.Windows.Shapes.Rectangle
    $gwRect.Width           = $gwWidth
    $gwRect.Height          = $gwHeight
    $gwRect.RadiusX         = 6
    $gwRect.RadiusY         = 6
    $gwRect.Stroke          = $accentBrush
    $gwRect.StrokeThickness = 2
    $gwRect.Fill            = $cardBgBrush
    [System.Windows.Controls.Canvas]::SetLeft($gwRect, $gwX)
    [System.Windows.Controls.Canvas]::SetTop($gwRect, $gwY)
    $Canvas.Children.Add($gwRect) | Out-Null

    $gatewayIP = if ((Test-Path variable:GlobalLabConfig) -and $GlobalLabConfig.Network.GatewayIp) {
        $GlobalLabConfig.Network.GatewayIp
    } else {
        '10.0.10.1'
    }

    $gwLabel = New-Object System.Windows.Controls.TextBlock
    $gwLabel.Text                = "NAT Gateway`n$gatewayIP"
    $gwLabel.Foreground          = $textBrush
    $gwLabel.FontSize            = 11
    $gwLabel.TextAlignment       = 'Center'
    $gwLabel.HorizontalAlignment = 'Center'
    $gwLabel.Width               = $gwWidth
    [System.Windows.Controls.Canvas]::SetLeft($gwLabel, $gwX)
    [System.Windows.Controls.Canvas]::SetTop($gwLabel, $gwY + 4)
    $Canvas.Children.Add($gwLabel) | Out-Null

    # ── Virtual Switch bar (middle) ─────────────────────────────
    $swMargin = 30
    $swWidth  = $cw - ($swMargin * 2)
    $swHeight = 30
    $swX = $swMargin
    $swY = $gwY + $gwHeight + 40

    $swRect = New-Object System.Windows.Shapes.Rectangle
    $swRect.Width           = $swWidth
    $swRect.Height          = $swHeight
    $swRect.RadiusX         = 4
    $swRect.RadiusY         = 4
    $swRect.Fill            = $cardBgBrush
    $swRect.Stroke          = $borderBrush
    $swRect.StrokeThickness = 1
    [System.Windows.Controls.Canvas]::SetLeft($swRect, $swX)
    [System.Windows.Controls.Canvas]::SetTop($swRect, $swY)
    $Canvas.Children.Add($swRect) | Out-Null

    $switchName = if ((Test-Path variable:GlobalLabConfig) -and $GlobalLabConfig.Network.SwitchName) {
        $GlobalLabConfig.Network.SwitchName
    } else {
        'AutomatedLab'
    }

    $swLabel = New-Object System.Windows.Controls.TextBlock
    $swLabel.Text                = "vSwitch: $switchName"
    $swLabel.Foreground          = $subTextBrush
    $swLabel.FontSize            = 11
    $swLabel.TextAlignment       = 'Center'
    $swLabel.HorizontalAlignment = 'Center'
    $swLabel.Width               = $swWidth
    $swLabel.Padding             = New-Object System.Windows.Thickness(0, 6, 0, 0)
    [System.Windows.Controls.Canvas]::SetLeft($swLabel, $swX)
    [System.Windows.Controls.Canvas]::SetTop($swLabel, $swY)
    $Canvas.Children.Add($swLabel) | Out-Null

    # ── Line from gateway to switch ─────────────────────────────
    $gwLine = New-Object System.Windows.Shapes.Line
    $gwLine.X1              = $cw / 2
    $gwLine.Y1              = $gwY + $gwHeight
    $gwLine.X2              = $cw / 2
    $gwLine.Y2              = $swY
    $gwLine.Stroke          = $borderBrush
    $gwLine.StrokeThickness = 2
    $Canvas.Children.Add($gwLine) | Out-Null

    # ── VM nodes below the switch ───────────────────────────────
    if (-not $VMStatuses -or $VMStatuses.Count -eq 0) { return }

    $nodeWidth  = 120
    $nodeHeight = 50
    $nodeY      = $swY + $swHeight + 40
    $vmCount    = @($VMStatuses).Count
    $spacing    = $cw / ($vmCount + 1)

    for ($i = 0; $i -lt $vmCount; $i++) {
        $vm = @($VMStatuses)[$i]
        $nodeX = ($spacing * ($i + 1)) - ($nodeWidth / 2)

        $stateColor = Get-StatusColor -State ($vm.State)

        # Line from switch to node
        $vmLine = New-Object System.Windows.Shapes.Line
        $vmLine.X1              = $spacing * ($i + 1)
        $vmLine.Y1              = $swY + $swHeight
        $vmLine.X2              = $spacing * ($i + 1)
        $vmLine.Y2              = $nodeY
        $vmLine.Stroke          = $stateColor
        $vmLine.StrokeThickness = 2
        $Canvas.Children.Add($vmLine) | Out-Null

        # Node rectangle
        $nodeRect = New-Object System.Windows.Shapes.Rectangle
        $nodeRect.Width           = $nodeWidth
        $nodeRect.Height          = $nodeHeight
        $nodeRect.RadiusX         = 6
        $nodeRect.RadiusY         = 6
        $nodeRect.Fill            = $cardBgBrush
        $nodeRect.Stroke          = $stateColor
        $nodeRect.StrokeThickness = 2
        [System.Windows.Controls.Canvas]::SetLeft($nodeRect, $nodeX)
        [System.Windows.Controls.Canvas]::SetTop($nodeRect, $nodeY)
        $Canvas.Children.Add($nodeRect) | Out-Null

        # Node label (VM name + IP)
        $ipText = if ($vm.NetworkStatus -and $vm.NetworkStatus -ne 'N/A') {
            $vm.NetworkStatus
        } else {
            '--'
        }
        $nodeLabel = New-Object System.Windows.Controls.TextBlock
        $nodeLabel.Text                = "$($vm.VMName.ToUpper())`n$ipText"
        $nodeLabel.Foreground          = $textBrush
        $nodeLabel.FontSize            = 10
        $nodeLabel.TextAlignment       = 'Center'
        $nodeLabel.HorizontalAlignment = 'Center'
        $nodeLabel.Width               = $nodeWidth
        $nodeLabel.Padding             = New-Object System.Windows.Thickness(0, 8, 0, 0)
        [System.Windows.Controls.Canvas]::SetLeft($nodeLabel, $nodeX)
        [System.Windows.Controls.Canvas]::SetTop($nodeLabel, $nodeY)
        $Canvas.Children.Add($nodeLabel) | Out-Null
    }
}

# ── Dashboard initialisation ──────────────────────────────────────────
function Initialize-DashboardView {
    <#
    .SYNOPSIS
        Populates the Dashboard with VM cards and starts a polling timer.
    #>
    [CmdletBinding()]
    param()

    # Resolve the view element that was just loaded into contentArea
    $viewElement = $script:contentArea.Children[0]

    $vmContainer          = $viewElement.FindName('vmCardContainer')
    $txtNoVMs             = $viewElement.FindName('txtNoVMs')
    $script:TopologyCanvas = $viewElement.FindName('topologyCanvas')

    # Determine VM names from lab config or use defaults
    $vmNames = if ((Test-Path variable:GlobalLabConfig) -and $GlobalLabConfig.Lab.CoreVMNames) {
        @($GlobalLabConfig.Lab.CoreVMNames)
    } else {
        @('dc1', 'svr1', 'ws1')
    }

    # Build a card for each VM
    $script:VMCards = @{}
    foreach ($vmName in $vmNames) {
        $card = New-VMCardElement -VMName $vmName

        # Wire button handlers — use .GetNewClosure() to capture $vmName
        $startBlock = { Start-VM -Name $vmName -ErrorAction SilentlyContinue }.GetNewClosure()
        $stopBlock  = { Stop-VM -Name $vmName -Force -ErrorAction SilentlyContinue }.GetNewClosure()
        $connBlock  = { & vmconnect.exe localhost $vmName }.GetNewClosure()

        $card.FindName('btnStart').Add_Click($startBlock)
        $card.FindName('btnStop').Add_Click($stopBlock)
        $card.FindName('btnConnect').Add_Click($connBlock)

        $vmContainer.Children.Add($card) | Out-Null
        $script:VMCards[$vmName] = $card
    }

    # Hide placeholder if we have VMs
    if ($vmNames.Count -gt 0) {
        $txtNoVMs.Visibility = [System.Windows.Visibility]::Collapsed
    }

    # ── Polling timer (5-second interval) ─────────────────────────
    $script:VMPollTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:VMPollTimer.Interval = [TimeSpan]::FromSeconds(5)
    $script:VMPollTimer.Add_Tick({
        try {
            $statuses = Get-LabStatus
            foreach ($vmData in $statuses) {
                $name = $vmData.VMName
                if ($script:VMCards.ContainsKey($name)) {
                    Update-VMCard -Card $script:VMCards[$name] -VMData $vmData
                }
            }
            Update-TopologyCanvas -Canvas $script:TopologyCanvas -VMStatuses $statuses
        }
        catch {
            # Silently ignore polling errors to keep the GUI responsive
        }
    })
    $script:VMPollTimer.Start()
}

# ── Actions view initialisation ────────────────────────────────────────
$script:ActionsInitialized = $false

function Initialize-ActionsView {
    <#
    .SYNOPSIS
        Wires up the Actions view controls: combo boxes, toggles, text boxes,
        command preview, and the Run button with destructive-action safety gates.
    #>
    [CmdletBinding()]
    param()

    if ($script:ActionsInitialized) { return }

    $viewElement = $script:contentArea.Children[0]

    # ── Resolve named controls ────────────────────────────────────
    $cmbAction          = $viewElement.FindName('cmbAction')
    $cmbMode            = $viewElement.FindName('cmbMode')
    $tglNonInteractive  = $viewElement.FindName('tglNonInteractive')
    $tglForce           = $viewElement.FindName('tglForce')
    $tglDryRun          = $viewElement.FindName('tglDryRun')
    $expAdvanced        = $viewElement.FindName('expAdvanced')
    $tglRemoveNetwork   = $viewElement.FindName('tglRemoveNetwork')
    $tglCoreOnly        = $viewElement.FindName('tglCoreOnly')
    $txtProfilePath     = $viewElement.FindName('txtProfilePath')
    $txtDefaultsFile    = $viewElement.FindName('txtDefaultsFile')
    $txtTargetHosts     = $viewElement.FindName('txtTargetHosts')
    $txtConfirmationToken = $viewElement.FindName('txtConfirmationToken')
    $txtCommandPreview  = $viewElement.FindName('txtCommandPreview')
    $btnRunAction       = $viewElement.FindName('btnRunAction')

    # ── Populate combo boxes ──────────────────────────────────────
    $actions = @('deploy', 'teardown', 'status', 'health', 'setup',
                 'one-button-setup', 'one-button-reset', 'blow-away')
    foreach ($a in $actions) { $cmbAction.Items.Add($a) | Out-Null }
    $cmbAction.SelectedIndex = 0

    $modes = @('quick', 'full')
    foreach ($m in $modes) { $cmbMode.Items.Add($m) | Out-Null }
    $cmbMode.SelectedIndex = 0

    # ── Collect options from controls ─────────────────────────────
    $getOptions = {
        $opts = @{
            Action            = $cmbAction.SelectedItem
            Mode              = $cmbMode.SelectedItem
            NonInteractive    = [bool]$tglNonInteractive.IsChecked
            Force             = [bool]$tglForce.IsChecked
            DryRun            = [bool]$tglDryRun.IsChecked
            RemoveNetwork     = [bool]$tglRemoveNetwork.IsChecked
            CoreOnly          = [bool]$tglCoreOnly.IsChecked
            ProfilePath       = $txtProfilePath.Text
            DefaultsFile      = $txtDefaultsFile.Text
            TargetHosts       = $txtTargetHosts.Text
            ConfirmationToken = $txtConfirmationToken.Text
        }
        return $opts
    }.GetNewClosure()

    # ── Update command preview ────────────────────────────────────
    $appScriptPath = Join-Path $script:RepoRoot 'OpenCodeLab.ps1'

    $updatePreview = {
        $opts = & $getOptions
        $preview = New-LabGuiCommandPreview -AppScriptPath $appScriptPath -Options $opts
        $txtCommandPreview.Text = $preview
    }.GetNewClosure()

    # ── Update layout (auto-expand advanced for destructive) ──────
    $updateLayout = {
        $opts = & $getOptions
        $layout = Get-LabGuiLayoutState -Action $opts.Action -Mode $opts.Mode `
                      -ProfilePath $opts.ProfilePath -TargetHosts $opts.TargetHosts
        if ($layout.ShowAdvanced) {
            $expAdvanced.IsExpanded = $true
        }
    }.GetNewClosure()

    # ── Wire events ───────────────────────────────────────────────
    $onChanged = {
        & $updatePreview
        & $updateLayout
    }.GetNewClosure()

    $cmbAction.Add_SelectionChanged($onChanged)
    $cmbMode.Add_SelectionChanged($onChanged)

    $tglNonInteractive.Add_Click({ & $updatePreview }.GetNewClosure())
    $tglForce.Add_Click({ & $updatePreview }.GetNewClosure())
    $tglDryRun.Add_Click({ & $updatePreview }.GetNewClosure())
    $tglRemoveNetwork.Add_Click({ & $updatePreview }.GetNewClosure())
    $tglCoreOnly.Add_Click({ & $updatePreview }.GetNewClosure())

    $txtProfilePath.Add_TextChanged($onChanged)
    $txtDefaultsFile.Add_TextChanged({ & $updatePreview }.GetNewClosure())
    $txtTargetHosts.Add_TextChanged($onChanged)
    $txtConfirmationToken.Add_TextChanged({ & $updatePreview }.GetNewClosure())

    # ── Run button handler ────────────────────────────────────────
    $btnRunAction.Add_Click({
        $opts = & $getOptions

        # Safety gate for destructive actions
        $guard = Get-LabGuiDestructiveGuard -Action $opts.Action -Mode $opts.Mode `
                     -ProfilePath $opts.ProfilePath
        if ($guard.RequiresConfirmation) {
            $result = [System.Windows.MessageBox]::Show(
                "This will perform: $($guard.ConfirmationLabel).`n`nAre you sure you want to continue?",
                'Confirm Destructive Action',
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning
            )
            if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
        }

        # Build argument list and launch elevated
        $argList = New-LabAppArgumentList -Options $opts
        $scriptPath = Join-Path $script:RepoRoot 'OpenCodeLab.ps1'
        $fullArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath) + $argList

        try {
            Start-Process powershell.exe -Verb RunAs -ArgumentList $fullArgs
        }
        catch {
            [System.Windows.MessageBox]::Show(
                "Failed to launch action: $_",
                'Error',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            ) | Out-Null
            return
        }

        # Log the action if Add-LogEntry is available
        if (Get-Command -Name Add-LogEntry -ErrorAction SilentlyContinue) {
            Add-LogEntry -Message "Launched: $($opts.Action) ($($opts.Mode))"
        }

        # Switch to Logs view
        Switch-View -ViewName 'Logs'
    }.GetNewClosure())

    # ── Initial preview ───────────────────────────────────────────
    & $updatePreview

    $script:ActionsInitialized = $true
}

# ── Log management ──────────────────────────────────────────────────────
$script:LogEntries        = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:LogFilter         = 'All'
$script:LogOutputElement  = $null
$script:LogScrollerElement = $null

function Add-LogEntry {
    <#
    .SYNOPSIS
        Appends a timestamped, levelled log entry and refreshes the log display.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info','Warning','Error','Success')]
        [string]$Level = 'Info'
    )

    $entry = [PSCustomObject]@{
        Timestamp = (Get-Date).ToString('HH:mm:ss')
        Level     = $Level
        Message   = $Message
    }
    $script:LogEntries.Add($entry)

    if ($script:LogOutputElement) {
        Render-LogEntries
    }
}

function Render-LogEntries {
    <#
    .SYNOPSIS
        Renders colour-coded log entries into the txtLogOutput TextBlock using Inlines.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:LogOutputElement) { return }

    $script:LogOutputElement.Inlines.Clear()

    foreach ($entry in $script:LogEntries) {
        if ($script:LogFilter -ne 'All' -and $entry.Level -ne $script:LogFilter) {
            continue
        }

        $text = "[$($entry.Timestamp)] [$($entry.Level.ToUpper())] $($entry.Message)`n"
        $run  = New-Object System.Windows.Documents.Run($text)

        $brushKey = switch ($entry.Level) {
            'Error'   { 'ErrorBrush' }
            'Warning' { 'WarningBrush' }
            'Success' { 'SuccessBrush' }
            default   { 'TextPrimaryBrush' }
        }
        $run.Foreground = $mainWindow.FindResource($brushKey)

        $script:LogOutputElement.Inlines.Add($run)
    }

    if ($script:LogScrollerElement) {
        $script:LogScrollerElement.ScrollToEnd()
    }
}

function Initialize-LogsView {
    <#
    .SYNOPSIS
        Wires up the Logs view controls: filter combo, clear button, and renders
        any existing log entries.
    #>
    [CmdletBinding()]
    param()

    $viewElement = $script:contentArea.Children[0]

    $script:LogOutputElement   = $viewElement.FindName('txtLogOutput')
    $script:LogScrollerElement = $viewElement.FindName('logScroller')
    $cmbLogFilter              = $viewElement.FindName('cmbLogFilter')
    $btnClearLogs              = $viewElement.FindName('btnClearLogs')

    # Populate filter combo
    $filterOptions = @('All', 'Info', 'Warning', 'Error', 'Success')
    foreach ($opt in $filterOptions) {
        $cmbLogFilter.Items.Add($opt) | Out-Null
    }

    # Set current filter selection
    $idx = $filterOptions.IndexOf($script:LogFilter)
    $cmbLogFilter.SelectedIndex = if ($idx -ge 0) { $idx } else { 0 }

    # Wire filter change
    $cmbLogFilter.Add_SelectionChanged({
        $selected = $cmbLogFilter.SelectedItem
        if ($selected) {
            $script:LogFilter = $selected.ToString()
            Render-LogEntries
        }
    }.GetNewClosure())

    # Wire clear button
    $btnClearLogs.Add_Click({
        $script:LogEntries.Clear()
        Render-LogEntries
    }.GetNewClosure())

    # Render existing entries
    Render-LogEntries
}

# ── Settings view initialisation ─────────────────────────────────────────
function Initialize-SettingsView {
    <#
    .SYNOPSIS
        Populates the Settings view controls from GlobalLabConfig and config.json,
        wires browse buttons, theme toggle, and save handler.
    #>
    [CmdletBinding()]
    param()

    $viewElement = $script:contentArea.Children[0]

    # ── Resolve named controls ────────────────────────────────────
    $txtLabRoot       = $viewElement.FindName('txtLabRoot')
    $txtIsoServer     = $viewElement.FindName('txtIsoServer')
    $txtIsoWin11      = $viewElement.FindName('txtIsoWin11')
    $btnBrowseServer  = $viewElement.FindName('btnBrowseServer')
    $btnBrowseWin11   = $viewElement.FindName('btnBrowseWin11')
    $txtSwitchName    = $viewElement.FindName('txtSwitchName')
    $txtSubnet        = $viewElement.FindName('txtSubnet')
    $txtGatewayIP     = $viewElement.FindName('txtGatewayIP')
    $txtAdminPassword = $viewElement.FindName('txtAdminPassword')
    $tglSettingsTheme = $viewElement.FindName('tglSettingsTheme')
    $btnSaveSettings  = $viewElement.FindName('btnSaveSettings')

    # ── Populate from GlobalLabConfig ─────────────────────────────
    if (Test-Path variable:GlobalLabConfig) {
        $txtLabRoot.Text    = $GlobalLabConfig.Paths.LabRoot
        $txtSwitchName.Text = $GlobalLabConfig.Network.SwitchName
        $txtSubnet.Text     = $GlobalLabConfig.Network.AddressSpace
        $txtGatewayIP.Text  = $GlobalLabConfig.Network.GatewayIp
        $txtAdminPassword.Password = $GlobalLabConfig.Credentials.AdminPassword
    }

    # ── Populate ISO paths from .planning/config.json ─────────────
    $configJsonPath = Join-Path $script:RepoRoot '.planning' 'config.json'
    if (Test-Path $configJsonPath) {
        try {
            $configJson = Get-Content -Path $configJsonPath -Raw | ConvertFrom-Json
            if ($configJson.IsoPaths) {
                $txtIsoServer.Text = $configJson.IsoPaths.Server2019
                $txtIsoWin11.Text  = $configJson.IsoPaths.Windows11
            }
        }
        catch {
            # Silently ignore parse errors
        }
    }

    # ── Theme toggle ──────────────────────────────────────────────
    $tglSettingsTheme.IsChecked = ($script:CurrentTheme -eq 'Dark')

    $tglSettingsTheme.Add_Click({
        $newTheme = if ($tglSettingsTheme.IsChecked) { 'Dark' } else { 'Light' }
        Set-AppTheme -Theme $newTheme

        $settings = Get-GuiSettings
        $settings['Theme'] = $newTheme
        Save-GuiSettings -Settings $settings

        # Sync sidebar theme toggle
        $script:btnThemeToggle.IsChecked = $tglSettingsTheme.IsChecked
    }.GetNewClosure())

    # ── Browse buttons (ISO file dialogs) ─────────────────────────
    Add-Type -AssemblyName System.Windows.Forms

    $btnBrowseServer.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title  = 'Select Server 2019 ISO'
        $dlg.Filter = 'ISO Files (*.iso)|*.iso|All Files (*.*)|*.*'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtIsoServer.Text = $dlg.FileName
        }
    }.GetNewClosure())

    $btnBrowseWin11.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title  = 'Select Windows 11 ISO'
        $dlg.Filter = 'ISO Files (*.iso)|*.iso|All Files (*.*)|*.*'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtIsoWin11.Text = $dlg.FileName
        }
    }.GetNewClosure())

    # ── Save button handler ───────────────────────────────────────
    $btnSaveSettings.Add_Click({
        # Validate gateway IP format
        $gwIP = $txtGatewayIP.Text.Trim()
        if ($gwIP -and $gwIP -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
            [System.Windows.MessageBox]::Show(
                "Invalid Gateway IP format. Please enter a valid IPv4 address (e.g. 10.0.0.1).",
                'Validation Error',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            ) | Out-Null
            return
        }

        # Update .planning/config.json ISO paths
        $configJsonPath = Join-Path $script:RepoRoot '.planning' 'config.json'
        try {
            if (Test-Path $configJsonPath) {
                $configJson = Get-Content -Path $configJsonPath -Raw | ConvertFrom-Json
            } else {
                $configJson = [PSCustomObject]@{ IsoPaths = [PSCustomObject]@{ Server2019 = ''; Windows11 = '' } }
            }

            $configJson.IsoPaths.Server2019 = $txtIsoServer.Text
            $configJson.IsoPaths.Windows11  = $txtIsoWin11.Text

            $parentDir = Split-Path -Parent $configJsonPath
            if (-not (Test-Path $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }
            $configJson | ConvertTo-Json -Depth 10 | Set-Content -Path $configJsonPath -Encoding UTF8

            [System.Windows.MessageBox]::Show(
                'Settings saved successfully.',
                'Settings',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            ) | Out-Null

            if (Get-Command -Name Add-LogEntry -ErrorAction SilentlyContinue) {
                Add-LogEntry -Message 'Settings saved' -Level 'Success'
            }
        }
        catch {
            [System.Windows.MessageBox]::Show(
                "Failed to save settings: $_",
                'Error',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            ) | Out-Null

            if (Get-Command -Name Add-LogEntry -ErrorAction SilentlyContinue) {
                Add-LogEntry -Message "Settings save failed: $_" -Level 'Error'
            }
        }
    }.GetNewClosure())
}

# ── Default view ────────────────────────────────────────────────────────
Switch-View -ViewName 'Dashboard'

# ── Show window (blocks until closed) ───────────────────────────────────
$mainWindow.ShowDialog() | Out-Null

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
        $helperFiles = Get-ChildItem -Path $dirPath -Filter '*.ps1' -Recurse
        foreach ($file in $helperFiles) {
            try {
                . $file.FullName
            }
            catch {
                throw "Failed to load $subDir helper '$($file.FullName)': $($_.Exception.Message)"
            }
        }
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
$script:GuiSettingsPath = Join-Path (Join-Path $script:RepoRoot '.planning') 'gui-settings.json'

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
        [void](New-Item -ItemType Directory -Path $parentDir -Force)
    }

    try {
        $Settings | ConvertTo-Json -Depth 10 | Set-Content -Path $script:GuiSettingsPath -Encoding UTF8
    }
    catch {
        Write-Warning "Failed to save GUI settings: $_"
    }
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

    $themePath = Join-Path (Join-Path $script:GuiRoot 'Themes') "$Theme.xaml"
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

    $viewPath = Join-Path (Join-Path $script:GuiRoot 'Views') "${ViewName}View.xaml"

    # ── Stop Dashboard timer when leaving ────────────────────────────
    if ($script:CurrentView -eq 'Dashboard') {
        if ($null -ne $script:VMPollTimer) {
            $script:VMPollTimer.Stop()
        }
    }

    try {
        $script:contentArea.Children.Clear()

        if (Test-Path $viewPath) {
            $viewElement = Import-XamlFile -Path $viewPath
            [void]$script:contentArea.Children.Add($viewElement)
        }
        else {
            $script:txtPlaceholder.Text = "$ViewName view coming soon..."
            [void]$script:contentArea.Children.Add($script:txtPlaceholder)
        }
    }
    catch {
        $script:contentArea.Children.Clear()
        $errBlock = New-Object System.Windows.Controls.TextBlock
        $errBlock.Text = "Failed to load $ViewName view: $_"
        $errBlock.Foreground = [System.Windows.Media.Brushes]::Red
        $errBlock.TextWrapping = 'Wrap'
        $errBlock.FontSize = 14
        [void]$script:contentArea.Children.Add($errBlock)
        return
    }

    # ── Clear stale element refs when leaving a view ────────────────
    if ($script:CurrentView -eq 'Logs') {
        $script:LogOutputElement  = $null
        $script:LogScrollerElement = $null
    }
    if ($script:CurrentView -eq 'Actions') {
        $script:ActionsInitialized = $false
    }

    $script:CurrentView = $ViewName

    # ── Post-load initialisation stubs ──────────────────────────────
    switch ($ViewName) {
        'Dashboard'  { Initialize-DashboardView }
        'Actions'    { Initialize-ActionsView }
        'Customize'  { Initialize-CustomizeView }
        'Logs'       { Initialize-LogsView }
        'Settings'   { Initialize-SettingsView }
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
$script:btnNavDashboard  = $mainWindow.FindName('btnNavDashboard')
$script:btnNavActions    = $mainWindow.FindName('btnNavActions')
$script:btnNavCustomize  = $mainWindow.FindName('btnNavCustomize')
$script:btnNavLogs       = $mainWindow.FindName('btnNavLogs')
$script:btnNavSettings   = $mainWindow.FindName('btnNavSettings')
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
$script:btnNavDashboard.Add_Click({  Switch-View -ViewName 'Dashboard' })
$script:btnNavActions.Add_Click({    Switch-View -ViewName 'Actions' })
$script:btnNavCustomize.Add_Click({  Switch-View -ViewName 'Customize' })
$script:btnNavLogs.Add_Click({       Switch-View -ViewName 'Logs' })
$script:btnNavSettings.Add_Click({   Switch-View -ViewName 'Settings' })

# ── Window Closing handler (cleanup timers) ─────────────────────────────
$mainWindow.Add_Closing({
    if ($null -ne $script:VMPollTimer) {
        $script:VMPollTimer.Stop()
        $script:VMPollTimer = $null
    }
})

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

    $cardPath = Join-Path (Join-Path $script:GuiRoot 'Components') 'VMCard.xaml'
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

    # IP text - use NetworkStatus if available, otherwise '--'
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
    [void]$Canvas.Children.Add($gwRect)

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
    [void]$Canvas.Children.Add($gwLabel)

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
    [void]$Canvas.Children.Add($swRect)

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
    [void]$Canvas.Children.Add($swLabel)

    # ── Line from gateway to switch ─────────────────────────────
    $gwLine = New-Object System.Windows.Shapes.Line
    $gwLine.X1              = $cw / 2
    $gwLine.Y1              = $gwY + $gwHeight
    $gwLine.X2              = $cw / 2
    $gwLine.Y2              = $swY
    $gwLine.Stroke          = $borderBrush
    $gwLine.StrokeThickness = 2
    [void]$Canvas.Children.Add($gwLine)

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
        [void]$Canvas.Children.Add($vmLine)

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
        [void]$Canvas.Children.Add($nodeRect)

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
        [void]$Canvas.Children.Add($nodeLabel)
    }
}

# ── Lab health state helper ───────────────────────────────────────────
function Get-LabHealthState {
    <#
    .SYNOPSIS
        Maps VM statuses to a lab health state (Healthy, Degraded, Offline, No Lab).
    .PARAMETER VMStatuses
        Array of VM status objects from Get-LabStatus.
    .OUTPUTS
        PSCustomObject with State (string) and Detail (string).
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        $VMStatuses
    )

    if (-not $VMStatuses -or @($VMStatuses).Count -eq 0) {
        return [pscustomobject]@{
            State  = 'No Lab'
            Detail = 'No VMs configured'
        }
    }

    $total   = @($VMStatuses).Count
    $running = @($VMStatuses | Where-Object { $_.State -eq 'Running' }).Count

    if ($running -eq $total) {
        return [pscustomobject]@{
            State  = 'Healthy'
            Detail = "$total of $total VMs running"
        }
    }
    elseif ($running -gt 0) {
        return [pscustomobject]@{
            State  = 'Degraded'
            Detail = "$running of $total VMs running"
        }
    }
    else {
        return [pscustomobject]@{
            State  = 'Offline'
            Detail = "0 of $total VMs running"
        }
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

    # Resolve new dashboard elements
    $healthBanner    = $viewElement.FindName('healthBanner')
    $txtHealthState  = $viewElement.FindName('txtHealthState')
    $txtHealthDetail = $viewElement.FindName('txtHealthDetail')
    $txtRAMUsage     = $viewElement.FindName('txtRAMUsage')
    $txtCPUUsage     = $viewElement.FindName('txtCPUUsage')
    $btnStartAll     = $viewElement.FindName('btnStartAll')
    $btnStopAll      = $viewElement.FindName('btnStopAll')
    $btnSaveCheckpoint = $viewElement.FindName('btnSaveCheckpoint')

    # ── Health banner update helper ──────────────────────────────
    $updateBanner = {
        param($VMStatuses)
        try {
            $health = Get-LabHealthState -VMStatuses $VMStatuses
            $txtHealthState.Text  = $health.State
            $txtHealthDetail.Text = $health.Detail

            switch ($health.State) {
                'Healthy'  {
                    $healthBanner.Background = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.Color]::FromRgb(27, 94, 32))
                }
                'Degraded' {
                    $healthBanner.Background = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.Color]::FromRgb(183, 149, 38))
                }
                'Offline'  {
                    $healthBanner.Background = [System.Windows.Media.SolidColorBrush]::new(
                        [System.Windows.Media.Color]::FromRgb(183, 28, 28))
                }
                default    {
                    $healthBanner.Background = $viewElement.FindResource('CardBackgroundBrush')
                }
            }
        }
        catch {
            $txtHealthState.Text  = 'Unknown'
            $txtHealthDetail.Text = 'Could not determine health state'
        }
    }.GetNewClosure()

    # ── Resource summary update helper ───────────────────────────
    $updateResources = {
        param($VMStatuses)
        try {
            $hostInfo = Get-LabHostResourceInfo

            # Calculate total RAM assigned from running VMs
            $totalAssignedGB = 0
            $runningCount = 0
            if ($VMStatuses) {
                foreach ($vm in @($VMStatuses)) {
                    if ($vm.State -eq 'Running' -and $vm.MemoryGB -and $vm.MemoryGB -ne 'N/A') {
                        $memText = $vm.MemoryGB -replace '[^0-9.]', ''
                        $parsed = 0.0
                        if ([double]::TryParse($memText, [ref]$parsed)) {
                            $totalAssignedGB += $parsed
                        }
                    }
                    if ($vm.State -eq 'Running') { $runningCount++ }
                }
            }

            $freeRAM = $hostInfo.FreeRAMGB
            $txtRAMUsage.Text = "RAM: $([math]::Round($totalAssignedGB, 1)) GB used by VMs | $freeRAM GB free on host"
            $txtCPUUsage.Text = "CPU: $runningCount VMs running / $($hostInfo.LogicalProcessors) logical cores on host"
        }
        catch {
            $txtRAMUsage.Text = 'RAM: unavailable'
            $txtCPUUsage.Text = 'CPU: unavailable'
        }
    }.GetNewClosure()

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

        # Wire button handlers - use .GetNewClosure() to capture $vmName
        $startBlock = { Start-VM -Name $vmName -ErrorAction SilentlyContinue }.GetNewClosure()
        $stopBlock  = { Stop-VM -Name $vmName -Force -ErrorAction SilentlyContinue }.GetNewClosure()
        $connBlock  = { & vmconnect.exe localhost $vmName }.GetNewClosure()

        $card.FindName('btnStart').Add_Click($startBlock)
        $card.FindName('btnStop').Add_Click($stopBlock)
        $card.FindName('btnConnect').Add_Click($connBlock)

        [void]$vmContainer.Children.Add($card)
        $script:VMCards[$vmName] = $card
    }

    # Hide placeholder if we have VMs
    if ($vmNames.Count -gt 0) {
        $txtNoVMs.Visibility = [System.Windows.Visibility]::Collapsed
    }

    # ── Wire bulk action buttons ──────────────────────────────────
    $btnStartAll.Add_Click({
        foreach ($vmName in $vmNames) {
            try { Start-VM -Name $vmName -ErrorAction SilentlyContinue } catch {}
        }
        if (Get-Command -Name Add-LogEntry -ErrorAction SilentlyContinue) {
            Add-LogEntry -Message "Started all lab VMs" -Level 'Info'
        }
    }.GetNewClosure())

    $btnStopAll.Add_Click({
        foreach ($vmName in $vmNames) {
            try { Stop-VM -Name $vmName -Force -ErrorAction SilentlyContinue } catch {}
        }
        if (Get-Command -Name Add-LogEntry -ErrorAction SilentlyContinue) {
            Add-LogEntry -Message "Stopped all lab VMs" -Level 'Info'
        }
    }.GetNewClosure())

    $btnSaveCheckpoint.Add_Click({
        $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
        foreach ($vmName in $vmNames) {
            try {
                Checkpoint-VM -Name $vmName -SnapshotName "GUI-$timestamp" -ErrorAction SilentlyContinue
            } catch {}
        }
        if (Get-Command -Name Add-LogEntry -ErrorAction SilentlyContinue) {
            Add-LogEntry -Message "Saved checkpoint for all lab VMs (GUI-$timestamp)" -Level 'Success'
        }
    }.GetNewClosure())

    # ── Initial poll (immediate update) ───────────────────────────
    try {
        $statuses = Get-LabStatus
        foreach ($vmData in $statuses) {
            $name = $vmData.VMName
            if ($script:VMCards.ContainsKey($name)) {
                Update-VMCard -Card $script:VMCards[$name] -VMData $vmData
            }
        }
        Update-TopologyCanvas -Canvas $script:TopologyCanvas -VMStatuses $statuses
        & $updateBanner $statuses
        & $updateResources $statuses
    }
    catch {
        # Silently ignore initial poll errors
    }

    # ── Polling timer (5-second interval) ─────────────────────────
    if ($null -ne $script:VMPollTimer) {
        # Timer already exists from previous Dashboard visit - just restart it
        $script:VMPollTimer.Start()
    }
    else {
        # Create new timer on first visit
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
                & $updateBanner $statuses
                & $updateResources $statuses
            }
            catch {
                # Silently ignore polling errors to keep the GUI responsive
            }
        }.GetNewClosure())
        $script:VMPollTimer.Start()
    }
}

# ── Customize view initialisation ──────────────────────────────────────
function Initialize-CustomizeView {
    <#
    .SYNOPSIS
        Wires up the Customize view controls: template selection, VM editor rows,
        save/apply/new/delete template buttons.
    #>
    [CmdletBinding()]
    param()

    try {
        $viewElement = $script:contentArea.Children[0]

    # ── Resolve named controls ────────────────────────────────────
    $cmbTemplate          = $viewElement.FindName('cmbTemplate')
    $btnNewTemplate       = $viewElement.FindName('btnNewTemplate')
    $btnDeleteTemplate    = $viewElement.FindName('btnDeleteTemplate')
    $txtTemplateDescription = $viewElement.FindName('txtTemplateDescription')
    $pnlNewTemplate       = $viewElement.FindName('pnlNewTemplate')
    $txtNewTemplateName   = $viewElement.FindName('txtNewTemplateName')
    $btnCreateTemplate    = $viewElement.FindName('btnCreateTemplate')
    $btnCancelNew         = $viewElement.FindName('btnCancelNew')
    $vmEditorContainer    = $viewElement.FindName('vmEditorContainer')
    $btnAddVM             = $viewElement.FindName('btnAddVM')
    $txtEditDescription   = $viewElement.FindName('txtEditDescription')
    $btnSaveTemplate      = $viewElement.FindName('btnSaveTemplate')
    $btnApplyTemplate     = $viewElement.FindName('btnApplyTemplate')

    # ── Available roles ───────────────────────────────────────────
    $roles = @('DC', 'Server', 'Client', 'DSC', 'IIS', 'SQL', 'WSUS', 'DHCP',
               'FileServer', 'PrintServer', 'Jumpbox', 'Ubuntu')

    # ── Capture function references and paths for closures ───────
    $fnSaveTemplate = Get-Command -Name Save-LabTemplate -ErrorAction Stop
    $repoRoot = $script:RepoRoot

    # ── Templates directory ───────────────────────────────────────
    $templatesDir = Join-Path (Join-Path $repoRoot '.planning') 'templates'

    # ── Helper: create a VM editor row ────────────────────────────
    $newVMEditorRow = {
        param(
            [string]$VMName = '',
            [string]$VMRole = 'Server',
            [string]$VMIP = '',
            [int]$VMMemory = 4,
            [int]$VMProcessors = 4
        )

        $rowBorder = New-Object System.Windows.Controls.Border
        $rowBorder.Background      = $viewElement.FindResource('CardBackgroundBrush')
        $rowBorder.BorderBrush     = $viewElement.FindResource('BorderBrush')
        $rowBorder.BorderThickness = New-Object System.Windows.Thickness(1)
        $rowBorder.CornerRadius    = New-Object System.Windows.CornerRadius(4)
        $rowBorder.Padding         = New-Object System.Windows.Thickness(8)
        $rowBorder.Margin          = New-Object System.Windows.Thickness(0, 0, 0, 4)

        $rowGrid = New-Object System.Windows.Controls.Grid
        $colWidths = @(120, 100, 120, 70, 70, 50)
        foreach ($w in $colWidths) {
            $colDef = New-Object System.Windows.Controls.ColumnDefinition
            $colDef.Width = New-Object System.Windows.GridLength($w)
            $rowGrid.ColumnDefinitions.Add($colDef)
        }

        # Name TextBox
        $txtName = New-Object System.Windows.Controls.TextBox
        $txtName.Text = $VMName
        $txtName.Tag  = 'vmName'
        $txtName.Style = $viewElement.FindResource('ModernTextBox')
        $txtName.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
        [System.Windows.Controls.Grid]::SetColumn($txtName, 0)
        [void]$rowGrid.Children.Add($txtName)

        # Role ComboBox
        $cmbRole = New-Object System.Windows.Controls.ComboBox
        $cmbRole.Tag = 'vmRole'
        $cmbRole.Style = $viewElement.FindResource('ModernComboBox')
        $cmbRole.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
        foreach ($r in $roles) { [void]$cmbRole.Items.Add($r) }
        $roleIdx = $roles.IndexOf($VMRole)
        $cmbRole.SelectedIndex = if ($roleIdx -ge 0) { $roleIdx } else { 1 }
        [System.Windows.Controls.Grid]::SetColumn($cmbRole, 1)
        [void]$rowGrid.Children.Add($cmbRole)

        # IP TextBox
        $txtIP = New-Object System.Windows.Controls.TextBox
        $txtIP.Text = $VMIP
        $txtIP.Tag  = 'vmIP'
        $txtIP.Style = $viewElement.FindResource('ModernTextBox')
        $txtIP.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
        [System.Windows.Controls.Grid]::SetColumn($txtIP, 2)
        [void]$rowGrid.Children.Add($txtIP)

        # Memory TextBox
        $txtMem = New-Object System.Windows.Controls.TextBox
        $txtMem.Text = $VMMemory.ToString()
        $txtMem.Tag  = 'vmMemory'
        $txtMem.Style = $viewElement.FindResource('ModernTextBox')
        $txtMem.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
        [System.Windows.Controls.Grid]::SetColumn($txtMem, 3)
        [void]$rowGrid.Children.Add($txtMem)

        # Processors TextBox
        $txtProc = New-Object System.Windows.Controls.TextBox
        $txtProc.Text = $VMProcessors.ToString()
        $txtProc.Tag  = 'vmProcessors'
        $txtProc.Style = $viewElement.FindResource('ModernTextBox')
        $txtProc.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
        [System.Windows.Controls.Grid]::SetColumn($txtProc, 4)
        [void]$rowGrid.Children.Add($txtProc)

        # Remove button
        $btnRemove = New-Object System.Windows.Controls.Button
        $btnRemove.Content = 'X'
        $btnRemove.Style   = $viewElement.FindResource('ModernButton')
        $btnRemove.Padding = New-Object System.Windows.Thickness(6, 2, 6, 2)
        [System.Windows.Controls.Grid]::SetColumn($btnRemove, 5)
        $btnRemove.Add_Click({
            $row = $this.Parent.Parent
            $vmEditorContainer.Children.Remove($row)
        }.GetNewClosure())
        [void]$rowGrid.Children.Add($btnRemove)

        $rowBorder.Child = $rowGrid
        return $rowBorder
    }.GetNewClosure()

    # ── Helper: read VM data from editor rows ─────────────────────
    $getVMsFromEditor = {
        $vmList = @()
        foreach ($row in $vmEditorContainer.Children) {
            $grid = $row.Child
            $vmName = ''; $vmRole = 'Server'; $vmIP = ''; $vmMem = 4; $vmProc = 4
            foreach ($child in $grid.Children) {
                $tag = $child.Tag
                if (-not $tag) { continue }
                switch ($tag) {
                    'vmName'       { $vmName = $child.Text }
                    'vmRole'       {
                        if ($child.SelectedItem) { $vmRole = $child.SelectedItem.ToString() }
                    }
                    'vmIP'         { $vmIP = $child.Text }
                    'vmMemory'     {
                        $parsed = 0
                        if ([int]::TryParse($child.Text, [ref]$parsed)) { $vmMem = $parsed }
                    }
                    'vmProcessors' {
                        $parsed = 0
                        if ([int]::TryParse($child.Text, [ref]$parsed)) { $vmProc = $parsed }
                    }
                }
            }
            $vmList += [pscustomobject]@{
                name       = $vmName
                role       = $vmRole
                ip         = $vmIP
                memoryGB   = $vmMem
                processors = $vmProc
            }
        }
        return $vmList
    }.GetNewClosure()

    # ── Helper: load a template into the editor ───────────────────
    $loadTemplate = {
        param([string]$TemplateName)

        $vmEditorContainer.Children.Clear()

        $templatePath = Join-Path $templatesDir "$TemplateName.json"
        if (-not (Test-Path $templatePath)) { return }

        try {
            $template = Get-Content -Path $templatePath -Raw | ConvertFrom-Json
        }
        catch {
            $txtTemplateDescription.Text = "Error loading template: $_"
            return
        }

        $txtTemplateDescription.Text = $template.description
        $txtEditDescription.Text     = $template.description

        foreach ($vm in $template.vms) {
            $row = & $newVMEditorRow -VMName $vm.name -VMRole $vm.role `
                       -VMIP $vm.ip -VMMemory ([int]$vm.memoryGB) -VMProcessors ([int]$vm.processors)
            [void]$vmEditorContainer.Children.Add($row)
        }
    }.GetNewClosure()

    # ── Helper: compute auto-incremented IP ───────────────────────
    $getNextIP = {
        $lastOctet = 10
        foreach ($row in $vmEditorContainer.Children) {
            $grid = $row.Child
            foreach ($child in $grid.Children) {
                if ($child.Tag -eq 'vmIP' -and $child.Text -match '\.(\d+)$') {
                    $octet = [int]$matches[1]
                    if ($octet -ge $lastOctet) { $lastOctet = $octet }
                }
            }
        }
        $newOctet = $lastOctet + 10
        return "10.0.10.$newOctet"
    }.GetNewClosure()

    # ── Populate template ComboBox ────────────────────────────────
    $refreshTemplateList = {
        param([string]$SelectName = '')

        $cmbTemplate.Items.Clear()

        if (-not (Test-Path $templatesDir)) { return }

        $templateFiles = Get-ChildItem -Path $templatesDir -Filter '*.json' -File
        foreach ($f in $templateFiles) {
            $tName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            [void]$cmbTemplate.Items.Add($tName)
        }

        if ($SelectName -and $cmbTemplate.Items.Contains($SelectName)) {
            $cmbTemplate.SelectedItem = $SelectName
        }
        elseif ($cmbTemplate.Items.Count -gt 0) {
            $cmbTemplate.SelectedIndex = 0
        }
    }.GetNewClosure()

    # ── Wire template selection ───────────────────────────────────
    $cmbTemplate.Add_SelectionChanged({
        $selected = $cmbTemplate.SelectedItem
        if ($selected) {
            & $loadTemplate -TemplateName $selected.ToString()
        }
    }.GetNewClosure())

    # ── New template button ───────────────────────────────────────
    $btnNewTemplate.Add_Click({
        $pnlNewTemplate.Visibility = [System.Windows.Visibility]::Visible
        $txtNewTemplateName.Text = ''
        [void]$txtNewTemplateName.Focus()
    }.GetNewClosure())

    $btnCancelNew.Add_Click({
        $pnlNewTemplate.Visibility = [System.Windows.Visibility]::Collapsed
    }.GetNewClosure())

    $btnCreateTemplate.Add_Click({
        $newName = $txtNewTemplateName.Text.Trim()
        if (-not $newName) {
            [void][System.Windows.MessageBox]::Show(
                'Please enter a template name.',
                'Validation Error',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        if ($newName -notmatch '^[a-zA-Z0-9_-]+$') {
            [void][System.Windows.MessageBox]::Show(
                'Template name must contain only letters, numbers, hyphens, and underscores.',
                'Validation Error',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        # Create a new template with one default VM
        $defaultVM = @([pscustomobject]@{
            name       = 'vm1'
            role       = 'Server'
            ip         = '10.0.10.10'
            memoryGB   = 4
            processors = 4
        })

        $result = & $fnSaveTemplate -RepoRoot $repoRoot -Name $newName `
                      -Description '' -VMs $defaultVM
        if ($result.Success) {
            $pnlNewTemplate.Visibility = [System.Windows.Visibility]::Collapsed
            & $refreshTemplateList -SelectName $newName
            if (Get-Command -Name Add-LogEntry -ErrorAction SilentlyContinue) {
                Add-LogEntry -Message "Created template: $newName" -Level 'Success'
            }
        }
        else {
            [void][System.Windows.MessageBox]::Show(
                $result.Message,
                'Error',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
        }
    }.GetNewClosure())

    # ── Delete template button ────────────────────────────────────
    $btnDeleteTemplate.Add_Click({
        $selected = $cmbTemplate.SelectedItem
        if (-not $selected) { return }

        $selectedName = $selected.ToString()
        if ($selectedName -eq 'default') {
            [void][System.Windows.MessageBox]::Show(
                'The default template cannot be deleted.',
                'Delete Template',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        $confirm = [System.Windows.MessageBox]::Show(
            "Delete template '$selectedName'?",
            'Confirm Delete',
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )

        if ($confirm -eq [System.Windows.MessageBoxResult]::Yes) {
            $templatePath = Join-Path $templatesDir "$selectedName.json"
            if (Test-Path $templatePath) {
                Remove-Item -Path $templatePath -Force
            }
            & $refreshTemplateList
            if (Get-Command -Name Add-LogEntry -ErrorAction SilentlyContinue) {
                Add-LogEntry -Message "Deleted template: $selectedName" -Level 'Info'
            }
        }
    }.GetNewClosure())

    # ── Add VM button ─────────────────────────────────────────────
    $btnAddVM.Add_Click({
        $nextIP = & $getNextIP
        $row = & $newVMEditorRow -VMName '' -VMRole 'Server' `
                   -VMIP $nextIP -VMMemory 4 -VMProcessors 4
        [void]$vmEditorContainer.Children.Add($row)
    }.GetNewClosure())

    # ── Save template button ──────────────────────────────────────
    $btnSaveTemplate.Add_Click({
        $selected = $cmbTemplate.SelectedItem
        if (-not $selected) {
            [void][System.Windows.MessageBox]::Show(
                'No template selected.',
                'Save Template',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        $templateName = $selected.ToString()
        $vms = & $getVMsFromEditor

        # Validate VM names are not empty
        $emptyNames = @($vms | Where-Object { [string]::IsNullOrWhiteSpace($_.name) })
        if ($emptyNames.Count -gt 0) {
            [void][System.Windows.MessageBox]::Show(
                "All VMs must have a name. Please fill in empty name fields.",
                'Validation Error',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        $description = $txtEditDescription.Text

        $result = & $fnSaveTemplate -RepoRoot $repoRoot -Name $templateName `
                      -Description $description -VMs $vms
        if ($result.Success) {
            [void][System.Windows.MessageBox]::Show(
                $result.Message,
                'Save Template',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            )
            if (Get-Command -Name Add-LogEntry -ErrorAction SilentlyContinue) {
                Add-LogEntry -Message "Saved template: $templateName" -Level 'Success'
            }
        }
        else {
            [void][System.Windows.MessageBox]::Show(
                $result.Message,
                'Validation Error',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
        }
    }.GetNewClosure())

    # ── Apply to Lab button ───────────────────────────────────────
    $btnApplyTemplate.Add_Click({
        $selected = $cmbTemplate.SelectedItem
        if (-not $selected) {
            [void][System.Windows.MessageBox]::Show(
                'No template selected.',
                'Apply Template',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        try {
            $templateName = $selected.ToString()
            $vms = & $getVMsFromEditor

            # Validate VM names are not empty
            $emptyNames = @($vms | Where-Object { [string]::IsNullOrWhiteSpace($_.name) })
            if ($emptyNames.Count -gt 0) {
                [void][System.Windows.MessageBox]::Show(
                    "All VMs must have a name. Please fill in empty name fields.",
                    'Validation Error',
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                )
                return
            }

            # First save the current state
            $description = $txtEditDescription.Text
            $saveResult = & $fnSaveTemplate -RepoRoot $repoRoot -Name $templateName `
                              -Description $description -VMs $vms
            if (-not $saveResult.Success) {
                [void][System.Windows.MessageBox]::Show(
                    $saveResult.Message,
                    'Validation Error',
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                )
                return
            }

            # Update config.json with ActiveTemplate and VMConfiguration
            $configPath = Join-Path (Join-Path $repoRoot '.planning') 'config.json'
            $configObj = $null
            if (Test-Path $configPath) {
                $configObj = Get-Content -Path $configPath -Raw | ConvertFrom-Json
            }
            if (-not $configObj) {
                $configObj = [PSCustomObject]@{}
            }

            # Set or update ActiveTemplate
            $existingProps = @($configObj.PSObject.Properties | ForEach-Object { $_.Name })
            if ($existingProps -contains 'ActiveTemplate') {
                $configObj.ActiveTemplate = $templateName
            }
            else {
                $configObj | Add-Member -MemberType NoteProperty -Name 'ActiveTemplate' -Value $templateName
            }

            # Build VMConfiguration from template VMs
            $vmConfig = [ordered]@{}
            foreach ($vm in $vms) {
                $vmName = [string]$vm.name
                $vmConfig[$vmName] = [ordered]@{
                    Role           = [string]$vm.role
                    MemoryGB       = [int]$vm.memoryGB
                    ProcessorCount = [int]$vm.processors
                    IP             = [string]$vm.ip
                }
            }

            if ($existingProps -contains 'VMConfiguration') {
                $configObj.VMConfiguration = $vmConfig
            }
            else {
                $configObj | Add-Member -MemberType NoteProperty -Name 'VMConfiguration' -Value $vmConfig
            }

            $parentDir = Split-Path -Parent $configPath
            if (-not (Test-Path $parentDir)) {
                [void](New-Item -ItemType Directory -Path $parentDir -Force)
            }
            $configObj | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Encoding UTF8

            [void][System.Windows.MessageBox]::Show(
                "Template '$templateName' applied to lab configuration.`nThe next deploy will use these VM definitions.",
                'Apply Template',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            )

            if (Get-Command -Name Add-LogEntry -ErrorAction SilentlyContinue) {
                Add-LogEntry -Message "Applied template '$templateName' to lab config" -Level 'Success'
            }
        }
        catch {
            [void][System.Windows.MessageBox]::Show(
                "Failed to apply template: $_",
                'Error',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
        }
    }.GetNewClosure())

        # ── Initial load ──────────────────────────────────────────────
        & $refreshTemplateList -SelectName 'default'
    }
    catch {
        try {
            $viewElement = $script:contentArea.Children[0]
            if ($viewElement) {
                $errBlock = New-Object System.Windows.Controls.TextBlock
                $errBlock.Text = "Customize view failed to initialize: $_"
                $errBlock.Foreground = [System.Windows.Media.Brushes]::Red
                $errBlock.TextWrapping = 'Wrap'
                $errBlock.Margin = New-Object System.Windows.Thickness(0, 16, 0, 0)
                if ($viewElement -is [System.Windows.Controls.Panel]) {
                    [void]$viewElement.Children.Add($errBlock)
                }
            }
        }
        catch { }
    }
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
    $txtDescription     = $viewElement.FindName('txtDescription')
    $btnRunAction       = $viewElement.FindName('btnRunAction')

    # ── Populate combo boxes ──────────────────────────────────────
    $actions = @('deploy', 'teardown', 'status', 'health', 'setup',
                 'one-button-setup', 'one-button-reset', 'blow-away',
                 'preflight', 'bootstrap', 'add-lin1', 'lin1-config',
                 'ansible', 'start', 'stop', 'asset-report',
                 'offline-bundle', 'terminal', 'new-project',
                 'push', 'test', 'save', 'rollback')
    foreach ($a in $actions) { [void]$cmbAction.Items.Add($a) }
    $cmbAction.SelectedIndex = 0

    $modes = @('quick', 'full')
    foreach ($m in $modes) { [void]$cmbMode.Items.Add($m) }
    $cmbMode.SelectedIndex = 0

    # ── Action/mode descriptions ─────────────────────────────────
    $actionDescriptions = @{
        'deploy'           = 'Create and configure lab VMs. Builds the virtual switch, provisions VMs from ISOs, joins them to the domain, and installs roles.'
        'teardown'         = 'Remove lab VMs and clean up resources. Stops and deletes VMs, removes virtual disks, and optionally removes the virtual switch.'
        'status'           = 'Show current state of all lab VMs. Displays power state, IP addresses, memory usage, and network connectivity.'
        'health'           = 'Run health checks against the lab environment. Verifies domain connectivity, DNS resolution, service status, and network configuration.'
        'setup'            = 'Install prerequisites and configure the host. Enables Hyper-V, creates directories, downloads ISOs, and validates the environment.'
        'one-button-setup' = 'Full automated lab deployment from scratch. Runs setup, then deploy in sequence - zero interaction required.'
        'one-button-reset' = 'Tear down and redeploy the entire lab. Destroys existing VMs, then runs a fresh one-button-setup.'
        'blow-away'        = 'DESTRUCTIVE: Complete removal of all lab resources. Deletes VMs, virtual switch, NAT rules, and all lab files. Requires confirmation token.'
        'preflight'        = 'Run pre-deployment validation checks. Verifies Hyper-V, disk space, ISO availability, and network prerequisites.'
        'bootstrap'        = 'Bootstrap the lab host environment. Installs required PowerShell modules, creates directory structure, and prepares configuration.'
        'add-lin1'         = 'Add the Ubuntu Linux VM (lin1) to the lab. Creates and configures the Linux VM with cloud-init.'
        'lin1-config'      = 'Configure the Linux VM (lin1). Applies post-install settings, network configuration, and domain integration.'
        'ansible'          = 'Install and configure Ansible on the Linux VM. Sets up Ansible for lab automation and configuration management.'
        'start'            = 'Start all lab VMs. Powers on all virtual machines in the correct boot order.'
        'stop'             = 'Stop all lab VMs gracefully. Sends shutdown commands and waits for clean power-off.'
        'asset-report'     = 'Generate a lab asset report. Lists all VMs, disks, network adapters, and resource usage.'
        'offline-bundle'   = 'Build an offline deployment bundle. Packages all required files for air-gapped lab deployment.'
        'terminal'         = 'Open interactive terminals to lab VMs. Launches PowerShell remoting or SSH sessions.'
        'new-project'      = 'Create a new lab project workspace. Scaffolds directory structure and configuration files for a new project.'
        'push'             = 'Push files to the WS1 workstation VM. Copies project files to the Windows 11 client for testing.'
        'test'             = 'Run tests on the WS1 workstation VM. Executes the test suite remotely on the client VM.'
        'save'             = 'Save current lab work. Creates checkpoints and backs up current state for later restoration.'
        'rollback'         = 'Rollback to the last saved checkpoint. Restores all VMs to their most recent saved state.'
    }
    $modeDescriptions = @{
        'quick' = 'Quick mode: Skip VMs that already exist and are running. Faster for incremental changes.'
        'full'  = 'Full mode: Rebuild all VMs regardless of current state. Use when you need a clean environment.'
    }
    $toggleDescriptions = @{
        'NonInteractive' = 'Suppress all confirmation prompts and run unattended.'
        'Force'          = 'Override safety checks and force the operation to proceed.'
        'DryRun'         = 'Preview what would happen without making any changes.'
        'RemoveNetwork'  = 'Also remove the virtual switch and NAT configuration during teardown.'
        'CoreOnly'       = 'Only deploy core VMs (dc1, svr1) - skip workstation and Linux VMs.'
    }

    $updateDescription = {
        $action = $cmbAction.SelectedItem
        $mode   = $cmbMode.SelectedItem
        $parts  = @()
        if ($action -and $actionDescriptions.ContainsKey($action)) {
            $parts += $actionDescriptions[$action]
        }
        if ($action -and -not $actionDescriptions.ContainsKey($action)) {
            $parts += "Run the '$action' action."
        }
        if ($mode -and $modeDescriptions.ContainsKey($mode)) {
            $parts += $modeDescriptions[$mode]
        }
        $txtDescription.Text = ($parts -join "`n`n")
    }.GetNewClosure()

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

    # ── Capture function references for closures ──────────────────
    $fnCommandPreview    = Get-Command -Name New-LabGuiCommandPreview -ErrorAction Stop
    $fnLayoutState       = Get-Command -Name Get-LabGuiLayoutState -ErrorAction Stop
    $fnDestructiveGuard  = Get-Command -Name Get-LabGuiDestructiveGuard -ErrorAction Stop
    $fnArgList           = Get-Command -Name New-LabAppArgumentList -ErrorAction Stop

    # ── Update command preview ────────────────────────────────────
    $appScriptPath = Join-Path $script:RepoRoot 'OpenCodeLab-App.ps1'

    $updatePreview = {
        $opts = & $getOptions
        $preview = & $fnCommandPreview -AppScriptPath $appScriptPath -Options $opts
        $txtCommandPreview.Text = $preview
    }.GetNewClosure()

    # ── Update layout (auto-expand advanced for destructive) ──────
    $updateLayout = {
        $opts = & $getOptions
        $layout = & $fnLayoutState -Action $opts.Action -Mode $opts.Mode `
                      -ProfilePath $opts.ProfilePath -TargetHosts $opts.TargetHosts
        if ($layout.ShowAdvanced) {
            $expAdvanced.IsExpanded = $true
        }
    }.GetNewClosure()

    # ── Wire events ───────────────────────────────────────────────
    $onChanged = {
        & $updatePreview
        & $updateLayout
        & $updateDescription
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

        # Validate blow-away requires a confirmation token
        if ($opts.Action -eq 'blow-away' -and [string]::IsNullOrWhiteSpace($opts.ConfirmationToken)) {
            [void][System.Windows.MessageBox]::Show(
                "The blow-away action requires a Confirmation Token. Expand Advanced Options and provide one.",
                'Missing Confirmation Token',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        # Safety gate for destructive actions
        $guard = & $fnDestructiveGuard -Action $opts.Action -Mode $opts.Mode `
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
        $argList = & $fnArgList -Options $opts
        $scriptPath = Join-Path $script:RepoRoot 'OpenCodeLab-App.ps1'
        $fullArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath) + $argList

        try {
            Start-Process powershell.exe -Verb RunAs -ArgumentList $fullArgs
        }
        catch {
            [void][System.Windows.MessageBox]::Show(
                "Failed to launch action: $_",
                'Error',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
            return
        }

        # Log the action if Add-LogEntry is available
        if (Get-Command -Name Add-LogEntry -ErrorAction SilentlyContinue) {
            Add-LogEntry -Message "Launched: $($opts.Action) ($($opts.Mode))"
        }

        # Switch to Logs view
        Switch-View -ViewName 'Logs'
    }.GetNewClosure())

    # ── Initial preview + description ────────────────────────────
    & $updatePreview
    & $updateDescription

    $script:ActionsInitialized = $true
}

# ── Log management ──────────────────────────────────────────────────────
$script:LogEntries        = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:LogEntriesMaxCount = 2000
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

    # Enforce size cap using FIFO trimming
    while ($script:LogEntries.Count -gt $script:LogEntriesMaxCount) {
        $script:LogEntries.RemoveAt(0)
    }

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
        $run.Foreground = [System.Windows.Application]::Current.FindResource($brushKey)

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
        [void]$cmbLogFilter.Items.Add($opt)
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
    $txtAdminUsername  = $viewElement.FindName('txtAdminUsername')
    $txtAdminPassword = $viewElement.FindName('txtAdminPassword')
    $tglSettingsTheme = $viewElement.FindName('tglSettingsTheme')
    $btnSaveSettings  = $viewElement.FindName('btnSaveSettings')

    # ── Populate from GlobalLabConfig ─────────────────────────────
    $configJsonPath = Join-Path (Join-Path $script:RepoRoot '.planning') 'config.json'

    if (Test-Path variable:GlobalLabConfig) {
        $txtLabRoot.Text    = $GlobalLabConfig.Paths.LabRoot
        $txtSwitchName.Text = $GlobalLabConfig.Network.SwitchName
        $txtSubnet.Text     = $GlobalLabConfig.Network.AddressSpace
        $txtGatewayIP.Text  = $GlobalLabConfig.Network.GatewayIp
        $txtAdminUsername.Text = $GlobalLabConfig.Credentials.InstallUser
        $txtAdminPassword.Password = $GlobalLabConfig.Credentials.AdminPassword
    }
    else {
        # Fall back to config.json for network and credential settings
        if (Test-Path $configJsonPath) {
            try {
                $configJson = Get-Content -Path $configJsonPath -Raw | ConvertFrom-Json
                if ($configJson.Network) {
                    $txtSwitchName.Text = if ($configJson.Network.SwitchName) { $configJson.Network.SwitchName } else { '' }
                    $txtSubnet.Text     = if ($configJson.Network.Subnet) { $configJson.Network.Subnet } else { '' }
                    $txtGatewayIP.Text  = if ($configJson.Network.GatewayIP) { $configJson.Network.GatewayIP } else { '' }
                }
                if ($configJson.AdminUsername) {
                    $txtAdminUsername.Text = $configJson.AdminUsername
                }
            }
            catch { }
        }
    }

    # ── Populate ISO paths from .planning/config.json ─────────────
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
        # Validate subnet format
        $subnet = $txtSubnet.Text.Trim()
        if ($subnet -and $subnet -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}$') {
            [void][System.Windows.MessageBox]::Show(
                "Invalid subnet format. Please enter CIDR notation (e.g. 10.0.10.0/24).",
                'Validation Error',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        # Validate gateway IP format
        $gwIP = $txtGatewayIP.Text.Trim()
        if ($gwIP -and $gwIP -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
            [void][System.Windows.MessageBox]::Show(
                "Invalid Gateway IP format. Please enter a valid IPv4 address (e.g. 10.0.0.1).",
                'Validation Error',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        # Update .planning/config.json ISO paths
        $configJsonPath = Join-Path (Join-Path $script:RepoRoot '.planning') 'config.json'
        try {
            if (Test-Path $configJsonPath) {
                $configJson = Get-Content -Path $configJsonPath -Raw | ConvertFrom-Json
            } else {
                $configJson = [PSCustomObject]@{ IsoPaths = [PSCustomObject]@{ Server2019 = ''; Windows11 = '' } }
            }

            $configJson.IsoPaths.Server2019 = $txtIsoServer.Text
            $configJson.IsoPaths.Windows11  = $txtIsoWin11.Text

            # Persist network settings
            $existingProps = @($configJson.PSObject.Properties | ForEach-Object { $_.Name })

            $networkSettings = [PSCustomObject]@{
                SwitchName  = $txtSwitchName.Text.Trim()
                Subnet      = $txtSubnet.Text.Trim()
                GatewayIP   = $gwIP
            }

            if ($existingProps -contains 'Network') {
                $configJson.Network = $networkSettings
            } else {
                $configJson | Add-Member -MemberType NoteProperty -Name 'Network' -Value $networkSettings
            }

            # Persist admin username (password stays in memory only -- never written to disk)
            $adminUser = $txtAdminUsername.Text.Trim()
            if (-not [string]::IsNullOrWhiteSpace($adminUser)) {
                if ($existingProps -contains 'AdminUsername') {
                    $configJson.AdminUsername = $adminUser
                } else {
                    $configJson | Add-Member -MemberType NoteProperty -Name 'AdminUsername' -Value $adminUser
                }
            }

            $parentDir = Split-Path -Parent $configJsonPath
            if (-not (Test-Path $parentDir)) {
                [void](New-Item -ItemType Directory -Path $parentDir -Force)
            }
            $configJson | ConvertTo-Json -Depth 10 | Set-Content -Path $configJsonPath -Encoding UTF8

            # Also persist admin username to gui-settings.json for cross-session recall
            $guiSettings = Get-GuiSettings
            $guiSettings['AdminUsername'] = $txtAdminUsername.Text.Trim()
            Save-GuiSettings -Settings $guiSettings

            [void][System.Windows.MessageBox]::Show(
                'Settings saved successfully.',
                'Settings',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            )

            if (Get-Command -Name Add-LogEntry -ErrorAction SilentlyContinue) {
                Add-LogEntry -Message 'Settings saved' -Level 'Success'
            }
        }
        catch {
            [void][System.Windows.MessageBox]::Show(
                "Failed to save settings: $_",
                'Error',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )

            if (Get-Command -Name Add-LogEntry -ErrorAction SilentlyContinue) {
                Add-LogEntry -Message "Settings save failed: $_" -Level 'Error'
            }
        }
    }.GetNewClosure())
}

# ── Default view ────────────────────────────────────────────────────────
Switch-View -ViewName 'Dashboard'

# ── Show window (blocks until closed) ───────────────────────────────────
[void]$mainWindow.ShowDialog()

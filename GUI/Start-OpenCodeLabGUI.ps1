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

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$appScriptPath = Join-Path $scriptRoot 'OpenCodeLab-App.ps1'
$argHelperPath = Join-Path $scriptRoot 'Private\New-LabAppArgumentList.ps1'
$artifactHelperPath = Join-Path $scriptRoot 'Private\Get-LabRunArtifactSummary.ps1'

if (-not (Test-Path -Path $appScriptPath)) {
    throw "OpenCodeLab-App.ps1 not found at path: $appScriptPath"
}
if (-not (Test-Path -Path $argHelperPath)) {
    throw "Argument helper not found at path: $argHelperPath"
}
if (-not (Test-Path -Path $artifactHelperPath)) {
    throw "Artifact helper not found at path: $artifactHelperPath"
}

. $argHelperPath
. $artifactHelperPath

function Get-PowerShellHostPath {
    $pwsh = Get-Command 'pwsh' -ErrorAction SilentlyContinue
    if ($pwsh) {
        return $pwsh.Source
    }

    $windowsPowerShell = Get-Command 'powershell.exe' -ErrorAction SilentlyContinue
    if ($windowsPowerShell) {
        return $windowsPowerShell.Source
    }

    throw 'Unable to find pwsh or powershell.exe in PATH.'
}

function Add-StatusLine {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Forms.TextBox]$StatusBox,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $StatusBox.AppendText("[$timestamp] $Message" + [Environment]::NewLine)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'OpenCodeLab GUI'
$form.Width = 980
$form.Height = 760
$form.StartPosition = 'CenterScreen'

$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'
$layout.ColumnCount = 4
$layout.RowCount = 9
$layout.Padding = New-Object System.Windows.Forms.Padding(12)
$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 180)))
$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 180)))
$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))

$actions = @('deploy', 'teardown', 'status', 'health', 'setup', 'one-button-setup', 'one-button-reset', 'blow-away')

$lblAction = New-Object System.Windows.Forms.Label
$lblAction.Text = 'Action'
$lblAction.AutoSize = $true
$cmbAction = New-Object System.Windows.Forms.ComboBox
$cmbAction.DropDownStyle = 'DropDownList'
$cmbAction.Items.AddRange($actions)
$cmbAction.SelectedItem = 'deploy'

$lblMode = New-Object System.Windows.Forms.Label
$lblMode.Text = 'Mode'
$lblMode.AutoSize = $true
$cmbMode = New-Object System.Windows.Forms.ComboBox
$cmbMode.DropDownStyle = 'DropDownList'
$cmbMode.Items.AddRange(@('quick', 'full'))
$cmbMode.SelectedItem = 'quick'

$chkNonInteractive = New-Object System.Windows.Forms.CheckBox
$chkNonInteractive.Text = 'NonInteractive'
$chkNonInteractive.Checked = $true
$chkForce = New-Object System.Windows.Forms.CheckBox
$chkForce.Text = 'Force'
$chkDryRun = New-Object System.Windows.Forms.CheckBox
$chkDryRun.Text = 'DryRun'

$chkRemoveNetwork = New-Object System.Windows.Forms.CheckBox
$chkRemoveNetwork.Text = 'RemoveNetwork'
$chkCoreOnly = New-Object System.Windows.Forms.CheckBox
$chkCoreOnly.Text = 'CoreOnly'
$chkCoreOnly.Checked = $true

$lblProfilePath = New-Object System.Windows.Forms.Label
$lblProfilePath.Text = 'ProfilePath'
$lblProfilePath.AutoSize = $true
$txtProfilePath = New-Object System.Windows.Forms.TextBox
$txtProfilePath.Dock = 'Fill'

$lblDefaultsFile = New-Object System.Windows.Forms.Label
$lblDefaultsFile.Text = 'DefaultsFile'
$lblDefaultsFile.AutoSize = $true
$txtDefaultsFile = New-Object System.Windows.Forms.TextBox
$txtDefaultsFile.Dock = 'Fill'

$lblPreview = New-Object System.Windows.Forms.Label
$lblPreview.Text = 'Command preview'
$lblPreview.AutoSize = $true
$txtPreview = New-Object System.Windows.Forms.TextBox
$txtPreview.Multiline = $true
$txtPreview.ReadOnly = $true
$txtPreview.ScrollBars = 'Vertical'
$txtPreview.Height = 90
$txtPreview.Dock = 'Fill'

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = 'Run'
$btnRun.Width = 120
$btnRun.Height = 34

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = 'Status / output'
$lblStatus.AutoSize = $true
$txtStatus = New-Object System.Windows.Forms.TextBox
$txtStatus.Multiline = $true
$txtStatus.ReadOnly = $true
$txtStatus.ScrollBars = 'Vertical'
$txtStatus.Dock = 'Fill'

$layout.Controls.Add($lblAction, 0, 0)
$layout.Controls.Add($cmbAction, 1, 0)
$layout.Controls.Add($lblMode, 2, 0)
$layout.Controls.Add($cmbMode, 3, 0)

$layout.Controls.Add($chkNonInteractive, 0, 1)
$layout.Controls.Add($chkForce, 1, 1)
$layout.Controls.Add($chkDryRun, 2, 1)
$layout.Controls.Add($chkRemoveNetwork, 3, 1)

$layout.Controls.Add($chkCoreOnly, 0, 2)
$layout.SetColumnSpan($chkCoreOnly, 4)

$layout.Controls.Add($lblProfilePath, 0, 3)
$layout.Controls.Add($txtProfilePath, 1, 3)
$layout.SetColumnSpan($txtProfilePath, 3)

$layout.Controls.Add($lblDefaultsFile, 0, 4)
$layout.Controls.Add($txtDefaultsFile, 1, 4)
$layout.SetColumnSpan($txtDefaultsFile, 3)

$layout.Controls.Add($lblPreview, 0, 5)
$layout.SetColumnSpan($lblPreview, 4)
$layout.Controls.Add($txtPreview, 0, 6)
$layout.SetColumnSpan($txtPreview, 4)

$layout.Controls.Add($btnRun, 0, 7)
$layout.Controls.Add($lblStatus, 0, 8)
$layout.SetColumnSpan($lblStatus, 4)

$statusHost = New-Object System.Windows.Forms.Panel
$statusHost.Dock = 'Bottom'
$statusHost.Height = 260
$statusHost.Padding = New-Object System.Windows.Forms.Padding(12, 0, 12, 12)
$statusHost.Controls.Add($txtStatus)

$form.Controls.Add($layout)
$form.Controls.Add($statusHost)

function Get-SelectedOptions {
    $options = @{
        Action = [string]$cmbAction.SelectedItem
        Mode = [string]$cmbMode.SelectedItem
        NonInteractive = [bool]$chkNonInteractive.Checked
        Force = [bool]$chkForce.Checked
        DryRun = [bool]$chkDryRun.Checked
        RemoveNetwork = [bool]$chkRemoveNetwork.Checked
        CoreOnly = [bool]$chkCoreOnly.Checked
    }

    $profilePath = $txtProfilePath.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($profilePath)) {
        $options.ProfilePath = $profilePath
    }

    $defaultsFile = $txtDefaultsFile.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($defaultsFile)) {
        $options.DefaultsFile = $defaultsFile
    }

    return $options
}

function Update-CommandPreview {
    try {
        $options = Get-SelectedOptions
        $txtPreview.Text = New-LabGuiCommandPreview -AppScriptPath $appScriptPath -Options $options
    }
    catch {
        $txtPreview.Text = "<preview unavailable: $($_.Exception.Message)>"
    }
}

$script:CurrentRunProcess = $null
$script:RunPollTimer = New-Object System.Windows.Forms.Timer
$script:RunPollTimer.Interval = 1500
$script:RunPollTimer.add_Tick({
    if ($null -eq $script:CurrentRunProcess) {
        $script:RunPollTimer.Stop()
        return
    }

    if (-not $script:CurrentRunProcess.HasExited) {
        return
    }

    $exitCode = $script:CurrentRunProcess.ExitCode
    Add-StatusLine -StatusBox $txtStatus -Message "Background run exited with code $exitCode"

    try {
        $artifactPath = Get-LabLatestRunArtifactPath
        if ([string]::IsNullOrWhiteSpace($artifactPath)) {
            Add-StatusLine -StatusBox $txtStatus -Message 'No run artifact found in C:\LabSources\Logs'
        }
        else {
            $artifactSummary = Get-LabRunArtifactSummary -ArtifactPath $artifactPath
            Add-StatusLine -StatusBox $txtStatus -Message $artifactSummary.SummaryText
            Add-StatusLine -StatusBox $txtStatus -Message "Artifact: $($artifactSummary.Path)"
        }
    }
    catch {
        Add-StatusLine -StatusBox $txtStatus -Message "Artifact parsing failed: $($_.Exception.Message)"
    }

    $script:CurrentRunProcess = $null
    $btnRun.Enabled = $true
    $script:RunPollTimer.Stop()
})

$refreshPreview = {
    Update-CommandPreview
}

$cmbAction.add_SelectedIndexChanged($refreshPreview)
$cmbMode.add_SelectedIndexChanged($refreshPreview)
$chkNonInteractive.add_CheckedChanged($refreshPreview)
$chkForce.add_CheckedChanged($refreshPreview)
$chkDryRun.add_CheckedChanged($refreshPreview)
$chkRemoveNetwork.add_CheckedChanged($refreshPreview)
$chkCoreOnly.add_CheckedChanged($refreshPreview)
$txtProfilePath.add_TextChanged($refreshPreview)
$txtDefaultsFile.add_TextChanged($refreshPreview)

$btnRun.add_Click({
    if ($null -ne $script:CurrentRunProcess -and -not $script:CurrentRunProcess.HasExited) {
        Add-StatusLine -StatusBox $txtStatus -Message 'A run is already in progress.'
        return
    }

    try {
        $options = Get-SelectedOptions
        $argumentList = New-LabAppArgumentList -Options $options
        $preview = New-LabGuiCommandPreview -AppScriptPath $appScriptPath -Options $options
        $hostPath = Get-PowerShellHostPath

        Add-StatusLine -StatusBox $txtStatus -Message "Starting: $preview"

        $processArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $appScriptPath) + $argumentList
        $script:CurrentRunProcess = Start-Process -FilePath $hostPath -ArgumentList $processArguments -PassThru -WindowStyle Hidden
        $btnRun.Enabled = $false
        $script:RunPollTimer.Start()
    }
    catch {
        Add-StatusLine -StatusBox $txtStatus -Message "Run failed to start: $($_.Exception.Message)"
    }
})

Update-CommandPreview
Add-StatusLine -StatusBox $txtStatus -Message 'GUI ready. Configure options and click Run.'

[void]$form.ShowDialog()

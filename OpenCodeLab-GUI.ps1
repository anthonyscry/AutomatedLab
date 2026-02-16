#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$appScriptPath = Join-Path $scriptRoot 'OpenCodeLab-App.ps1'
$argHelperPath = Join-Path $scriptRoot 'Private\New-LabAppArgumentList.ps1'
$artifactHelperPath = Join-Path $scriptRoot 'Private\Get-LabRunArtifactSummary.ps1'
$destructiveGuardHelperPath = Join-Path $scriptRoot 'Private\Get-LabGuiDestructiveGuard.ps1'
$targetHostHelperPath = Join-Path $scriptRoot 'Private\ConvertTo-LabTargetHostList.ps1'
$layoutStateHelperPath = Join-Path $scriptRoot 'Private\Get-LabGuiLayoutState.ps1'

if (-not (Test-Path -Path $appScriptPath)) {
    throw "OpenCodeLab-App.ps1 not found at path: $appScriptPath"
}
if (-not (Test-Path -Path $argHelperPath)) {
    throw "Argument helper not found at path: $argHelperPath"
}
if (-not (Test-Path -Path $artifactHelperPath)) {
    throw "Artifact helper not found at path: $artifactHelperPath"
}
if (-not (Test-Path -Path $destructiveGuardHelperPath)) {
    throw "Destructive guard helper not found at path: $destructiveGuardHelperPath"
}
if (-not (Test-Path -Path $targetHostHelperPath)) {
    throw "Target host helper not found at path: $targetHostHelperPath"
}
if (-not (Test-Path -Path $layoutStateHelperPath)) {
    throw "Gui layout helper not found at path: $layoutStateHelperPath"
}

. $argHelperPath
. $artifactHelperPath
. $destructiveGuardHelperPath
. $targetHostHelperPath
. $layoutStateHelperPath

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
$layout.RowCount = 8
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

$chkRemoveNetwork = New-Object System.Windows.Forms.CheckBox
$chkRemoveNetwork.Text = 'RemoveNetwork'
$chkCoreOnly = New-Object System.Windows.Forms.CheckBox
$chkCoreOnly.Text = 'CoreOnly'
$chkCoreOnly.Checked = $true

$chkDryRun = New-Object System.Windows.Forms.CheckBox
$chkDryRun.Text = 'DryRun'

$btnToggleAdvanced = New-Object System.Windows.Forms.Button
$btnToggleAdvanced.Text = 'Show advanced options'
$btnToggleAdvanced.Width = 180
$btnToggleAdvanced.Height = 28

$pnlAdvanced = New-Object System.Windows.Forms.Panel
$pnlAdvanced.Dock = 'Fill'
$pnlAdvanced.AutoSize = $true
$pnlAdvanced.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$pnlAdvanced.Visible = $false

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

$lblTargetHosts = New-Object System.Windows.Forms.Label
$lblTargetHosts.Text = 'TargetHosts (comma/space/semicolon)'
$lblTargetHosts.AutoSize = $true
$txtTargetHosts = New-Object System.Windows.Forms.TextBox
$txtTargetHosts.Dock = 'Fill'

$lblConfirmationToken = New-Object System.Windows.Forms.Label
$lblConfirmationToken.Text = 'ConfirmationToken'
$lblConfirmationToken.AutoSize = $true
$txtConfirmationToken = New-Object System.Windows.Forms.TextBox
$txtConfirmationToken.Dock = 'Fill'

$lblPreview = New-Object System.Windows.Forms.Label
$lblPreview.Text = 'Command preview'
$lblPreview.AutoSize = $true
$txtPreview = New-Object System.Windows.Forms.TextBox
$txtPreview.Multiline = $true
$txtPreview.ReadOnly = $true
$txtPreview.ScrollBars = 'Vertical'
$txtPreview.Height = 90
$txtPreview.Dock = 'Fill'

$chkShowArtifactDetails = New-Object System.Windows.Forms.CheckBox
$chkShowArtifactDetails.Text = 'Show artifact details on completion'
$chkShowArtifactDetails.AutoSize = $true

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

$advancedLayout = New-Object System.Windows.Forms.TableLayoutPanel
$advancedLayout.ColumnCount = 4
$advancedLayout.RowCount = 6
$advancedLayout.Dock = 'Fill'
$advancedLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 180)))
$advancedLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$advancedLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 180)))
$advancedLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))

$advancedLayout.Controls.Add($chkRemoveNetwork, 0, 0)
$advancedLayout.SetColumnSpan($chkRemoveNetwork, 2)
$advancedLayout.Controls.Add($chkCoreOnly, 2, 0)
$advancedLayout.SetColumnSpan($chkCoreOnly, 2)

$advancedLayout.Controls.Add($chkDryRun, 0, 1)
$advancedLayout.SetColumnSpan($chkDryRun, 4)

$advancedLayout.Controls.Add($lblProfilePath, 0, 2)
$advancedLayout.Controls.Add($txtProfilePath, 1, 2)
$advancedLayout.SetColumnSpan($txtProfilePath, 3)

$advancedLayout.Controls.Add($lblDefaultsFile, 0, 3)
$advancedLayout.Controls.Add($txtDefaultsFile, 1, 3)
$advancedLayout.SetColumnSpan($txtDefaultsFile, 3)

$advancedLayout.Controls.Add($lblTargetHosts, 0, 4)
$advancedLayout.Controls.Add($txtTargetHosts, 1, 4)
$advancedLayout.SetColumnSpan($txtTargetHosts, 3)

$advancedLayout.Controls.Add($lblConfirmationToken, 0, 5)
$advancedLayout.Controls.Add($txtConfirmationToken, 1, 5)
$advancedLayout.SetColumnSpan($txtConfirmationToken, 3)

$pnlAdvanced.Controls.Add($advancedLayout)

$layout.Controls.Add($lblAction, 0, 0)
$layout.Controls.Add($cmbAction, 1, 0)
$layout.Controls.Add($lblMode, 2, 0)
$layout.Controls.Add($cmbMode, 3, 0)

$layout.Controls.Add($chkNonInteractive, 0, 1)
$layout.Controls.Add($chkForce, 1, 1)
$layout.Controls.Add($btnToggleAdvanced, 0, 2)
$layout.SetColumnSpan($btnToggleAdvanced, 4)

$layout.Controls.Add($pnlAdvanced, 0, 3)
$layout.SetColumnSpan($pnlAdvanced, 4)

$layout.Controls.Add($lblPreview, 0, 4)
$layout.SetColumnSpan($lblPreview, 4)
$layout.Controls.Add($txtPreview, 0, 5)
$layout.SetColumnSpan($txtPreview, 4)

$layout.Controls.Add($btnRun, 0, 6)
$layout.Controls.Add($chkShowArtifactDetails, 1, 6)
$layout.SetColumnSpan($chkShowArtifactDetails, 3)
$layout.Controls.Add($lblStatus, 0, 7)
$layout.SetColumnSpan($lblStatus, 4)

$statusHost = New-Object System.Windows.Forms.Panel
$statusHost.Dock = 'Bottom'
$statusHost.Height = 260
$statusHost.Padding = New-Object System.Windows.Forms.Padding(12, 0, 12, 12)
$statusHost.Controls.Add($txtStatus)

$form.Controls.Add($layout)
$form.Controls.Add($statusHost)

function Get-SelectedOptions {
    $targetHosts = Get-ParsedTargetHosts -Text $txtTargetHosts.Text

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

    if ($targetHosts.Count -gt 0) {
        $options.TargetHosts = $targetHosts
    }

    $confirmationToken = $txtConfirmationToken.Text.Trim()
    if (-not [string]::IsNullOrWhiteSpace($confirmationToken)) {
        $options.ConfirmationToken = $confirmationToken
    }

    return $options
}

function Get-ParsedTargetHosts {
    param(
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    return @($Text | ConvertTo-LabTargetHostList)
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

$script:ShowAdvancedPanel = $false

function Set-NonInteractiveSafetyDefault {
    $targetHosts = Get-ParsedTargetHosts -Text $txtTargetHosts.Text
    $layoutState = Get-LabGuiLayoutState -Action ([string]$cmbAction.SelectedItem) -Mode ([string]$cmbMode.SelectedItem) -ProfilePath $txtProfilePath.Text -TargetHosts $targetHosts

    $chkNonInteractive.Checked = $layoutState.RecommendedNonInteractiveDefault

    $showAdvanced = if ($layoutState.ShowAdvanced) { $true } else { $script:ShowAdvancedPanel }
    $pnlAdvanced.Visible = $showAdvanced
    if ($showAdvanced) {
        $btnToggleAdvanced.Text = 'Hide advanced options'
    }
    else {
        $btnToggleAdvanced.Text = 'Show advanced options'
    }

    Update-CommandPreview
}

function Add-RunSummaryLine {
    param(
        [Parameter(Mandatory)]
        [object]$ArtifactSummary,

        [switch]$Verbose
    )

    if ($Verbose) {
        Add-StatusLine -StatusBox $txtStatus -Message "Artifact summary: $($ArtifactSummary.SummaryText)"
        if (-not [string]::IsNullOrWhiteSpace($ArtifactSummary.Error)) {
            Add-StatusLine -StatusBox $txtStatus -Message "Artifact error: $($ArtifactSummary.Error)"
        }
        Add-StatusLine -StatusBox $txtStatus -Message "Artifact path: $($ArtifactSummary.Path)"
    }
    else {
        Add-StatusLine -StatusBox $txtStatus -Message "Artifact: $($ArtifactSummary.Path) :: $($ArtifactSummary.SummaryText)"
    }
}

$script:CurrentRunProcess = $null
$script:CurrentRunStartedUtc = $null
$script:CurrentRunPreArtifacts = @()
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
    if ($exitCode -eq 0) {
        Add-StatusLine -StatusBox $txtStatus -Message 'Run result: SUCCESS (exit code 0)'
    }
    else {
        Add-StatusLine -StatusBox $txtStatus -Message "Run result: FAILED (exit code $exitCode)"
        if ($script:RunOutputLog -and (Test-Path $script:RunOutputLog)) {
            $tail = Get-Content $script:RunOutputLog -Tail 10 -ErrorAction SilentlyContinue
            if ($tail) {
                Add-StatusLine -StatusBox $txtStatus -Message "--- Last output lines ---"
                foreach ($line in $tail) { Add-StatusLine -StatusBox $txtStatus -Message $line }
            }
        }
        if ($script:RunOutputLog -and (Test-Path "$($script:RunOutputLog).err")) {
            $errTail = Get-Content "$($script:RunOutputLog).err" -Tail 5 -ErrorAction SilentlyContinue
            if ($errTail) {
                Add-StatusLine -StatusBox $txtStatus -Message "--- Errors ---"
                foreach ($line in $errTail) { Add-StatusLine -StatusBox $txtStatus -Message $line }
            }
        }
    }

    try {
        $artifactPath = Get-LabLatestRunArtifactPath -SinceUtc $script:CurrentRunStartedUtc -ExcludeArtifactPaths $script:CurrentRunPreArtifacts
        if ([string]::IsNullOrWhiteSpace($artifactPath)) {
            Add-StatusLine -StatusBox $txtStatus -Message 'No matching run artifact found for this execution.'
        }
        else {
            $artifactSummary = Get-LabRunArtifactSummary -ArtifactPath $artifactPath
            Add-RunSummaryLine -ArtifactSummary $artifactSummary -Verbose:$chkShowArtifactDetails.Checked
        }
    }
    catch {
        Add-StatusLine -StatusBox $txtStatus -Message "Artifact parsing failed: $($_.Exception.Message)"
    }

    $script:CurrentRunProcess = $null
    $script:CurrentRunStartedUtc = $null
    $script:CurrentRunPreArtifacts = @()
    $btnRun.Enabled = $true
    $script:RunPollTimer.Stop()
})

$refreshPreview = {
    Update-CommandPreview
}

$cmbAction.add_SelectedIndexChanged({ Set-NonInteractiveSafetyDefault })
$cmbMode.add_SelectedIndexChanged({ Set-NonInteractiveSafetyDefault })
$chkNonInteractive.add_CheckedChanged($refreshPreview)
$chkForce.add_CheckedChanged($refreshPreview)
$chkDryRun.add_CheckedChanged($refreshPreview)
$chkRemoveNetwork.add_CheckedChanged($refreshPreview)
$chkCoreOnly.add_CheckedChanged($refreshPreview)
$txtProfilePath.add_TextChanged({ Set-NonInteractiveSafetyDefault })
$txtDefaultsFile.add_TextChanged($refreshPreview)
$txtTargetHosts.add_TextChanged({ Set-NonInteractiveSafetyDefault })
$txtConfirmationToken.add_TextChanged($refreshPreview)

$btnToggleAdvanced.add_Click({
    $targetHosts = Get-ParsedTargetHosts -Text $txtTargetHosts.Text
    $layoutState = Get-LabGuiLayoutState -Action ([string]$cmbAction.SelectedItem) -Mode ([string]$cmbMode.SelectedItem) -ProfilePath $txtProfilePath.Text -TargetHosts $targetHosts
    if ($layoutState.AdvancedForDestructiveAction) {
        return
    }

    $script:ShowAdvancedPanel = -not $pnlAdvanced.Visible
    Set-NonInteractiveSafetyDefault
})

$btnRun.add_Click({
    if ($null -ne $script:CurrentRunProcess -and -not $script:CurrentRunProcess.HasExited) {
        Add-StatusLine -StatusBox $txtStatus -Message 'A run is already in progress.'
        return
    }

    try {
        $options = Get-SelectedOptions
        $profilePathForGuard = if ($options.ContainsKey('ProfilePath') -and $null -ne $options.ProfilePath) {
            [string]$options.ProfilePath
        }
        else {
            ''
        }

        $guard = Get-LabGuiDestructiveGuard -Action $options.Action -Mode $options.Mode -ProfilePath $profilePathForGuard
        if ($guard.RequiresConfirmation) {
            $confirmResult = [System.Windows.Forms.MessageBox]::Show(
                "This will run $($guard.ConfirmationLabel). Click Yes to continue.",
                'Confirm destructive action',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )

            if ($confirmResult -ne [System.Windows.Forms.DialogResult]::Yes) {
                Add-StatusLine -StatusBox $txtStatus -Message 'Destructive action cancelled at confirmation gate.'
                return
            }
        }

        $argumentList = New-LabAppArgumentList -Options $options
        $preview = New-LabGuiCommandPreview -AppScriptPath $appScriptPath -Options $options
        $hostPath = Get-PowerShellHostPath
        $startWindowStyle = if ($options.NonInteractive) { 'Hidden' } else { 'Normal' }

        Add-StatusLine -StatusBox $txtStatus -Message "Starting: $preview"
        if (-not $options.NonInteractive) {
            Add-StatusLine -StatusBox $txtStatus -Message 'Launching visible PowerShell window for interactive prompts.'
        }

        $processArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $appScriptPath) + $argumentList
        $script:CurrentRunPreArtifacts = Get-LabRunArtifactPaths
        $script:CurrentRunStartedUtc = [datetime]::UtcNow
        $startParams = @{
            FilePath = $hostPath
            ArgumentList = $processArguments
            PassThru = $true
            WindowStyle = $startWindowStyle
        }
        if ($options.NonInteractive) {
            $script:RunOutputLog = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "opencodelab-run-$(Get-Date -Format 'yyyyMMdd-HHmmss').log")
            $startParams.RedirectStandardOutput = $script:RunOutputLog
            $startParams.RedirectStandardError = "$($script:RunOutputLog).err"
            Add-StatusLine -StatusBox $txtStatus -Message "Output log: $($script:RunOutputLog)"
        }
        $script:CurrentRunProcess = Start-Process @startParams
        $btnRun.Enabled = $false
        $script:RunPollTimer.Start()
    }
    catch {
        $script:CurrentRunProcess = $null
        $script:CurrentRunStartedUtc = $null
        $script:CurrentRunPreArtifacts = @()
        Add-StatusLine -StatusBox $txtStatus -Message "Run failed to start: $($_.Exception.Message)"
    }
})

Set-NonInteractiveSafetyDefault
Update-CommandPreview
Add-StatusLine -StatusBox $txtStatus -Message 'GUI ready. Configure options and click Run.'

[void]$form.ShowDialog()

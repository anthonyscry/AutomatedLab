function Test-LabConfigValidation {
    <#
    .SYNOPSIS
        Runs unified configuration validation against host resources and lab config.
    .DESCRIPTION
        Compares host resource availability against scenario template requirements,
        checks Hyper-V status, and validates GlobalLabConfig structure. Returns a
        consolidated pass/fail report with guided diagnostics and remediation steps.
    .PARAMETER Scenario
        Optional scenario name to validate against (e.g., SecurityLab, MultiTierApp).
        When provided, RAM/Disk/CPU checks compare host resources against scenario requirements.
    .PARAMETER TemplatesRoot
        Path to the directory containing scenario template JSON files.
        Defaults to .planning/templates relative to the repository root.
    .PARAMETER DiskPath
        Optional disk path passed to Get-LabHostResourceInfo for disk space checks.
    .EXAMPLE
        Test-LabConfigValidation
        Runs basic checks (Hyper-V, config structure) without scenario comparison.
    .EXAMPLE
        Test-LabConfigValidation -Scenario SecurityLab
        Validates host resources against SecurityLab scenario requirements.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Object with OverallStatus (Pass/Fail), Checks (array), Summary (string).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$Scenario,

        [Parameter()]
        [string]$TemplatesRoot = (Join-Path (Join-Path $PSScriptRoot '..') '.planning/templates'),

        [Parameter()]
        [string]$DiskPath
    )

    try {
        $checks = @()

        # --- 1. Hyper-V Check ---
        $hyperVCheck = [pscustomobject]@{
            Name        = 'HyperV'
            Status      = 'Pass'
            Message     = ''
            Remediation = $null
        }
        try {
            $hyperVFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -ErrorAction Stop
            if ($hyperVFeature.State -eq 'Enabled') {
                $hyperVCheck.Message = 'Hyper-V is enabled'
            }
            else {
                $hyperVCheck.Status = 'Fail'
                $hyperVCheck.Message = "Hyper-V is not enabled (state: $($hyperVFeature.State))"
                $hyperVCheck.Remediation = "Run 'Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All' as Administrator and reboot"
            }
        }
        catch {
            $hyperVCheck.Status = 'Warn'
            $hyperVCheck.Message = 'Hyper-V check only available on Windows'
            $hyperVCheck.Remediation = $null
        }
        $checks += $hyperVCheck

        # --- Get host resources ---
        $hostInfoParams = @{}
        if (-not [string]::IsNullOrEmpty($DiskPath)) {
            $hostInfoParams['DiskPath'] = $DiskPath
        }
        $hostInfo = Get-LabHostResourceInfo @hostInfoParams

        # --- Get scenario requirements if specified ---
        $scenarioEstimate = $null
        if (-not [string]::IsNullOrEmpty($Scenario)) {
            if (Get-Command -Name Get-LabScenarioResourceEstimate -ErrorAction SilentlyContinue) {
                try {
                    $estimateParams = @{ Scenario = $Scenario }
                    if (-not [string]::IsNullOrEmpty($TemplatesRoot)) {
                        $estimateParams['TemplatesRoot'] = $TemplatesRoot
                    }
                    $scenarioEstimate = Get-LabScenarioResourceEstimate @estimateParams
                }
                catch {
                    # Scenario lookup failed - treat resource checks as warnings
                    $scenarioEstimate = $null
                }
            }
        }

        $scenarioAvailable = $null -ne $scenarioEstimate
        $scenarioCommandExists = [bool](Get-Command -Name Get-LabScenarioResourceEstimate -ErrorAction SilentlyContinue)

        # --- 2. RAM Check ---
        $ramCheck = [pscustomobject]@{
            Name        = 'RAM'
            Status      = 'Pass'
            Message     = ''
            Remediation = $null
        }
        if ([string]::IsNullOrEmpty($Scenario)) {
            $ramCheck.Message = "No scenario specified for RAM comparison. Host has $($hostInfo.FreeRAMGB)GB free."
        }
        elseif (-not $scenarioCommandExists) {
            $ramCheck.Status = 'Warn'
            $ramCheck.Message = 'Scenario resource estimation not available (Get-LabScenarioResourceEstimate not loaded)'
        }
        elseif (-not $scenarioAvailable) {
            $ramCheck.Status = 'Warn'
            $ramCheck.Message = "Could not estimate resources for scenario '$Scenario'"
        }
        else {
            if ($hostInfo.FreeRAMGB -lt $scenarioEstimate.TotalRAMGB) {
                $ramCheck.Status = 'Fail'
                $ramCheck.Message = "Insufficient RAM: need $($scenarioEstimate.TotalRAMGB)GB but only $($hostInfo.FreeRAMGB)GB available"
                $ramCheck.Remediation = "Close applications to free memory. Need $($scenarioEstimate.TotalRAMGB)GB but only $($hostInfo.FreeRAMGB)GB available. Consider reducing VM memory in scenario template."
            }
            else {
                $ramCheck.Message = "RAM OK: $($hostInfo.FreeRAMGB)GB free, $($scenarioEstimate.TotalRAMGB)GB required"
            }
        }
        $checks += $ramCheck

        # --- 3. Disk Check ---
        $diskCheck = [pscustomobject]@{
            Name        = 'Disk'
            Status      = 'Pass'
            Message     = ''
            Remediation = $null
        }
        if ([string]::IsNullOrEmpty($Scenario)) {
            $diskCheck.Message = "No scenario specified for disk comparison. Host has $($hostInfo.FreeDiskGB)GB free on $($hostInfo.DiskPath)."
        }
        elseif (-not $scenarioCommandExists) {
            $diskCheck.Status = 'Warn'
            $diskCheck.Message = 'Scenario resource estimation not available (Get-LabScenarioResourceEstimate not loaded)'
        }
        elseif (-not $scenarioAvailable) {
            $diskCheck.Status = 'Warn'
            $diskCheck.Message = "Could not estimate disk requirements for scenario '$Scenario'"
        }
        else {
            if ($hostInfo.FreeDiskGB -lt $scenarioEstimate.TotalDiskGB) {
                $diskCheck.Status = 'Fail'
                $diskCheck.Message = "Insufficient disk: need $($scenarioEstimate.TotalDiskGB)GB but only $($hostInfo.FreeDiskGB)GB available on $($hostInfo.DiskPath)"
                $diskCheck.Remediation = "Free disk space on $($hostInfo.DiskPath). Need $($scenarioEstimate.TotalDiskGB)GB but only $($hostInfo.FreeDiskGB)GB available. Remove unused VMs/checkpoints with Hyper-V Manager."
            }
            else {
                $diskCheck.Message = "Disk OK: $($hostInfo.FreeDiskGB)GB free, $($scenarioEstimate.TotalDiskGB)GB required on $($hostInfo.DiskPath)"
            }
        }
        $checks += $diskCheck

        # --- 4. CPU Check ---
        $cpuCheck = [pscustomobject]@{
            Name        = 'CPU'
            Status      = 'Pass'
            Message     = ''
            Remediation = $null
        }
        if ([string]::IsNullOrEmpty($Scenario)) {
            $cpuCheck.Message = "No scenario specified for CPU comparison. Host has $($hostInfo.LogicalProcessors) logical processors."
        }
        elseif (-not $scenarioCommandExists) {
            $cpuCheck.Status = 'Warn'
            $cpuCheck.Message = 'Scenario resource estimation not available (Get-LabScenarioResourceEstimate not loaded)'
        }
        elseif (-not $scenarioAvailable) {
            $cpuCheck.Status = 'Warn'
            $cpuCheck.Message = "Could not estimate CPU requirements for scenario '$Scenario'"
        }
        else {
            if ($hostInfo.LogicalProcessors -lt $scenarioEstimate.TotalProcessors) {
                $cpuCheck.Status = 'Warn'
                $cpuCheck.Message = "Host has $($hostInfo.LogicalProcessors) logical processors, scenario requests $($scenarioEstimate.TotalProcessors). VMs will share CPU time."
            }
            else {
                $cpuCheck.Message = "CPU OK: $($hostInfo.LogicalProcessors) logical processors, $($scenarioEstimate.TotalProcessors) requested"
            }
        }
        $checks += $cpuCheck

        # --- 5. Config Check ---
        $configCheck = [pscustomobject]@{
            Name        = 'Config'
            Status      = 'Pass'
            Message     = ''
            Remediation = $null
        }
        $configExists = Test-Path variable:GlobalLabConfig
        if (-not $configExists -or $null -eq $GlobalLabConfig) {
            $configCheck.Status = 'Fail'
            $configCheck.Message = 'GlobalLabConfig is not defined'
            $configCheck.Remediation = "Verify Lab-Config.ps1 is present and dot-sourced. Required sections: Lab, Network, Credentials, VMSizing."
        }
        else {
            $requiredSections = @('Lab', 'Network', 'Credentials', 'VMSizing')
            $missingSections = @()
            foreach ($section in $requiredSections) {
                if (-not $GlobalLabConfig.ContainsKey($section)) {
                    $missingSections += $section
                }
            }
            if ($missingSections.Count -gt 0) {
                $configCheck.Status = 'Fail'
                $configCheck.Message = "GlobalLabConfig missing required sections: $($missingSections -join ', ')"
                $configCheck.Remediation = "Verify Lab-Config.ps1 is present and dot-sourced. Required sections: Lab, Network, Credentials, VMSizing."
            }
            else {
                $configCheck.Message = 'GlobalLabConfig has all required sections (Lab, Network, Credentials, VMSizing)'
            }
        }
        $checks += $configCheck

        # --- Compute overall status and summary ---
        $passCount = @($checks | Where-Object { $_.Status -eq 'Pass' }).Count
        $failCount = @($checks | Where-Object { $_.Status -eq 'Fail' }).Count
        $warnCount = @($checks | Where-Object { $_.Status -eq 'Warn' }).Count

        $overallStatus = if ($failCount -gt 0) { 'Fail' } else { 'Pass' }
        $summary = "$passCount passed, $failCount failed, $warnCount warnings"

        return [pscustomobject]@{
            OverallStatus = $overallStatus
            Checks        = $checks
            Summary       = $summary
        }
    }
    catch {
        if ($_.Exception.Message -like 'Test-LabConfigValidation:*') {
            throw
        }
        throw "Test-LabConfigValidation: $($_.Exception.Message)"
    }
}

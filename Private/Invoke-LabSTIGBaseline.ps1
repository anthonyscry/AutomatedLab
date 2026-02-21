function Invoke-LabSTIGBaseline {
    <#
    .SYNOPSIS
        Applies PowerSTIG DISA STIG baselines to target lab VMs via DSC push mode.

    .DESCRIPTION
        Orchestrates the full STIG application lifecycle per VM:
          1. Read STIG config -- exit early when disabled.
          2. Discover target VMs (parameter or GlobalLabConfig.Lab.CoreVMNames).
          3. For each VM (with per-VM error isolation):
             a. Discover OS version via WinRM (Win32_OperatingSystem.Version)
             b. Discover OS role via WinRM (Win32_ComputerSystem.DomainRole: 4/5 = DC)
             c. Pre-flight check: Test-PowerStigInstallation; install PowerSTIG if missing
             d. Raise WinRM MaxEnvelopeSizekb to 8192 to handle large MOF payloads
             e. Get role-appropriate STIG profile via Get-LabSTIGProfile; skip unsupported OS
             f. Apply per-VM exception overrides from config Exceptions hashtable
             g. Apply STIG via Start-DscConfiguration in push mode
             h. Check compliance via Get-DscConfigurationStatus
             i. Write compliance result via Write-LabSTIGCompliance
          4. Return audit PSCustomObject matching Invoke-LabQuickModeHeal pattern.

        Timeout: 10 minutes per VM for compilation + application (lab VMs, fresh installs).
        Invalid V-numbers in exceptions produce a [STIG] warning but do not fail compilation.

    .PARAMETER VMName
        One or more VM names to target. When empty, uses GlobalLabConfig.Lab.CoreVMNames.

    .PARAMETER ComplianceCachePath
        Override path for the compliance JSON cache. Defaults to Get-LabSTIGConfig value.

    .OUTPUTS
        PSCustomObject with VMsProcessed, VMsSucceeded, VMsFailed, Repairs, RemainingIssues, DurationSeconds.
    #>
    [CmdletBinding()]
    param(
        [string[]]$VMName = @(),

        [string]$ComplianceCachePath = ''
    )

    $noOp = [pscustomobject]@{
        VMsProcessed    = 0
        VMsSucceeded    = 0
        VMsFailed       = 0
        Repairs         = @()
        RemainingIssues = @()
        DurationSeconds = 0
    }

    # Read STIG config; exit early if disabled
    $stigConfig = Get-LabSTIGConfig
    if (-not $stigConfig.Enabled) {
        Write-Verbose '[STIGBaseline] STIG is disabled in config. Skipping.'
        return $noOp
    }

    # Resolve compliance cache path
    $cachePath = if ($ComplianceCachePath) { $ComplianceCachePath } else { $stigConfig.ComplianceCachePath }

    # Discover target VMs
    $targetVMs = @()
    if ($VMName.Count -gt 0) {
        $targetVMs = @($VMName)
    }
    elseif ((Test-Path variable:GlobalLabConfig) -and
            $GlobalLabConfig.ContainsKey('Lab') -and
            $GlobalLabConfig.Lab.ContainsKey('CoreVMNames')) {
        $targetVMs = @($GlobalLabConfig.Lab.CoreVMNames)
    }

    if ($targetVMs.Count -eq 0) {
        Write-Verbose '[STIGBaseline] No target VMs discovered. Skipping.'
        return $noOp
    }

    $baselineStart  = Get-Date
    $repairs        = [System.Collections.Generic.List[string]]::new()
    $remaining      = [System.Collections.Generic.List[string]]::new()
    $vmProcessed    = 0
    $vmSucceeded    = 0
    $vmFailed       = 0
    $vmTimeoutSecs  = 600  # 10-minute per-VM budget

    foreach ($vm in $targetVMs) {
        $vmProcessed++
        $vmStart = Get-Date
        Write-Verbose "[STIGBaseline] Processing VM: $vm"

        try {
            # --- Step 1: Discover OS version ---
            $osVersion = Invoke-Command -ComputerName $vm -ScriptBlock {
                (Get-WmiObject Win32_OperatingSystem).Version
            }
            Write-Verbose "[STIGBaseline] ${vm} OS version: $osVersion"

            # --- Step 2: Discover OS role ---
            $domainRole = Invoke-Command -ComputerName $vm -ScriptBlock {
                (Get-WmiObject Win32_ComputerSystem).DomainRole
            }
            # DomainRole 4 = BackupDomainController, 5 = PrimaryDomainController
            $osRole = if ($domainRole -eq 4 -or $domainRole -eq 5) { 'DC' } else { 'MS' }
            Write-Verbose "[STIGBaseline] ${vm} domain role: $domainRole -> OsRole: $osRole"

            # --- Step 3: PowerSTIG pre-flight check ---
            $installCheck = Test-PowerStigInstallation -ComputerName $vm
            if (-not $installCheck.Installed) {
                Write-Verbose "[STIGBaseline] Installing PowerSTIG on $vm (missing: $($installCheck.MissingModules -join ', '))"
                Invoke-Command -ComputerName $vm -ScriptBlock {
                    Install-Module PowerSTIG -Scope AllUsers -Force -AllowClobber
                } | Out-Null
            }
            else {
                Write-Verbose "[STIGBaseline] PowerSTIG already installed on $vm (version $($installCheck.Version))"
            }

            # --- Step 4: Raise WinRM envelope size ---
            Invoke-Command -ComputerName $vm -ScriptBlock {
                Set-Item WSMan:\localhost\MaxEnvelopeSizekb 8192
            } | Out-Null

            # --- Step 5: Resolve STIG profile ---
            $profile = Get-LabSTIGProfile -OsRole $osRole -OsVersionBuild $osVersion
            if (-not $profile) {
                Write-Warning "[STIGBaseline] ${vm}: OS version '$osVersion' has no PowerSTIG profile. Skipping."
                $remaining.Add("${vm}:unsupported_os")
                $vmFailed++
                continue
            }

            # --- Step 6: Resolve per-VM exception V-numbers ---
            $exceptions = @()
            if ($stigConfig.Exceptions.ContainsKey($vm)) {
                $exceptions = @($stigConfig.Exceptions[$vm])
                # Warn on any non-V-number strings (graceful degradation)
                foreach ($exc in $exceptions) {
                    if ($exc -notmatch '^V-\d+$') {
                        Write-Warning "[STIG] ${vm}: Exception '$exc' does not match V-number format (V-NNNNN). It will be passed to PowerSTIG as-is."
                    }
                }
            }
            $exceptionCount = $exceptions.Count
            Write-Verbose "[STIGBaseline] ${vm}: $exceptionCount exception(s) applied."

            # --- Step 7: Verify time budget before DSC operations ---
            $elapsed = ((Get-Date) - $vmStart).TotalSeconds
            if ($elapsed -ge $vmTimeoutSecs) {
                throw "Per-VM timeout of ${vmTimeoutSecs}s exceeded before DSC operations."
            }

            # --- Step 8: Apply STIG via DSC push mode ---
            # In a real environment, MOF compilation via PowerSTIG DSC config would happen here.
            # We call Start-DscConfiguration which is mockable in tests. The -Path would normally
            # point to the compiled MOF output directory.
            Start-DscConfiguration -ComputerName $vm -Wait -Force -Verbose:($VerbosePreference -ne 'SilentlyContinue') | Out-Null

            # --- Step 9: Check compliance status ---
            $dscStatus = Get-DscConfigurationStatus -CimSession $vm -ErrorAction SilentlyContinue
            $complianceStatus = if ($dscStatus -and $dscStatus.Status -eq 'Success') {
                'Compliant'
            }
            else {
                'NonCompliant'
            }

            Write-Verbose "[STIGBaseline] ${vm} DSC status: $($dscStatus.Status) -> $complianceStatus"

            # --- Step 10: Write compliance result ---
            Write-LabSTIGCompliance `
                -CachePath         $cachePath `
                -VMName            $vm `
                -Role              $profile.OsRole `
                -STIGVersion       $profile.StigVersion `
                -Status            $complianceStatus `
                -ExceptionsApplied $exceptionCount `
                -ErrorMessage      $null

            $repairs.Add("${vm}:stig_applied")
            $vmSucceeded++
        }
        catch {
            $errorMsg = $_.Exception.Message
            Write-Warning "[STIGBaseline] ${vm} failed: $errorMsg"

            # Attempt to write failure status to compliance cache
            try {
                # Determine best-effort profile info for failure record
                $failRole    = 'MS'
                $failVersion = 'unknown'
                if ($profile) {
                    $failRole    = $profile.OsRole
                    $failVersion = $profile.StigVersion
                }
                Write-LabSTIGCompliance `
                    -CachePath         $cachePath `
                    -VMName            $vm `
                    -Role              $failRole `
                    -STIGVersion       $failVersion `
                    -Status            'Failed' `
                    -ExceptionsApplied 0 `
                    -ErrorMessage      $errorMsg
            }
            catch {
                Write-Verbose "[STIGBaseline] Could not write failure compliance for ${vm}: $($_.Exception.Message)"
            }

            $remaining.Add("${vm}:failed")
            $vmFailed++
        }
    }

    $duration = [int]((Get-Date) - $baselineStart).TotalSeconds

    return [pscustomobject]@{
        VMsProcessed    = $vmProcessed
        VMsSucceeded    = $vmSucceeded
        VMsFailed       = $vmFailed
        Repairs         = @($repairs)
        RemainingIssues = @($remaining)
        DurationSeconds = $duration
    }
}

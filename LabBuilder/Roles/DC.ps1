function Get-LabRole_DC {
    <#
    .SYNOPSIS
        Returns the Domain Controller role definition for LabBuilder.
    .DESCRIPTION
        Defines DC1 with RootDC + CaRoot AutomatedLab built-in roles,
        plus a PostInstall scriptblock that configures DNS forwarders
        and validates AD DS services.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    return @{
        Tag        = 'DC'
        VMName     = $Config.VMNames.DC
        Roles      = @('RootDC', 'CaRoot')
        OS         = $Config.ServerOS
        IP         = $Config.IPPlan.DC
        Gateway    = $Config.Network.Gateway
        DnsServer1 = $Config.IPPlan.DC                  # DC is its own DNS
        Memory     = $Config.ServerVM.Memory
        MinMemory  = $Config.ServerVM.MinMemory
        MaxMemory  = $Config.ServerVM.MaxMemory
        Processors = $Config.ServerVM.Processors
        DomainName = $Config.DomainName
        Network    = $Config.Network.SwitchName

        PostInstall = {
            param([hashtable]$LabConfig)

            $dcName = $LabConfig.VMNames.DC

            try {
                # 1. Configure DNS forwarders (idempotent)
                Invoke-LabCommand -ComputerName $dcName -ActivityName 'DC-Configure-DNS-Forwarders' -ScriptBlock {
                    $targetForwarders = @('1.1.1.1', '8.8.8.8')
                    $existing = @()
                    $fwd = Get-DnsServerForwarder -ErrorAction SilentlyContinue
                    if ($fwd) {
                        $existing = @($fwd.IPAddress | ForEach-Object { $_.IPAddressToString })
                    }
                    $missing = @($targetForwarders | Where-Object { $_ -notin $existing })
                    if ($missing.Count -gt 0) {
                        Add-DnsServerForwarder -IPAddress $missing -ErrorAction Stop
                        Write-Host "  [OK] DNS forwarders added: $($missing -join ', ')" -ForegroundColor Green
                    }
                    else {
                        Write-Host '  [OK] DNS forwarders already configured.' -ForegroundColor Green
                    }
                } -Retries 3 -RetryIntervalInSeconds 15

                # 2. Validate AD DS + DNS services are operational
                $adCheck = Invoke-LabCommand -ComputerName $dcName -ActivityName 'DC-Validate-Services' -PassThru -ScriptBlock {
                    $ntds = Get-Service NTDS -ErrorAction SilentlyContinue
                    $adws = Get-Service ADWS -ErrorAction SilentlyContinue
                    $dns  = Get-Service DNS  -ErrorAction SilentlyContinue
                    @{
                        NTDSRunning = ($null -ne $ntds -and $ntds.Status -eq 'Running')
                        ADWSRunning = ($null -ne $adws -and $adws.Status -eq 'Running')
                        DNSRunning  = ($null -ne $dns  -and $dns.Status  -eq 'Running')
                    }
                }

                if (-not $adCheck.DNSRunning) {
                    Write-Warning "DC role: DNS service is not running on $dcName. Run on DC: Get-Service NTDS,ADWS,DNS | Format-Table Name,Status"
                }
                if (-not $adCheck.NTDSRunning -or -not $adCheck.ADWSRunning) {
                    Write-Warning "DC role: AD services not fully operational on $dcName. NTDS=$($adCheck.NTDSRunning), ADWS=$($adCheck.ADWSRunning). Run on DC: Get-Service NTDS,ADWS,DNS | Format-Table Name,Status"
                }

                if ($adCheck.NTDSRunning -and $adCheck.ADWSRunning -and $adCheck.DNSRunning) {
                    Write-Host '  [OK] AD DS services verified running (NTDS + ADWS + DNS).' -ForegroundColor Green
                }

                # 3. Apply STIG baseline (if enabled)
                if (Test-Path variable:GlobalLabConfig) {
                    if ($GlobalLabConfig.ContainsKey('STIG') -and $GlobalLabConfig.STIG.ContainsKey('Enabled') -and $GlobalLabConfig.STIG.Enabled) {
                        if ($GlobalLabConfig.STIG.ContainsKey('AutoApplyOnDeploy') -and -not $GlobalLabConfig.STIG.AutoApplyOnDeploy) {
                            Write-Host '  [SKIP] STIG baselines enabled but AutoApplyOnDeploy is false.' -ForegroundColor Yellow
                        }
                        else {
                            Write-Host "  Applying STIG baseline to ${dcName}..." -ForegroundColor Cyan
                            try {
                                $stigResult = Invoke-LabSTIGBaselineCore -VMName $dcName
                                if ($stigResult.VMsFailed -eq 0) {
                                    Write-Host "  [OK] STIG baseline applied to ${dcName} ($($stigResult.VMsSucceeded) succeeded)." -ForegroundColor Green
                                }
                                else {
                                    Write-Warning "DC role: STIG baseline application had failures on ${dcName}. Check .planning/stig-compliance.json for details."
                                }
                            }
                            catch {
                                Write-Warning "DC role: STIG baseline application failed on ${dcName}: $($_.Exception.Message). Lab deployment continues without STIG."
                            }
                        }
                    }
                }
            }
            catch {
                Write-Warning "DC role post-install failed on ${dcName}: $($_.Exception.Message). Check: AD DS features installed, VM has network connectivity, DNS server service started. Run on DC: Get-Service NTDS,ADWS,DNS | Format-Table Name,Status"
            }
        }
    }
}

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

            # 2. Validate AD DS services are operational
            $adCheck = Invoke-LabCommand -ComputerName $dcName -ActivityName 'DC-Validate-ADDS' -PassThru -ScriptBlock {
                $ntds = Get-Service NTDS -ErrorAction SilentlyContinue
                $adws = Get-Service ADWS -ErrorAction SilentlyContinue
                @{
                    NTDSRunning = ($null -ne $ntds -and $ntds.Status -eq 'Running')
                    ADWSRunning = ($null -ne $adws -and $adws.Status -eq 'Running')
                }
            }
            if (-not $adCheck.NTDSRunning -or -not $adCheck.ADWSRunning) {
                Write-Warning "DC1 AD services may not be fully operational. NTDS=$($adCheck.NTDSRunning), ADWS=$($adCheck.ADWSRunning)"
            }
            else {
                Write-Host '  [OK] AD DS services are running (NTDS + ADWS).' -ForegroundColor Green
            }
        }
    }
}

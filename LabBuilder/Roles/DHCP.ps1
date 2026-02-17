function Get-LabRole_DHCP {
    <#
    .SYNOPSIS
        Returns the DHCP Server role definition for LabBuilder.
    .DESCRIPTION
        Uses AutomatedLab cmdlets for feature installation and command execution.
        Note: AutomatedLab's built-in DHCP role is not currently implemented,
        so this role keeps DHCP configuration explicit and lean.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    return @{
        Tag        = 'DHCP'
        VMName     = $Config.VMNames.DHCP
        Roles      = @()
        OS         = $Config.ServerOS
        IP         = $Config.IPPlan.DHCP
        Gateway    = $Config.Network.Gateway
        DnsServer1 = $Config.IPPlan.DC
        Memory     = $Config.ServerVM.Memory
        MinMemory  = $Config.ServerVM.MinMemory
        MaxMemory  = $Config.ServerVM.MaxMemory
        Processors = $Config.ServerVM.Processors
        DomainName = $Config.DomainName
        Network    = $Config.Network.SwitchName

        PostInstall = {
            param([hashtable]$LabConfig)

            # Prerequisite validation: DHCP config section required
            if (-not $LabConfig.ContainsKey('DHCP') -or -not $LabConfig.DHCP) {
                Write-Warning "DHCP role prereq check failed: `$LabConfig.DHCP section not found. Add DHCP config (ScopeId, Start, End, Mask) to Lab-Config.ps1."
                return
            }
            $dhcpRequiredKeys = @('ScopeId', 'Start', 'End', 'Mask')
            $dhcpMissing = @($dhcpRequiredKeys | Where-Object { -not $LabConfig.DHCP.ContainsKey($_) -or [string]::IsNullOrWhiteSpace([string]$LabConfig.DHCP[$_]) })
            if ($dhcpMissing.Count -gt 0) {
                Write-Warning "DHCP role prereq check failed: Missing config keys in `$LabConfig.DHCP: $($dhcpMissing -join ', '). Add these to Lab-Config.ps1."
                return
            }
            if (-not $LabConfig.ContainsKey('Network') -or -not $LabConfig.Network -or [string]::IsNullOrWhiteSpace($LabConfig.Network.Gateway)) {
                Write-Warning "DHCP role prereq check failed: `$LabConfig.Network.Gateway not configured."
                return
            }
            if (-not $LabConfig.ContainsKey('IPPlan') -or -not $LabConfig.IPPlan -or [string]::IsNullOrWhiteSpace($LabConfig.IPPlan.DC)) {
                Write-Warning "DHCP role prereq check failed: `$LabConfig.IPPlan.DC not configured."
                return
            }

            Install-LabWindowsFeature -ComputerName $LabConfig.VMNames.DHCP -FeatureName DHCP -IncludeManagementTools

            Invoke-LabCommand -ComputerName $LabConfig.VMNames.DHCP -ActivityName 'DHCP-Configure-Scope' -ScriptBlock {
                param(
                    [string]$ScopeId,
                    [string]$StartRange,
                    [string]$EndRange,
                    [string]$Mask,
                    [string]$Router,
                    [string]$Dns,
                    [string]$DnsDomain,
                    [string]$ServerIp
                )

                try {
                    Write-Verbose "Authorizing DHCP server in AD..."
                    $null = Add-DhcpServerInDC -DnsName "$env:COMPUTERNAME.$env:USERDNSDOMAIN" -IPAddress $ServerIp -ErrorAction Stop
                    Write-Host '    [OK] DHCP server authorized in AD.' -ForegroundColor Green
                }
                catch {
                    Write-Verbose "DHCP authorization already present or unavailable: $($_.Exception.Message)"
                }

                $scope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue |
                    Where-Object { $_.ScopeId.IPAddressToString -eq $ScopeId }

                if (-not $scope) {
                    Write-Verbose "Creating DHCP scope: $ScopeId ($StartRange - $EndRange)..."
                    $null = Add-DhcpServerv4Scope -Name 'LabBuilder' -StartRange $StartRange -EndRange $EndRange -SubnetMask $Mask -State Active
                    Write-Host "    [OK] DHCP scope created: $ScopeId" -ForegroundColor Green
                }
                else {
                    Write-Host "    [OK] DHCP scope already exists: $ScopeId" -ForegroundColor Green
                }

                Write-Verbose "Setting DHCP scope options for $ScopeId..."
                $null = Set-DhcpServerv4OptionValue -ScopeId $ScopeId -Router $Router -DnsServer @($Dns, '1.1.1.1') -DnsDomain $DnsDomain
                Write-Host '    [OK] DHCP scope options configured.' -ForegroundColor Green

                Set-Service DHCPServer -StartupType Automatic
                Restart-Service DHCPServer -ErrorAction SilentlyContinue
            } -ArgumentList $LabConfig.DHCP.ScopeId, $LabConfig.DHCP.Start, $LabConfig.DHCP.End, $LabConfig.DHCP.Mask, $LabConfig.Network.Gateway, $LabConfig.IPPlan.DC, $LabConfig.DomainName, $LabConfig.IPPlan.DHCP -Retries 2 -RetryIntervalInSeconds 15
        }
    }
}

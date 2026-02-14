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
                    Add-DhcpServerInDC -DnsName "$env:COMPUTERNAME.$env:USERDNSDOMAIN" -IPAddress $ServerIp -ErrorAction Stop | Out-Null
                    Write-Host '    [OK] DHCP server authorized in AD.' -ForegroundColor Green
                }
                catch {
                    Write-Verbose "DHCP authorization already present or unavailable: $($_.Exception.Message)"
                }

                $scope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue |
                    Where-Object { $_.ScopeId.IPAddressToString -eq $ScopeId }

                if (-not $scope) {
                    Add-DhcpServerv4Scope -Name 'LabBuilder' -StartRange $StartRange -EndRange $EndRange -SubnetMask $Mask -State Active | Out-Null
                    Write-Host "    [OK] DHCP scope created: $ScopeId" -ForegroundColor Green
                }
                else {
                    Write-Host "    [OK] DHCP scope already exists: $ScopeId" -ForegroundColor Green
                }

                Set-DhcpServerv4OptionValue -ScopeId $ScopeId -Router $Router -DnsServer @($Dns, '1.1.1.1') -DnsDomain $DnsDomain | Out-Null
                Write-Host '    [OK] DHCP scope options configured.' -ForegroundColor Green

                Set-Service DHCPServer -StartupType Automatic
                Restart-Service DHCPServer -ErrorAction SilentlyContinue
            } -ArgumentList $LabConfig.DHCP.ScopeId, $LabConfig.DHCP.Start, $LabConfig.DHCP.End, $LabConfig.DHCP.Mask, $LabConfig.Network.Gateway, $LabConfig.IPPlan.DC, $LabConfig.DomainName, $LabConfig.IPPlan.DHCP -Retries 2 -RetryIntervalInSeconds 15
        }
    }
}

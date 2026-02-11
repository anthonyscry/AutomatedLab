function Get-LabRole_Jumpbox {
    <#
    .SYNOPSIS
        Returns the Jumpbox/Admin workstation role definition for LabBuilder.
    .DESCRIPTION
        Defines JUMP1 as a Windows 11 client VM with RSAT tools installed.
        Used as the admin workstation for managing the lab domain.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    return @{
        Tag        = 'Jumpbox'
        VMName     = $Config.VMNames.Jumpbox
        Roles      = @()
        OS         = $Config.ClientOS                   # Windows 11
        IP         = $Config.IPPlan.Jumpbox
        Gateway    = $Config.Network.Gateway
        DnsServer1 = $Config.IPPlan.DC
        Memory     = $Config.ClientVM.Memory
        MinMemory  = $Config.ClientVM.MinMemory
        MaxMemory  = $Config.ClientVM.MaxMemory
        Processors = $Config.ClientVM.Processors
        DomainName = $Config.DomainName
        Network    = $Config.Network.SwitchName

        PostInstall = {
            param([hashtable]$LabConfig)

            Invoke-LabCommand -ComputerName $LabConfig.VMNames.Jumpbox -ActivityName 'Jumpbox-Install-RSAT' -ScriptBlock {
                # Install RSAT tools via Add-WindowsCapability (idempotent, PS5.1 on Win11)
                $rsatCapabilities = @(
                    'Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'
                    'Rsat.Dns.Tools~~~~0.0.1.0'
                    'Rsat.DHCP.Tools~~~~0.0.1.0'
                    'Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0'
                    'Rsat.ServerManager.Tools~~~~0.0.1.0'
                )

                foreach ($cap in $rsatCapabilities) {
                    $installed = Get-WindowsCapability -Online -Name $cap -ErrorAction SilentlyContinue
                    if ($installed -and $installed.State -ne 'Installed') {
                        try {
                            Add-WindowsCapability -Online -Name $cap -ErrorAction Stop | Out-Null
                            Write-Host "    [OK] Installed: $cap" -ForegroundColor Green
                        }
                        catch {
                            Write-Warning "    Failed to install ${cap}: $($_.Exception.Message)"
                        }
                    }
                    elseif ($installed -and $installed.State -eq 'Installed') {
                        Write-Host "    [OK] Already installed: $cap" -ForegroundColor Green
                    }
                }

                # Enable Remote Desktop (idempotent)
                $rdpKey = 'HKLM:\System\CurrentControlSet\Control\Terminal Server'
                $current = (Get-ItemProperty -Path $rdpKey -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue).fDenyTSConnections
                if ($current -ne 0) {
                    Set-ItemProperty -Path $rdpKey -Name 'fDenyTSConnections' -Value 0
                    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
                    Write-Host '    [OK] Remote Desktop enabled.' -ForegroundColor Green
                }
            } -Retries 2 -RetryIntervalInSeconds 15
        }
    }
}

function Get-LabRole_Client {
    <#
    .SYNOPSIS
        Returns the Client VM role definition for LabBuilder.
    .DESCRIPTION
        Defines WIN10-01 as a Windows 11 client VM with Remote Desktop
        enabled and optional drive mapping to the File Server share.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    return @{
        Tag        = 'Client'
        VMName     = $Config.VMNames.Client
        Roles      = @()
        OS         = $Config.ClientOS                   # Windows 11
        IP         = $Config.IPPlan.Client
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

            Invoke-LabCommand -ComputerName $LabConfig.VMNames.Client -ActivityName 'Client-Baseline-Config' -ScriptBlock {
                param($GlobalLabConfig.Lab.DomainName, $FileServerName, $FileServerSelected)

                # Map drive to file share if File Server was selected (idempotent)
                if ($FileServerSelected -and $FileServerName) {
                    $sharePath = "\\$FileServerName\LabShare"
                    $existingDrive = Get-PSDrive -Name 'S' -ErrorAction SilentlyContinue
                    if (-not $existingDrive) {
                        $netUse = net use S: $sharePath /persistent:yes 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host "    [OK] Mapped S: to $sharePath" -ForegroundColor Green
                        }
                        else {
                            Write-Warning "    Drive mapping to $sharePath failed: $netUse"
                        }
                    }
                    else {
                        Write-Host "    [OK] Drive S: already mapped." -ForegroundColor Green
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
                else {
                    Write-Host '    [OK] Remote Desktop already enabled.' -ForegroundColor Green
                }
            } -ArgumentList $LabConfig.DomainName, $LabConfig.VMNames.FileServer, ('FileServer' -in $LabConfig.SelectedRoles)
        }
    }
}

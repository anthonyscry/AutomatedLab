function Get-LabRole_PrintServer {
    <#
    .SYNOPSIS
        Returns the Print Server role definition for LabBuilder.
    .DESCRIPTION
        Defines PRN1 as a domain-joined server VM and installs the Print
        and Document Services role using native AutomatedLab cmdlets.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    return @{
        Tag        = 'PrintServer'
        VMName     = $Config.VMNames.PrintServer
        Roles      = @()
        OS         = $Config.ServerOS
        IP         = $Config.IPPlan.PrintServer
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

            $target = Get-LabVM -ComputerName $LabConfig.VMNames.PrintServer -ErrorAction SilentlyContinue
            if ($target) {
                Install-LabWindowsFeature -ComputerName $target -FeatureName Print-Server -IncludeAllSubFeature -IncludeManagementTools | Out-Null
            } else {
                Install-LabWindowsFeature -ComputerName $LabConfig.VMNames.PrintServer -FeatureName Print-Server -IncludeAllSubFeature -IncludeManagementTools | Out-Null
            }

            Invoke-LabCommand -ComputerName $LabConfig.VMNames.PrintServer -ActivityName 'PrintServer-Verify' -ScriptBlock {
                $feature = Get-WindowsFeature -Name Print-Server -ErrorAction SilentlyContinue
                if (-not $feature -or $feature.InstallState -ne 'Installed') {
                    throw 'Print-Server feature is not installed.'
                }

                $rule = Get-NetFirewallRule -DisplayName 'Print Server RPC (135)' -ErrorAction SilentlyContinue
                if (-not $rule) {
                    New-NetFirewallRule -DisplayName 'Print Server RPC (135)' -Direction Inbound -Protocol TCP -LocalPort 135 -Action Allow | Out-Null
                }
            } -Retries 2 -RetryIntervalInSeconds 10

            Write-Host "    [OK] Print Server installed on $($LabConfig.VMNames.PrintServer)." -ForegroundColor Green
        }
    }
}

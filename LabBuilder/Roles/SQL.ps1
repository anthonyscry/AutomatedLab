function Get-LabRole_SQL {
    <#
    .SYNOPSIS
        Returns the SQL Server role definition for LabBuilder (scaffold).
    .DESCRIPTION
        Defines SQL1 as a domain-joined server VM. SQL Server installation
        is not automated — the VM is created and ready for manual setup.
        PostInstall prints guidance on completing the installation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    return @{
        Tag        = 'SQL'
        VMName     = $Config.VMNames.SQL
        Roles      = @()
        OS         = $Config.ServerOS
        IP         = $Config.IPPlan.SQL
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

            Write-Host ''
            Write-Host '    [SCAFFOLD] SQL Server post-install is not yet implemented.' -ForegroundColor Yellow
            Write-Host '    To complete manually:' -ForegroundColor Yellow
            Write-Host '      1. Place SQL Server ISO in C:\LabSources\ISOs' -ForegroundColor Gray
            Write-Host '      2. Mount ISO on SQL1 and run setup.exe /QUIET /ACTION=Install ...' -ForegroundColor Gray
            Write-Host '      3. Or use: Install-LabSoftwarePackage -Path <iso> -CommandLine <args>' -ForegroundColor Gray
            Write-Host '      4. Configure SQL instance, firewall port 1433, SA account' -ForegroundColor Gray
            Write-Host ''
        }
    }
}

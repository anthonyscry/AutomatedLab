function Get-LabRole_WSUS {
    <#
    .SYNOPSIS
        Returns the WSUS role definition for LabBuilder (scaffold).
    .DESCRIPTION
        Defines WSUS1 as a domain-joined server VM. WSUS installation
        is not automated — the VM is created and ready for manual setup.
        PostInstall prints guidance on completing the installation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    return @{
        Tag        = 'WSUS'
        VMName     = $Config.VMNames.WSUS
        Roles      = @()
        OS         = $Config.ServerOS
        IP         = $Config.IPPlan.WSUS
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
            Write-Host '    [SCAFFOLD] WSUS post-install is not yet implemented.' -ForegroundColor Yellow
            Write-Host '    To complete manually:' -ForegroundColor Yellow
            Write-Host '      1. Install-WindowsFeature UpdateServices -IncludeManagementTools' -ForegroundColor Gray
            Write-Host '      2. Run: wsusutil.exe postinstall CONTENT_DIR=C:\WSUS' -ForegroundColor Gray
            Write-Host '      3. Configure WSUS products, classifications, and sync schedule' -ForegroundColor Gray
            Write-Host '      4. Configure GPO for WSUS client targeting' -ForegroundColor Gray
            Write-Host ''
        }
    }
}

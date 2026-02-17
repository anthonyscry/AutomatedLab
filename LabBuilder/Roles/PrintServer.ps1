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

            $printVMName = $LabConfig.VMNames.PrintServer

            try {
                $target = Get-LabVM -ComputerName $printVMName -ErrorAction SilentlyContinue
                if ($target) {
                    Write-Verbose "Installing Print-Server feature on $printVMName (via LabVM object)..."
                    $null = Install-LabWindowsFeature -ComputerName $target -FeatureName Print-Server -IncludeAllSubFeature -IncludeManagementTools
                } else {
                    Write-Verbose "Installing Print-Server feature on $printVMName (via name)..."
                    $null = Install-LabWindowsFeature -ComputerName $printVMName -FeatureName Print-Server -IncludeAllSubFeature -IncludeManagementTools
                }

                Invoke-LabCommand -ComputerName $printVMName -ActivityName 'PrintServer-Verify' -ScriptBlock {
                    $feature = Get-WindowsFeature -Name Print-Server -ErrorAction SilentlyContinue
                    if (-not $feature -or $feature.InstallState -ne 'Installed') {
                        throw 'Print-Server feature is not installed.'
                    }

                    $rule = Get-NetFirewallRule -DisplayName 'Print Server RPC (135)' -ErrorAction SilentlyContinue
                    if (-not $rule) {
                        Write-Verbose "Creating firewall rule for Print Server RPC port 135..."
                        $null = New-NetFirewallRule -DisplayName 'Print Server RPC (135)' -Direction Inbound -Protocol TCP -LocalPort 135 -Action Allow
                    }
                } -Retries 2 -RetryIntervalInSeconds 10

                # Verify Spooler service is running
                $spoolerVerify = Invoke-LabCommand -ComputerName $printVMName -ActivityName 'PrintServer-Verify-Spooler' -PassThru -ScriptBlock {
                    $svc = Get-Service Spooler -ErrorAction SilentlyContinue
                    @{ Running = ($null -ne $svc -and $svc.Status -eq 'Running') }
                }
                if (-not $spoolerVerify.Running) {
                    Write-Warning "PrintServer role: Spooler service is not running on $printVMName. Run on PrintServer VM: Get-Service Spooler | Format-Table Name,Status"
                }
                else {
                    Write-Host "    [OK] Print Server installed and Spooler verified running on $printVMName." -ForegroundColor Green
                }
            }
            catch {
                Write-Warning "PrintServer role post-install failed on ${printVMName}: $($_.Exception.Message). Check: Print-Server feature available. Run on PrintServer VM: Get-WindowsFeature Print-Server"
            }
        }
    }
}

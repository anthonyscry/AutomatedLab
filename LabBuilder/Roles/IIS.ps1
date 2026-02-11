function Get-LabRole_IIS {
    <#
    .SYNOPSIS
        Returns the IIS Web Server role definition for LabBuilder.
    .DESCRIPTION
        Defines IIS1 with a PostInstall that installs IIS, creates a sample
        site directory with a default page, and opens firewall port 80.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    return @{
        Tag        = 'IIS'
        VMName     = $Config.VMNames.IIS
        Roles      = @()
        OS         = $Config.ServerOS
        IP         = $Config.IPPlan.IIS
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

            Invoke-LabCommand -ComputerName $LabConfig.VMNames.IIS -ActivityName 'IIS-Install-WebServer' -ScriptBlock {
                # Install IIS (idempotent)
                $feat = Get-WindowsFeature Web-Server -ErrorAction SilentlyContinue
                if ($feat.InstallState -ne 'Installed') {
                    Install-WindowsFeature Web-Server -IncludeManagementTools -ErrorAction Stop
                    Write-Host '    [OK] IIS Web Server installed.' -ForegroundColor Green
                }
                else {
                    Write-Host '    [OK] IIS Web Server already installed.' -ForegroundColor Green
                }

                # Create sample site directory (idempotent)
                $sitePath = 'C:\inetpub\LabSite'
                if (-not (Test-Path $sitePath)) {
                    New-Item -Path $sitePath -ItemType Directory -Force | Out-Null
                }

                # Default page (idempotent)
                $indexPath = Join-Path $sitePath 'index.html'
                if (-not (Test-Path $indexPath)) {
                    $html = @'
<!DOCTYPE html>
<html>
<head><title>LabBuilder IIS</title></head>
<body>
    <h1>LabBuilder IIS - IIS1</h1>
    <p>Server is running. Deployed by LabBuilder.</p>
</body>
</html>
'@
                    Set-Content -Path $indexPath -Value $html -Encoding UTF8
                    Write-Host '    [OK] Sample site created at C:\inetpub\LabSite' -ForegroundColor Green
                }

                # Firewall rule (idempotent)
                $rule = Get-NetFirewallRule -DisplayName 'IIS HTTP (80)' -ErrorAction SilentlyContinue
                if (-not $rule) {
                    New-NetFirewallRule -DisplayName 'IIS HTTP (80)' `
                        -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow | Out-Null
                    Write-Host '    [OK] Firewall rule created for port 80.' -ForegroundColor Green
                }
            } -Retries 2 -RetryIntervalInSeconds 10
        }
    }
}

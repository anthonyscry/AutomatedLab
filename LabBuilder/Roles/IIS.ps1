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

            $iisVMName = $LabConfig.VMNames.IIS

            try {
                Invoke-LabCommand -ComputerName $iisVMName -ActivityName 'IIS-Install-WebServer' -ScriptBlock {
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
                        $null = New-Item -Path $sitePath -ItemType Directory -Force
                        Write-Verbose "Created IIS site directory: $sitePath"
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
                        Write-Verbose "Creating firewall rule for IIS HTTP port 80..."
                        $null = New-NetFirewallRule -DisplayName 'IIS HTTP (80)' `
                            -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow
                        Write-Host '    [OK] Firewall rule created for port 80.' -ForegroundColor Green
                    }
                } -Retries 2 -RetryIntervalInSeconds 10

                # Verify W3SVC service is running
                $iisVerify = Invoke-LabCommand -ComputerName $iisVMName -ActivityName 'IIS-Verify-Service' -PassThru -ScriptBlock {
                    $svc = Get-Service W3SVC -ErrorAction SilentlyContinue
                    @{ Running = ($null -ne $svc -and $svc.Status -eq 'Running') }
                }
                if (-not $iisVerify.Running) {
                    Write-Warning "IIS role: W3SVC service is not running on $iisVMName after installation. Run on IIS VM: Get-Service W3SVC | Format-Table Name,Status"
                }
                else {
                    Write-Host '    [OK] IIS W3SVC service verified running.' -ForegroundColor Green
                }
            }
            catch {
                Write-Warning "IIS role post-install failed on ${iisVMName}: $($_.Exception.Message). Check: Web-Server feature available, VM has sufficient disk space. Run on IIS VM: Get-Service W3SVC | Format-Table Name,Status"
            }
        }
    }
}

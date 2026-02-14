function Get-LabRole_WSUS {
    <#
    .SYNOPSIS
        Returns the WSUS role definition for LabBuilder.
    .DESCRIPTION
        Uses AutomatedLab module cmdlets for feature install and remote post-config.
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

            $wsusConfig = if ($LabConfig.ContainsKey('WSUS') -and $LabConfig.WSUS) { $LabConfig.WSUS } else { @{} }
            $contentDir = if ($wsusConfig.ContainsKey('ContentDir') -and -not [string]::IsNullOrWhiteSpace([string]$wsusConfig.ContentDir)) { [string]$wsusConfig.ContentDir } else { 'C:\WSUS' }
            $wsusPort = if ($wsusConfig.ContainsKey('Port') -and [int]$wsusConfig.Port -gt 0) { [int]$wsusConfig.Port } else { 8530 }

            Install-LabWindowsFeature -ComputerName $LabConfig.VMNames.WSUS -FeatureName 'UpdateServices-Services,UpdateServices-DB' -IncludeManagementTools

            Invoke-LabCommand -ComputerName $LabConfig.VMNames.WSUS -ActivityName 'WSUS-PostInstall' -ScriptBlock {
                param(
                    [string]$ContentDir,
                    [int]$WsusPort
                )

                if (-not (Test-Path $ContentDir)) {
                    New-Item -Path $ContentDir -ItemType Directory -Force | Out-Null
                }

                $wsusUtil = 'C:\Program Files\Update Services\Tools\wsusutil.exe'
                if (-not (Test-Path $wsusUtil)) {
                    throw "wsusutil.exe not found at $wsusUtil"
                }

                $alreadyConfigured = Test-Path 'HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup'
                if (-not $alreadyConfigured) {
                    Start-Process -FilePath $wsusUtil -ArgumentList 'postinstall', "CONTENT_DIR=\"$ContentDir\"" -Wait -NoNewWindow
                    if ($LASTEXITCODE -ne 0) {
                        throw "wsusutil postinstall failed with exit code $LASTEXITCODE"
                    }
                    Write-Host "    [OK] WSUS postinstall completed (ContentDir=$ContentDir)." -ForegroundColor Green
                }
                else {
                    Write-Host '    [OK] WSUS already configured (postinstall skipped).' -ForegroundColor Green
                }

                Set-Service -Name WsusService -StartupType Automatic -ErrorAction SilentlyContinue
                Start-Service -Name WsusService -ErrorAction SilentlyContinue

                $ruleName = "WSUS HTTP ($WsusPort)"
                if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
                    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort $WsusPort -Action Allow | Out-Null
                    Write-Host "    [OK] Firewall rule created for WSUS port $WsusPort." -ForegroundColor Green
                }
            } -ArgumentList $contentDir, $wsusPort -Retries 2 -RetryIntervalInSeconds 20
        }
    }
}

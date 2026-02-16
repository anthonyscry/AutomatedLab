function Get-LabRole_FileServer {
    <#
    .SYNOPSIS
        Returns the File Server role definition for LabBuilder.
    .DESCRIPTION
        Defines FILE1 with a PostInstall that installs File Services,
        creates a shared directory structure (LabShare), configures an
        SMB share with domain permissions, and opens firewall port 445.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    return @{
        Tag        = 'FileServer'
        VMName     = $Config.VMNames.FileServer
        Roles      = @()
        OS         = $Config.ServerOS
        IP         = $Config.IPPlan.FileServer
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

            Invoke-LabCommand -ComputerName $LabConfig.VMNames.FileServer -ActivityName 'FileServer-Configure' -ScriptBlock {
                param($GlobalLabConfig.Lab.DomainName)

                # Install File Services (idempotent)
                $feat = Get-WindowsFeature FS-FileServer -ErrorAction SilentlyContinue
                if ($feat -and $feat.InstallState -ne 'Installed') {
                    Install-WindowsFeature FS-FileServer -ErrorAction Stop
                    Write-Host '    [OK] File Services installed.' -ForegroundColor Green
                }
                else {
                    Write-Host '    [OK] File Services already installed.' -ForegroundColor Green
                }

                # Create share directory and sub-folders (idempotent)
                $sharePath = 'C:\LabShare'
                if (-not (Test-Path $sharePath)) {
                    New-Item -Path $sharePath -ItemType Directory -Force | Out-Null
                }

                $subFolders = @('Public', 'Departments', 'IT')
                foreach ($folder in $subFolders) {
                    $sub = Join-Path $sharePath $folder
                    if (-not (Test-Path $sub)) {
                        New-Item -Path $sub -ItemType Directory -Force | Out-Null
                    }
                }

                # Create SMB share (idempotent)
                $shareName = 'LabShare'
                if (-not (Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue)) {
                    $netbios = ($GlobalLabConfig.Lab.DomainName -split '\.')[0].ToUpper()
                    New-SmbShare -Name $shareName -Path $sharePath `
                        -FullAccess "$netbios\Domain Admins" `
                        -ChangeAccess "$netbios\Domain Users" `
                        -Description 'LabBuilder File Share' | Out-Null
                    Write-Host "    [OK] SMB share created: \\$env:COMPUTERNAME\$shareName" -ForegroundColor Green
                }
                else {
                    Write-Host "    [OK] SMB share already exists: \\$env:COMPUTERNAME\$shareName" -ForegroundColor Green
                }

                # Firewall rule for SMB (idempotent)
                $rule = Get-NetFirewallRule -DisplayName 'File Server SMB (445)' -ErrorAction SilentlyContinue
                if (-not $rule) {
                    New-NetFirewallRule -DisplayName 'File Server SMB (445)' `
                        -Direction Inbound -LocalPort 445 -Protocol TCP -Action Allow | Out-Null
                    Write-Host '    [OK] Firewall rule created for SMB port 445.' -ForegroundColor Green
                }
            } -ArgumentList $LabConfig.DomainName -Retries 2 -RetryIntervalInSeconds 10
        }
    }
}

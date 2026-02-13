function Get-LabRole_Ubuntu {
    <#
    .SYNOPSIS
        Returns the Ubuntu Linux role definition for LabBuilder.
    .DESCRIPTION
        Defines LIN1 as an Ubuntu 24.04 Linux VM. Unlike Windows roles,
        Linux VMs bypass AutomatedLab's Install-Lab and are created manually
        using Hyper-V cmdlets + cloud-init autoinstall via CIDATA VHDX.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    # Dot-source Lab-Common.ps1 for Linux helper functions
    $labCommonPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Lab-Common.ps1'
    if (Test-Path $labCommonPath) { . $labCommonPath }

    return @{
        Tag            = 'Ubuntu'
        VMName         = $Config.VMNames.Ubuntu
        IsLinux        = $true
        SkipInstallLab = $true

        OS         = $Config.LinuxOS
        Memory     = $Config.LinuxVM.Memory
        MinMemory  = $Config.LinuxVM.MinMemory
        MaxMemory  = $Config.LinuxVM.MaxMemory
        Processors = $Config.LinuxVM.Processors

        IP         = $Config.IPPlan.Ubuntu
        Gateway    = $Config.Network.Gateway
        DnsServer1 = $Config.IPPlan.DC
        Network    = $Config.Network.SwitchName
        DomainName = $Config.DomainName

        Roles      = @()

        CreateVM = {
            param([hashtable]$LabConfig)

            $vmName = $LabConfig.VMNames.Ubuntu
            $labPath = $LabConfig.LabPath
            $isoDir = Join-Path $LabConfig.LabSourcesRoot 'ISOs'

            # Find Ubuntu ISO
            $ubuntuIso = Get-ChildItem -Path $isoDir -Filter 'ubuntu-24.04*.iso' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
            if (-not $ubuntuIso) {
                throw "Ubuntu 24.04 ISO not found in $isoDir"
            }
            Write-Host "    [OK] Ubuntu ISO: $ubuntuIso" -ForegroundColor Green

            # Resolve password
            $envPassword = [System.Environment]::GetEnvironmentVariable($LabConfig.CredentialEnvVar)
            if ([string]::IsNullOrWhiteSpace($envPassword)) { $envPassword = 'Server123!' }

            # Generate SHA512 password hash
            $pwHash = Get-Sha512PasswordHash -Password $envPassword

            # Read SSH public key
            $sshPubKey = ''
            $sshPubKeyPath = $LabConfig.Linux.SSHPublicKey
            if ($sshPubKeyPath -and (Test-Path $sshPubKeyPath)) {
                $sshPubKey = (Get-Content $sshPubKeyPath -Raw).Trim()
                Write-Host '    [OK] SSH public key found' -ForegroundColor Green
            }

            # Create CIDATA VHDX seed disk
            $cidataPath = Join-Path $labPath "$vmName-cidata.vhdx"
            Write-Host '    Creating CIDATA seed disk...' -ForegroundColor Gray
            New-CidataVhdx -OutputPath $cidataPath `
                -Hostname $vmName `
                -Username $LabConfig.Linux.User `
                -PasswordHash $pwHash `
                -SSHPublicKey $sshPubKey `
                -Distro 'Ubuntu2404'

            # Create the VM
            Write-Host '    Creating Hyper-V Gen2 VM...' -ForegroundColor Gray
            New-LinuxVM -UbuntuIsoPath $ubuntuIso `
                -CidataVhdxPath $cidataPath `
                -VMName $vmName `
                -SwitchName $LabConfig.Network.SwitchName `
                -Memory $LabConfig.LinuxVM.Memory `
                -MinMemory $LabConfig.LinuxVM.MinMemory `
                -MaxMemory $LabConfig.LinuxVM.MaxMemory `
                -Processors $LabConfig.LinuxVM.Processors

            # Start VM - autoinstall begins
            Start-VM -Name $vmName
            Write-Host "    [OK] $vmName started. Ubuntu autoinstall in progress..." -ForegroundColor Green

            # Wait for SSH reachability
            $waitMinutes = $LabConfig.Timeouts.LinuxSSHWait
            Write-Host "    Waiting for SSH (up to $waitMinutes min)..." -ForegroundColor Cyan

            $deadline = [datetime]::Now.AddMinutes($waitMinutes)
            $lastKnownIp = ''
            $sshReady = $false
            $pollInterval = $LabConfig.Timeouts.SSHPollInitialSec
            $pollMax = $LabConfig.Timeouts.SSHPollMaxSec

            while ([datetime]::Now -lt $deadline) {
                $adapter = Get-VMNetworkAdapter -VMName $vmName -ErrorAction SilentlyContinue | Select-Object -First 1
                $ips = @()
                if ($adapter -and ($adapter.PSObject.Properties.Name -contains 'IPAddresses')) {
                    $ips = @($adapter.IPAddresses) | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^169\.254\.' }
                }

                if ($ips) {
                    $ip = $ips | Select-Object -First 1
                    $lastKnownIp = $ip
                    $sshCheck = Test-NetConnection -ComputerName $ip -Port 22 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                    if ($sshCheck.TcpTestSucceeded) {
                        $sshReady = $true
                        Write-Host "    [OK] $vmName SSH reachable at $ip" -ForegroundColor Green
                        break
                    }
                }

                if ($lastKnownIp) {
                    Write-Host "      IP: $lastKnownIp, waiting for SSH..." -ForegroundColor Gray
                }
                else {
                    Write-Host '      Waiting for DHCP lease...' -ForegroundColor Gray
                }

                Start-Sleep -Seconds $pollInterval
                $pollInterval = [math]::Min([int]($pollInterval * 1.5), $pollMax)
            }

            if (-not $sshReady) {
                Write-Warning "$vmName did not become SSH-reachable within $waitMinutes minutes."
                Write-Host '      Run Configure-LIN1.ps1 manually after Ubuntu install completes.' -ForegroundColor Yellow
                return
            }

            # Finalize boot media (detach ISO + CIDATA)
            Finalize-LinuxInstallMedia -VMName $vmName
        }

        PostInstall = {
            param([hashtable]$LabConfig)

            $vmName = $LabConfig.VMNames.Ubuntu
            $linuxUser = $LabConfig.Linux.User

            # Get VM IP
            $adapter = Get-VMNetworkAdapter -VMName $vmName -ErrorAction SilentlyContinue | Select-Object -First 1
            $vmIp = ''
            if ($adapter -and ($adapter.PSObject.Properties.Name -contains 'IPAddresses')) {
                $vmIp = @($adapter.IPAddresses) | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^169\.254\.' } | Select-Object -First 1
            }
            if (-not $vmIp) {
                Write-Warning "Cannot determine $vmName IP. Skipping post-install."
                return
            }

            # Find SSH key
            $sshKey = $LabConfig.Linux.SSHPrivateKey
            if (-not $sshKey -or -not (Test-Path $sshKey)) {
                Write-Warning "SSH private key not found at $sshKey. Skipping post-install."
                return
            }

            $sshExe = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
            if (-not (Test-Path $sshExe)) {
                Write-Warning 'OpenSSH client not found. Skipping post-install.'
                return
            }

            $sshArgs = @(
                '-o', 'StrictHostKeyChecking=no',
                '-o', 'UserKnownHostsFile=NUL',
                '-o', "ConnectTimeout=$($LabConfig.Timeouts.SSHConnectTimeout)",
                '-i', $sshKey,
                "$linuxUser@$vmIp"
            )

            Write-Host "    Running post-install on $vmName ($vmIp)..." -ForegroundColor Cyan

            # Post-install commands via SSH
            $postInstallScript = @"
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
SUDO=""
if [ "`$(id -u)" -ne 0 ]; then SUDO="sudo -n"; fi

echo "[POST] Updating packages..."
`$SUDO apt-get update -qq || true
`$SUDO apt-get install -y -qq openssh-server cifs-utils net-tools curl wget git jq build-essential || true

echo "[POST] Configuring SSH..."
`$SUDO systemctl enable --now ssh || true

echo "[POST] Installing dev tools..."
`$SUDO apt-get install -y -qq python3 python3-pip nodejs npm 2>/dev/null || true

echo "[POST] Post-install complete."
"@

            # Write script to temp, send via SSH
            $tempScript = Join-Path $env:TEMP "postinstall-$vmName.sh"
            $postInstallScript | Set-Content -Path $tempScript -Encoding ASCII -Force

            try {
                # Copy script using SCP
                $scpExe = Join-Path $env:WINDIR 'System32\OpenSSH\scp.exe'
                & $scpExe -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -i $sshKey $tempScript "${linuxUser}@${vmIp}:/tmp/postinstall.sh" 2>&1 | Out-Null

                # Execute it
                & $sshExe @sshArgs "chmod +x /tmp/postinstall.sh && bash /tmp/postinstall.sh && rm -f /tmp/postinstall.sh" 2>&1 | ForEach-Object {
                    Write-Host "      $_" -ForegroundColor Gray
                }

                Write-Host "    [OK] Post-install complete on $vmName" -ForegroundColor Green
            }
            catch {
                Write-Warning "Post-install SSH execution failed on ${vmName}: $($_.Exception.Message)"
            }
            finally {
                Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

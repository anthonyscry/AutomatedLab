function Get-LabRole_DockerUbuntu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $labCommonPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Lab-Common.ps1'
    if (Test-Path $labCommonPath) { . $labCommonPath }

    return @{
        Tag            = 'DockerUbuntu'
        VMName         = $Config.VMNames.DockerUbuntu
        IsLinux        = $true
        SkipInstallLab = $true

        OS         = $Config.LinuxOS
        Memory     = $Config.LinuxVM.Memory
        MinMemory  = $Config.LinuxVM.MinMemory
        MaxMemory  = $Config.LinuxVM.MaxMemory
        Processors = $Config.LinuxVM.Processors

        IP         = $Config.IPPlan.DockerUbuntu
        Gateway    = $Config.Network.Gateway
        DnsServer1 = $Config.IPPlan.DC
        Network    = $Config.Network.SwitchName
        DomainName = $Config.DomainName

        Roles      = @()

        CreateVM = {
            param([hashtable]$LabConfig)

            $vmName = $LabConfig.VMNames.DockerUbuntu
            $labPath = $LabConfig.LabPath
            $isoDir = Join-Path $LabConfig.LabSourcesRoot 'ISOs'

            $ubuntuIso = Get-ChildItem -Path $isoDir -Filter 'ubuntu-24.04*.iso' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
            if (-not $ubuntuIso) {
                throw "Ubuntu 24.04 ISO not found in $isoDir"
            }
            Write-Host "    [OK] Ubuntu ISO: $ubuntuIso" -ForegroundColor Green

            $envPassword = [System.Environment]::GetEnvironmentVariable($LabConfig.CredentialEnvVar)
            if ([string]::IsNullOrWhiteSpace($envPassword)) { $envPassword = 'Server123!' }
            $pwHash = Get-Sha512PasswordHash -Password $envPassword

            $sshPubKey = ''
            $sshPubKeyPath = $LabConfig.Linux.SSHPublicKey
            if ($sshPubKeyPath -and (Test-Path $sshPubKeyPath)) {
                $sshPubKey = (Get-Content $sshPubKeyPath -Raw).Trim()
                Write-Host '    [OK] SSH public key found' -ForegroundColor Green
            }

            $cidataPath = Join-Path $labPath "$vmName-cidata.vhdx"
            Write-Host '    Creating CIDATA seed disk...' -ForegroundColor Gray
            New-CidataVhdx -OutputPath $cidataPath `
                -Hostname $vmName `
                -Username $LabConfig.Linux.User `
                -PasswordHash $pwHash `
                -SSHPublicKey $sshPubKey

            Write-Host '    Creating Hyper-V Gen2 VM...' -ForegroundColor Gray
            New-LinuxVM -UbuntuIsoPath $ubuntuIso `
                -CidataVhdxPath $cidataPath `
                -VMName $vmName `
                -SwitchName $LabConfig.Network.SwitchName `
                -Memory $LabConfig.LinuxVM.Memory `
                -MinMemory $LabConfig.LinuxVM.MinMemory `
                -MaxMemory $LabConfig.LinuxVM.MaxMemory `
                -Processors $LabConfig.LinuxVM.Processors

            Start-VM -Name $vmName
            Write-Host "    [OK] $vmName started. Ubuntu autoinstall in progress..." -ForegroundColor Green

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
                return
            }

            Finalize-LinuxInstallMedia -VMName $vmName
        }

        PostInstall = {
            param([hashtable]$LabConfig)

            $vmName = $LabConfig.VMNames.DockerUbuntu
            $linuxUser = $LabConfig.Linux.User

            $adapter = Get-VMNetworkAdapter -VMName $vmName -ErrorAction SilentlyContinue | Select-Object -First 1
            $vmIp = ''
            if ($adapter -and ($adapter.PSObject.Properties.Name -contains 'IPAddresses')) {
                $vmIp = @($adapter.IPAddresses) | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^169\.254\.' } | Select-Object -First 1
            }
            if (-not $vmIp) {
                Write-Warning "Cannot determine $vmName IP. Skipping post-install."
                return
            }

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

            $postInstallScript = @"
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
SUDO=""
if [ "`$(id -u)" -ne 0 ]; then SUDO="sudo -n"; fi

echo "[Docker] Installing prerequisites..."
`$SUDO apt-get update -qq
`$SUDO apt-get install -y -qq ca-certificates curl gnupg lsb-release
`$SUDO install -m 0755 -d /etc/apt/keyrings
`$SUDO curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
`$SUDO chmod a+r /etc/apt/keyrings/docker.asc

echo "[Docker] Configuring Docker APT repository..."
ARCH=`$(dpkg --print-architecture)
CODENAME=`$(. /etc/os-release && echo "`${UBUNTU_CODENAME:-`$VERSION_CODENAME}")
echo "deb [arch=`$ARCH signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu `$CODENAME stable" | `$SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null

echo "[Docker] Installing Docker CE + Compose plugin..."
`$SUDO apt-get update -qq
`$SUDO apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
`$SUDO systemctl enable --now docker
`$SUDO usermod -aG docker $linuxUser || true

echo "[Docker] Installed. docker --version:"
`$SUDO docker --version || true
echo "[Docker] Compose plugin version:"
`$SUDO docker compose version || true
"@

            $tempScript = Join-Path $env:TEMP "postinstall-$vmName.sh"
            $postInstallScript | Set-Content -Path $tempScript -Encoding ASCII -Force

            try {
                $scpExe = Join-Path $env:WINDIR 'System32\OpenSSH\scp.exe'
                & $scpExe -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -i $sshKey $tempScript "${linuxUser}@${vmIp}:/tmp/postinstall.sh" 2>&1 | Out-Null
                & $sshExe @sshArgs "chmod +x /tmp/postinstall.sh && bash /tmp/postinstall.sh && rm -f /tmp/postinstall.sh" 2>&1 | ForEach-Object {
                    Write-Host "      $_" -ForegroundColor Gray
                }
                Write-Host "    [OK] Docker installed on $vmName" -ForegroundColor Green
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

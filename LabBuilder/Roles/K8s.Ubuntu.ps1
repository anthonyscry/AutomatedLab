function Get-LabRole_K8sUbuntu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $labCommonPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Lab-Common.ps1'
    if (Test-Path $labCommonPath) { . $labCommonPath }

    return @{
        Tag            = 'K8sUbuntu'
        VMName         = $Config.VMNames.K8sUbuntu
        IsLinux        = $true
        SkipInstallLab = $true

        OS         = $Config.LinuxOS
        Memory     = $Config.LinuxVM.Memory
        MinMemory  = $Config.LinuxVM.MinMemory
        MaxMemory  = $Config.LinuxVM.MaxMemory
        Processors = $Config.LinuxVM.Processors

        IP         = $Config.IPPlan.K8sUbuntu
        Gateway    = $Config.Network.Gateway
        DnsServer1 = $Config.IPPlan.DC
        Network    = $Config.Network.SwitchName
        DomainName = $Config.DomainName

        Roles      = @()

        CreateVM = {
            param([hashtable]$LabConfig)

            $vmName = $LabConfig.VMNames.K8sUbuntu
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

            $vmName = $LabConfig.VMNames.K8sUbuntu
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

echo "[K8s] Installing dependencies..."
`$SUDO apt-get update -qq
`$SUDO apt-get install -y -qq curl ca-certificates

echo "[K8s] Installing k3s (single-node server)..."
curl -sfL https://get.k3s.io | `$SUDO sh -

echo "[K8s] Waiting for node to become Ready..."
for i in `$(seq 1 60); do
    if `$SUDO k3s kubectl get nodes 2>/dev/null | grep -q ' Ready '; then
        break
    fi
    sleep 5
done

`$SUDO systemctl enable --now k3s
`$SUDO mkdir -p /home/$linuxUser/.kube
`$SUDO cp /etc/rancher/k3s/k3s.yaml /home/$linuxUser/.kube/config
`$SUDO chown -R ${linuxUser}:${linuxUser} /home/$linuxUser/.kube

echo "[K8s] Node status:"
`$SUDO k3s kubectl get nodes -o wide || true
echo "[K8s] k3s installation complete."
"@

            $tempScript = Join-Path $env:TEMP "postinstall-$vmName.sh"
            $postInstallScript | Set-Content -Path $tempScript -Encoding ASCII -Force

            try {
                $scpExe = Join-Path $env:WINDIR 'System32\OpenSSH\scp.exe'
                & $scpExe -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -i $sshKey $tempScript "${linuxUser}@${vmIp}:/tmp/postinstall.sh" 2>&1 | Out-Null
                & $sshExe @sshArgs "chmod +x /tmp/postinstall.sh && bash /tmp/postinstall.sh && rm -f /tmp/postinstall.sh" 2>&1 | ForEach-Object {
                    Write-Host "      $_" -ForegroundColor Gray
                }
                Write-Host "    [OK] k3s installed on $vmName" -ForegroundColor Green
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

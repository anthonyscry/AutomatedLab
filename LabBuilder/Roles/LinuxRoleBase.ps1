function Invoke-LinuxRoleCreateVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$LabConfig,
        [Parameter(Mandatory)][string]$VMNameKey,
        [string]$ISOPattern = 'ubuntu-24.04*.iso'
    )

    # Null-guards: validate config before accessing properties
    if (-not $LabConfig.VMNames -or -not $LabConfig.VMNames.ContainsKey($VMNameKey)) {
        Write-Warning "VM name key '$VMNameKey' not found in config VMNames. Skipping Linux VM creation."
        return
    }
    if (-not $LabConfig.LabSourcesRoot) {
        Write-Warning "LabSourcesRoot not configured. Skipping Linux VM creation."
        return
    }
    if (-not $LabConfig.ContainsKey('Linux') -or -not $LabConfig.Linux) {
        Write-Warning "Linux config section not found. Skipping Linux VM creation."
        return
    }

    $vmName = $LabConfig.VMNames[$VMNameKey]
    $labPath = $LabConfig.LabPath
    $isoDir = Join-Path $LabConfig.LabSourcesRoot 'ISOs'

    # Find ISO
    $ubuntuIso = Get-ChildItem -Path $isoDir -Filter $ISOPattern -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (-not $ubuntuIso) {
        throw "$ISOPattern not found in $isoDir"
    }
    Write-Host "    [OK] ISO: $ubuntuIso" -ForegroundColor Green

    # Resolve password
    $envPassword = [System.Environment]::GetEnvironmentVariable($LabConfig.CredentialEnvVar)
    if ([string]::IsNullOrWhiteSpace($envPassword)) { $envPassword = 'SimpleLab123!' }
    $pwHash = Get-Sha512PasswordHash -Password $envPassword

    # SSH public key
    $sshPubKey = ''
    $sshPubKeyPath = $LabConfig.Linux.SSHPublicKey
    if ($sshPubKeyPath -and (Test-Path $sshPubKeyPath)) {
        $sshPubKey = (Get-Content $sshPubKeyPath -Raw).Trim()
        Write-Host '    [OK] SSH public key found' -ForegroundColor Green
    }

    # Create CIDATA
    $cidataPath = Join-Path $labPath "$vmName-cidata.vhdx"
    Write-Host '    Creating CIDATA seed disk...' -ForegroundColor Gray
    New-CidataVhdx -OutputPath $cidataPath -Hostname $vmName -Username $LabConfig.Linux.User -PasswordHash $pwHash -SSHPublicKey $sshPubKey

    # Create VM
    Write-Host '    Creating Hyper-V Gen2 VM...' -ForegroundColor Gray
    New-LinuxVM -UbuntuIsoPath $ubuntuIso -CidataVhdxPath $cidataPath -VMName $vmName `
        -SwitchName $LabConfig.Network.SwitchName `
        -Memory $LabConfig.LinuxVM.Memory -MinMemory $LabConfig.LinuxVM.MinMemory `
        -MaxMemory $LabConfig.LinuxVM.MaxMemory -Processors $LabConfig.LinuxVM.Processors

    # Start VM
    Start-VM -Name $vmName
    Write-Host "    [OK] $vmName started. Autoinstall in progress..." -ForegroundColor Green

    # Wait for SSH
    # Timeout defaults if section missing
    $waitMinutes = 10
    $pollInterval = 15
    $pollMax = 60
    if ($LabConfig.ContainsKey('Timeouts') -and $LabConfig.Timeouts) {
        if ($LabConfig.Timeouts.ContainsKey('LinuxSSHWait')) { $waitMinutes = $LabConfig.Timeouts.LinuxSSHWait }
        if ($LabConfig.Timeouts.ContainsKey('SSHPollInitialSec')) { $pollInterval = $LabConfig.Timeouts.SSHPollInitialSec }
        if ($LabConfig.Timeouts.ContainsKey('SSHPollMaxSec')) { $pollMax = $LabConfig.Timeouts.SSHPollMaxSec }
    }
    Write-Host "    Waiting for SSH (up to $waitMinutes min)..." -ForegroundColor Cyan

    $deadline = [datetime]::Now.AddMinutes($waitMinutes)
    $lastKnownIp = ''
    $sshReady = $false

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

        if ($lastKnownIp) { Write-Host "      IP: $lastKnownIp, waiting for SSH..." -ForegroundColor Gray }
        else { Write-Host '      Waiting for DHCP lease...' -ForegroundColor Gray }

        Start-Sleep -Seconds $pollInterval
        $pollInterval = [math]::Min([int]($pollInterval * 1.5), $pollMax)
    }

    if (-not $sshReady) {
        Write-Warning "$vmName did not become SSH-reachable within $waitMinutes minutes."
        return
    }

    Finalize-LinuxInstallMedia -VMName $vmName
}

function Invoke-LinuxRolePostInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$LabConfig,
        [Parameter(Mandatory)][string]$VMNameKey,
        [Parameter(Mandatory)][string]$BashScript,
        [string]$SuccessMessage = 'Post-install complete',
        [int]$RetryCount = 3,
        [int]$RetryDelaySeconds = 10
    )

    # Read defaults from LabConfig if not explicitly provided
    if (-not $PSBoundParameters.ContainsKey('RetryCount') -and $LabConfig.ContainsKey('Timeouts') -and $LabConfig.Timeouts.ContainsKey('SSHRetryCount')) {
        $RetryCount = $LabConfig.Timeouts.SSHRetryCount
    }
    if (-not $PSBoundParameters.ContainsKey('RetryDelaySeconds') -and $LabConfig.ContainsKey('Timeouts') -and $LabConfig.Timeouts.ContainsKey('SSHRetryDelaySeconds')) {
        $RetryDelaySeconds = $LabConfig.Timeouts.SSHRetryDelaySeconds
    }

    # Null-guards for PostInstall
    if (-not $LabConfig.VMNames -or -not $LabConfig.VMNames.ContainsKey($VMNameKey)) {
        Write-Warning "VM name key '$VMNameKey' not found in config VMNames. Skipping Linux post-install."
        return
    }
    if (-not $LabConfig.ContainsKey('Linux') -or -not $LabConfig.Linux -or -not $LabConfig.Linux.User) {
        Write-Warning "Linux config section or Linux.User not found. Skipping Linux post-install."
        return
    }

    $vmName = $LabConfig.VMNames[$VMNameKey]
    $linuxUser = $LabConfig.Linux.User

    $adapter = Get-VMNetworkAdapter -VMName $vmName -ErrorAction SilentlyContinue | Select-Object -First 1
    $vmIp = ''
    if ($adapter -and ($adapter.PSObject.Properties.Name -contains 'IPAddresses')) {
        $vmIp = @($adapter.IPAddresses) | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^169\.254\.' } | Select-Object -First 1
    }
    if (-not $vmIp) { Write-Warning "Cannot determine $vmName IP. Skipping post-install."; return }

    $sshKey = $LabConfig.Linux.SSHPrivateKey
    if (-not $sshKey -or -not (Test-Path $sshKey)) { Write-Warning "SSH private key not found. Skipping post-install."; return }

    $winDir = if ($env:WINDIR) { $env:WINDIR } else { 'C:\Windows' }
    $tempDir = if ($env:TEMP) { $env:TEMP } else { $env:TMP }
    if (-not $tempDir) { $tempDir = [System.IO.Path]::GetTempPath().TrimEnd([System.IO.Path]::DirectorySeparatorChar) }

    $sshExe = Join-Path $winDir 'System32\OpenSSH\ssh.exe'
    if (-not (Test-Path $sshExe)) { Write-Warning 'OpenSSH client not found. Skipping post-install.'; return }

    $sshArgs = @(
        '-o', 'StrictHostKeyChecking=accept-new', '-o', "UserKnownHostsFile=$($GlobalLabConfig.SSH.KnownHostsPath)",
        '-o', "ConnectTimeout=$($LabConfig.Timeouts.SSHConnectTimeout)",
        '-i', $sshKey, "$linuxUser@$vmIp"
    )

    Write-Host "    Running post-install on $vmName ($vmIp)..." -ForegroundColor Cyan

    $tempScript = Join-Path $tempDir "postinstall-$vmName.sh"
    $BashScript | Set-Content -Path $tempScript -Encoding ASCII -Force

    $attempt = 0
    $succeeded = $false
    $scpExe = Join-Path $winDir 'System32\OpenSSH\scp.exe'

    while ($attempt -lt $RetryCount -and -not $succeeded) {
        $attempt++
        try {
            & $scpExe -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$($GlobalLabConfig.SSH.KnownHostsPath)" -i $sshKey $tempScript "${linuxUser}@${vmIp}:/tmp/postinstall.sh" 2>&1 | Out-Null
            & $sshExe @sshArgs "chmod +x /tmp/postinstall.sh && bash /tmp/postinstall.sh && rm -f /tmp/postinstall.sh" 2>&1 | ForEach-Object {
                Write-Host "      $_" -ForegroundColor Gray
            }
            $succeeded = $true
            Write-Host "    [OK] $SuccessMessage on $vmName" -ForegroundColor Green
        }
        catch {
            if ($attempt -lt $RetryCount) {
                Write-Warning "SSH attempt $attempt/$RetryCount failed on ${vmName}: $($_.Exception.Message). Retrying in ${RetryDelaySeconds}s..."
                Start-Sleep -Seconds $RetryDelaySeconds
            }
            else {
                Write-Warning "Post-install SSH execution failed on ${vmName} after $RetryCount attempts: $($_.Exception.Message)"
            }
        }
    }

    Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
}

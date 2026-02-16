# Install-Ansible.ps1 -- Install Ansible on a Linux VM and deploy inventory/playbooks
# Ansible runs FROM the Linux VM to manage other lab machines.

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$VMName = 'LIN1',
    [switch]$NonInteractive,
    [switch]$AutoStart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = Split-Path -Parent $ScriptDir
$ConfigPath = Join-Path $RepoRoot 'Lab-Config.ps1'
$CommonPath = Join-Path $RepoRoot 'Lab-Common.ps1'
if (Test-Path $ConfigPath) { . $ConfigPath }
if (Test-Path $CommonPath) { . $CommonPath }

Write-Host "`n=== INSTALL ANSIBLE ===" -ForegroundColor Cyan

# Ensure VM is running
Ensure-VMsReady -VMNames @($VMName) -NonInteractive:$NonInteractive -AutoStart:$AutoStart

# Get VM IP
$ip = Get-LinuxVMIPv4 -VMName $VMName
if (-not $ip) {
    throw "$VMName is not reachable. Ensure it has an IP."
}

$sshExe = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
$scpExe = Join-Path $env:WINDIR 'System32\OpenSSH\scp.exe'
$sshArgs = @('-o','StrictHostKeyChecking=accept-new','-o','UserKnownHostsFile=NUL','-o',"ConnectTimeout=$SSH_ConnectTimeout",'-i',$SSHPrivateKey,"$LinuxUser@$ip")

# Install Ansible via pip (more current than apt)
Write-Host "  Installing Ansible on $VMName..." -ForegroundColor Yellow
$installScript = @'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo -n"

echo "[Ansible] Installing prerequisites..."
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq python3 python3-pip python3-venv sshpass

echo "[Ansible] Creating virtual environment..."
python3 -m venv ~/ansible-venv
source ~/ansible-venv/bin/activate

echo "[Ansible] Installing Ansible..."
pip install --upgrade pip
pip install ansible

echo "[Ansible] Verifying..."
ansible --version

# Add to .bashrc for convenience
grep -q 'ansible-venv' ~/.bashrc || echo 'source ~/ansible-venv/bin/activate' >> ~/.bashrc

echo "[Ansible] Creating directory structure..."
mkdir -p ~/ansible/{inventory,playbooks,roles}

echo "[Ansible] Installation complete."
'@

$tempScript = Join-Path $env:TEMP "install-ansible-$VMName.sh"
$installScript | Set-Content -Path $tempScript -Encoding ASCII -Force

try {
    & $scpExe -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=NUL -i $SSHPrivateKey $tempScript "${LinuxUser}@${ip}:/tmp/install-ansible.sh" 2>&1 | Out-Null
    & $sshExe @sshArgs 'chmod +x /tmp/install-ansible.sh && bash /tmp/install-ansible.sh && rm -f /tmp/install-ansible.sh' 2>&1 | ForEach-Object {
        Write-Host "    $_" -ForegroundColor Gray
    }
    Write-LabStatus -Status OK -Message "Ansible installed on $VMName"
} catch {
    throw "Ansible installation failed: $($_.Exception.Message)"
} finally {
    Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
}

# Deploy inventory template
Write-Host "  Deploying inventory template..." -ForegroundColor Yellow
$ansibleDir = Join-Path $ScriptDir 'Ansible'
$inventoryTemplate = Join-Path $ansibleDir 'inventory.yml.template'
if (Test-Path $inventoryTemplate) {
    # Generate actual inventory from template
    $inventoryContent = (Get-Content $inventoryTemplate -Raw)
    $inventoryContent = $inventoryContent -replace '__DC1_IP__', $dc1_Ip
    $inventoryContent = $inventoryContent -replace '__LIN1_IP__', $lin1_Ip
    $inventoryContent = $inventoryContent -replace '__DOMAIN__', $DomainName
    $inventoryContent = $inventoryContent -replace '__LINUX_USER__', $LinuxUser
    $inventoryContent = $inventoryContent -replace '__ADMIN_USER__', $LabInstallUser

    $inventoryPath = Join-Path $env:TEMP "lab-inventory-$VMName.yml"
    $inventoryContent | Set-Content -Path $inventoryPath -Encoding ASCII -Force

    & $scpExe -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=NUL -i $SSHPrivateKey $inventoryPath "${LinuxUser}@${ip}:~/ansible/inventory/lab.yml" 2>&1 | Out-Null
    Remove-Item $inventoryPath -Force -ErrorAction SilentlyContinue
    Write-LabStatus -Status OK -Message "Inventory deployed to ~/ansible/inventory/lab.yml"
}

# Deploy playbooks
$playbooksDir = Join-Path $ansibleDir 'playbooks'
if (Test-Path $playbooksDir) {
    $playbooks = Get-ChildItem $playbooksDir -Filter '*.yml' -ErrorAction SilentlyContinue
    foreach ($pb in $playbooks) {
        & $scpExe -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=NUL -i $SSHPrivateKey $pb.FullName "${LinuxUser}@${ip}:~/ansible/playbooks/$($pb.Name)" 2>&1 | Out-Null
    }
    Write-LabStatus -Status OK -Message "$($playbooks.Count) playbook(s) deployed"
}

Write-Host "`n=== ANSIBLE READY ===" -ForegroundColor Green
Write-Host "  SSH into $VMName and run:" -ForegroundColor White
Write-Host "    cd ~/ansible" -ForegroundColor Yellow
Write-Host "    ansible-playbook -i inventory/lab.yml playbooks/lab-baseline.yml" -ForegroundColor Yellow

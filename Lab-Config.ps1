# Lab-Config.ps1 -- Central config for OpenCode Dev Lab helper scripts
# Put this file in the same folder as OpenCodeLab-App.ps1 (C:\LabSources\Scripts\ recommended).
# You can edit values here once instead of in every script.

# Lab identity
$LabName     = 'SimpleLab'
$LabVMs      = @('DC1','Server1','Win11')
$DomainName  = 'simplelab.local'

# Lab paths
$LabPath        = "C:\AutomatedLab\$LabName"
$LabSourcesRoot = 'C:\LabSources'
$ScriptsRoot    = Join-Path $LabSourcesRoot 'Scripts'

# Linux VM defaults (LIN1)
$LinuxUser   = 'anthonyscry'
$LinuxHome   = "/home/$LinuxUser"
$LinuxProjectsRoot = "$LinuxHome/projects"
$LinuxLabShareMount = "/mnt/labshare"

# Windows paths
$SSHKeyDir     = Join-Path $LabSourcesRoot 'SSHKeys'
$SSHPrivateKey = Join-Path $SSHKeyDir 'id_ed25519'
$SSHPublicKey  = "$SSHPrivateKey.pub"
$SSHKey        = $SSHPrivateKey

# Networking: dedicated Internal vSwitch + host NAT
$LabSwitch    = 'SimpleLabSwitch'
$AddressSpace = '192.168.11.0/24'
$GatewayIp    = '192.168.11.1'
$NatName      = "${LabSwitch}NAT"

# Static IP plan
$DC1_Ip     = '192.168.11.3'
$Server1_Ip = '192.168.11.4'
$Win11_Ip   = '192.168.11.5'
$LIN1_Ip    = '192.168.11.6'
$DnsIp      = $DC1_Ip

# Legacy aliases (for backward compatibility)
$WSUS1_Ip = $Server1_Ip
$WS1_Ip   = $Win11_Ip

# DHCP scope for the lab subnet (keeps .1-.99 free for statics)
$DhcpScopeId = '192.168.11.0'
$DhcpStart   = '192.168.11.100'
$DhcpEnd     = '192.168.11.200'
$DhcpMask    = '255.255.255.0'

# VM sizing
$DC_Memory      = 4GB
$DC_MinMemory   = 2GB
$DC_MaxMemory   = 6GB
$DC_Processors  = 4

$CL_Memory      = 4GB
$CL_MinMemory   = 2GB
$CL_MaxMemory   = 6GB
$CL_Processors  = 4

$Server_Memory      = 4GB
$Server_MinMemory   = 2GB
$Server_MaxMemory   = 6GB
$Server_Processors  = 4

# Legacy alias (for backward compatibility)
$WSUS_Memory     = $Server_Memory
$WSUS_MinMemory  = $Server_MinMemory
$WSUS_MaxMemory  = $Server_MaxMemory
$WSUS_Processors = $Server_Processors

$UBU_Memory     = 4GB
$UBU_MinMemory  = 2GB
$UBU_MaxMemory  = 6GB
$UBU_Processors = 4

# Share settings (hosted on DC1)
$ShareName   = 'LabShare'
$SharePath   = 'C:\LabShare'
$GitRepoPath = 'C:\LabShare\Repos'

# Bootstrap/deploy helpers
$BootstrapScript = 'Bootstrap.ps1'
$DeployScript    = 'Deploy.ps1'

# Required ISOs (used by Bootstrap, Deploy, Preflight)
$RequiredISOs = @('server2019.iso', 'windows11.iso')

# AutomatedLab timeout overrides (minutes)
# Defaults are too short for resource-constrained hosts
$AL_Timeout_DcRestart   = 90    # default 60 - wait for DC VM restart after promotion
$AL_Timeout_AdwsReady   = 120   # default 20 - wait for AD/ADWS readiness after promotion
$AL_Timeout_StartVM     = 90    # default 60 - wait for Start-LabVM
$AL_Timeout_WaitVM      = 90    # default 60 - wait for Wait-LabVM

# Optional: Git identity (leave blank to prompt when needed)
$GitName  = ''
$GitEmail = ''

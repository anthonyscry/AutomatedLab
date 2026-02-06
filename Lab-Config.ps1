<#
.SYNOPSIS
  Lab-Config.ps1 -- Central config for OpenCode Dev Lab helper scripts
.NOTES
  Put this file in the same folder as OpenCodeLab-App.ps1 (C:\LabSources\Scripts\ recommended).
  You can edit values here once instead of in every script.
#>

# Lab identity
$LabName     = 'OpenCodeLab'
$LabVMs      = @('DC1','WS1','LIN1')
$DomainName  = 'opencode.lab'

# Lab paths
$LabPath        = "C:\AutomatedLab\$LabName"
$LabSourcesRoot = 'C:\LabSources'
$ScriptsRoot    = Join-Path $LabSourcesRoot 'Scripts'

# Linux VM defaults (LIN1)
$LinuxUser   = 'install'
$LinuxHome   = "/home/$LinuxUser"
$LinuxProjectsRoot = "$LinuxHome/projects"
$LinuxLabShareMount = "/mnt/labshare"

# Windows paths
$SSHKeyDir     = Join-Path $LabSourcesRoot 'SSHKeys'
$SSHPrivateKey = Join-Path $SSHKeyDir 'id_ed25519'
$SSHPublicKey  = "$SSHPrivateKey.pub"
$SSHKey        = $SSHPrivateKey

# Networking: dedicated Internal vSwitch + host NAT
$LabSwitch    = 'OpenCodeLabSwitch'
$AddressSpace = '192.168.11.0/24'
$GatewayIp    = '192.168.11.1'
$NatName      = "${LabSwitch}NAT"

# Static IP plan
$DC1_Ip  = '192.168.11.3'
$WS1_Ip  = '192.168.11.4'
$LIN1_Ip = '192.168.11.5'
$DnsIp   = $DC1_Ip

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

# Optional: Git identity (leave blank to prompt when needed)
$GitName  = ''
$GitEmail = ''

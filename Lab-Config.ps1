# Lab-Config.ps1 -- Central config for AutomatedLab deployment
# Config for 4-VM lab: dc1 (DC), svr1 (Member), dsc (DSC Pull), ws1 (Client)

# Lab identity
$LabName     = 'AutomatedLab'
$LabVMs      = @('dc1','svr1','dsc','ws1')
$DomainName  = 'simplelab.local'

# Lab paths
$LabPath        = "C:\AutomatedLab\$LabName"
$LabSourcesRoot = 'C:\LabSources'
$ScriptsRoot    = Join-Path $LabSourcesRoot 'Scripts'

# Networking: dedicated Internal vSwitch + host NAT
$LabSwitch    = 'AutomatedLab'
$AddressSpace = '10.0.10.0/24'
$GatewayIp    = '10.0.10.1'
$NatName      = "${LabSwitch}NAT"

# Static IP plan
$dc1_Ip   = '10.0.10.10'   # Domain Controller
$svr1_Ip  = '10.0.10.20'   # Member Server
$ws1_Ip   = '10.0.10.30'   # Windows 11 Client
$dsc_Ip   = '10.0.10.40'   # DSC Pull Server
$DnsIp    = $dc1_Ip

# Legacy aliases (for backward compatibility)
$DC1_Ip     = $dc1_Ip
$Server1_Ip = $svr1_Ip
$Win11_Ip   = $ws1_Ip

# VM sizing
$DC_Memory      = 4GB
$DC_MinMemory   = 2GB
$DC_MaxMemory   = 6GB
$DC_Processors  = 4

$Server_Memory      = 4GB
$Server_MinMemory   = 2GB
$Server_MaxMemory   = 6GB
$Server_Processors  = 4

$Client_Memory      = 4GB
$Client_MinMemory   = 2GB
$Client_MaxMemory   = 6GB
$Client_Processors  = 4

$DSC_Memory     = 4GB
$DSC_MinMemory  = 2GB
$DSC_MaxMemory  = 6GB
$DSC_Processors = 4

# Credentials
$LabInstallUser = 'Administrator'
$AdminPassword  = 'SimpleLab123!'

# Required ISOs
$RequiredISOs = @('server2019.iso', 'windows11.iso')

# AutomatedLab timeout overrides (minutes)
# Defaults are too short for resource-constrained hosts
$AL_Timeout_DcRestart   = 90    # default 60
$AL_Timeout_AdwsReady   = 120   # default 20
$AL_Timeout_StartVM     = 90    # default 60
$AL_Timeout_WaitVM      = 90    # default 60

# ── Linux VM Static IPs ──
$lin1_Ip  = '10.0.10.110'   # Ubuntu Linux 1
$LIN1_Ip  = $lin1_Ip         # Legacy alias

# ── Ubuntu VM Sizing ──
$UBU_Memory     = 2GB
$UBU_MinMemory  = 1GB
$UBU_MaxMemory  = 4GB
$UBU_Processors = 2

# ── DHCP Scope (used by DC1 for Linux DHCP leases) ──
$DhcpScopeId = '10.0.10.0'
$DhcpStart   = '10.0.10.100'
$DhcpEnd     = '10.0.10.200'
$DhcpMask    = '255.255.255.0'

# ── SSH / Linux Identity ──
$SSHKeyDir     = Join-Path $LabSourcesRoot 'SSHKeys'
$SSHPublicKey  = Join-Path $SSHKeyDir 'id_ed25519.pub'
$SSHPrivateKey = Join-Path $SSHKeyDir 'id_ed25519'
$LinuxUser     = 'labadmin'

# ── Share paths (DC1) ──
$ShareName = 'LabShare'
$SharePath = 'C:\LabShare'
$GitRepoPath = 'C:\LabShare\GitRepo'

# ── Linux Mount/Project paths ──
$LinuxLabShareMount = '/mnt/labshare'
$LinuxProjectsRoot  = '/home/labadmin/projects'

# ── Linux-specific timeouts ──
$LIN1_WaitMinutes   = 30    # Max wait for Ubuntu SSH reachability
$SSH_ConnectTimeout  = 8     # SSH connect timeout in seconds
$SSH_PollInitialSec  = 10    # Initial polling interval for SSH wait
$SSH_PollMaxSec      = 30    # Max polling interval (backoff ceiling)

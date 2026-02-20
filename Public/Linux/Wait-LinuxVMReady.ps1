# Wait-LinuxVMReady.ps1 -- Wait for Linux VM SSH readiness
function Wait-LinuxVMReady {
    <#
    .SYNOPSIS
    Wait for a Linux VM to become reachable via SSH after boot or installation.

    .DESCRIPTION
    Polls the VM's IP address via Hyper-V guest services (Get-LinuxVMIPv4) and
    tests TCP port 22 until it succeeds or the deadline is exceeded.  When no
    Hyper-V IP is visible yet, falls back to querying the DHCP server lease for
    an early signal that the VM is on the network.  Poll interval starts at
    PollInitialSec seconds and grows by 50% each tick up to PollMaxSec to reduce
    overhead during long installations.  Returns a hashtable with keys Ready
    (bool), IP (string), and LeaseIP (string).

    .PARAMETER VMName
    Name of the Hyper-V VM to monitor (default: LIN1).

    .PARAMETER WaitMinutes
    Maximum number of minutes to wait before returning a not-ready result
    (default: 30).

    .PARAMETER DhcpServer
    Hostname or IP of the DHCP server used for lease fallback lookups
    (default: DC1).

    .PARAMETER ScopeId
    DHCP scope ID used for lease lookups (default: 10.0.10.0).

    .PARAMETER PollInitialSec
    Initial poll interval in seconds (default: 15).

    .PARAMETER PollMaxSec
    Maximum poll interval cap in seconds (default: 45).

    .EXAMPLE
    $result = Wait-LinuxVMReady -VMName 'LIN1'
    if ($result.Ready) { Write-Host "LIN1 is up at $($result.IP)" }

    .EXAMPLE
    # Use after starting a freshly installed VM
    Start-VM -Name 'LIN1'
    $result = Wait-LinuxVMReady -VMName 'LIN1' -WaitMinutes 45
    if (-not $result.Ready) { throw 'LIN1 did not come up in time.' }

    .EXAMPLE
    # Custom DHCP scope for non-default lab network
    $result = Wait-LinuxVMReady -VMName 'LIN2' -DhcpServer 'DC1' -ScopeId '192.168.10.0' -WaitMinutes 20
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$VMName = 'LIN1',
        [int]$WaitMinutes = 30,
        [string]$DhcpServer = 'DC1',
        [string]$ScopeId = '10.0.10.0',
        [int]$PollInitialSec = 15,
        [int]$PollMaxSec = 45
    )

    $deadline = [datetime]::Now.AddMinutes($WaitMinutes)
    $lastKnownIp = ''
    $lastLeaseIp = ''
    $waitTick = 0

    $pollInterval = [math]::Max(1, $PollInitialSec)
    $pollCap = [math]::Max(1, $PollMaxSec)
    if ($pollInterval -gt $pollCap) {
        $pollInterval = $pollCap
    }

    while ([datetime]::Now -lt $deadline) {
        $waitTick++

        $vmIp = Get-LinuxVMIPv4 -VMName $VMName
        if ($vmIp) {
            $lastKnownIp = $vmIp
            $sshCheck = Test-NetConnection -ComputerName $vmIp -Port 22 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            if ($sshCheck.TcpTestSucceeded) {
                Write-LabStatus -Status OK -Message "$VMName SSH is reachable at $vmIp"
                return @{ Ready = $true; IP = $vmIp; LeaseIP = $lastLeaseIp }
            }
        }

        if (-not $lastKnownIp) {
            $leaseIp = Get-LinuxVMDhcpLeaseIPv4 -VMName $VMName -DhcpServer $DhcpServer -ScopeId $ScopeId
            if ($leaseIp) {
                $lastLeaseIp = $leaseIp
            }
        }

        if ($lastKnownIp) {
            Write-Host "    $VMName has IP ($lastKnownIp), waiting for SSH..." -ForegroundColor Gray
        }
        elseif ($lastLeaseIp) {
            Write-Host "    DHCP lease seen for $VMName ($lastLeaseIp), waiting for Hyper-V guest IP + SSH..." -ForegroundColor Gray
        }
        else {
            Write-Host "    Still waiting for $VMName DHCP lease..." -ForegroundColor Gray
        }

        if (($waitTick % 6) -eq 0) {
            $vmState = (Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue).State
            Write-Host "    $VMName VM state: $vmState" -ForegroundColor DarkGray
        }

        Start-Sleep -Seconds $pollInterval
        $pollInterval = [math]::Min([int][math]::Ceiling($pollInterval * 1.5), $pollCap)
    }

    Write-LabStatus -Status WARN -Message "$VMName did not become SSH-reachable after $WaitMinutes min."
    if ($lastLeaseIp) {
        Write-LabStatus -Status INFO -Message "$VMName DHCP lease observed at: $lastLeaseIp"
    }

    return @{ Ready = $false; IP = $lastKnownIp; LeaseIP = $lastLeaseIp }
}

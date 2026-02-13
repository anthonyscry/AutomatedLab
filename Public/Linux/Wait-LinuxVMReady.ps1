# Wait-LinuxVMReady.ps1 -- Wait for Linux VM SSH readiness
function Wait-LinuxVMReady {
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

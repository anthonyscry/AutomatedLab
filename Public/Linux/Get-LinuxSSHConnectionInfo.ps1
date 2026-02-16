# Get-LinuxSSHConnectionInfo.ps1 -- Build SSH connection details for Linux VM
function Get-LinuxSSHConnectionInfo {
    <#
    .SYNOPSIS
    Returns SSH connection details for a Linux VM.
    .DESCRIPTION
    Resolves the VM's IP address and constructs an SSH command string.
    Returns $null if the VM is not reachable.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$VMName = 'LIN1',
        [string]$User = $(if ($LinuxUser) { $LinuxUser } else { 'labadmin' }),
        [string]$KeyPath = $(if ($SSHPrivateKey) { $SSHPrivateKey } else { 'C:\LabSources\SSHKeys\id_ed25519' })
    )

    $ip = Get-LinuxVMIPv4 -VMName $VMName
    if (-not $ip) { return $null }

    $sshCmd = "ssh -o StrictHostKeyChecking=accept-new -i `"$KeyPath`" $User@$ip"

    return @{
        VMName  = $VMName
        IP      = $ip
        User    = $User
        KeyPath = $KeyPath
        Command = $sshCmd
    }
}

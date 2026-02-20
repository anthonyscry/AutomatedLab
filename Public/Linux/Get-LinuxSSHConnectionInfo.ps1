# Get-LinuxSSHConnectionInfo.ps1 -- Build SSH connection details for Linux VM
function Get-LinuxSSHConnectionInfo {
    <#
    .SYNOPSIS
        Returns SSH connection details for a Linux VM.

    .DESCRIPTION
        Resolves the VM's current IPv4 address via the Hyper-V network adapter and
        constructs a ready-to-use SSH command string. Returns $null if the VM has no
        reachable IP address.

        The returned hashtable includes the VM name, IP address, username, key path,
        and the full SSH command string.

    .PARAMETER VMName
        Name of the Hyper-V virtual machine. Defaults to 'LIN1'.

    .PARAMETER User
        SSH username to connect as. Defaults to the value of $LinuxUser if set,
        otherwise 'labadmin'.

    .PARAMETER KeyPath
        Path to the SSH private key file. Defaults to the value of $SSHPrivateKey
        if set, otherwise 'C:\LabSources\SSHKeys\id_ed25519'.

    .EXAMPLE
        Get-LinuxSSHConnectionInfo

        Returns connection details for the default LIN1 VM using the lab SSH key.

    .EXAMPLE
        $info = Get-LinuxSSHConnectionInfo -VMName 'LIN2' -User 'ubuntu'
        Invoke-Expression $info.Command

        Retrieves connection info for LIN2 and opens an interactive SSH session.
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

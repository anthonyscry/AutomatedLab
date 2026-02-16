# Invoke-LinuxSSH.ps1 -- Execute command on Linux over SSH
function Invoke-LinuxSSH {
    <#
    .SYNOPSIS
    Execute a command on a Linux VM via SSH.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$IP,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Command,
        [string]$User = $LinuxUser,
        [string]$KeyPath = $SSHPrivateKey,
        [int]$ConnectTimeout = $(if ($SSH_ConnectTimeout) { $SSH_ConnectTimeout } else { 10 }),
        [switch]$PassThru
    )

    $sshExe = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
    if (-not (Test-Path $sshExe)) {
        throw "OpenSSH client not found at $sshExe. Install Windows optional feature: OpenSSH Client."
    }

    $sshArgs = @(
        '-o', 'StrictHostKeyChecking=accept-new',
        '-o', 'UserKnownHostsFile=NUL',
        '-o', "ConnectTimeout=$ConnectTimeout",
        '-i', $KeyPath,
        "$User@$IP",
        $Command
    )

    if ($PassThru) {
        return (& $sshExe @sshArgs 2>&1)
    }
    else {
        & $sshExe @sshArgs 2>&1 | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "SSH command exited with code $LASTEXITCODE"
        }
    }
}

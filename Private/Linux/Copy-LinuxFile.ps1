# Copy-LinuxFile.ps1 -- Copy local file to Linux VM over SCP
function Copy-LinuxFile {
    <#
    .SYNOPSIS
    Copy a file to a Linux VM via SCP.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$IP,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$LocalPath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$RemotePath,
        [string]$User = $LinuxUser,
        [string]$KeyPath = $SSHPrivateKey
    )

    $scpExe = Join-Path $env:WINDIR 'System32\OpenSSH\scp.exe'
    if (-not (Test-Path $scpExe)) {
        throw "OpenSSH scp not found at $scpExe."
    }

    # Ensure known_hosts directory exists
    $knownHostsDir = Split-Path -Parent $GlobalLabConfig.SSH.KnownHostsPath
    if (-not (Test-Path $knownHostsDir)) {
        $null = New-Item -ItemType Directory -Path $knownHostsDir -Force
        Write-Verbose "Created directory: $knownHostsDir"
    }

    & $scpExe -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$($GlobalLabConfig.SSH.KnownHostsPath)" -i $KeyPath $LocalPath "${User}@${IP}:${RemotePath}" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "SCP failed with exit code $LASTEXITCODE copying '$LocalPath' to '${User}@${IP}:${RemotePath}'"
    }
}

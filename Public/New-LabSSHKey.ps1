function New-LabSSHKey {
    <#
    .SYNOPSIS
        Generates SSH key pair for lab Linux VMs.

    .DESCRIPTION
        Generates an ed25519 SSH key pair using Windows OpenSSH ssh-keygen.exe.
        Keys are saved to the configured SSHKeyDir.

    .EXAMPLE
        New-LabSSHKey

    .EXAMPLE
        New-LabSSHKey -Comment "lab-opencode"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$Comment = "lab-ssh",

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [switch]$Force
    )

    $sshKeyDir = if ($OutputPath) {
        $OutputPath
    } elseif ((Test-Path variable:GlobalLabConfig) -and $GlobalLabConfig.Linux.SSHKeyDir) {
        $GlobalLabConfig.Linux.SSHKeyDir
    } else {
        Write-Warning "No SSH key directory configured. Set `$GlobalLabConfig.Linux.SSHKeyDir in Lab-Config.ps1. Falling back to C:\LabSources\SSHKeys."
        'C:\LabSources\SSHKeys'
    }

    $privateKey = Join-Path $sshKeyDir 'id_ed25519'
    $publicKey = "$privateKey.pub"

    # Check if keys already exist
    if ((Test-Path $privateKey) -and (Test-Path $publicKey) -and -not $Force) {
        return [PSCustomObject]@{
            OverallStatus = 'Exists'
            PrivateKeyPath = $privateKey
            PublicKeyPath = $publicKey
            Message = "SSH key pair already exists. Use -Force to regenerate."
        }
    }

    # Ensure directory exists
    if (-not (Test-Path $sshKeyDir)) {
        New-Item -ItemType Directory -Force -Path $sshKeyDir | Out-Null
    }

    # Find ssh-keygen.exe
    $sshExe = Join-Path $env:WINDIR "System32\OpenSSH\ssh-keygen.exe"
    if (-not (Test-Path $sshExe)) {
        return [PSCustomObject]@{
            OverallStatus = 'Failed'
            PrivateKeyPath = $null
            PublicKeyPath = $null
            Message = "OpenSSH ssh-keygen not found at $sshExe. Install Windows optional feature: OpenSSH Client."
        }
    }

    # Generate key pair using cmd.exe to avoid PowerShell quoting issues
    $cmd = '"' + $sshExe + '" -t ed25519 -f "' + $privateKey + '" -N ""'
    if ($Comment -and $Comment.Trim().Length -gt 0) {
        $cmd += ' -C "' + $Comment.Replace('"','\"') + '"'
    }

    & $env:ComSpec /c $cmd 2>&1 | Out-Null

    if ($LASTEXITCODE -ne 0) {
        return [PSCustomObject]@{
            OverallStatus = 'Failed'
            PrivateKeyPath = $null
            PublicKeyPath = $null
            Message = "ssh-keygen failed with exit code $LASTEXITCODE"
        }
    }

    # Verify files were created
    if (-not (Test-Path $privateKey) -or -not (Test-Path $publicKey)) {
        return [PSCustomObject]@{
            OverallStatus = 'Failed'
            PrivateKeyPath = $null
            PublicKeyPath = $null
            Message = "ssh-keygen reported success but key files were not found"
        }
    }

    # Read public key content
    $publicKeyContent = Get-Content $publicKey -Raw

    return [PSCustomObject]@{
        OverallStatus = 'OK'
        PrivateKeyPath = $privateKey
        PublicKeyPath = $publicKey
        PublicKeyContent = $publicKeyContent.Trim()
        Message = "SSH key pair generated successfully"
    }
}

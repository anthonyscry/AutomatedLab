# Ensure-SSHKey.ps1 -- Validate SSH private key presence
function Ensure-SSHKey {
    param([string]$KeyPath)
    if (-not (Test-Path $KeyPath)) {
        throw "SSH key not found: $KeyPath`nGenerate it with: C:\Windows\System32\OpenSSH\ssh-keygen.exe -t ed25519 -f `"$KeyPath`" -N `"`""
    }
}

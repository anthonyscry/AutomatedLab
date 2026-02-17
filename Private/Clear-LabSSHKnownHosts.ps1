function Clear-LabSSHKnownHosts {
    <#
    .SYNOPSIS
        Removes the lab-specific SSH known_hosts file.
    .DESCRIPTION
        Called during teardown to clear stale host keys so redeploy
        can accept fresh keys without host key mismatch errors.
    #>
    [CmdletBinding()]
    param()

    $knownHostsPath = $GlobalLabConfig.SSH.KnownHostsPath
    if ([string]::IsNullOrWhiteSpace($knownHostsPath)) {
        Write-Warning '[Clear-LabSSHKnownHosts] SSH.KnownHostsPath not configured.'
        return
    }

    if (Test-Path $knownHostsPath) {
        Remove-Item -Path $knownHostsPath -Force
        Write-Host "  [OK] Cleared lab SSH known_hosts: $knownHostsPath" -ForegroundColor Green
    } else {
        Write-Verbose "Lab SSH known_hosts not found (already clean): $knownHostsPath"
    }
}

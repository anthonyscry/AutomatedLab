function Invoke-LabLogRetention {
    [CmdletBinding()]
    param(
        [int]$RetentionDays = 14,
        [string]$LogRoot
    )

    if ($RetentionDays -lt 1) { return }
    if ([string]::IsNullOrWhiteSpace($LogRoot)) { return }
    if (-not (Test-Path $LogRoot)) { return }

    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    Get-ChildItem -Path $LogRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Invoke-LabLogRetention {
    [CmdletBinding()]
    param(
        [int]$RetentionDays = 14,
        [string]$LogRoot
    )

    try {
        if ($RetentionDays -lt 1) { return }
        if ([string]::IsNullOrWhiteSpace($LogRoot)) { return }
        if (-not (Test-Path $LogRoot)) { return }

        $cutoff = (Get-Date).AddDays(-$RetentionDays)
        Get-ChildItem -Path $LogRoot -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
    catch {
        $PSCmdlet.WriteError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Invoke-LabLogRetention: log retention cleanup failed for '$LogRoot' - $_", $_.Exception),
                'Invoke-LabLogRetention.Failure',
                [System.Management.Automation.ErrorCategory]::NotSpecified,
                $null
            )
        )
    }
}

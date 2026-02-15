function Test-LabTransientTransportFailure {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Message
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $false
    }

    $normalizedMessage = $Message.Trim()

    if ($normalizedMessage -match '(?i)(access\s+is\s+denied|scoped\s+confirmation|execution\s+policy|run_scope_mismatch|host_scope_mismatch|operation_scope_mismatch)') {
        return $false
    }

    return ($normalizedMessage -match '(?i)(winrm|wsman|timed?\s*out|timeout|cannot\s+connect\s+to\s+the\s+destination|destination\s+is\s+not\s+reachable|temporar(?:y|ily)\s+unavailable)')
}

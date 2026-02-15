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

    if ($normalizedMessage -match '(?i)(access\s+is\s+denied|scoped\s+confirmation\s+(?:failed|failure|token\s+validation\s+failed)|declined\s+scoped\s+confirmation|scoped\s+confirmation\s+token\s+prompt\s+declined|execution\s+policy|run_scope_mismatch|host_scope_mismatch|operation_scope_mismatch|authentication\s+failed|authorization\s+failed|rejected\s+the\s+credentials|invalid\s+credentials|unauthoriz(?:ed|ation)|logon\s+failure|kerberos\s+authentication)') {
        return $false
    }

    return ($normalizedMessage -match '(?i)(winrm|wsman|timed?\s*out|timeout|cannot\s+connect\s+to\s+the\s+destination|destination\s+is\s+not\s+reachable|temporar(?:y|ily)\s+unavailable)')
}

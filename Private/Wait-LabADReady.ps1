function Wait-LabADReady {
    <#
    .SYNOPSIS
        Waits for Active Directory Web Services (ADWS) to become ready after DC promotion.

    .DESCRIPTION
        Gates ADMX/GPO operations on ADWS readiness by polling Get-ADDomain until success
        or timeout. This eliminates the race condition where DC promotion returns before
        ADWS is fully responsive.

    .PARAMETER DomainName
        The Active Directory domain name to query (e.g., 'simplelab.local').

    .PARAMETER TimeoutSeconds
        Maximum seconds to wait for ADWS readiness. Default is 120 seconds.

    .PARAMETER RetryIntervalSeconds
        Seconds between Get-ADDomain retry attempts. Default is 10 seconds.

    .OUTPUTS
        PSCustomObject with Ready (bool), DomainName (string), WaitSeconds (int) fields.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$DomainName,

        [int]$TimeoutSeconds = 120,

        [int]$RetryIntervalSeconds = 10
    )

    $startTime = Get-Date
    $elapsed = 0
    $ready = $false

    while (-not $ready -and $elapsed -lt $TimeoutSeconds) {
        try {
            # Get-ADDomain validates full ADWS functionality
            $domain = Get-ADDomain -Identity $DomainName -ErrorAction Stop
            $ready = $true
            Write-Verbose "[Wait-LabADReady] ADWS is ready for domain '$DomainName'"
        }
        catch {
            Write-Verbose "[Wait-LabADReady] ADWS not ready yet: $($_.Exception.Message)"
            Start-Sleep -Seconds $RetryIntervalSeconds
        }
        $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
    }

    return [pscustomobject]@{
        Ready      = $ready
        DomainName = $DomainName
        WaitSeconds = $elapsed
    }
}

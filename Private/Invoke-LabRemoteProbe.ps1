function Invoke-LabRemoteProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HostName,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [object[]]$ArgumentList = @()
    )

    $localHostNames = @(
        'localhost',
        '.',
        [Environment]::MachineName,
        $env:COMPUTERNAME
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if ($localHostNames -contains $HostName) {
        try {
            return & $ScriptBlock @ArgumentList
        }
        catch {
            throw "Local probe failed for host '$HostName': $($_.Exception.Message)"
        }
    }

    try {
        return Invoke-Command -ComputerName $HostName -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
    }
    catch {
        throw "Remote probe failed for host '$HostName': $($_.Exception.Message)"
    }
}

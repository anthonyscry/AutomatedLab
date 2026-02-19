Set-StrictMode -Version Latest

function Write-LabEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject]$ArtifactSet,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [psobject]$Event
    )

    $eventsFilePath = [string]$ArtifactSet.EventsFilePath
    if ([string]::IsNullOrWhiteSpace($eventsFilePath)) {
        throw 'ArtifactSet.EventsFilePath is required'
    }

    $payload = [ordered]@{
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    }

    if ($Event -is [System.Collections.IDictionary]) {
        foreach ($key in $Event.Keys) {
            $payload[[string]$key] = $Event[$key]
        }
    }
    else {
        foreach ($property in $Event.PSObject.Properties) {
            $payload[$property.Name] = $property.Value
        }
    }

    $line = $payload | ConvertTo-Json -Compress -Depth 10
    Add-Content -Path $eventsFilePath -Value $line -Encoding utf8

    return [pscustomobject]$payload
}

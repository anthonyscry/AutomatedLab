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

    $eventsFileProperty = $ArtifactSet.PSObject.Properties['EventsFilePath']
    if ($null -eq $eventsFileProperty) {
        throw 'ArtifactSet.EventsFilePath is required'
    }

    $eventsFilePath = [string]$eventsFileProperty.Value
    if ([string]::IsNullOrWhiteSpace($eventsFilePath)) {
        throw 'ArtifactSet.EventsFilePath is required'
    }

    $payload = [ordered]@{
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    }

    $eventBaseObject = $Event.PSObject.BaseObject

    if ($eventBaseObject -is [System.Collections.IDictionary]) {
        foreach ($key in $eventBaseObject.Keys) {
            if ([string]::Equals([string]$key, 'timestamp', [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $payload[[string]$key] = $eventBaseObject[$key]
        }
    }
    elseif ($eventBaseObject -is [pscustomobject]) {
        foreach ($property in $Event.PSObject.Properties) {
            if ([string]::Equals($property.Name, 'timestamp', [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $payload[$property.Name] = $property.Value
        }
    }
    else {
        throw 'Event must be a dictionary or object with named properties'
    }

    $line = $payload | ConvertTo-Json -Compress -Depth 10
    Add-Content -Path $eventsFilePath -Value $line -Encoding utf8

    return [pscustomobject]$payload
}

function Write-DeployEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Type,

        [Parameter(Mandatory)]
        [string]$Status,

        [string]$Message,

        [hashtable]$Properties
    )

    if (-not $script:DeployEventsPath) { return }

    $payload = [ordered]@{
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
        type      = $Type
        status    = $Status
    }
    if ($Message) { $payload['message'] = $Message }
    if ($Properties) {
        foreach ($key in $Properties.Keys) {
            $payload[$key] = $Properties[$key]
        }
    }

    $line = $payload | ConvertTo-Json -Compress -Depth 5
    Add-Content -Path $script:DeployEventsPath -Value $line -Encoding utf8
}

function Write-DeployProgress {
    param([int]$Percent, [string]$Status, [string]$Activity = 'Lab Deployment')
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $Percent
    Write-Host "[$Percent%] $Status" -ForegroundColor Cyan
}

function Read-LabMenuCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [int]$DefaultValue = 0
    )

    $inputValue = (Read-Host ("  {0} [{1}]" -f $Prompt, $DefaultValue)).Trim()
    if ([string]::IsNullOrWhiteSpace($inputValue)) {
        return $DefaultValue
    }

    $count = 0
    if ([int]::TryParse($inputValue, [ref]$count) -and $count -ge 0) {
        return $count
    }

    Write-Host '  Invalid value; using default.' -ForegroundColor Yellow
    return $DefaultValue
}

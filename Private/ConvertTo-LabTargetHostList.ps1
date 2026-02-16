function ConvertTo-LabTargetHostList {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string[]]$InputHosts
    )

    begin { $collected = [System.Collections.Generic.List[string]]::new() }

    process {
        foreach ($entry in $InputHosts) {
            if (-not [string]::IsNullOrWhiteSpace($entry)) {
                foreach ($segment in ($entry -split '[,;\s]+')) {
                    $trimmed = $segment.Trim()
                    if ($trimmed.Length -gt 0) {
                        if ($trimmed -notmatch '^[a-zA-Z0-9]([a-zA-Z0-9\-\.]{0,253}[a-zA-Z0-9])?$') {
                            Write-Warning "[ConvertTo-LabTargetHostList] Skipping invalid hostname: '$trimmed'"
                            continue
                        }
                        $collected.Add($trimmed)
                    }
                }
            }
        }
    }

    end { return @($collected) }
}

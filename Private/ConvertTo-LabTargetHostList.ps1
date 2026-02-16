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
                        $collected.Add($trimmed)
                    }
                }
            }
        }
    }

    end { return @($collected) }
}

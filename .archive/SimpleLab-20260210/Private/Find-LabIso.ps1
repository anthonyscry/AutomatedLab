function Find-LabIso {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$IsoName,

        [Parameter(Mandatory)]
        [string[]]$SearchPaths,

        [Parameter()]
        [string]$Pattern = "*.iso"
    )

    try {
        # Initialize result object
        $searchedPaths = [System.Collections.Generic.List[string]]::new()
        $foundPath = $null

        # Iterate through each search path
        foreach ($searchPath in $SearchPaths) {
            # Track this path as searched
            $searchedPaths.Add($searchPath)

            # Check if directory exists, skip if not
            if (-not (Test-Path -Path $searchPath -PathType Container)) {
                continue
            }

            try {
                # Search for ISO files with pattern (max depth 2 for performance)
                $foundFiles = Get-ChildItem -Path $searchPath -Filter $Pattern -Recurse -Depth 2 -ErrorAction Stop |
                    Where-Object { -not $_.PSIsContainer } |
                    Select-Object -First 1

                if ($foundFiles) {
                    $foundPath = $foundFiles.FullName
                    break  # Stop searching after first match
                }
            }
            catch {
                # Silently skip inaccessible directories (permission errors, etc.)
                continue
            }
        }

        # Build result object
        $result = [PSCustomObject]@{
            Name = $IsoName
            FoundPath = $foundPath
            SearchedPaths = $searchedPaths.ToArray()
            Found = ($null -ne $foundPath)
        }

        return $result
    }
    catch {
        Write-Error "Failed to search for ISO '$IsoName': $($_.Exception.Message)"
        return [PSCustomObject]@{
            Name = $IsoName
            FoundPath = $null
            SearchedPaths = $SearchPaths
            Found = $false
        }
    }
}

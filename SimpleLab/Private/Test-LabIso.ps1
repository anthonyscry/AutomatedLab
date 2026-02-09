function Test-LabIso {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$IsoName,

        [Parameter(Mandatory)]
        [string]$IsoPath
    )

    try {
        # Initialize result object
        $result = [PSCustomObject]@{
            Name = $IsoName
            Path = $IsoPath
            Exists = $false
            IsValidIso = $false
            Status = "Fail"
        }

        # Check if file exists (Test-Path with -PathType Leaf ensures it's a file, not a directory)
        $fileExists = Test-Path -Path $IsoPath -PathType Leaf

        if ($fileExists) {
            $result.Exists = $true

            # Validate .iso extension using regex
            if ($IsoPath -match '\.iso$') {
                $result.IsValidIso = $true
                $result.Status = "Pass"
            }
            else {
                $result.IsValidIso = $false
                $result.Status = "Warning"
            }
        }

        return $result
    }
    catch {
        Write-Error "Failed to validate ISO '$IsoName' at path '$IsoPath': $($_.Exception.Message)"
        return [PSCustomObject]@{
            Name = $IsoName
            Path = $IsoPath
            Exists = $false
            IsValidIso = $false
            Status = "Error"
        }
    }
}

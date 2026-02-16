function Test-LabIso {
    <#
    .SYNOPSIS
        Validates that an ISO file exists and has the correct extension.

    .DESCRIPTION
        Checks whether the specified ISO file exists at the given path and
        verifies it has a .iso extension. Returns a status object indicating
        Pass, Warning (exists but wrong extension), Fail, or Error.

    .PARAMETER IsoName
        Friendly name for the ISO (e.g., "Server2019", "Windows11") used in reporting.

    .PARAMETER IsoPath
        Full path to the ISO file to validate.

    .OUTPUTS
        PSCustomObject with Name, Path, Exists, IsValidIso, and Status properties.

    .EXAMPLE
        Test-LabIso -IsoName "Server2019" -IsoPath "C:\ISOs\server2019.iso"

    .EXAMPLE
        Get-LabConfig | ForEach-Object { Test-LabIso -IsoName $_.Name -IsoPath $_.Path }
    #>
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

Set-StrictMode -Version Latest

function Test-LabCustomRoleSchema {
    <#
    .SYNOPSIS
        Validates the schema of a custom lab role hashtable.
    .DESCRIPTION
        Checks that all required fields are present and valid in a custom role hashtable
        loaded from a JSON file. Returns a result object with Valid flag and error list.
    .PARAMETER RoleData
        The hashtable representing the parsed custom role JSON.
    .PARAMETER FilePath
        The file path of the JSON role file (used in error messages).
    .OUTPUTS
        [pscustomobject] with Valid ([bool]) and Errors ([string[]]) properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$RoleData,

        [Parameter(Mandatory)]
        [string]$FilePath
    )

    $errors = [System.Collections.Generic.List[string]]::new()

    # Required top-level string fields
    $requiredStringFields = @('name', 'tag', 'description', 'os')
    foreach ($field in $requiredStringFields) {
        if (-not $RoleData.ContainsKey($field) -or [string]::IsNullOrWhiteSpace($RoleData[$field])) {
            $errors.Add("Custom role '$FilePath': missing required field '$field'")
        }
    }

    # Validate tag format (alphanumeric, hyphen, underscore only — no spaces or special chars)
    if ($RoleData.ContainsKey('tag') -and -not [string]::IsNullOrWhiteSpace($RoleData['tag'])) {
        if ($RoleData['tag'] -notmatch '^[A-Za-z0-9_-]+$') {
            $errors.Add("Custom role '$FilePath': field 'tag' must be alphanumeric (hyphens and underscores allowed, no spaces or special characters). Got: '$($RoleData['tag'])'")
        }
    }

    # Validate os value
    if ($RoleData.ContainsKey('os') -and -not [string]::IsNullOrWhiteSpace($RoleData['os'])) {
        $validOS = @('windows', 'linux')
        if ($RoleData['os'] -notin $validOS) {
            $errors.Add("Custom role '$FilePath': field 'os' must be 'windows' or 'linux'. Got: '$($RoleData['os'])'")
        }
    }

    # Validate provisioningSteps
    if (-not $RoleData.ContainsKey('provisioningSteps') -or $null -eq $RoleData['provisioningSteps']) {
        $errors.Add("Custom role '$FilePath': missing required field 'provisioningSteps'")
    }
    else {
        $steps = $RoleData['provisioningSteps']
        $stepsArray = @($steps)
        if ($stepsArray.Count -eq 0) {
            $errors.Add("Custom role '$FilePath': field 'provisioningSteps' must be a non-empty array")
        }
        else {
            $validStepTypes = @('windowsFeature', 'powershellScript', 'linuxCommand')
            $stepIndex = 0
            foreach ($step in $stepsArray) {
                $stepRef = "step[$stepIndex]"

                # Convert PSCustomObject to hashtable if needed
                if ($step -is [System.Management.Automation.PSCustomObject]) {
                    $stepHt = @{}
                    foreach ($prop in $step.PSObject.Properties) {
                        $stepHt[$prop.Name] = $prop.Value
                    }
                    $step = $stepHt
                }

                $stepIsHashtable = $step -is [hashtable]

                # Check step required fields
                foreach ($stepField in @('name', 'type', 'value')) {
                    $hasField = if ($stepIsHashtable) { $step.ContainsKey($stepField) } else { $false }
                    $fieldValue = if ($hasField) { $step[$stepField] } else { $null }
                    if (-not $hasField -or [string]::IsNullOrWhiteSpace($fieldValue)) {
                        $errors.Add("Custom role '$FilePath': $stepRef missing required field '$stepField'")
                    }
                }

                # Validate step type
                if ($stepIsHashtable -and $step.ContainsKey('type') -and -not [string]::IsNullOrWhiteSpace($step['type'])) {
                    if ($step['type'] -notin $validStepTypes) {
                        $errors.Add("Custom role '$FilePath': $stepRef field 'type' must be one of: $($validStepTypes -join ', '). Got: '$($step['type'])'")
                    }
                }

                $stepIndex++
            }
        }
    }

    return [pscustomobject]@{
        Valid  = ($errors.Count -eq 0)
        Errors = $errors.ToArray()
    }
}

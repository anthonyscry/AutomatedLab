Set-StrictMode -Version Latest

$script:ComplianceControlMapCache = $null
$script:ComplianceHelperRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

function Get-ComplianceControlMap {
    if ($null -ne $script:ComplianceControlMapCache) {
        return $script:ComplianceControlMapCache
    }

    $mapPath = Join-Path $script:ComplianceHelperRoot 'Compliance\ControlMap.psd1'
    if (-not (Test-Path $mapPath)) {
        throw "Compliance control map not found at $mapPath"
    }

    $map = Import-PowerShellDataFile -Path $mapPath
    if (-not $map.ContainsKey('Checks')) {
        throw 'Compliance control map is missing the Checks section.'
    }

    $script:ComplianceControlMapCache = $map
    return $script:ComplianceControlMapCache
}

function Resolve-ComplianceMappings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CheckId
    )

    $map = Get-ComplianceControlMap
    $checks = $map.Checks
    if (-not $checks.ContainsKey($CheckId)) {
        throw "Check '$CheckId' is not defined in the compliance control map."
    }

    return $checks[$CheckId].FrameworkMappings
}

function Add-ComplianceAnnotation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]$CheckId
    )

    process {
        $frameworkMappings = Resolve-ComplianceMappings -CheckId $CheckId
        $controlIds = @($frameworkMappings | ForEach-Object { $_.ControlId } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)

        $InputObject | Add-Member -MemberType NoteProperty -Name FrameworkMappings -Value $frameworkMappings -Force
        $InputObject | Add-Member -MemberType NoteProperty -Name ControlIds -Value $controlIds -Force

        $InputObject
    }
}

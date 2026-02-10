# SimpleLab.psm1
# SimpleLab Module - Streamlined Windows domain lab automation

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Dot-source private functions
$PrivateFunctions = Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue
foreach ($file in $PrivateFunctions) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error "Failed to import function $($file.BaseName): $_"
        throw
    }
}

# Dot-source public functions
$PublicFunctions = Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue
foreach ($file in $PublicFunctions) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error "Failed to import function $($file.BaseName): $_"
        throw
    }
}

# Export public functions explicitly
Export-ModuleMember -Function @(
    'Initialize-LabNetwork',
    'New-LabSwitch',
    'Test-HyperVEnabled',
    'Test-LabIso',
    'Test-LabNetwork',
    'Test-LabNetworkHealth',
    'Test-LabPrereqs',
    'Write-RunArtifact',
    'Write-ValidationReport'
)

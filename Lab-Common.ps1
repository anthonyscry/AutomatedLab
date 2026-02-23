# Lab-Common.ps1 -- Shim: loads all shared helpers from Private/ and Public/
# Standalone scripts (Deploy.ps1, Add-LIN1.ps1, etc.) dot-source this file.
# The SimpleLab module loads these directly via SimpleLab.psm1.

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

$importHelperPath = Join-Path -Path $ScriptRoot -ChildPath 'Private\Import-LabScriptTree.ps1'
if (-not (Test-Path -Path $importHelperPath -PathType Leaf)) {
    throw "Required import helper not found: $importHelperPath"
}

. $importHelperPath

$privateFiles = Get-LabScriptFiles -RootPath $ScriptRoot -RelativePaths @('Private') -ExcludeFileNames @('Import-LabScriptTree.ps1')
foreach ($file in $privateFiles) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to import private helper '$($file.FullName)': $($_.Exception.Message)"
    }
}

$publicFiles = Get-LabScriptFiles -RootPath $ScriptRoot -RelativePaths @('Public')
foreach ($file in $publicFiles) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to import public helper '$($file.FullName)': $($_.Exception.Message)"
    }
}

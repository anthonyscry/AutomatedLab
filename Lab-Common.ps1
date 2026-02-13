# Lab-Common.ps1 -- Shim: loads all shared helpers from Private/ and Public/
# Standalone scripts (Deploy.ps1, Add-LIN1.ps1, etc.) dot-source this file.
# The SimpleLab module loads these directly via SimpleLab.psm1.

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

$privateFiles = @(Get-ChildItem -Path "$ScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue | Sort-Object Name)
foreach ($file in $privateFiles) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to import private helper '$($file.BaseName)': $($_.Exception.Message)"
    }
}

$publicFiles = @(Get-ChildItem -Path "$ScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue | Sort-Object Name)
foreach ($file in $publicFiles) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to import public helper '$($file.BaseName)': $($_.Exception.Message)"
    }
}

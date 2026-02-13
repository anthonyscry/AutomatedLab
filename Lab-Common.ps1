# Lab-Common.ps1 -- Shim: loads all shared helpers from Private/ and Public/
# Standalone scripts (Deploy.ps1, Add-LIN1.ps1, etc.) dot-source this file.
# The SimpleLab module loads these directly via SimpleLab.psm1.
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
foreach ($f in (Get-ChildItem -Path "$ScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue)) { . $f.FullName }
foreach ($f in (Get-ChildItem -Path "$ScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue)) { . $f.FullName }

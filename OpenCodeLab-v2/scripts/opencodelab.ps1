[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Command
)

Set-StrictMode -Version Latest

$moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '../src/OpenCodeLab.App/OpenCodeLab.App.psd1'

Import-Module $moduleManifestPath -Force

$commandMap = Get-LabCommandMap

if (-not $commandMap.Contains($Command)) {
    throw "Unsupported command: $Command"
}

$commandMap[$Command]

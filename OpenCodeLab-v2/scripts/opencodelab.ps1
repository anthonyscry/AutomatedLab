[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('preflight', 'deploy', 'teardown', 'status', 'health', 'dashboard')]
    [string]$Command
)

$moduleManifestPath = Join-Path -Path $PSScriptRoot -ChildPath '../src/OpenCodeLab.App/OpenCodeLab.App.psd1'

Import-Module $moduleManifestPath -Force

$commandMap = Get-LabCommandMap

if (-not $commandMap.ContainsKey($Command)) {
    throw "Unsupported command: $Command"
}

$commandMap[$Command]

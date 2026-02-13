#Requires -RunAsAdministrator
<#
.SYNOPSIS
    LabBuilder v1.0.0 - Console role toggler + automated lab build.
.DESCRIPTION
    Main entry point for LabBuilder. Presents an interactive checkbox-style
    menu to select lab roles, then builds the complete Hyper-V lab using
    AutomatedLab with per-role post-install configuration.

    Supports three operations:
      Menu  — Interactive role toggler (default)
      Build — Non-interactive build with -Roles parameter
      Help  — Print usage information

.PARAMETER Operation
    The operation to perform: Menu (default), Build, or Help.
.PARAMETER Roles
    For -Operation Build: array of role tags to deploy.
    Example: -Roles DC,DSC,IIS
.PARAMETER ConfigPath
    Optional path to LabDefaults.psd1. Defaults to Config\LabDefaults.psd1.

.EXAMPLE
    .\Invoke-LabBuilder.ps1
    # Interactive menu mode

.EXAMPLE
    .\Invoke-LabBuilder.ps1 -Operation Build -Roles DC,DSC,IIS
    # Non-interactive build with specified roles

.EXAMPLE
    .\Invoke-LabBuilder.ps1 -Operation Help
    # Print usage information

.NOTES
    Requires: AutomatedLab module, Hyper-V, Windows 11 host
    PowerShell: 5.1 only
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Menu', 'Build', 'Help')]
    [string]$Operation = 'Menu',

    [Parameter(Mandatory = $false)]
    [string[]]$Roles,

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath
)

# Exit codes
$EXIT_SUCCESS    = 0
$EXIT_ERROR      = 1
$EXIT_VALIDATION = 2
$EXIT_CANCELLED  = 3

$ErrorActionPreference = 'Stop'
$script:exitCode = $EXIT_SUCCESS

# Resolve paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $ScriptDir 'Config\LabDefaults.psd1'
}

# Dot-source dependencies
. (Join-Path $ScriptDir 'Select-LabRoles.ps1')
. (Join-Path $ScriptDir 'Build-LabFromSelection.ps1')

function Show-LabBuilderBanner {
    Write-Host ''
    Write-Host '  LabBuilder v1.0.0 - Automated Lab Environment Builder' -ForegroundColor Cyan
    Write-Host ('  ' + ('=' * 53)) -ForegroundColor Gray
    Write-Host ''
}

try {
    switch ($Operation) {
        'Menu' {
            Show-LabBuilderBanner
            $result = Select-LabRoles -ConfigPath $ConfigPath

            if ($result.Cancelled) {
                Write-Host '  Build cancelled by user.' -ForegroundColor Yellow
                $script:exitCode = $EXIT_CANCELLED
            }
            elseif ($result.SelectedRoles.Count -eq 0) {
                Write-Host '  No roles selected.' -ForegroundColor Yellow
                $script:exitCode = $EXIT_VALIDATION
            }
            else {
                Build-LabFromSelection -SelectedRoles $result.SelectedRoles -ConfigPath $ConfigPath
            }
        }

        'Build' {
            Show-LabBuilderBanner

            if (-not $Roles -or $Roles.Count -eq 0) {
                Write-Host '  -Roles parameter required for Build operation.' -ForegroundColor Red
                Write-Host '  Example: .\Invoke-LabBuilder.ps1 -Operation Build -Roles DC,DSC,IIS' -ForegroundColor Gray
                $script:exitCode = $EXIT_VALIDATION
            }
            else {
                # Ensure DC is always included
                if ('DC' -notin $Roles) {
                    $Roles = @('DC') + $Roles
                    Write-Host '  [INFO] DC role auto-added (always required).' -ForegroundColor Yellow
                }

                # Validate all role tags
                $validTags = @('DC', 'DSC', 'IIS', 'SQL', 'WSUS', 'FileServer', 'Jumpbox', 'Client', 'Ubuntu', 'WebServerUbuntu', 'DatabaseUbuntu', 'DockerUbuntu', 'K8sUbuntu')
                $invalid = @($Roles | Where-Object { $_ -notin $validTags })
                if ($invalid.Count -gt 0) {
                    Write-Host "  Invalid role(s): $($invalid -join ', ')" -ForegroundColor Red
                    Write-Host "  Valid roles: $($validTags -join ', ')" -ForegroundColor Gray
                    $script:exitCode = $EXIT_VALIDATION
                }
                else {
                    # Convention: Get-LabRole_<Tag> uses underscore separator for dynamic dispatch.
                    # This is intentional -- the tag name maps directly to the function suffix.
                    Build-LabFromSelection -SelectedRoles $Roles -ConfigPath $ConfigPath
                }
            }
        }

        'Help' {
            Show-LabBuilderBanner
            Write-Host '  Usage:' -ForegroundColor White
            Write-Host '    .\Invoke-LabBuilder.ps1                                    # Interactive menu' -ForegroundColor Gray
            Write-Host '    .\Invoke-LabBuilder.ps1 -Operation Build -Roles DC,DSC,IIS # Non-interactive' -ForegroundColor Gray
            Write-Host '    .\Invoke-LabBuilder.ps1 -Operation Help                    # This help' -ForegroundColor Gray
            Write-Host ''
            Write-Host '  Available Roles:' -ForegroundColor White
            Write-Host '    DC          Domain Controller + DNS + CA (always required)' -ForegroundColor Gray
            Write-Host '    DSC         DSC Pull Server (HTTP 8080 + compliance 9080)' -ForegroundColor Gray
            Write-Host '    IIS         IIS Web Server with sample site' -ForegroundColor Gray
            Write-Host '    SQL         SQL Server [scaffold]' -ForegroundColor Gray
            Write-Host '    WSUS        WSUS [scaffold]' -ForegroundColor Gray
            Write-Host '    FileServer  File Server with SMB share (\\FILE1\LabShare)' -ForegroundColor Gray
            Write-Host '    Jumpbox     Admin workstation (Win11 + RSAT)' -ForegroundColor Gray
            Write-Host '    Client      Client VM (Win11 + RDP)' -ForegroundColor Gray
            Write-Host '    Ubuntu      Ubuntu Server 24.04 (LIN1 + cloud-init + SSH)' -ForegroundColor Gray
            Write-Host '    WebServerUbuntu Ubuntu Web Server (LINWEB1 + nginx)' -ForegroundColor Gray
            Write-Host '    DatabaseUbuntu  Ubuntu Database (LINDB1 + PostgreSQL)' -ForegroundColor Gray
            Write-Host '    DockerUbuntu    Ubuntu Docker Host (LINDOCK1 + Docker CE)' -ForegroundColor Gray
            Write-Host '    K8sUbuntu       Ubuntu Kubernetes (LINK8S1 + k3s)' -ForegroundColor Gray
            Write-Host ''
            Write-Host '  Configuration:' -ForegroundColor White
            Write-Host '    Edit Config\LabDefaults.psd1 to customize:' -ForegroundColor Gray
            Write-Host '      - Domain name, subnet, IP plan' -ForegroundColor Gray
            Write-Host '      - VM names, memory, CPU counts' -ForegroundColor Gray
            Write-Host '      - OS images, DSC server ports' -ForegroundColor Gray
            Write-Host ''
            Write-Host '  Credentials:' -ForegroundColor White
            Write-Host '    Set $env:LAB_ADMIN_PASSWORD before running, or enter at prompt.' -ForegroundColor Gray
            Write-Host '    No plaintext passwords are stored in any file.' -ForegroundColor Gray
            Write-Host ''
            Write-Host '  Logs:' -ForegroundColor White
            Write-Host '    Logs\LabBuild-YYYYMMDD-HHMMSS.log          # Full transcript' -ForegroundColor Gray
            Write-Host '    Logs\LabBuild-YYYYMMDD-HHMMSS.summary.json # Machine plan + timing' -ForegroundColor Gray
            Write-Host ''
            Write-Host '  Exit Codes:' -ForegroundColor White
            Write-Host '    0 = Success' -ForegroundColor Gray
            Write-Host '    1 = Error' -ForegroundColor Gray
            Write-Host '    2 = Validation failure' -ForegroundColor Gray
            Write-Host '    3 = Cancelled by user' -ForegroundColor Gray
            Write-Host ''
        }
    }
}
catch {
    Write-Host "  [FATAL] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  $($_.ScriptStackTrace)" -ForegroundColor DarkRed
    $script:exitCode = $EXIT_ERROR
}

exit $script:exitCode

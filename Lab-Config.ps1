﻿<#
.SYNOPSIS
  Lab-Config.ps1 -- Central config for OpenCode Dev Lab helper scripts
.NOTES
  Put this file in the same folder as Lab-Menu.ps1 (C:\LabSources\Scripts\ recommended).
  You can edit values here once instead of in every script.
#>

# Lab identity
$LabName     = 'OpenCodeLab'
$LabVMs      = @('DC1','WS1','LIN1')

# Linux VM defaults (LIN1)
$LinuxUser   = 'install'
$LinuxHome   = "/home/$LinuxUser"
$LinuxProjectsRoot = "$LinuxHome/projects"
$LinuxLabShareMount = "/mnt/labshare"

# Windows paths
$LabSourcesRoot = 'C:\LabSources'
$ScriptsRoot    = Join-Path $LabSourcesRoot 'Scripts'
$SSHKey         = Join-Path $LabSourcesRoot 'SSHKeys\id_ed25519'

# Bootstrap/deploy helpers
$BootstrapScript = 'Bootstrap-OpenCodeLab_FIXED_FINAL.ps1'
$DeployScript    = 'Deploy-OpenCodeLab-Slim_FIXED_FINAL.ps1'

# Optional: Git identity (leave blank to prompt when needed)
$GitName  = ''
$GitEmail = ''

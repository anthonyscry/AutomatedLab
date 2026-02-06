﻿<#
.SYNOPSIS
  Lab-Common.ps1 -- Shared helpers for OpenCode Dev Lab workflow scripts
#>

Set-StrictMode -Version Latest

function Import-OpenCodeLab {
    param([string]$Name)

    try {
        Import-Module AutomatedLab -ErrorAction Stop | Out-Null
    } catch {
        throw "AutomatedLab module not available. Install AutomatedLab first."
    }

    try {
        Import-Lab -Name $Name -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Ensure-VMRunning {
    param(
        [Parameter(Mandatory)] [string[]] $VMNames,
        [switch] $AutoStart
    )
    $missing = @()
    foreach ($n in $VMNames) {
        $vm = Get-VM -Name $n -ErrorAction SilentlyContinue
        if (-not $vm) { $missing += $n; continue }
        if ($vm.State -ne 'Running') {
            if ($AutoStart) {
                Start-VM -Name $n -ErrorAction SilentlyContinue | Out-Null
            } else {
                return $false
            }
        }
    }
    if ($missing.Count -gt 0) {
        throw "Missing Hyper-V VM(s): $($missing -join ', ')"
    }
    # If we autostarted, wait a moment for adapters to populate
    Start-Sleep -Seconds 2
    return $true
}

function Get-LIN1IPv4 {
    $ip = (Get-VMNetworkAdapter -VMName 'LIN1' -ErrorAction SilentlyContinue).IPAddresses |
        Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } |
        Select-Object -First 1
    return $ip
}

function Ensure-SSHKey {
    param([string]$KeyPath)
    if (-not (Test-Path $KeyPath)) {
        throw "SSH key not found: $KeyPath`nGenerate it with: C:\Windows\System32\OpenSSH\ssh-keygen.exe -t ed25519 -f `"$KeyPath`" -N `"`""
    }
}

function Get-GitIdentity {
    param([string]$DefaultName, [string]$DefaultEmail)

    $name  = $DefaultName
    $email = $DefaultEmail

    if ([string]::IsNullOrWhiteSpace($name))  { $name  = Read-Host "  Git user.name (e.g. Anthony Tran)" }
    if ([string]::IsNullOrWhiteSpace($email)) { $email = Read-Host "  Git user.email (e.g. you@domain)" }

    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($email)) {
        throw "Git identity is required."
    }

    return @{ Name = $name; Email = $email }
}

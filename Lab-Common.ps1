# Lab-Common.ps1 -- Shared helpers for OpenCode Dev Lab workflow scripts

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

function Ensure-VMsReady {
    param(
        [Parameter(Mandatory)][string[]]$VMNames,
        [switch]$NonInteractive,
        [switch]$AutoStart
    )
    if (-not (Ensure-VMRunning -VMNames $VMNames)) {
        if ($NonInteractive -or $AutoStart) {
            Ensure-VMRunning -VMNames $VMNames -AutoStart | Out-Null
        } else {
            $vmList = $VMNames -join ', '
            $start = Read-Host "  $vmList not running. Start now? (y/n)"
            if ($start -ne 'y') { exit 0 }
            Ensure-VMRunning -VMNames $VMNames -AutoStart | Out-Null
        }
    }
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

function Invoke-BashOnLIN1 {
    param(
        [Parameter(Mandatory)][string]$BashScript,
        [Parameter(Mandatory)][string]$ActivityName,
        [hashtable]$Variables = @{},
        [switch]$PassThru
    )
    # Apply variable substitutions (placeholder pattern: __KEY__)
    $content = $BashScript
    foreach ($key in $Variables.Keys) {
        $content = $content.Replace("__${key}__", $Variables[$key])
    }

    $tempName = "$ActivityName-$(Get-Date -Format 'HHmmss').sh"
    $tempPath = Join-Path $env:TEMP $tempName
    $content | Set-Content -Path $tempPath -Encoding ASCII -Force

    try {
        Copy-LabFileItem -Path $tempPath -ComputerName 'LIN1' -DestinationFolderPath '/tmp'

        $invokeParams = @{
            ComputerName = 'LIN1'
            ActivityName = $ActivityName
            ScriptBlock = {
                param($ScriptFile)
                chmod +x "/tmp/$ScriptFile"
                bash "/tmp/$ScriptFile"
            }
            ArgumentList = @($tempName)
        }
        if ($PassThru) { $invokeParams.PassThru = $true }

        Invoke-LabCommand @invokeParams
    } finally {
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
    }
}

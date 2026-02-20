# New-LinuxGoldenVhdx.ps1 -- Create reusable Linux golden VHDX template
function New-LinuxGoldenVhdx {
    <#
    .SYNOPSIS
    Creates a pre-installed golden VHDX template for Linux VMs.
    .DESCRIPTION
    If a golden template VHDX exists, New-LinuxVM can clone it instead of
    installing from ISO each time. This function creates the template by:
    1. Creating a temporary VM with the ISO + CIDATA
    2. Waiting for installation to complete
    3. Shutting down and saving the OS VHDX as the golden template

    Subsequent VMs can use Copy-Item on the golden VHDX instead of
    reinstalling from ISO (saves 15-25 minutes per VM).
    .PARAMETER TemplatePath
    Path where the golden VHDX template will be saved.
    .PARAMETER UbuntuIsoPath
    Path to the Ubuntu installation ISO.
    .PARAMETER Hostname
    Temporary hostname for the template VM.
    .PARAMETER Username
    Username for the template VM.
    .PARAMETER Password
    Password for the template VM.

    .PARAMETER SwitchName
    Hyper-V switch to attach the template VM to during installation.

    .PARAMETER WaitMinutes
    Maximum minutes to wait for SSH readiness before giving up (default: 45).

    .PARAMETER DiskSize
    OS disk size for the template VM (default: 60 GB).

    .EXAMPLE
    New-LinuxGoldenVhdx -TemplatePath 'C:\LabSources\golden-ubuntu2404.vhdx' `
        -UbuntuIsoPath 'C:\LabSources\ubuntu-24.04-live-server-amd64.iso'
    # Creates a golden VHDX template at the specified path.

    .EXAMPLE
    # Subsequent VMs clone the golden template instead of reinstalling from ISO
    $template = New-LinuxGoldenVhdx -TemplatePath 'C:\LabSources\golden-ubuntu2404.vhdx' `
        -UbuntuIsoPath 'C:\iso\ubuntu-24.04.iso' -WaitMinutes 60
    if ($template) { Copy-Item $template "C:\VMs\LIN2\LIN2.vhdx" }

    .EXAMPLE
    # Idempotent: if the template already exists the function returns the path immediately
    New-LinuxGoldenVhdx -TemplatePath 'C:\LabSources\golden-ubuntu2404.vhdx' `
        -UbuntuIsoPath 'C:\iso\ubuntu-24.04.iso'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TemplatePath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$UbuntuIsoPath,
        [string]$Hostname = 'golden-template',
        [string]$Username = 'labadmin',
        [string]$Password = $(if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig.Credentials.AdminPassword } else { '' }),
        [string]$SwitchName = $GlobalLabConfig.Network.SwitchName,
        [int]$WaitMinutes = 45,
        [long]$DiskSize = 60GB
    )

    if (Test-Path $TemplatePath) {
        Write-LabStatus -Status OK -Message "Golden VHDX template already exists: $TemplatePath" -Indent 2
        return $TemplatePath
    }

    $templateDir = Split-Path $TemplatePath -Parent
    if ($templateDir) {
        $null = New-Item -ItemType Directory -Path $templateDir -Force
        Write-Verbose "Created directory: $templateDir"
    }

    $tempVMName = "GoldenTemplate-$(Get-Date -Format 'yyyyMMddHHmmss')"

    Write-Host "    Creating golden template VM '$tempVMName'..." -ForegroundColor Cyan

    $cidataPath = $null
    $tempVhdxPath = Join-Path $env:TEMP "$tempVMName.vhdx"

    try {
        # Generate password hash
        $pwHash = Get-Sha512PasswordHash -Password $Password

        # Create CIDATA for template
        $cidataPath = Join-Path $env:TEMP "$tempVMName-cidata.vhdx"
        New-CidataVhdx -OutputPath $cidataPath -Hostname $Hostname -Username $Username -PasswordHash $pwHash

        # Create temp VM
        New-LinuxVM -UbuntuIsoPath $UbuntuIsoPath -CidataVhdxPath $cidataPath `
            -VMName $tempVMName -VhdxPath $tempVhdxPath `
            -SwitchName $SwitchName -DiskSize $DiskSize

        Start-VM -Name $tempVMName
        Write-Host "    Template VM started. Waiting for install ($WaitMinutes min max)..." -ForegroundColor Gray

        # Wait for SSH or timeout
        $waitResult = Wait-LinuxVMReady -VMName $tempVMName -WaitMinutes $WaitMinutes

        if ($waitResult.Ready) {
            Write-Host "    Template installation complete. Shutting down..." -ForegroundColor Green
            Stop-VM -Name $tempVMName -Force
            $shutdownDeadline = [datetime]::Now.AddSeconds(30)
            while ([datetime]::Now -lt $shutdownDeadline) {
                $tempVmState = Hyper-V\Get-VM -Name $tempVMName -ErrorAction SilentlyContinue
                if (-not $tempVmState -or $tempVmState.State -eq 'Off') { break }
                Start-Sleep -Seconds 2
            }

            # Finalize media
            Finalize-LinuxInstallMedia -VMName $tempVMName

            # Copy the OS VHDX as the golden template
            Copy-Item $tempVhdxPath $TemplatePath -Force
            Write-LabStatus -Status OK -Message "Golden VHDX template saved: $TemplatePath" -Indent 2
        } else {
            Write-Warning "Template VM did not become ready within $WaitMinutes minutes."
            Write-Warning "Golden template not created."
        }
    }
    finally {
        # Cleanup temp VM
        $null = Remove-HyperVVMStale -VMName $tempVMName -Context 'golden-template-cleanup'
        if ($cidataPath) {
            Remove-Item $cidataPath -Force -ErrorAction SilentlyContinue
        }
        Remove-Item (Join-Path $env:TEMP "$tempVMName.vhdx") -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $TemplatePath) {
        return $TemplatePath
    }
    return $null
}

# Finalize-LinuxInstallMedia.ps1 -- Detach installer media post-install
function Finalize-LinuxInstallMedia {
    <#
    .SYNOPSIS
    Finalize Linux VM boot media after Ubuntu install completes.

    Removes installer DVD/CIDATA devices and sets firmware to boot from OS disk
    so the VM does not return to the Ubuntu installer wizard on subsequent boots.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$VMName = 'LIN1'
    )

    $vm = Hyper-V\Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if (-not $vm) {
        Write-Verbose "VM '$VMName' not found; skipping install-media finalization."
        return $false
    }

    $osDisk = Hyper-V\Get-VMHardDiskDrive -VMName $VMName -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path -notmatch '(?i)cidata' } |
        Select-Object -First 1
    if ($osDisk) {
        try {
            Hyper-V\Set-VMFirmware -VMName $VMName -FirstBootDevice $osDisk -ErrorAction Stop
            Write-LabStatus -Status OK -Message "$VMName firmware set to boot from OS disk" -Indent 2
        } catch {
            Write-Verbose "Unable to set first boot device for '$VMName': $($_.Exception.Message)"
        }
    }

    Hyper-V\Get-VMDvdDrive -VMName $VMName -ErrorAction SilentlyContinue |
        ForEach-Object {
            $dvd = $_
            try {
                Hyper-V\Remove-VMDvdDrive -VMDvdDrive $dvd -ErrorAction Stop
                Write-LabStatus -Status OK -Message "Detached installer DVD from $VMName" -Indent 2
            } catch {
                Write-Verbose "Unable to remove DVD drive from '$VMName': $($_.Exception.Message)"
            }
        }

    Hyper-V\Get-VMHardDiskDrive -VMName $VMName -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path -match '(?i)cidata' } |
        ForEach-Object {
            $seed = $_
            try {
                Hyper-V\Remove-VMHardDiskDrive -VMHardDiskDrive $seed -ErrorAction Stop
                Write-LabStatus -Status OK -Message "Detached CIDATA seed disk from $VMName" -Indent 2
            } catch {
                Write-Verbose "Unable to detach CIDATA disk from '$VMName': $($_.Exception.Message)"
            }

            if ($seed.Path -and (Test-Path $seed.Path)) {
                Remove-Item $seed.Path -Force -ErrorAction SilentlyContinue
            }
        }

    return $true
}

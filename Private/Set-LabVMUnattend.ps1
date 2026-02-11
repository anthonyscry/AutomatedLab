# Set-LabVMUnattend.ps1
# Injects unattend.xml into VM VHD for automated installation

function Set-LabVMUnattend {
    <#
    .SYNOPSIS
        Injects unattend.xml into a VM's VHD for automated Windows installation.

    .DESCRIPTION
        Mounts the VM's VHD, copies unattend.xml to the appropriate location,
        and dismounts the VHD. This enables fully automated Windows installation.

    .PARAMETER VMName
        Name of the VM to configure.

    .PARAMETER ComputerName
        Computer name to set in unattend.xml.

    .PARAMETER AdministratorPassword
        Administrator password for unattend.xml.

    .PARAMETER OSType
        Operating system type: Server2019 or Windows11.

    .OUTPUTS
        PSCustomObject with status and details.

    .EXAMPLE
        Set-LabVMUnattend -VMName "dc1" -ComputerName "dc1" -AdministratorPassword "P@ssw0rd" -OSType "Server2019"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [string]$ComputerName,

        [Parameter(Mandatory = $true)]
        [string]$AdministratorPassword,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Server2019", "Windows11")]
        [string]$OSType
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        VMName = $VMName
        Injected = $false
        Status = "Failed"
        Message = ""
        UnattendPath = $null
        Duration = $null
    }

    try {
        Write-Verbose "Injecting unattend.xml for '$VMName'..."

        # Step 1: Get VM and VHD path
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if ($null -eq $vm) {
            $result.Status = "NotFound"
            $result.Message = "VM '$VMName' not found"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Get the VHD path (first hard drive)
        if ($vm.HardDrives.Count -eq 0) {
            $result.Status = "NoVHD"
            $result.Message = "VM '$VMName' has no hard drives attached"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }
        $vhdPath = ($vm.HardDrives[0]).Path
        if ([string]::IsNullOrEmpty($vhdPath)) {
            $result.Status = "NoVHD"
            $result.Message = "No VHD found for VM '$VMName'"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        Write-Verbose "VHD Path: $vhdPath"

        # Step 2: VM must be off to mount VHD
        if ($vm.State -ne "Off") {
            $result.Status = "VMRunning"
            $result.Message = "VM '$VMName' must be off to inject unattend.xml. Current state: $($vm.State)"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Step 3: Generate unattend.xml content
        Write-Verbose "Generating unattend.xml content..."
        $unattendXml = New-LabUnattendXml -ComputerName $ComputerName -AdministratorPassword $AdministratorPassword -OSType $OSType

        # Step 4: Mount the VHD
        Write-Verbose "Mounting VHD..."
        try {
            $mountResult = Mount-VHD -Path $vhdPath -PassThru -ErrorAction Stop
            Start-Sleep -Seconds 1  # Give it a moment to mount
        }
        catch {
            $result.Status = "MountFailed"
            $result.Message = "Failed to mount VHD: $($_.Exception.Message)"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        try {
            # Step 5: Get the drive letter of the mounted VHD
            $disk = Get-Disk | Where-Object { $_.Location -eq $vhdPath }
            if ($null -eq $disk) {
                $result.Status = "DiskNotFound"
                $result.Message = "Could not find mounted disk for VHD"
                $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
                return $result
            }

            $partition = $disk | Get-Partition | Where-Object { $_.DriveLetter -and $_.Type -eq "IFS" } | Select-Object -First 1
            if ($null -eq $partition) {
                $result.Status = "NoPartition"
                $result.Message = "Could not find accessible partition on VHD"
                $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
                return $result
            }

            $driveLetter = $partition.DriveLetter
            $drivePath = "${driveLetter}:\"
            $windowsPath = Join-Path $drivePath "Windows"
            $pantherPath = Join-Path $windowsPath "Panther"
            $unattendPath = Join-Path $pantherPath "unattend.xml"

            Write-Verbose "Mounted VHD at drive $driveLetter"

            # Step 6: Ensure Panther directory exists
            if (-not (Test-Path $pantherPath)) {
                # For a fresh VHD, Windows folder won't exist yet
                # Place unattend.xml in the root of the drive instead
                $unattendPath = Join-Path $drivePath "unattend.xml"
                Write-Verbose "Panther path not found, using root: $unattendPath"
            }

            # Step 7: Write unattend.xml to VHD
            Write-Verbose "Writing unattend.xml to: $unattendPath"
            $unattendXml | Out-File -FilePath $unattendPath -Encoding UTF8 -NoNewline -Force -ErrorAction Stop

            $result.UnattendPath = $unattendPath
            Write-Verbose "unattend.xml written successfully"

            # Step 8: Also try to place it in the Panther\Unattend folder for Windows Setup
            $pantherUnattendPath = Join-Path $drivePath "Windows\Panther\Unattend\unattend.xml"
            if (Test-Path (Split-Path $pantherUnattendPath)) {
                $unattendXml | Out-File -FilePath $pantherUnattendPath -Encoding UTF8 -NoNewline -Force -ErrorAction SilentlyContinue
                Write-Verbose "Also placed at: $pantherUnattendPath"
            }

            # Success!
            $result.Injected = $true
            $result.Status = "OK"
            $result.Message = "Successfully injected unattend.xml into '$VMName'"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            Write-Verbose "unattend.xml injection completed successfully"

            return $result
        }
        finally {
            # Always dismount the VHD
            Write-Verbose "Dismounting VHD..."
            Dismount-VHD -Path $vhdPath -ErrorAction SilentlyContinue | Out-Null
        }
    }
    catch {
        $result.Status = "Failed"
        $result.Message = "Failed to inject unattend.xml: $($_.Exception.Message)"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
}

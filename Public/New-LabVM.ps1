function New-LabVM {
    <#
    .SYNOPSIS
        Creates a single Hyper-V virtual machine for the lab.

    .DESCRIPTION
        Creates a Generation 2 Hyper-V VM with the specified memory, processor,
        and VHD configuration. Validates disk space before creation, attaches
        an ISO if provided, and sets the DVD as the first boot device. Cleans
        up partially created VMs on failure.

    .PARAMETER VMName
        Name of the virtual machine to create.

    .PARAMETER MemoryGB
        Startup memory in gigabytes.

    .PARAMETER VHDPath
        Full path for the new virtual hard disk file (.vhdx).

    .PARAMETER SwitchName
        Virtual switch to connect the VM to (default: "SimpleLab").

    .PARAMETER IsoPath
        Path to an ISO file to attach as a DVD drive.

    .PARAMETER ProcessorCount
        Number of virtual processors (default: 2).

    .PARAMETER Generation
        Hyper-V VM generation (default: 2).

    .PARAMETER Force
        Remove and recreate the VM if it already exists.

    .OUTPUTS
        PSCustomObject with VMName, Created, Status, Message, VHDPath, MemoryGB, ProcessorCount.

    .EXAMPLE
        New-LabVM -VMName "dc1" -MemoryGB 4 -VHDPath "C:\Lab\VMs\dc1.vhdx"

    .EXAMPLE
        New-LabVM -VMName "ws1" -MemoryGB 4 -VHDPath "C:\Lab\VMs\ws1.vhdx" -IsoPath "C:\ISOs\win11.iso" -Force
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$VMName,

        [Parameter(Mandatory = $true)]
        [int]$MemoryGB,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$VHDPath,

        [Parameter()]
        [string]$SwitchName = "SimpleLab",

        [Parameter()]
        [string]$IsoPath,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$ProcessorCount = 2,

        [Parameter()]
        [int]$Generation = 2,

        [Parameter()]
        [switch]$Force
    )

    # Initialize result object
    $result = [PSCustomObject]@{
        VMName = $VMName
        Created = $false
        Status = "Failed"
        Message = ""
        VHDPath = $VHDPath
        MemoryGB = $MemoryGB
        ProcessorCount = $ProcessorCount
    }

    try {
        # Step 1: Check if Hyper-V module is available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            $result.Status = "Failed"
            $result.Message = "Hyper-V module is not available"
            return $result
        }

        # Step 2: Validate disk space (65 GB needed for VHD + overhead)
        $vhdDir = Split-Path -Parent $VHDPath
        if ($vhdDir -and (Test-Path $vhdDir)) {
            $drive = (Get-Item $vhdDir).PSDrive
            $freeGB = [math]::Round((Get-PSDrive $drive.Name).Free / 1GB, 1)
            if ($freeGB -lt 65) {
                $result.Status = "Failed"
                $result.Message = "Insufficient disk space: ${freeGB} GB free, 65 GB required"
                return $result
            }
        }

        # Step 3: Check if VM already exists
        $vmTest = Test-LabVM -VMName $VMName
        $vmExists = $vmTest.Exists

        # Step 3: Skip creation if exists and not forcing
        if ($vmExists -and -not $Force) {
            $result.Status = "AlreadyExists"
            $result.Created = $false
            $result.Message = "VM '$VMName' already exists"
            return $result
        }

        # Step 4: Remove existing VM if Force is specified
        if ($vmExists -and $Force) {
            try {
                Remove-VM -Name $VMName -Force -ErrorAction Stop
                Start-Sleep -Seconds 2
            }
            catch {
                $result.Status = "Failed"
                $result.Message = "Failed to remove existing VM: $($_.Exception.Message)"
                return $result
            }
        }

        # Step 5: Create the new VM
        try {
            $newVM = New-VM -Name $VMName `
                -MemoryStartupBytes ($MemoryGB * 1GB) `
                -NewVHDPath $VHDPath `
                -NewVHDSizeBytes (60GB) `
                -Generation $Generation `
                -SwitchName $SwitchName `
                -ErrorAction Stop

            # Step 6: Configure processor count
            Set-VMProcessor -VMName $VMName -Count $ProcessorCount -ErrorAction Stop

            # Step 7: Configure static memory (disable dynamic memory)
            Set-VMMemory -VMName $VMName -StartupBytes ($MemoryGB * 1GB) -DynamicMemoryEnabled $false -ErrorAction Stop

            # Step 8: Attach ISO if provided
            if ($IsoPath) {
                if (Test-Path -Path $IsoPath -PathType Leaf) {
                    Add-VMDvdDrive -VMName $VMName -Path $IsoPath -ErrorAction Stop

                    # Step 8a: Set DVD drive as first boot device (required for Gen2 VMs)
                    $dvdDrive = Get-VMDvdDrive -VMName $VMName -ErrorAction Stop
                    Set-VMFirmware -VMName $VMName -FirstBootDevice $dvdDrive -ErrorAction Stop | Out-Null
                }
                else {
                    $result.Status = "ISONotFound"
                    $result.Created = $false
                    $result.Message = "ISO file not found: $IsoPath"
                    return $result
                }
            }

            $result.Status = "OK"
            $result.Created = $true
            $result.Message = "VM '$VMName' created successfully"
        }
        catch {
            $result.Status = "Failed"
            $result.Message = "Failed to create VM: $($_.Exception.Message)"

            # Cleanup: Remove partially created VM if it exists
            try {
                $partialVM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
                if ($null -ne $partialVM) {
                    Write-Verbose "Cleaning up partially created VM '$VMName'..."
                    Remove-VM -Name $VMName -Force -ErrorAction SilentlyContinue
                    # Also try to remove the VHD if it was created
                    if ($partialVM.HardDrives.Count -gt 0) {
                        $vhdToRemove = $partialVM.HardDrives[0].Path
                        if (Test-Path -Path $vhdToRemove -ErrorAction SilentlyContinue) {
                            Remove-Item -Path $vhdToRemove -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
            catch {
                Write-Verbose "Cleanup error: $($_.Exception.Message)"
            }

            return $result
        }
    }
    catch {
        $result.Status = "Failed"
        $result.Message = "Unexpected error: $($_.Exception.Message)"
    }

    return $result
}

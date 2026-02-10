function Get-LabVMConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$VMName,
        [Parameter()]
        [switch]$IncludeLinux
    )

    # Initialize default VM configurations
    $defaultVMConfigs = @{
        "SimpleDC" = [PSCustomObject]@{
            MemoryGB = 4
            MinMemoryGB = 2
            MaxMemoryGB = 6
            ProcessorCount = 4
            DiskSizeGB = 60
            Generation = 2
            ISO = 'Server2019'
            EnableSecureBoot = $true
        }
        "SimpleServer" = [PSCustomObject]@{
            MemoryGB = 4
            MinMemoryGB = 2
            MaxMemoryGB = 6
            ProcessorCount = 4
            DiskSizeGB = 60
            Generation = 2
            ISO = 'Server2019'
            EnableSecureBoot = $true
        }
        "SimpleWin11" = [PSCustomObject]@{
            MemoryGB = 4
            MinMemoryGB = 2
            MaxMemoryGB = 6
            ProcessorCount = 4
            DiskSizeGB = 60
            Generation = 2
            ISO = 'Windows11'
            EnableSecureBoot = $true
        }
        "SimpleLIN" = [PSCustomObject]@{
            MemoryGB = 4
            MinMemoryGB = 2
            MaxMemoryGB = 6
            ProcessorCount = 4
            DiskSizeGB = 40
            Generation = 2
            ISO = 'Ubuntu'
            EnableSecureBoot = $false
            Type = 'Linux'
        }
    }

    # Get lab configuration
    $labConfig = Get-LabConfig

    # If no config exists, use defaults
    if ($null -eq $labConfig) {
        if ($PSBoundParameters.ContainsKey('VMName')) {
            if ($defaultVMConfigs.ContainsKey($VMName)) {
                return $defaultVMConfigs[$VMName]
            }
            else {
                return $null
            }
        }
        return $defaultVMConfigs
    }

    # Check if LabSettings.EnableLinux is set
    $enableLinux = if ($labConfig.PSObject.Properties.Name -contains 'LabSettings') {
        $labConfig.LabSettings.PSObject.Properties.Name -contains 'EnableLinux' -and $labConfig.LabSettings.EnableLinux -eq $true
    } else {
        $false
    }

    # Check if VMConfiguration section exists
    if ($labConfig.PSObject.Properties.Name -contains 'VMConfiguration') {
        $vmConfig = $labConfig.VMConfiguration

        # Build result object from config
        $result = @{}

        foreach ($vm in $defaultVMConfigs.Keys) {
            # Skip Linux VM unless explicitly enabled
            if ($vm -eq 'SimpleLIN' -and -not $enableLinux -and -not $IncludeLinux) {
                continue
            }

            if ($vmConfig.PSObject.Properties.Name -contains $vm) {
                $configVM = $vmConfig.$vm

                $result[$vm] = [PSCustomObject]@{
                    MemoryGB = if ($configVM.PSObject.Properties.Name -contains 'MemoryGB') { $configVM.MemoryGB } else { $defaultVMConfigs[$vm].MemoryGB }
                    MinMemoryGB = if ($configVM.PSObject.Properties.Name -contains 'MinMemoryGB') { $configVM.MinMemoryGB } else { $defaultVMConfigs[$vm].MinMemoryGB }
                    MaxMemoryGB = if ($configVM.PSObject.Properties.Name -contains 'MaxMemoryGB') { $configVM.MaxMemoryGB } else { $defaultVMConfigs[$vm].MaxMemoryGB }
                    ProcessorCount = if ($configVM.PSObject.Properties.Name -contains 'ProcessorCount') { $configVM.ProcessorCount } else { $defaultVMConfigs[$vm].ProcessorCount }
                    DiskSizeGB = if ($configVM.PSObject.Properties.Name -contains 'DiskSizeGB') { $configVM.DiskSizeGB } else { $defaultVMConfigs[$vm].DiskSizeGB }
                    Generation = if ($configVM.PSObject.Properties.Name -contains 'Generation') { $configVM.Generation } else { $defaultVMConfigs[$vm].Generation }
                    ISO = if ($configVM.PSObject.Properties.Name -contains 'ISO') { $configVM.ISO } else { $defaultVMConfigs[$vm].ISO }
                    EnableSecureBoot = if ($configVM.PSObject.Properties.Name -contains 'EnableSecureBoot') { $configVM.EnableSecureBoot } else { $defaultVMConfigs[$vm].EnableSecureBoot }
                    Type = if ($configVM.PSObject.Properties.Name -contains 'Type') { $configVM.Type } else { $defaultVMConfigs[$vm].Type }
                }
            }
            else {
                $result[$vm] = $defaultVMConfigs[$vm]
            }
        }

        if ($PSBoundParameters.ContainsKey('VMName')) {
            if ($result.ContainsKey($VMName)) {
                return $result[$VMName]
            }
            else {
                return $null
            }
        }

        return $result
    }

    # Return defaults if VMConfiguration section doesn't exist
    if ($PSBoundParameters.ContainsKey('VMName')) {
        if ($defaultVMConfigs.ContainsKey($VMName)) {
            # Don't return Linux VM if not enabled
            if ($VMName -eq 'SimpleLIN' -and -not $enableLinux -and -not $IncludeLinux) {
                return $null
            }
            return $defaultVMConfigs[$VMName]
        }
        else {
            return $null
        }
    }

    # Filter out Linux VM if not enabled
    $filteredConfigs = @{}
    foreach ($key in $defaultVMConfigs.Keys) {
        if ($key -eq 'SimpleLIN' -and -not $enableLinux -and -not $IncludeLinux) {
            continue
        }
        $filteredConfigs[$key] = $defaultVMConfigs[$key]
    }

    return $filteredConfigs
}

function Get-LabVMConfig {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$VMName
    )

    # Initialize default VM configurations
    $defaultVMConfigs = @{
        "SimpleDC" = [PSCustomObject]@{
            MemoryGB = 2
            ProcessorCount = 2
            DiskSizeGB = 60
            Generation = 2
            ISO = 'Server2019'
        }
        "SimpleServer" = [PSCustomObject]@{
            MemoryGB = 2
            ProcessorCount = 2
            DiskSizeGB = 60
            Generation = 2
            ISO = 'Server2019'
        }
        "SimpleWin11" = [PSCustomObject]@{
            MemoryGB = 4
            ProcessorCount = 2
            DiskSizeGB = 60
            Generation = 2
            ISO = 'Windows11'
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

    # Check if VMConfiguration section exists
    if ($labConfig.PSObject.Properties.Name -contains 'VMConfiguration') {
        $vmConfig = $labConfig.VMConfiguration

        # Build result object from config
        $result = @{}

        foreach ($vm in $defaultVMConfigs.Keys) {
            if ($vmConfig.PSObject.Properties.Name -contains $vm) {
                $configVM = $vmConfig.$vm

                $result[$vm] = [PSCustomObject]@{
                    MemoryGB = if ($configVM.PSObject.Properties.Name -contains 'MemoryGB') { $configVM.MemoryGB } else { $defaultVMConfigs[$vm].MemoryGB }
                    ProcessorCount = if ($configVM.PSObject.Properties.Name -contains 'ProcessorCount') { $configVM.ProcessorCount } else { $defaultVMConfigs[$vm].ProcessorCount }
                    DiskSizeGB = if ($configVM.PSObject.Properties.Name -contains 'DiskSizeGB') { $configVM.DiskSizeGB } else { $defaultVMConfigs[$vm].DiskSizeGB }
                    Generation = if ($configVM.PSObject.Properties.Name -contains 'Generation') { $configVM.Generation } else { $defaultVMConfigs[$vm].Generation }
                    ISO = if ($configVM.PSObject.Properties.Name -contains 'ISO') { $configVM.ISO } else { $defaultVMConfigs[$vm].ISO }
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
            return $defaultVMConfigs[$VMName]
        }
        else {
            return $null
        }
    }

    return $defaultVMConfigs
}

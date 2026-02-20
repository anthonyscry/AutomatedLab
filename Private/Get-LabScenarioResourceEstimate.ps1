function Get-LabScenarioResourceEstimate {
    <#
    .SYNOPSIS
        Estimates total resource requirements for a lab scenario.
    .DESCRIPTION
        Calls Get-LabScenarioTemplate to retrieve VM definitions for a scenario,
        then sums up RAM, CPU, and estimated disk requirements. Disk estimates
        use a role-based lookup table.
    .PARAMETER Scenario
        The scenario name to estimate (e.g., SecurityLab, MultiTierApp, MinimalAD).
    .PARAMETER TemplatesRoot
        Path to the directory containing scenario template JSON files.
        Defaults to .planning/templates relative to the repository root.
    .EXAMPLE
        Get-LabScenarioResourceEstimate -Scenario SecurityLab
        Returns resource totals: 10GB RAM, 8 CPUs, 3 VMs, estimated disk.
    .EXAMPLE
        Get-LabScenarioResourceEstimate -Scenario MultiTierApp -TemplatesRoot 'C:\MyTemplates'
        Returns resource totals from a custom templates directory.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Object with Scenario, VMCount, TotalRAMGB, TotalDiskGB, TotalProcessors, VMs properties.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Scenario,

        [Parameter()]
        [string]$TemplatesRoot = (Join-Path (Join-Path $PSScriptRoot '..') '.planning/templates')
    )

    try {
        $vmDefs = Get-LabScenarioTemplate -Scenario $Scenario -TemplatesRoot $TemplatesRoot

        # Role-based disk size estimates (GB)
        $diskLookup = @{
            'DC'     = 80
            'SQL'    = 100
            'IIS'    = 60
            'Server' = 60
            'Client' = 60
            'Ubuntu' = 40
        }
        $defaultDiskGB = 60

        $totalRam = 0
        $totalCpus = 0
        $totalDisk = 0
        $vmCount = @($vmDefs).Count

        foreach ($vm in $vmDefs) {
            $totalRam += $vm.MemoryGB
            $totalCpus += $vm.Processors
            if ($diskLookup.ContainsKey($vm.Role)) {
                $totalDisk += $diskLookup[$vm.Role]
            }
            else {
                $totalDisk += $defaultDiskGB
            }
        }

        return [pscustomobject]@{
            Scenario        = $Scenario
            VMCount         = $vmCount
            TotalRAMGB      = $totalRam
            TotalDiskGB     = $totalDisk
            TotalProcessors = $totalCpus
            VMs             = $vmDefs
        }
    }
    catch {
        if ($_.Exception.Message -like 'Get-LabScenarioResourceEstimate:*') {
            throw
        }
        throw "Get-LabScenarioResourceEstimate: $($_.Exception.Message)"
    }
}

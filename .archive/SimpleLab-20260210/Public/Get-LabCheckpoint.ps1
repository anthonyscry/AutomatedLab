function Get-LabCheckpoint {
    <#
    .SYNOPSIS
        Lists all checkpoints for SimpleLab virtual machines.

    .DESCRIPTION
        Retrieves and displays all checkpoints for each lab VM, including
        creation time and type (Standard/Production).

    .PARAMETER SwitchName
        Name of the virtual switch (default: "SimpleLab").

    .OUTPUTS
        Array of PSCustomObject with checkpoint information.

    .EXAMPLE
        Get-LabCheckpoint

    .EXAMPLE
        Get-LabCheckpoint | Format-Table -AutoSize
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [string]$SwitchName = "SimpleLab"
    )

    try {
        # Check if Hyper-V module is available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            Write-Warning "Hyper-V module is not available"
            return @()
        }

        # Get VM configurations
        $vmConfigs = Get-LabVMConfig
        if ($null -eq $vmConfigs) {
            Write-Warning "Failed to retrieve VM configurations"
            return @()
        }

        $results = @()
        $labVMs = @("SimpleDC", "SimpleServer", "SimpleWin11")

        foreach ($vmName in $labVMs) {
            # Check if VM exists
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($null -eq $vm) {
                $results += [PSCustomObject]@{
                    VMName = $vmName
                    CheckpointName = "N/A"
                    Created = $null
                    Type = "N/A"
                    Status = "VM does not exist"
                }
                continue
            }

            # Get checkpoints for this VM (wrap in @() to ensure array)
            $checkpoints = @(Get-VMCheckpoint -VMName $vmName -ErrorAction SilentlyContinue)

            if ($checkpoints.Count -eq 0) {
                $results += [PSCustomObject]@{
                    VMName = $vmName
                    CheckpointName = "None"
                    Created = $null
                    Type = "N/A"
                    Status = "No checkpoints"
                }
                continue
            }

            # Add each checkpoint to results
            foreach ($checkpoint in $checkpoints) {
                $results += [PSCustomObject]@{
                    VMName = $vmName
                    CheckpointName = $checkpoint.Name
                    Created = $checkpoint.CreationTime
                    Type = if ($checkpoint.IsSnapshot) { "Snapshot" } else { "Checkpoint" }
                    Status = "Available"
                }
            }
        }

        return $results
    }
    catch {
        Write-Error "Failed to get checkpoints: $($_.Exception.Message)"
        return @()
    }
}

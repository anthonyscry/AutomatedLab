function Get-LabStatus {
    <#
    .SYNOPSIS
        Gets the current status of all SimpleLab virtual machines.

    .DESCRIPTION
        Retrieves and displays the status of all lab VMs including state,
        CPU usage, memory usage, uptime, and network status.

    .PARAMETER SwitchName
        Name of the virtual switch (default: "SimpleLab").

    .PARAMETER Compact
        Show compact view with key properties only.

    .OUTPUTS
        Array of PSCustomObject representing each VM with its status.

    .EXAMPLE
        Get-LabStatus

    .EXAMPLE
        Get-LabStatus -Compact

    .EXAMPLE
        Get-LabStatus | Format-Table -AutoSize
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [string]$SwitchName = "SimpleLab",

        [Parameter()]
        [switch]$Compact
    )

    try {
        # Check if Hyper-V module is available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            Write-Warning "Hyper-V module is not available"
            return @()
        }

        $results = New-Object System.Collections.Generic.List[object]
        $labVMs = @("dc1", "svr1", "dsc", "ws1")
        if (Get-VM -Name "LIN1" -ErrorAction SilentlyContinue) {
            $labVMs += "LIN1"
        }

        $knownVMs = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.Name -in $labVMs }
        $vmMap = @{}
        foreach ($vm in $knownVMs) {
            $vmMap[$vm.Name.ToLowerInvariant()] = $vm
        }

        $adapterMap = @{}
        if (-not $Compact -and $knownVMs.Count -gt 0) {
            $vmNames = @($knownVMs | ForEach-Object { $_.Name })
            $allAdapters = Get-VMNetworkAdapter -VMName $vmNames -ErrorAction SilentlyContinue
            foreach ($adapter in $allAdapters) {
                $adapterKey = $adapter.VMName.ToLowerInvariant()
                if (-not $adapterMap.ContainsKey($adapterKey)) {
                    $adapterMap[$adapterKey] = New-Object System.Collections.Generic.List[object]
                }
                $adapterMap[$adapterKey].Add($adapter) | Out-Null
            }
        }

        foreach ($vmName in $labVMs) {
            $vm = $vmMap[$vmName.ToLowerInvariant()]

            if ($null -eq $vm) {
                if ($Compact) {
                    $results.Add([PSCustomObject]@{
                        VMName = $vmName
                        State = "NotCreated"
                        Heartbeat = "N/A"
                    }) | Out-Null
                }
                else {
                    $results.Add([PSCustomObject]@{
                        VMName = $vmName
                        State = "NotCreated"
                        Status = "VM does not exist"
                        CPUUsage = "N/A"
                        MemoryGB = "N/A"
                        Uptime = "N/A"
                        NetworkStatus = "N/A"
                        Heartbeat = "N/A"
                    }) | Out-Null
                }
                continue
            }

            # Get heartbeat status
            $heartbeat = switch ([string]$vm.Heartbeat) {
                "Ok" { "Healthy" }
                "Error" { "Error" }
                "LostCommunication" { "Lost" }
                default { if ($vm.State -eq "Running") { "Starting" } else { "N/A" } }
            }

            if ($Compact) {
                $results.Add([PSCustomObject]@{
                    VMName = $vmName
                    State = [string]$vm.State
                    Heartbeat = $heartbeat
                }) | Out-Null
            }
            else {
                # Calculate uptime if running
                $uptime = if ($vm.State -eq "Running" -and $vm.Uptime) {
                    $vm.Uptime.ToString("hh\:mm\:ss")
                }
                else {
                    "N/A"
                }

                # Get CPU usage (percentage)
                $cpuUsage = if ($vm.State -eq "Running") {
                    $cpu = $vm.CPUUsage
                    if ($cpu) { "$cpu%" } else { "N/A" }
                }
                else {
                    "N/A"
                }

                # Get memory assigned
                $memoryBytes = if ($vm.MemoryAssigned -and $vm.MemoryAssigned -gt 0) { $vm.MemoryAssigned } else { $vm.MemoryStartup }
                $memoryGB = if ($memoryBytes) {
                    "$([math]::Round($memoryBytes / 1GB, 2)) GB"
                }
                else {
                    "N/A"
                }

                # Get network adapter status
                $netStatus = "No adapter"
                $adapterKey = $vmName.ToLowerInvariant()
                if ($adapterMap.ContainsKey($adapterKey)) {
                    $adapterStatus = @(
                        $adapterMap[$adapterKey] | ForEach-Object {
                            "$($_.SwitchName) [$($_.Status)]"
                        }
                    )
                    if ($adapterStatus.Count -gt 0) {
                        $netStatus = $adapterStatus -join "; "
                    }
                }

                $results.Add([PSCustomObject]@{
                    VMName = $vmName
                    State = [string]$vm.State
                    Status = if ($vm.State -eq "Running") { "Running" } else { "Stopped" }
                    CPUUsage = $cpuUsage
                    MemoryGB = $memoryGB
                    Uptime = $uptime
                    NetworkStatus = $netStatus
                    Heartbeat = $heartbeat
                }) | Out-Null
            }
        }

        return @($results)
    }
    catch {
        Write-Error "Failed to get lab status: $($_.Exception.Message)"
        return @()
    }
}

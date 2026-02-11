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

        # Get VM configurations
        $vmConfigs = Get-LabVMConfig
        if ($null -eq $vmConfigs) {
            Write-Warning "Failed to retrieve VM configurations"
            return @()
        }

        $results = @()
        $labVMs = @("dc1", "svr1", "ws1")

        foreach ($vmName in $labVMs) {
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue

            if ($null -eq $vm) {
                if ($Compact) {
                    $results += [PSCustomObject]@{
                        VMName = $vmName
                        State = "NotCreated"
                        Heartbeat = "N/A"
                    }
                }
                else {
                    $results += [PSCustomObject]@{
                        VMName = $vmName
                        State = "NotCreated"
                        Status = "VM does not exist"
                        CPUUsage = "N/A"
                        MemoryGB = "N/A"
                        Uptime = "N/A"
                        NetworkStatus = "N/A"
                        Heartbeat = "N/A"
                    }
                }
                continue
            }

            # Get heartbeat status
            $heartbeat = switch ($vm.Heartbeat) {
                "Ok" { "Healthy" }
                "Error" { "Error" }
                "LostCommunication" { "Lost" }
                default { if ($vm.State -eq "Running") { "Starting" } else { "N/A" } }
            }

            if ($Compact) {
                $results += [PSCustomObject]@{
                    VMName = $vmName
                    State = $vm.State
                    Heartbeat = $heartbeat
                }
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
                $memoryGB = if ($vm.Memory) {
                    "$([math]::Round($vm.Memory / 1GB, 2)) GB"
                }
                else {
                    "N/A"
                }

                # Get network adapter status
                $netStatus = try {
                    $adapter = Get-VMNetworkAdapter -VMName $vmName -ErrorAction SilentlyContinue
                    if ($adapter) {
                        "$($adapter.SwitchName) [$($adapter.Status)]"
                    }
                    else {
                        "No adapter"
                    }
                }
                catch {
                    "Unknown"
                }

                $results += [PSCustomObject]@{
                    VMName = $vmName
                    State = $vm.State
                    Status = if ($vm.State -eq "Running") { "Running" } else { "Stopped" }
                    CPUUsage = $cpuUsage
                    MemoryGB = $memoryGB
                    Uptime = $uptime
                    NetworkStatus = $netStatus
                    Heartbeat = $heartbeat
                }
            }
        }

        return $results
    }
    catch {
        Write-Error "Failed to get lab status: $($_.Exception.Message)"
        return @()
    }
}

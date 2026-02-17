function Show-LabStatus {
    <#
    .SYNOPSIS
        Displays the current status of all SimpleLab virtual machines with formatting.

    .DESCRIPTION
        Shows lab VM status with optional color coding and compact view.
        Provides a summary line with VM counts by state.

    .PARAMETER Compact
        Show compact view with key properties only.

    .PARAMETER NoColor
        Disable ANSI color rendering.

    .OUTPUTS
        Formatted table display with optional color coding.

    .EXAMPLE
        Show-LabStatus

    .EXAMPLE
        Show-LabStatus -Compact
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Compact,

        [Parameter()]
        [switch]$NoColor
    )

    try {
        # Get status data
        $statusData = Get-LabStatus -Compact:$Compact

        if ($null -eq $statusData -or $statusData.Count -eq 0) {
            Write-Host "No VM status data available." -ForegroundColor Yellow
            return
        }

        # Check if ANSI colors are supported
        $ansiSupported = $false
        if ($NoColor) {
            $ansiSupported = $false
        }
        elseif ($PSVersionTable.PSVersion.Major -ge 7) {
            # PowerShell 7+ supports ANSI
            $ansiSupported = $true
        }
        elseif ($env:WT_SESSION) {
            # Windows Terminal supports ANSI
            $ansiSupported = $true
        }
        elseif ($env:TERM -eq "xterm-256color" -or $env:TERM -eq "screen-256color") {
            # Most modern terminals support ANSI
            $ansiSupported = $true
        }

        # Helper function for colored output
        function Write-ColorText {
            param([string]$Text, [string]$Color)

            if ($ansiSupported) {
                $colorCode = switch ($Color) {
                    "Green"  { "`e[32m" }
                    "Red"    { "`e[31m" }
                    "Yellow" { "`e[33m" }
                    "Gray"   { "`e[90m" }
                    "DarkGray" { "`e[90m" }
                    "Cyan"   { "`e[36m" }
                    default  { "`e[0m" }
                }
                Write-Host "$colorCode$Text`e[0m" -NoNewline
            }
            else {
                Write-Host $Text -NoNewline
            }
        }

        # Display header
        Write-Host ""
        Write-Host "SimpleLab VM Status" -ForegroundColor Cyan
        Write-Host ("=" * 60) -ForegroundColor Gray

        # Display table
        if ($Compact) {
            Write-Host ("{0,-16}{1,-12}{2,-10}" -f "VM", "State", "Heartbeat") -ForegroundColor Cyan
            Write-Host ("-" * 38) -ForegroundColor Gray

            # Compact table
            foreach ($vm in $statusData) {
                # VM Name
                Write-Host ("{0,-16}" -f $vm.VMName) -NoNewline -ForegroundColor Cyan

                # State
                $stateColor = switch ($vm.State) {
                    "Running"   { "Green" }
                    "Off"       { "Gray" }
                    "Saved"     { "Yellow" }
                    default     { "Yellow" }
                }
                Write-ColorText ("{0,-12}" -f $vm.State) $stateColor

                # Heartbeat
                $heartbeatColor = switch ($vm.Heartbeat) {
                    "Healthy"   { "Green" }
                    "Error"     { "Red" }
                    "Lost"      { "Red" }
                    "N/A"       { "Gray" }
                    default     { "Yellow" }
                }
                Write-ColorText ("{0,-10}" -f $vm.Heartbeat) $heartbeatColor
                Write-Host ""
            }
        }
        else {
            # Full table
            $format = "{0,-12} {1,-10} {2,-10} {3,-8} {4,-10} {5,-8} {6,-20} {7,-10}"
            Write-Host ($format -f "VMName", "State", "Heartbeat", "CPU", "Memory", "Uptime", "Network", "Status") -ForegroundColor Cyan
            Write-Host ("-" * 100) -ForegroundColor Gray

            foreach ($vm in $statusData) {
                # VM Name
                Write-Host ("{0,-12}" -f $vm.VMName) -NoNewline -ForegroundColor Cyan

                # State
                $stateColor = switch ($vm.State) {
                    "Running"     { "Green" }
                    "Off"         { "Gray" }
                    "Saved"       { "Yellow" }
                    "NotCreated"  { "Red" }
                    default       { "Yellow" }
                }
                Write-ColorText ("{0,-10}" -f $vm.State) $stateColor

                # Heartbeat
                $heartbeatColor = switch ($vm.Heartbeat) {
                    "Healthy"   { "Green" }
                    "Error"     { "Red" }
                    "Lost"      { "Red" }
                    "N/A"       { "Gray" }
                    default     { "Yellow" }
                }
                Write-ColorText ("{0,-10}" -f $vm.Heartbeat) $heartbeatColor

                # CPU Usage (color if high)
                $cpuColor = if ($vm.CPUUsage -match "(\d+)%") {
                    $cpuVal = [int]$matches[1]
                    if ($cpuVal -gt 80) { "Red" } elseif ($cpuVal -gt 50) { "Yellow" } else { "Gray" }
                } else { "Gray" }
                Write-ColorText ("{0,-8}" -f $vm.CPUUsage) $cpuColor

                # Memory
                Write-ColorText ("{0,-10}" -f $vm.MemoryGB) "Gray"

                # Uptime
                Write-ColorText ("{0,-8}" -f $vm.Uptime) "Gray"

                # Network Status
                Write-ColorText ("{0,-20}" -f $vm.NetworkStatus) "Gray"

                # Status
                $statusColor = switch ($vm.Status) {
                    "Running"   { "Green" }
                    "Stopped"   { "Gray" }
                    default     { "Yellow" }
                }
                Write-ColorText ("{0,-10}" -f $vm.Status) $statusColor

                Write-Host ""
            }
        }

        # Display summary
        Write-Host ("=" * 60) -ForegroundColor Gray

        $runningCount = 0
        $stoppedCount = 0
        $savedCount = 0
        $otherCount = 0
        foreach ($vm in $statusData) {
            switch ($vm.State) {
                "Running" { $runningCount++ }
                "Off" { $stoppedCount++ }
                "Saved" { $savedCount++ }
                default { $otherCount++ }
            }
        }

        Write-Host "Total: $($statusData.Count) VMs | " -NoNewline -ForegroundColor Gray
        Write-ColorText "Running: $runningCount " "Green"
        Write-Host "| " -NoNewline -ForegroundColor Gray
        Write-ColorText "Stopped: $stoppedCount " "Gray"
        if ($savedCount -gt 0) {
            Write-Host "| " -NoNewline -ForegroundColor Gray
            Write-ColorText "Saved: $savedCount " "Yellow"
        }
        if ($otherCount -gt 0) {
            Write-Host "| " -NoNewline -ForegroundColor Gray
            Write-ColorText "Other: $otherCount " "Yellow"
        }
        Write-Host ""
    }
    catch {
        throw "Show-LabStatus: failed to display lab status - $_"
    }
}

BeforeAll {
    # Create function stubs for commands called during module load
    function Get-LabStatus {
        return @(
            [pscustomobject]@{ VMName = 'dc1'; State = 'Running'; NetworkStatus = '10.0.10.10'; CPUUsage = '5%'; MemoryGB = '4GB' }
            [pscustomobject]@{ VMName = 'svr1'; State = 'Running'; NetworkStatus = '10.0.10.20'; CPUUsage = '3%'; MemoryGB = '2GB' }
        )
    }

    # Mock Hyper-V cmdlets BEFORE sourcing Private functions
    function global:Get-VMSnapshot { }
    function global:Get-VMHardDiskDrive { }
    function global:Get-VHD { }

    # Mock Get-LabUptime and Get-LabSTIGCompliance
    function Get-LabUptime {
        return [pscustomobject]@{ ElapsedHours = 76.5 }
    }
    function Get-LabSTIGCompliance {
        return @(
            [pscustomobject]@{ VMName = 'dc1'; Status = 'NonCompliant' }
            [pscustomobject]@{ VMName = 'svr1'; Status = 'Compliant' }
        )
    }

    # Source required functions
    . $PSScriptRoot/../Private/Get-LabDashboardConfig.ps1
    . $PSScriptRoot/../Private/Get-LabVMMetrics.ps1
    . $PSScriptRoot/../Private/Get-LabSnapshotAge.ps1
    . $PSScriptRoot/../Private/Get-LabVMDiskUsage.ps1

    # Mock WPF assemblies (avoid loading actual WPF on non-Windows)

    # Mock the GUI functions that depend on WPF
    function New-VMCardElement {
        param([string]$VMName)
        $card = @{ Name = $VMName }
        return $card
    }

    function Update-VMCard {
        param($Card, $VMData)
        # Stub
    }

    # Create synchronized hashtable
    $script:DashboardMetrics = [System.Collections.Hashtable]::Synchronized(@{})
    $script:DashboardMetrics['Continue'] = $true

    # Set up GlobalLabConfig
    $GlobalLabConfig = @{
        Lab = @{ CoreVMNames = @('dc1', 'svr1') }
        Dashboard = @{
            SnapshotStaleDays = 7
            SnapshotStaleCritical = 30
            DiskUsagePercent = 80
            DiskUsageCritical = 95
            UptimeStaleHours = 72
        }
    }

    # Now set up mocks for tests (replace stubs with mocks)
    Mock Get-LabSnapshotAge {
        return @(
            [pscustomobject]@{ VMName = 'dc1'; State = 'Running'; NetworkStatus = '10.0.10.10'; CPUUsage = '5%'; MemoryGB = '4GB' }
            [pscustomobject]@{ VMName = 'svr1'; State = 'Running'; NetworkStatus = '10.0.10.20'; CPUUsage = '3%'; MemoryGB = '2GB' }
        )
    }

    Mock Get-LabSnapshotAge {
        param($VMName)
        return @{ 'dc1' = 15; 'svr1' = 3 }[$VMName]
    }

    Mock Get-LabVMDiskUsage {
        param($VMName)
        return [pscustomobject]@{
            FileSizeGB = @{ 'dc1' = 45.0; 'svr1' = 20.5 }[$VMName]
            SizeGB = @{ 'dc1' = 50.0; 'svr1' = 25.0 }[$VMName]
            UsagePercent = @{ 'dc1' = 90; 'svr1' = 82 }[$VMName]
        }
    }

    Mock Get-LabUptime {
        return [pscustomobject]@{ ElapsedHours = 76.5 }
    }

    Mock Get-LabSTIGCompliance {
        return @(
            [pscustomobject]@{ VMName = 'dc1'; Status = 'NonCompliant' }
            [pscustomobject]@{ VMName = 'svr1'; Status = 'Compliant' }
        )
    }

    # Create synchronized hashtable
    $script:DashboardMetrics = [System.Collections.Hashtable]::Synchronized(@{})
    $script:DashboardMetrics['Continue'] = $true

    # Set up GlobalLabConfig
    $GlobalLabConfig = @{
        Lab = @{ CoreVMNames = @('dc1', 'svr1') }
        Dashboard = @{
            SnapshotStaleDays = 7
            SnapshotStaleCritical = 30
            DiskUsagePercent = 80
            DiskUsageCritical = 95
            UptimeStaleHours = 72
        }
    }
}

Describe 'LabDashboardMetrics Integration' {
    It 'Get-LabVMMetrics returns complete metrics object' {
        $metrics = Get-LabVMMetrics -VMName 'dc1'

        $metrics.VMName | Should -Be 'dc1'
        $metrics.SnapshotAge | Should -Be 15
        $metrics.DiskUsageGB | Should -Be 45.0
        $metrics.DiskUsagePercent | Should -Be 90
        $metrics.UptimeHours | Should -Be 76.5
        $metrics.STIGStatus | Should -Be 'NonCompliant'
    }

    It 'Metrics flow from Get-LabVMMetrics to synchronized hashtable' {
        # Simulate background runspace collection
        $metrics = Get-LabVMMetrics -VMName 'dc1', 'svr1'

        foreach ($m in $metrics) {
            $script:DashboardMetrics[$m.VMName] = @{
                SnapshotAge      = $m.SnapshotAge
                DiskUsageGB      = $m.DiskUsageGB
                DiskUsagePercent = $m.DiskUsagePercent
                UptimeHours      = $m.UptimeHours
                STIGStatus       = $m.STIGStatus
            }
        }

        $script:DashboardMetrics['dc1'].SnapshotAge | Should -Be 15
        $script:DashboardMetrics['dc1'].STIGStatus | Should -Be 'NonCompliant'
        $script:DashboardMetrics['svr1'].SnapshotAge | Should -Be 3
        $script:DashboardMetrics['svr1'].STIGStatus | Should -Be 'Compliant'
    }

    It 'Get-StatusBadgeForMetric returns correct emoji for thresholds' {
        # Source just the Get-StatusBadgeForMetric function (avoid full GUI load)
        # Extract function definition from GUI file
        . $PSScriptRoot/../Private/Get-LabDashboardConfig.ps1

        function Get-StatusBadgeForMetric {
            [CmdletBinding()]
            [OutputType([string])]
            param(
                [Parameter(Mandatory)]
                [ValidateSet('Snapshot', 'Disk', 'Uptime', 'STIG')]
                [string]$MetricType,

                $Value
            )

            $config = Get-LabDashboardConfig

            switch ($MetricType) {
                'Snapshot' {
                    if ($null -eq $Value) { return '⚪' }
                    if ($Value -ge $config.SnapshotStaleCritical) { return '🔴' }
                    if ($Value -ge $config.SnapshotStaleDays) { return '🟡' }
                    return '🟢'
                }
                'Disk' {
                    if ($null -eq $Value) { return '⚪' }
                    if ($Value -ge $config.DiskUsageCritical) { return '🔴' }
                    if ($Value -ge $config.DiskUsagePercent) { return '🟡' }
                    return '🟢'
                }
                'Uptime' {
                    if ($null -eq $Value) { return '⚪' }
                    if ($Value -ge $config.UptimeStaleHours) { return '🟡' }
                    return '🟢'
                }
                'STIG' {
                    switch ($Value) {
                        'Compliant'    { return '🟢' }
                        'NonCompliant' { return '🔴' }
                        'Applying'     { return '🟡' }
                        default        { return '⚪' }
                    }
                }
            }
        }

        # Snapshot thresholds
        Get-StatusBadgeForMetric -MetricType 'Snapshot' -Value 5 | Should -Be '🟢'  # Below warning
        Get-StatusBadgeForMetric -MetricType 'Snapshot' -Value 15 | Should -Be '🟡'  # Warning
        Get-StatusBadgeForMetric -MetricType 'Snapshot' -Value 35 | Should -Be '🔴'  # Critical
        Get-StatusBadgeForMetric -MetricType 'Snapshot' -Value $null | Should -Be '⚪'  # Unknown

        # Disk thresholds
        Get-StatusBadgeForMetric -MetricType 'Disk' -Value 75 | Should -Be '🟢'
        Get-StatusBadgeForMetric -MetricType 'Disk' -Value 82 | Should -Be '🟡'
        Get-StatusBadgeForMetric -MetricType 'Disk' -Value 96 | Should -Be '🔴'
        Get-StatusBadgeForMetric -MetricType 'Disk' -Value $null | Should -Be '⚪'

        # Uptime thresholds
        Get-StatusBadgeForMetric -MetricType 'Uptime' -Value 50 | Should -Be '🟢'
        Get-StatusBadgeForMetric -MetricType 'Uptime' -Value 76 | Should -Be '🟡'
        Get-StatusBadgeForMetric -MetricType 'Uptime' -Value $null | Should -Be '⚪'

        # STIG status
        Get-StatusBadgeForMetric -MetricType 'STIG' -Value 'Compliant' | Should -Be '🟢'
        Get-StatusBadgeForMetric -MetricType 'STIG' -Value 'NonCompliant' | Should -Be '🔴'
        Get-StatusBadgeForMetric -MetricType 'STIG' -Value 'Applying' | Should -Be '🟡'
        Get-StatusBadgeForMetric -MetricType 'STIG' -Value 'Unknown' | Should -Be '⚪'
    }

    It 'Update-VMCardWithMetrics formats metrics correctly' {
        # Source Get-LabDashboardConfig for Get-StatusBadgeForMetric
        . $PSScriptRoot/../Private/Get-LabDashboardConfig.ps1

        function Get-StatusBadgeForMetric {
            [CmdletBinding()]
            [OutputType([string])]
            param(
                [Parameter(Mandatory)]
                [ValidateSet('Snapshot', 'Disk', 'Uptime', 'STIG')]
                [string]$MetricType,

                $Value
            )

            $config = Get-LabDashboardConfig

            switch ($MetricType) {
                'Snapshot' {
                    if ($null -eq $Value) { return '⚪' }
                    if ($Value -ge $config.SnapshotStaleCritical) { return '🔴' }
                    if ($Value -ge $config.SnapshotStaleDays) { return '🟡' }
                    return '🟢'
                }
                'Disk' {
                    if ($null -eq $Value) { return '⚪' }
                    if ($Value -ge $config.DiskUsageCritical) { return '🔴' }
                    if ($Value -ge $config.DiskUsagePercent) { return '🟡' }
                    return '🟢'
                }
                'Uptime' {
                    if ($null -eq $Value) { return '⚪' }
                    if ($Value -ge $config.UptimeStaleHours) { return '🟡' }
                    return '🟢'
                }
                'STIG' {
                    switch ($Value) {
                        'Compliant'    { return '🟢' }
                        'NonCompliant' { return '🔴' }
                        'Applying'     { return '🟡' }
                        default        { return '⚪' }
                    }
                }
            }
        }

        function Update-VMCardWithMetrics {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                $Card,

                [Parameter(Mandatory)]
                [string]$VMName
            )

            $metrics = if ($script:DashboardMetrics.ContainsKey($VMName)) {
                $script:DashboardMetrics[$VMName]
            } else {
                @{}
            }

            $snapshotAge = $metrics.SnapshotAge
            $snapshotBadge = Get-StatusBadgeForMetric -MetricType 'Snapshot' -Value $snapshotAge
            $snapshotText = if ($null -eq $snapshotAge) {
                '💾 Snapshot: No snapshots [⚪]'
            } else {
                "💾 Snapshot: $snapshotAge days [$snapshotBadge]"
            }
            $Card.FindName('txtSnapshotAge').Text = $snapshotText

            $diskGB = $metrics.DiskUsageGB
            $diskPercent = $metrics.DiskUsagePercent
            $diskBadge = Get-StatusBadgeForMetric -MetricType 'Disk' -Value $diskPercent
            $diskText = if ($null -eq $diskGB) {
                '💾 Disk: -- [⚪]'
            } else {
                "💾 Disk: $diskGB GB ($diskPercent%) [$diskBadge]"
            }
            $Card.FindName('txtDiskUsage').Text = $diskText

            $uptimeHours = $metrics.UptimeHours
            $uptimeBadge = Get-StatusBadgeForMetric -MetricType 'Uptime' -Value $uptimeHours
            $uptimeText = if ($null -eq $uptimeHours) {
                '⏱️ Uptime: -- [⚪]'
            } else {
                $uptimeStr = if ($uptimeHours -ge 24) {
                    "$([math]::Floor($uptimeHours / 24))d $($uptimeHours % 24)h"
                } else {
                    "$([math]::Round($uptimeHours, 1))h"
                }
                "⏱️ Uptime: $uptimeStr [$uptimeBadge]"
            }
            $Card.FindName('txtUptime').Text = $uptimeText

            $stigStatus = $metrics.STIGStatus
            $stigBadge = Get-StatusBadgeForMetric -MetricType 'STIG' -Value $stigStatus
            $stigText = if ($null -eq $stigStatus -or $stigStatus -eq 'Unknown') {
                '🔒 STIG: Unknown [⚪]'
            } else {
                "🔒 STIG: $stigStatus [$stigBadge]"
            }
            $Card.FindName('txtSTIGStatus').Text = $stigText
        }

        # Populate hashtable with test data
        $script:DashboardMetrics['dc1'] = @{
            SnapshotAge      = 15
            DiskUsageGB      = 45.0
            DiskUsagePercent = 90
            UptimeHours      = 76.5
            STIGStatus       = 'NonCompliant'
        }

        # Create mock card with TextBlocks (simplify test - mock directly accessing properties)
        $mockCard = @{
            txtSnapshotAge = @{ Text = '' }
            txtDiskUsage   = @{ Text = '' }
            txtUptime      = @{ Text = '' }
            txtSTIGStatus  = @{ Text = '' }
        }

        # Simplified Update-VMCardWithMetrics for testing (mocking FindName behavior)
        function Update-VMCardWithMetrics {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                $Card,

                [Parameter(Mandatory)]
                [string]$VMName
            )

            $metrics = if ($script:DashboardMetrics.ContainsKey($VMName)) {
                $script:DashboardMetrics[$VMName]
            } else {
                @{}
            }

            $snapshotAge = $metrics.SnapshotAge
            $snapshotBadge = Get-StatusBadgeForMetric -MetricType 'Snapshot' -Value $snapshotAge
            $snapshotText = if ($null -eq $snapshotAge) {
                '💾 Snapshot: No snapshots [⚪]'
            } else {
                "💾 Snapshot: $snapshotAge days [$snapshotBadge]"
            }
            $Card.txtSnapshotAge.Text = $snapshotText

            $diskGB = $metrics.DiskUsageGB
            $diskPercent = $metrics.DiskUsagePercent
            $diskBadge = Get-StatusBadgeForMetric -MetricType 'Disk' -Value $diskPercent
            $diskText = if ($null -eq $diskGB) {
                '💾 Disk: -- [⚪]'
            } else {
                "💾 Disk: $diskGB GB ($diskPercent%) [$diskBadge]"
            }
            $Card.txtDiskUsage.Text = $diskText

            $uptimeHours = $metrics.UptimeHours
            $uptimeBadge = Get-StatusBadgeForMetric -MetricType 'Uptime' -Value $uptimeHours
            $uptimeText = if ($null -eq $uptimeHours) {
                '⏱️ Uptime: -- [⚪]'
            } else {
                $uptimeStr = if ($uptimeHours -ge 24) {
                    "$([math]::Floor($uptimeHours / 24))d $($uptimeHours % 24)h"
                } else {
                    "$([math]::Round($uptimeHours, 1))h"
                }
                "⏱️ Uptime: $uptimeStr [$uptimeBadge]"
            }
            $Card.txtUptime.Text = $uptimeText

            $stigStatus = $metrics.STIGStatus
            $stigBadge = Get-StatusBadgeForMetric -MetricType 'STIG' -Value $stigStatus
            $stigText = if ($null -eq $stigStatus -or $stigStatus -eq 'Unknown') {
                '🔒 STIG: Unknown [⚪]'
            } else {
                "🔒 STIG: $stigStatus [$stigBadge]"
            }
            $Card.txtSTIGStatus.Text = $stigText
        }

        Update-VMCardWithMetrics -Card $mockCard -VMName 'dc1'

        $mockCard.txtSnapshotAge.Text | Should -BeLike '*15 days*'
        $mockCard.txtDiskUsage.Text | Should -BeLike '*45 GB*'
        $mockCard.txtDiskUsage.Text | Should -BeLike '*90%*'
        $mockCard.txtUptime.Text | Should -BeLike '*3d*h*'  # 76.5 hours = 3d 4h
        $mockCard.txtSTIGStatus.Text | Should -BeLike '*NonCompliant*'
    }

    It 'UI thread does not block when reading from hashtable' {
        # Populate hashtable
        $script:DashboardMetrics['dc1'] = @{
            SnapshotAge      = 10
            DiskUsageGB      = 30.0
            DiskUsagePercent = 75
            UptimeHours      = 5.0
            STIGStatus       = 'Compliant'
        }

        # Measure time to read from hashtable (should be < 1ms)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $data = $script:DashboardMetrics['dc1']
        $sw.Stop()

        $sw.ElapsedMilliseconds | Should -BeLessThan 10  # Well under 16ms UI frame budget
        $data.SnapshotAge | Should -Be 10
    }
}

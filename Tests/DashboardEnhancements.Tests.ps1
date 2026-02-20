# Pester tests for Dashboard Enhancements (DASH-01, DASH-02, DASH-03)
# Covers health state logic, resource summary, and bulk action wiring.

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $guiScriptPath = Join-Path $repoRoot 'GUI/Start-OpenCodeLabGUI.ps1'
    $dashboardXamlPath = Join-Path $repoRoot 'GUI/Views/DashboardView.xaml'

    # Read source files once for structural tests
    $guiSource = Get-Content -Path $guiScriptPath -Raw
    $dashboardXaml = [xml](Get-Content -Path $dashboardXamlPath -Raw)

    # Extract Get-LabHealthState function from source using brace counting
    $funcStart = $guiSource.IndexOf('function Get-LabHealthState')
    if ($funcStart -lt 0) { throw 'Get-LabHealthState not found in GUI script' }

    $braceCount = 0
    $funcEnd = -1
    $foundFirst = $false
    for ($i = $funcStart; $i -lt $guiSource.Length; $i++) {
        if ($guiSource[$i] -eq '{') {
            $braceCount++
            $foundFirst = $true
        }
        elseif ($guiSource[$i] -eq '}') {
            $braceCount--
            if ($foundFirst -and $braceCount -eq 0) {
                $funcEnd = $i + 1
                break
            }
        }
    }

    if ($funcEnd -lt 0) { throw 'Could not find closing brace for Get-LabHealthState' }

    $funcBlock = $guiSource.Substring($funcStart, $funcEnd - $funcStart)
    # Define the function in the test scope
    Invoke-Expression $funcBlock
}

Describe 'Dashboard Enhancements' {

    Context 'Get-LabHealthState logic (DASH-01)' {

        It 'returns No Lab when VMStatuses is null' {
            $result = Get-LabHealthState -VMStatuses $null
            $result.State | Should -Be 'No Lab'
            $result.Detail | Should -BeLike '*No VMs*'
        }

        It 'returns No Lab when VMStatuses is empty array' {
            $result = Get-LabHealthState -VMStatuses @()
            $result.State | Should -Be 'No Lab'
        }

        It 'returns Healthy when all VMs are running' {
            $mockVMs = @(
                [PSCustomObject]@{ VMName = 'dc1'; State = 'Running' }
                [PSCustomObject]@{ VMName = 'svr1'; State = 'Running' }
                [PSCustomObject]@{ VMName = 'ws1'; State = 'Running' }
            )
            $result = Get-LabHealthState -VMStatuses $mockVMs
            $result.State | Should -Be 'Healthy'
            $result.Detail | Should -Be '3 of 3 VMs running'
        }

        It 'returns Degraded when some VMs are off' {
            $mockVMs = @(
                [PSCustomObject]@{ VMName = 'dc1'; State = 'Running' }
                [PSCustomObject]@{ VMName = 'svr1'; State = 'Off' }
            )
            $result = Get-LabHealthState -VMStatuses $mockVMs
            $result.State | Should -Be 'Degraded'
            $result.Detail | Should -Be '1 of 2 VMs running'
        }

        It 'returns Offline when no VMs are running' {
            $mockVMs = @(
                [PSCustomObject]@{ VMName = 'dc1'; State = 'Off' }
                [PSCustomObject]@{ VMName = 'svr1'; State = 'Off' }
                [PSCustomObject]@{ VMName = 'ws1'; State = 'Off' }
            )
            $result = Get-LabHealthState -VMStatuses $mockVMs
            $result.State | Should -Be 'Offline'
            $result.Detail | Should -Be '0 of 3 VMs running'
        }

        It 'treats Paused and Saved as non-running (Degraded)' {
            $mockVMs = @(
                [PSCustomObject]@{ VMName = 'dc1'; State = 'Running' }
                [PSCustomObject]@{ VMName = 'svr1'; State = 'Paused' }
                [PSCustomObject]@{ VMName = 'ws1'; State = 'Saved' }
            )
            $result = Get-LabHealthState -VMStatuses $mockVMs
            $result.State | Should -Be 'Degraded'
            $result.Detail | Should -Be '1 of 3 VMs running'
        }

        It 'returns correct detail format with running count and total' {
            $mockVMs = @(
                [PSCustomObject]@{ VMName = 'dc1'; State = 'Running' }
                [PSCustomObject]@{ VMName = 'svr1'; State = 'Running' }
                [PSCustomObject]@{ VMName = 'ws1'; State = 'Off' }
                [PSCustomObject]@{ VMName = 'lin1'; State = 'Off' }
            )
            $result = Get-LabHealthState -VMStatuses $mockVMs
            $result.Detail | Should -Match '^\d+ of \d+ VMs running$'
        }

        It 'works with a single running VM' {
            $mockVMs = @(
                [PSCustomObject]@{ VMName = 'dc1'; State = 'Running' }
            )
            $result = Get-LabHealthState -VMStatuses $mockVMs
            $result.State | Should -Be 'Healthy'
            $result.Detail | Should -Be '1 of 1 VMs running'
        }
    }

    Context 'Health banner source structure (DASH-01)' {

        It 'source contains healthBanner FindName resolution' {
            $guiSource | Should -Match 'FindName\(.+healthBanner.+\)'
        }

        It 'source contains health state color mapping for Healthy state' {
            $guiSource | Should -Match "'Healthy'"
        }

        It 'source contains health state color mapping for Degraded state' {
            $guiSource | Should -Match "'Degraded'"
        }

        It 'source contains health state color mapping for Offline state' {
            $guiSource | Should -Match "'Offline'"
        }

        It 'source sets healthBanner.Background based on state' {
            $guiSource | Should -Match '\$healthBanner\.Background\s*='
        }
    }

    Context 'Resource summary source structure (DASH-02)' {

        It 'source contains txtRAMUsage element resolution' {
            $guiSource | Should -Match 'FindName\(.+txtRAMUsage.+\)'
        }

        It 'source contains txtCPUUsage element resolution' {
            $guiSource | Should -Match 'FindName\(.+txtCPUUsage.+\)'
        }

        It 'source references Get-LabHostResourceInfo' {
            $guiSource | Should -Match 'Get-LabHostResourceInfo'
        }
    }

    Context 'DashboardView.xaml structure (DASH-01, DASH-02, DASH-03)' {

        It 'DashboardView.xaml contains healthBanner element' {
            $node = $dashboardXaml.SelectSingleNode('//*[@Name="healthBanner"]', $null)
            if (-not $node) {
                # Try with namespace-unaware approach
                $raw = Get-Content -Path $dashboardXamlPath -Raw
                $raw | Should -Match 'x:Name="healthBanner"'
            }
        }

        It 'DashboardView.xaml contains txtHealthState element' {
            $raw = Get-Content -Path $dashboardXamlPath -Raw
            $raw | Should -Match 'x:Name="txtHealthState"'
        }

        It 'DashboardView.xaml contains txtHealthDetail element' {
            $raw = Get-Content -Path $dashboardXamlPath -Raw
            $raw | Should -Match 'x:Name="txtHealthDetail"'
        }

        It 'DashboardView.xaml contains txtRAMUsage element' {
            $raw = Get-Content -Path $dashboardXamlPath -Raw
            $raw | Should -Match 'x:Name="txtRAMUsage"'
        }

        It 'DashboardView.xaml contains txtCPUUsage element' {
            $raw = Get-Content -Path $dashboardXamlPath -Raw
            $raw | Should -Match 'x:Name="txtCPUUsage"'
        }

        It 'DashboardView.xaml contains btnStartAll element' {
            $raw = Get-Content -Path $dashboardXamlPath -Raw
            $raw | Should -Match 'x:Name="btnStartAll"'
        }

        It 'DashboardView.xaml contains btnStopAll element' {
            $raw = Get-Content -Path $dashboardXamlPath -Raw
            $raw | Should -Match 'x:Name="btnStopAll"'
        }

        It 'DashboardView.xaml contains btnSaveCheckpoint element' {
            $raw = Get-Content -Path $dashboardXamlPath -Raw
            $raw | Should -Match 'x:Name="btnSaveCheckpoint"'
        }
    }

    Context 'Bulk action source structure (DASH-03)' {

        It 'source contains btnStartAll click handler wiring' {
            $guiSource | Should -Match '\$btnStartAll\.Add_Click'
        }

        It 'source contains btnStopAll click handler wiring' {
            $guiSource | Should -Match '\$btnStopAll\.Add_Click'
        }

        It 'source contains btnSaveCheckpoint click handler wiring' {
            $guiSource | Should -Match '\$btnSaveCheckpoint\.Add_Click'
        }

        It 'source contains Start-VM call in bulk handler context' {
            # Verify Start-VM is called inside a bulk action handler
            $guiSource | Should -Match 'Start-VM\s+-Name'
        }

        It 'source contains Stop-VM call' {
            $guiSource | Should -Match 'Stop-VM\s+-Name'
        }

        It 'source contains Checkpoint-VM call' {
            $guiSource | Should -Match 'Checkpoint-VM\s+-Name'
        }
    }
}

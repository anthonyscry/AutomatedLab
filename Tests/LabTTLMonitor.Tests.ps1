# Invoke-LabTTLMonitor tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Get-LabTTLConfig.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabTTLMonitor.ps1')
}

Describe 'Invoke-LabTTLMonitor' {
    BeforeEach {
        # Track VM action calls
        $script:saveVMCalls = [System.Collections.Generic.List[string]]::new()
        $script:stopVMCalls = [System.Collections.Generic.List[string]]::new()
        $script:stateWritten = $null
        $script:stateWritePath = $null

        # Default config: TTL disabled
        $script:mockConfig = [pscustomobject]@{
            Enabled        = $false
            IdleMinutes    = 0
            WallClockHours = 8
            Action         = 'Suspend'
        }

        # Default VMs: empty
        $script:mockVMs = @()

        # Stub functions
        function Get-LabTTLConfig { return $script:mockConfig }

        function Get-VM {
            param($ErrorAction)
            return $script:mockVMs
        }

        function Save-VM {
            param([string]$Name, $ErrorAction)
            $script:saveVMCalls.Add($Name)
        }

        function Stop-VM {
            param([string]$Name, [switch]$Force, $ErrorAction)
            $script:stopVMCalls.Add($Name)
        }

        function Set-Content {
            param([string]$Path, $Value, $Encoding)
            $script:stateWritePath = $Path
            $script:stateWritten = $Value
        }

        function Get-Content {
            param([string]$Path, [switch]$Raw, $ErrorAction)
            return $null
        }

        # Clean up GlobalLabConfig
        if (Test-Path variable:GlobalLabConfig) {
            Remove-Variable -Name GlobalLabConfig -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'returns no-op result when TTL is disabled' {
        $script:mockConfig = [pscustomobject]@{
            Enabled = $false; IdleMinutes = 0; WallClockHours = 8; Action = 'Suspend'
        }

        $result = Invoke-LabTTLMonitor -StatePath '/tmp/test-ttl-state.json'

        $result.TTLExpired | Should -BeFalse
        $result.ActionAttempted | Should -Be 'None'
        $result.ActionSucceeded | Should -BeFalse
        $result.VMsProcessed | Should -HaveCount 0
    }

    It 'returns no-op when no lab VMs exist' {
        $script:mockConfig = [pscustomobject]@{
            Enabled = $true; IdleMinutes = 0; WallClockHours = 8; Action = 'Suspend'
        }
        $script:mockVMs = @()

        $result = Invoke-LabTTLMonitor -StatePath '/tmp/test-ttl-state.json'

        $result.TTLExpired | Should -BeFalse
        $result.VMsProcessed | Should -HaveCount 0
    }

    It 'detects wall-clock expiry when elapsed hours exceed WallClockHours' {
        $script:mockConfig = [pscustomobject]@{
            Enabled = $true; IdleMinutes = 0; WallClockHours = 1; Action = 'Suspend'
        }
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running'; Uptime = (New-TimeSpan -Hours 2) }
        )

        # Start time 2 hours ago
        $startTime = (Get-Date).AddHours(-2)
        $result = Invoke-LabTTLMonitor -StatePath '/tmp/test-ttl-state.json' -LabStartTime $startTime

        $result.TTLExpired | Should -BeTrue
        $script:saveVMCalls | Should -HaveCount 1
    }

    It 'does NOT trigger when wall-clock is within limit' {
        $script:mockConfig = [pscustomobject]@{
            Enabled = $true; IdleMinutes = 0; WallClockHours = 8; Action = 'Suspend'
        }
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running'; Uptime = (New-TimeSpan -Minutes 30) }
        )

        $startTime = (Get-Date).AddMinutes(-30)
        $result = Invoke-LabTTLMonitor -StatePath '/tmp/test-ttl-state.json' -LabStartTime $startTime

        $result.TTLExpired | Should -BeFalse
        $script:saveVMCalls | Should -HaveCount 0
    }

    It 'detects idle expiry when all VMs have been running beyond IdleMinutes threshold' {
        $script:mockConfig = [pscustomobject]@{
            Enabled = $true; IdleMinutes = 30; WallClockHours = 100; Action = 'Suspend'
        }
        # VM has been running for 60 minutes (beyond 30-min idle threshold)
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running'; Uptime = (New-TimeSpan -Minutes 60) }
        )

        $startTime = (Get-Date).AddMinutes(-10)
        $result = Invoke-LabTTLMonitor -StatePath '/tmp/test-ttl-state.json' -LabStartTime $startTime

        $result.TTLExpired | Should -BeTrue
    }

    It 'does NOT trigger idle when IdleMinutes is 0 (disabled)' {
        $script:mockConfig = [pscustomobject]@{
            Enabled = $true; IdleMinutes = 0; WallClockHours = 100; Action = 'Suspend'
        }
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running'; Uptime = (New-TimeSpan -Hours 5) }
        )

        $startTime = (Get-Date).AddMinutes(-10)
        $result = Invoke-LabTTLMonitor -StatePath '/tmp/test-ttl-state.json' -LabStartTime $startTime

        $result.TTLExpired | Should -BeFalse
    }

    It 'calls Save-VM on each running VM when Action is Suspend and TTL expired' {
        $script:mockConfig = [pscustomobject]@{
            Enabled = $true; IdleMinutes = 0; WallClockHours = 1; Action = 'Suspend'
        }
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running'; Uptime = (New-TimeSpan -Hours 2) }
            [pscustomobject]@{ Name = 'svr1'; State = 'Running'; Uptime = (New-TimeSpan -Hours 2) }
        )

        $startTime = (Get-Date).AddHours(-2)
        $result = Invoke-LabTTLMonitor -StatePath '/tmp/test-ttl-state.json' -LabStartTime $startTime

        $script:saveVMCalls | Should -HaveCount 2
        $script:saveVMCalls | Should -Contain 'dc1'
        $script:saveVMCalls | Should -Contain 'svr1'
        $result.ActionAttempted | Should -Be 'Suspend'
    }

    It 'calls Stop-VM on each running VM when Action is Off and TTL expired' {
        $script:mockConfig = [pscustomobject]@{
            Enabled = $true; IdleMinutes = 0; WallClockHours = 1; Action = 'Off'
        }
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running'; Uptime = (New-TimeSpan -Hours 2) }
        )

        $startTime = (Get-Date).AddHours(-2)
        $result = Invoke-LabTTLMonitor -StatePath '/tmp/test-ttl-state.json' -LabStartTime $startTime

        $script:stopVMCalls | Should -HaveCount 1
        $script:stopVMCalls | Should -Contain 'dc1'
        $result.ActionAttempted | Should -Be 'Off'
    }

    It 'skips VMs not in Running state' {
        $script:mockConfig = [pscustomobject]@{
            Enabled = $true; IdleMinutes = 0; WallClockHours = 1; Action = 'Suspend'
        }
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running'; Uptime = (New-TimeSpan -Hours 2) }
            [pscustomobject]@{ Name = 'svr1'; State = 'Saved'; Uptime = (New-TimeSpan -Hours 0) }
            [pscustomobject]@{ Name = 'ws1'; State = 'Off'; Uptime = (New-TimeSpan -Hours 0) }
        )

        $startTime = (Get-Date).AddHours(-2)
        $result = Invoke-LabTTLMonitor -StatePath '/tmp/test-ttl-state.json' -LabStartTime $startTime

        $script:saveVMCalls | Should -HaveCount 1
        $script:saveVMCalls | Should -Contain 'dc1'
    }

    It 'returns audit result with expected fields' {
        $script:mockConfig = [pscustomobject]@{
            Enabled = $true; IdleMinutes = 0; WallClockHours = 1; Action = 'Suspend'
        }
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running'; Uptime = (New-TimeSpan -Hours 2) }
        )

        $startTime = (Get-Date).AddHours(-2)
        $result = Invoke-LabTTLMonitor -StatePath '/tmp/test-ttl-state.json' -LabStartTime $startTime

        $result.PSObject.Properties.Name | Should -Contain 'TTLExpired'
        $result.PSObject.Properties.Name | Should -Contain 'ActionAttempted'
        $result.PSObject.Properties.Name | Should -Contain 'ActionSucceeded'
        $result.PSObject.Properties.Name | Should -Contain 'VMsProcessed'
        $result.PSObject.Properties.Name | Should -Contain 'RemainingIssues'
        $result.PSObject.Properties.Name | Should -Contain 'DurationSeconds'
    }

    It 'writes state JSON to configured path after each check' {
        $script:mockConfig = [pscustomobject]@{
            Enabled = $true; IdleMinutes = 0; WallClockHours = 8; Action = 'Suspend'
        }
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running'; Uptime = (New-TimeSpan -Minutes 30) }
        )

        $startTime = (Get-Date).AddMinutes(-30)
        Invoke-LabTTLMonitor -StatePath '/tmp/test-ttl-state.json' -LabStartTime $startTime | Out-Null

        $script:stateWritePath | Should -Be '/tmp/test-ttl-state.json'
        $script:stateWritten | Should -Not -BeNullOrEmpty
    }

    It 'handles Save-VM failure gracefully and continues other VMs' {
        $script:mockConfig = [pscustomobject]@{
            Enabled = $true; IdleMinutes = 0; WallClockHours = 1; Action = 'Suspend'
        }
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running'; Uptime = (New-TimeSpan -Hours 2) }
            [pscustomobject]@{ Name = 'svr1'; State = 'Running'; Uptime = (New-TimeSpan -Hours 2) }
        )

        # Override Save-VM to fail on dc1
        function Save-VM {
            param([string]$Name, $ErrorAction)
            if ($Name -eq 'dc1') { throw "VM locked" }
            $script:saveVMCalls.Add($Name)
        }

        $startTime = (Get-Date).AddHours(-2)
        $result = Invoke-LabTTLMonitor -StatePath '/tmp/test-ttl-state.json' -LabStartTime $startTime -WarningAction SilentlyContinue

        $result.RemainingIssues | Should -HaveCount 1
        $result.RemainingIssues[0] | Should -Match 'dc1'
        $result.ActionSucceeded | Should -BeFalse
        # svr1 should still be processed
        $script:saveVMCalls | Should -Contain 'svr1'
    }

    It 'either trigger (wall-clock OR idle) causes expiry' {
        # Wall clock OK (100h limit) but idle fires (30 min, VM has 60 min uptime)
        $script:mockConfig = [pscustomobject]@{
            Enabled = $true; IdleMinutes = 30; WallClockHours = 100; Action = 'Suspend'
        }
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running'; Uptime = (New-TimeSpan -Minutes 60) }
        )

        $startTime = (Get-Date).AddMinutes(-10)
        $result = Invoke-LabTTLMonitor -StatePath '/tmp/test-ttl-state.json' -LabStartTime $startTime

        $result.TTLExpired | Should -BeTrue
        $script:saveVMCalls | Should -HaveCount 1
    }
}

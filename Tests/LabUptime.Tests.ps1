# Get-LabUptime tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Get-LabTTLConfig.ps1')
    . (Join-Path $repoRoot 'Public/Get-LabUptime.ps1')
}

Describe 'Get-LabUptime' {
    BeforeEach {
        $script:mockVMs = @()
        $script:mockConfig = [pscustomobject]@{
            Enabled = $false; IdleMinutes = 0; WallClockHours = 8; Action = 'Suspend'
        }

        function Get-VM {
            param($ErrorAction)
            return $script:mockVMs
        }

        function Get-LabTTLConfig { return $script:mockConfig }

        function Get-Content {
            param([string]$Path, [switch]$Raw, $ErrorAction)
            return $null
        }

        if (Test-Path variable:GlobalLabConfig) {
            Remove-Variable -Name GlobalLabConfig -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'returns empty array when no lab is running' {
        $script:mockVMs = @()

        $result = Get-LabUptime -StatePath '/tmp/nonexistent.json'

        $result | Should -HaveCount 0
    }

    It 'returns PSCustomObject with correct fields' {
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running' }
        )

        $result = Get-LabUptime -StatePath '/tmp/nonexistent.json'

        $result.PSObject.Properties.Name | Should -Contain 'LabName'
        $result.PSObject.Properties.Name | Should -Contain 'StartTime'
        $result.PSObject.Properties.Name | Should -Contain 'ElapsedHours'
        $result.PSObject.Properties.Name | Should -Contain 'TTLConfigured'
        $result.PSObject.Properties.Name | Should -Contain 'TTLRemainingMinutes'
        $result.PSObject.Properties.Name | Should -Contain 'Action'
        $result.PSObject.Properties.Name | Should -Contain 'Status'
    }

    It 'ElapsedHours is rounded to 1 decimal place' {
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running' }
        )

        $result = Get-LabUptime -StatePath '/tmp/nonexistent.json'

        # ElapsedHours should be a number with at most 1 decimal
        $result.ElapsedHours | Should -BeOfType [double]
        $decimalPart = $result.ElapsedHours.ToString() -replace '^\d+\.?', ''
        $decimalPart.Length | Should -BeLessOrEqual 1
    }

    It 'TTLRemainingMinutes is -1 when TTL not configured' {
        $script:mockConfig = [pscustomobject]@{
            Enabled = $false; IdleMinutes = 0; WallClockHours = 8; Action = 'Suspend'
        }
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running' }
        )

        $result = Get-LabUptime -StatePath '/tmp/nonexistent.json'

        $result.TTLRemainingMinutes | Should -Be -1
    }

    It 'TTLRemainingMinutes calculated correctly when TTL configured' {
        $script:mockConfig = [pscustomobject]@{
            Enabled = $true; IdleMinutes = 0; WallClockHours = 8; Action = 'Suspend'
        }
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running' }
        )

        # No cached state, so start time will be ~now, remaining should be ~480 min
        $result = Get-LabUptime -StatePath '/tmp/nonexistent.json'

        $result.TTLRemainingMinutes | Should -BeGreaterOrEqual 470
        $result.TTLRemainingMinutes | Should -BeLessOrEqual 480
    }

    It 'Status is Active when lab running and TTL not expired' {
        $script:mockConfig = [pscustomobject]@{
            Enabled = $true; IdleMinutes = 0; WallClockHours = 8; Action = 'Suspend'
        }
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running' }
        )

        $result = Get-LabUptime -StatePath '/tmp/nonexistent.json'

        $result.Status | Should -Be 'Active'
    }

    It 'Status is Expired when TTL has expired' {
        $script:mockConfig = [pscustomobject]@{
            Enabled = $true; IdleMinutes = 0; WallClockHours = 8; Action = 'Suspend'
        }
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running' }
        )

        # Mock cached state with expired TTL
        $cachedState = @{
            StartTime  = (Get-Date).AddHours(-10).ToString('o')
            TTLExpired = $true
        } | ConvertTo-Json

        function Get-Content {
            param([string]$Path, [switch]$Raw, $ErrorAction)
            return $cachedState
        }

        # Need Test-Path to return true for state path
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            $cachedState | Set-Content -Path $tempFile
            # Override Get-Content to return the cached state for this path
            function Get-Content {
                param([string]$Path, [switch]$Raw, $ErrorAction)
                return $cachedState
            }

            $result = Get-LabUptime -StatePath $tempFile

            $result.Status | Should -Be 'Expired'
        }
        finally {
            Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
        }
    }

    It 'Status is Disabled when TTL feature is disabled' {
        $script:mockConfig = [pscustomobject]@{
            Enabled = $false; IdleMinutes = 0; WallClockHours = 8; Action = 'Suspend'
        }
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running' }
        )

        $result = Get-LabUptime -StatePath '/tmp/nonexistent.json'

        $result.Status | Should -Be 'Disabled'
    }

    It 'reads from cached state JSON when available' {
        $script:mockConfig = [pscustomobject]@{
            Enabled = $true; IdleMinutes = 0; WallClockHours = 8; Action = 'Suspend'
        }
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running' }
        )

        $knownStart = (Get-Date).AddHours(-2)
        $cachedState = @{
            StartTime  = $knownStart.ToString('o')
            TTLExpired = $false
        } | ConvertTo-Json

        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            $cachedState | Set-Content -Path $tempFile

            function Get-Content {
                param([string]$Path, [switch]$Raw, $ErrorAction)
                return $cachedState
            }

            $result = Get-LabUptime -StatePath $tempFile

            # Should show ~2 hours elapsed
            $result.ElapsedHours | Should -BeGreaterOrEqual 1.9
            $result.ElapsedHours | Should -BeLessOrEqual 2.1
        }
        finally {
            Remove-Item -Path $tempFile -ErrorAction SilentlyContinue
        }
    }

    It 'falls back to live VM query when state JSON missing' {
        $script:mockConfig = [pscustomobject]@{
            Enabled = $true; IdleMinutes = 0; WallClockHours = 8; Action = 'Suspend'
        }
        $script:mockVMs = @(
            [pscustomobject]@{ Name = 'dc1'; State = 'Running' }
        )

        # No state file exists
        $result = Get-LabUptime -StatePath '/tmp/definitely-no-file-here.json'

        # Should still return result (falls back to current time as start)
        $result.ElapsedHours | Should -BeLessOrEqual 0.1
        $result.Status | Should -Be 'Active'
    }
}

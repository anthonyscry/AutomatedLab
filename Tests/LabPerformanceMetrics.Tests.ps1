Describe 'LabPerformanceMetrics' {
    BeforeAll {
        $modulePath = $PSScriptRoot | Split-Path | Join-Path -ChildPath "SimpleLab.psd1"
        Import-Module $modulePath -Force

        $repoRoot = Split-Path -Parent $PSScriptRoot

        . "$repoRoot\Private\Get-LabPerformanceConfig.ps1"
        . "$repoRoot\Private\Write-LabPerformanceMetric.ps1"

        $testStoragePath = Join-Path $TestDrive 'test-performance.json'
    }

    BeforeEach {
        if (Test-Path $testStoragePath) {
            Remove-Item $testStoragePath -Force
        }

        $originalConfig = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig.Clone() } else { $null }
        $GlobalLabConfig = @{
            Performance = @{
                Enabled       = $true
                StoragePath   = $testStoragePath
                RetentionDays = 90
            }
        }
    }

    AfterEach {
        if (Test-Path $testStoragePath) {
            Remove-Item $testStoragePath -Force
        }

        if ($null -ne $originalConfig) {
            $GlobalLabConfig = $originalConfig
        }
    }

    Context 'Get-LabPerformanceConfig' {
        It 'Returns performance configuration when Performance block exists' {
            $config = Get-LabPerformanceConfig

            $config.Enabled | Should -BeTrue
            $config.StoragePath | Should -Be $testStoragePath
            $config.RetentionDays | Should -Be 90
        }

        It 'Returns safe defaults when Performance block is missing' {
            $GlobalLabConfig = @{}

            $config = Get-LabPerformanceConfig

            $config.Enabled | Should -BeTrue
            $config.StoragePath | Should -Be '.planning/performance-metrics.json'
            $config.RetentionDays | Should -Be 90
        }

        It 'Returns safe defaults when Performance block is empty' {
            $GlobalLabConfig = @{ Performance = @{} }

            $config = Get-LabPerformanceConfig

            $config.Enabled | Should -BeTrue
            $config.StoragePath | Should -Be '.planning/performance-metrics.json'
            $config.RetentionDays | Should -Be 90
        }

        It 'Uses ContainsKey guards to prevent StrictMode failures' {
            Set-StrictMode -Version Latest

            $GlobalLabConfig = @{ Performance = @{ Enabled = $false } }

            $config = Get-LabPerformanceConfig

            $config.Enabled | Should -BeFalse
            $config.StoragePath | Should -Be '.planning/performance-metrics.json'
        }
    }

    Context 'Write-LabPerformanceMetric' {
        It 'Creates storage directory if it does not exist' {
            $nestedPath = Join-Path $TestDrive 'nested\dir\metrics.json'
            $GlobalLabConfig.Performance.StoragePath = $nestedPath

            Write-LabPerformanceMetric -Operation 'VMStart' -VMName 'dc1' -Duration 1000 -Success $true

            Test-Path (Split-Path $nestedPath) | Should -BeTrue
        }

        It 'Writes metric to new storage file' {
            Write-LabPerformanceMetric -Operation 'VMStart' -VMName 'dc1' -Duration 15234 -Success $true

            Test-Path $testStoragePath | Should -BeTrue

            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $data.metrics.Count | Should -Be 1
            $data.metrics[0].Operation | Should -Be 'VMStart'
            $data.metrics[0].VMName | Should -Be 'dc1'
            $data.metrics[0].Duration | Should -Be 15234
            $data.metrics[0].Success | Should -BeTrue
        }

        It 'Appends metric to existing storage file' {
            Write-LabPerformanceMetric -Operation 'VMStart' -VMName 'dc1' -Duration 1000 -Success $true
            Write-LabPerformanceMetric -Operation 'VMStop' -VMName 'dc1' -Duration 500 -Success $true

            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $data.metrics.Count | Should -Be 2
        }

        It 'Includes metadata when provided' {
            $metadata = @{ MemoryGB = 4; Processors = 2 }
            Write-LabPerformanceMetric -Operation 'VMStart' -VMName 'svr1' -Duration 8000 -Success $true -Metadata $metadata

            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $data.metrics[0].Metadata.MemoryGB | Should -Be 4
            $data.metrics[0].Metadata.Processors | Should -Be 2
        }

        It 'Handles empty VM name for lab-wide operations' {
            Write-LabPerformanceMetric -Operation 'LabDeploy' -VMName '' -Duration 300000 -Success $true

            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $data.metrics[0].VMName | Should -Be ''
        }

        It 'Does not write when performance tracking is disabled' {
            $GlobalLabConfig.Performance.Enabled = $false

            Write-LabPerformanceMetric -Operation 'VMStart' -VMName 'dc1' -Duration 1000 -Success $true

            Test-Path $testStoragePath | Should -BeFalse
        }

        It 'Logs warning but does not throw on write failure' {
            Mock -CommandName Set-Content -MockWith { throw "Access denied" }

            { Write-LabPerformanceMetric -Operation 'VMStart' -VMName 'dc1' -Duration 1000 -Success $true } | Should -Not -Throw
        }
    }

    Context 'Invoke-LabPerformanceRetention' {
        It 'Removes metrics older than retention period' {
            $oldDate = (Get-Date).AddDays(-100).ToString('o')
            $newDate = (Get-Date).AddDays(-1).ToString('o')

            $metrics = @(
                @{ Timestamp = $oldDate; Operation = 'VMStart'; VMName = 'old'; Duration = 1000; Success = $true; Metadata = $null; Host = 'TEST' }
                @{ Timestamp = $newDate; Operation = 'VMStart'; VMName = 'new'; Duration = 1000; Success = $true; Metadata = $null; Host = 'TEST' }
            )

            @{ metrics = $metrics } | ConvertTo-Json -Depth 8 | Set-Content $testStoragePath

            Invoke-LabPerformanceRetention -StoragePath $testStoragePath -RetentionDays 90

            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $data.metrics.Count | Should -Be 1
            $data.metrics[0].VMName | Should -Be 'new'
        }

        It 'Does not remove any metrics when retention is zero' {
            $oldDate = (Get-Date).AddDays(-100).ToString('o')

            $metrics = @(
                @{ Timestamp = $oldDate; Operation = 'VMStart'; VMName = 'old'; Duration = 1000; Success = $true; Metadata = $null; Host = 'TEST' }
            )

            @{ metrics = $metrics } | ConvertTo-Json -Depth 8 | Set-Content $testStoragePath

            Invoke-LabPerformanceRetention -StoragePath $testStoragePath -RetentionDays 0

            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $data.metrics.Count | Should -Be 1
        }

        It 'Handles missing storage file gracefully' {
            { Invoke-LabPerformanceRetention -StoragePath $testStoragePath -RetentionDays 90 } | Should -Not -Throw
        }
    }
}

Describe 'Measure-LabVMOperation' {
    BeforeAll {
        $modulePath = $PSScriptRoot | Split-Path | Join-Path -ChildPath "SimpleLab.psd1"
        Import-Module $modulePath -Force

        $repoRoot = Split-Path -Parent $PSScriptRoot

        # Dot-source private helpers needed for tests
        . "$repoRoot\Private\Get-LabPerformanceConfig.ps1"
        . "$repoRoot\Private\Write-LabPerformanceMetric.ps1"
        . "$repoRoot\Public\Measure-LabVMOperation.ps1"

        $testStoragePath = Join-Path $TestDrive 'measure-performance.json'
    }

    BeforeEach {
        if (Test-Path $testStoragePath) {
            Remove-Item $testStoragePath -Force
        }

        $originalConfig = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig.Clone() } else { $null }
        $GlobalLabConfig = @{
            Performance = @{
                Enabled       = $true
                StoragePath   = $testStoragePath
                RetentionDays = 90
            }
        }
    }

    AfterEach {
        if (Test-Path $testStoragePath) {
            Remove-Item $testStoragePath -Force
        }

        if ($null -ne $originalConfig) {
            $GlobalLabConfig = $originalConfig
        }
    }

    Context 'Basic measurement' {
        It 'Measures successful operation duration' {
            Measure-LabVMOperation -Operation 'TestOp' -VMName 'testvm' -ScriptBlock {
                Start-Sleep -Milliseconds 50
                return 'done'
            }

            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $data.metrics.Count | Should -Be 1
            $data.metrics[0].Duration | Should -BeGreaterThan 40
            $data.metrics[0].Success | Should -BeTrue
        }

        It 'Records failure on exception' {
            { Measure-LabVMOperation -Operation 'TestOp' -VMName 'testvm' -ScriptBlock {
                throw 'Test error'
            } } | Should -Throw

            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $data.metrics[0].Success | Should -BeFalse
            $data.metrics[0].Metadata.Error | Should -Be 'Test error'
        }

        It 'Includes metadata in metric' {
            Measure-LabVMOperation -Operation 'TestOp' -VMName 'testvm' -Metadata @{ Extra = 'data' } -ScriptBlock {
                return 'result'
            }

            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $data.metrics[0].Metadata.Extra | Should -Be 'data'
        }

        It 'Returns scriptblock result' {
            $result = Measure-LabVMOperation -Operation 'TestOp' -VMName 'testvm' -ScriptBlock {
                return 42
            }

            $result | Should -Be 42
        }

        It 'Re-throws exceptions while still recording metric' {
            { Measure-LabVMOperation -Operation 'TestOp' -VMName 'testvm' -ScriptBlock {
                throw 'Original error'
            } } | Should -Throw 'Original error'

            $data = Get-Content $testStoragePath -Raw | ConvertFrom-Json
            $data.metrics.Count | Should -Be 1
        }

        It 'Does not measure when performance tracking is disabled' {
            $GlobalLabConfig.Performance.Enabled = $false

            Measure-LabVMOperation -Operation 'TestOp' -VMName 'testvm' -ScriptBlock { return 'done' }

            Test-Path $testStoragePath | Should -BeFalse
        }
    }
}

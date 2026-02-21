Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Write-LabSTIGCompliance.ps1')
}

Describe 'Write-LabSTIGCompliance' {

    Context 'File creation' {

        It 'Creates new compliance JSON file when it does not exist' {
            $tmpPath = Join-Path $TestDrive 'new-compliance.json'

            Mock Set-Content { } -Verifiable
            Mock Get-Content { }
            Mock Test-Path { $false } -ParameterFilter { $Path -eq $tmpPath }
            Mock Test-Path { $true } -ParameterFilter { $Path -ne $tmpPath }
            Mock New-Item { }

            { Write-LabSTIGCompliance -CachePath $tmpPath -VMName 'VM1' -Role 'MS' -STIGVersion '2022' -Status 'Compliant' } |
                Should -Not -Throw
            Should -InvokeVerifiable
        }

        It 'Writes correct schema: LastUpdated and VMs array at top level' {
            $tmpPath = Join-Path $TestDrive 'schema-test.json'
            $captured = $null

            Mock Test-Path { $false } -ParameterFilter { $Path -eq $tmpPath }
            Mock Test-Path { $true } -ParameterFilter { $Path -ne $tmpPath }
            Mock Get-Content { }
            Mock New-Item { }
            Mock Set-Content {
                param($Path, $Value, $Encoding)
                $script:capturedJson = $Value
            }

            Write-LabSTIGCompliance -CachePath $tmpPath -VMName 'VM1' -Role 'MS' -STIGVersion '2022' -Status 'Compliant'

            $parsed = $script:capturedJson | ConvertFrom-Json
            $parsed.LastUpdated | Should -Not -BeNullOrEmpty
            $parsed.VMs | Should -Not -BeNullOrEmpty
        }

        It 'Does not throw when output directory does not exist (creates it)' {
            $tmpPath = Join-Path $TestDrive 'subdir' 'nested' 'compliance.json'
            $dirPath = Split-Path -Parent $tmpPath

            Mock Test-Path { $false } -ParameterFilter { $Path -eq $tmpPath }
            Mock Test-Path { $false } -ParameterFilter { $Path -eq $dirPath }
            Mock New-Item { } -Verifiable
            Mock Get-Content { }
            Mock Set-Content { }

            { Write-LabSTIGCompliance -CachePath $tmpPath -VMName 'VM1' -Role 'MS' -STIGVersion '2022' -Status 'Compliant' } |
                Should -Not -Throw
            Should -InvokeVerifiable
        }
    }

    Context 'VM entry schema' {

        BeforeEach {
            $script:capturedJson = $null
            Mock Test-Path { $false }
            Mock Get-Content { }
            Mock New-Item { }
            Mock Set-Content {
                param($Path, $Value, $Encoding)
                $script:capturedJson = $Value
            }
        }

        It 'Each VM entry contains VMName, Role, STIGVersion, Status, ExceptionsApplied, LastChecked, ErrorMessage' {
            Write-LabSTIGCompliance -CachePath 'fake.json' -VMName 'DC1' -Role 'DC' -STIGVersion '2019' -Status 'Compliant'

            $parsed = $script:capturedJson | ConvertFrom-Json
            $vm = $parsed.VMs[0]
            $vm.VMName            | Should -Not -BeNullOrEmpty
            $vm.Role              | Should -Not -BeNullOrEmpty
            $vm.STIGVersion       | Should -Not -BeNullOrEmpty
            $vm.Status            | Should -Not -BeNullOrEmpty
            $vm.PSObject.Properties.Name | Should -Contain 'ExceptionsApplied'
            $vm.PSObject.Properties.Name | Should -Contain 'LastChecked'
            $vm.PSObject.Properties.Name | Should -Contain 'ErrorMessage'
        }

        It 'LastUpdated is written as an ISO 8601 string in the JSON' {
            Write-LabSTIGCompliance -CachePath 'fake.json' -VMName 'VM1' -Role 'MS' -STIGVersion '2022' -Status 'Compliant'

            # Check the raw JSON string directly (ConvertFrom-Json auto-converts ISO 8601 to DateTime)
            # ISO 8601 round-trip format from Get-Date .ToString('o') contains 'T' separator
            $script:capturedJson | Should -Match '"LastUpdated"\s*:\s*"[^"]*T[^"]*"'
        }

        It 'Status is Compliant when DSC application succeeds with no errors' {
            Write-LabSTIGCompliance -CachePath 'fake.json' -VMName 'VM1' -Role 'MS' -STIGVersion '2022' -Status 'Compliant'

            $parsed = $script:capturedJson | ConvertFrom-Json
            $parsed.VMs[0].Status | Should -Be 'Compliant'
        }

        It 'Status is NonCompliant when DSC reports non-compliant resources' {
            Write-LabSTIGCompliance -CachePath 'fake.json' -VMName 'VM1' -Role 'MS' -STIGVersion '2022' -Status 'NonCompliant'

            $parsed = $script:capturedJson | ConvertFrom-Json
            $parsed.VMs[0].Status | Should -Be 'NonCompliant'
        }

        It 'Status is Failed when DSC application throws an error' {
            Write-LabSTIGCompliance -CachePath 'fake.json' -VMName 'VM1' -Role 'MS' -STIGVersion '2022' -Status 'Failed' -ErrorMessage 'DSC push failed'

            $parsed = $script:capturedJson | ConvertFrom-Json
            $parsed.VMs[0].Status | Should -Be 'Failed'
        }

        It 'ErrorMessage is null on success' {
            Write-LabSTIGCompliance -CachePath 'fake.json' -VMName 'VM1' -Role 'MS' -STIGVersion '2022' -Status 'Compliant'

            $parsed = $script:capturedJson | ConvertFrom-Json
            $parsed.VMs[0].ErrorMessage | Should -BeNullOrEmpty
        }

        It 'ErrorMessage contains error text on failure' {
            Write-LabSTIGCompliance -CachePath 'fake.json' -VMName 'VM1' -Role 'MS' -STIGVersion '2022' -Status 'Failed' -ErrorMessage 'MOF compilation failed'

            $parsed = $script:capturedJson | ConvertFrom-Json
            $parsed.VMs[0].ErrorMessage | Should -Be 'MOF compilation failed'
        }

        It 'ExceptionsApplied is integer count of excluded V-numbers' {
            Write-LabSTIGCompliance -CachePath 'fake.json' -VMName 'VM1' -Role 'MS' -STIGVersion '2022' -Status 'Compliant' -ExceptionsApplied 3

            $parsed = $script:capturedJson | ConvertFrom-Json
            $parsed.VMs[0].ExceptionsApplied | Should -Be 3
        }

        It 'ExceptionsApplied defaults to 0 when not specified' {
            Write-LabSTIGCompliance -CachePath 'fake.json' -VMName 'VM1' -Role 'MS' -STIGVersion '2022' -Status 'Compliant'

            $parsed = $script:capturedJson | ConvertFrom-Json
            $parsed.VMs[0].ExceptionsApplied | Should -Be 0
        }
    }

    Context 'Update/append behavior' {

        BeforeEach {
            $script:capturedJson = $null
        }

        It 'Updates existing VM entry by VMName match without duplicating' {
            $existingCache = @{
                LastUpdated = '2026-01-01T00:00:00Z'
                VMs = @(
                    @{
                        VMName = 'VM1'; Role = 'MS'; STIGVersion = '2022'; Status = 'NonCompliant'
                        ExceptionsApplied = 0; LastChecked = '2026-01-01T00:00:00Z'; ErrorMessage = $null
                    }
                )
            } | ConvertTo-Json -Depth 5

            Mock Test-Path { $true } -ParameterFilter { $Path -eq 'fake.json' }
            Mock Test-Path { $true } -ParameterFilter { $Path -ne 'fake.json' }
            Mock Get-Content { $existingCache }
            Mock New-Item { }
            Mock Set-Content {
                param($Path, $Value, $Encoding)
                $script:capturedJson = $Value
            }

            Write-LabSTIGCompliance -CachePath 'fake.json' -VMName 'VM1' -Role 'MS' -STIGVersion '2022' -Status 'Compliant'

            $parsed = $script:capturedJson | ConvertFrom-Json
            # Should not have duplicated VM1
            ($parsed.VMs | Where-Object { $_.VMName -eq 'VM1' }).Count | Should -Be 1
            ($parsed.VMs | Where-Object { $_.VMName -eq 'VM1' }).Status | Should -Be 'Compliant'
        }

        It 'Adds new VM entry when VMName not previously in cache' {
            $existingCache = @{
                LastUpdated = '2026-01-01T00:00:00Z'
                VMs = @(
                    @{
                        VMName = 'VM1'; Role = 'MS'; STIGVersion = '2022'; Status = 'Compliant'
                        ExceptionsApplied = 0; LastChecked = '2026-01-01T00:00:00Z'; ErrorMessage = $null
                    }
                )
            } | ConvertTo-Json -Depth 5

            Mock Test-Path { $true } -ParameterFilter { $Path -eq 'fake.json' }
            Mock Test-Path { $true } -ParameterFilter { $Path -ne 'fake.json' }
            Mock Get-Content { $existingCache }
            Mock New-Item { }
            Mock Set-Content {
                param($Path, $Value, $Encoding)
                $script:capturedJson = $Value
            }

            Write-LabSTIGCompliance -CachePath 'fake.json' -VMName 'VM2' -Role 'DC' -STIGVersion '2019' -Status 'Compliant'

            $parsed = $script:capturedJson | ConvertFrom-Json
            $parsed.VMs.Count | Should -Be 2
            ($parsed.VMs | Where-Object { $_.VMName -eq 'VM2' }) | Should -Not -BeNullOrEmpty
        }

        It 'Preserves existing VM entries when updating a single VM' {
            $existingCache = @{
                LastUpdated = '2026-01-01T00:00:00Z'
                VMs = @(
                    @{
                        VMName = 'VM1'; Role = 'MS'; STIGVersion = '2022'; Status = 'Compliant'
                        ExceptionsApplied = 0; LastChecked = '2026-01-01T00:00:00Z'; ErrorMessage = $null
                    },
                    @{
                        VMName = 'DC1'; Role = 'DC'; STIGVersion = '2019'; Status = 'Compliant'
                        ExceptionsApplied = 2; LastChecked = '2026-01-01T00:00:00Z'; ErrorMessage = $null
                    }
                )
            } | ConvertTo-Json -Depth 5

            Mock Test-Path { $true } -ParameterFilter { $Path -eq 'fake.json' }
            Mock Test-Path { $true } -ParameterFilter { $Path -ne 'fake.json' }
            Mock Get-Content { $existingCache }
            Mock New-Item { }
            Mock Set-Content {
                param($Path, $Value, $Encoding)
                $script:capturedJson = $Value
            }

            Write-LabSTIGCompliance -CachePath 'fake.json' -VMName 'VM1' -Role 'MS' -STIGVersion '2022' -Status 'NonCompliant'

            $parsed = $script:capturedJson | ConvertFrom-Json
            # VM1 updated, DC1 preserved
            $parsed.VMs.Count | Should -Be 2
            ($parsed.VMs | Where-Object { $_.VMName -eq 'DC1' }).Status | Should -Be 'Compliant'
            ($parsed.VMs | Where-Object { $_.VMName -eq 'DC1' }).ExceptionsApplied | Should -Be 2
        }
    }
}

Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Get-LabSTIGConfig.ps1')
    . (Join-Path $repoRoot 'Public/Get-LabSTIGCompliance.ps1')
}

Describe 'Get-LabSTIGCompliance (Public)' {

    Context 'Missing cache file' {

        It 'Returns empty array when stig-compliance.json does not exist' {
            $tempPath = Join-Path $TestDrive 'nonexistent-compliance.json'

            $result = Get-LabSTIGCompliance -CachePath $tempPath

            $result | Should -BeNullOrEmpty
            @($result).Count | Should -Be 0
        }
    }

    Context 'Valid JSON cache' {

        It 'Returns PSCustomObject array with correct fields from valid JSON' {
            $tempPath = Join-Path $TestDrive 'compliance.json'
            $json = @{
                LastUpdated = (Get-Date).ToString('o')
                VMs = @(
                    @{
                        VMName            = 'DC1'
                        Role              = 'DC'
                        STIGVersion       = '2019'
                        Status            = 'Compliant'
                        ExceptionsApplied = 2
                        LastChecked       = (Get-Date).ToString('o')
                        ErrorMessage      = $null
                    }
                )
            } | ConvertTo-Json -Depth 5
            Set-Content -Path $tempPath -Value $json -Encoding UTF8

            $result = Get-LabSTIGCompliance -CachePath $tempPath

            @($result).Count | Should -Be 1
            $result[0].VMName | Should -Be 'DC1'
            $result[0].Role   | Should -Be 'DC'
        }

        It 'Returns PSCustomObject entries with all 7 required fields' {
            $tempPath = Join-Path $TestDrive 'compliance-fields.json'
            $json = @{
                LastUpdated = (Get-Date).ToString('o')
                VMs = @(
                    @{
                        VMName            = 'SVR1'
                        Role              = 'MS'
                        STIGVersion       = '2022'
                        Status            = 'NonCompliant'
                        ExceptionsApplied = 0
                        LastChecked       = (Get-Date).ToString('o')
                        ErrorMessage      = 'DSC timeout'
                    }
                )
            } | ConvertTo-Json -Depth 5
            Set-Content -Path $tempPath -Value $json -Encoding UTF8

            $result = Get-LabSTIGCompliance -CachePath $tempPath
            $entry  = $result[0]

            $props = $entry.PSObject.Properties.Name
            $props | Should -Contain 'VMName'
            $props | Should -Contain 'Role'
            $props | Should -Contain 'STIGVersion'
            $props | Should -Contain 'Status'
            $props | Should -Contain 'ExceptionsApplied'
            $props | Should -Contain 'LastChecked'
            $props | Should -Contain 'ErrorMessage'
        }

        It 'Returns per-VM objects with correct field values' {
            $tempPath = Join-Path $TestDrive 'compliance-values.json'
            $json = @{
                LastUpdated = (Get-Date).ToString('o')
                VMs = @(
                    @{
                        VMName            = 'DC1'
                        Role              = 'DC'
                        STIGVersion       = '2019'
                        Status            = 'Compliant'
                        ExceptionsApplied = 3
                        LastChecked       = '2026-02-21T04:00:00Z'
                        ErrorMessage      = $null
                    },
                    @{
                        VMName            = 'SVR1'
                        Role              = 'MS'
                        STIGVersion       = '2022'
                        Status            = 'Failed'
                        ExceptionsApplied = 0
                        LastChecked       = '2026-02-21T04:05:00Z'
                        ErrorMessage      = 'Connection refused'
                    }
                )
            } | ConvertTo-Json -Depth 5
            Set-Content -Path $tempPath -Value $json -Encoding UTF8

            $result = @(Get-LabSTIGCompliance -CachePath $tempPath)

            $result.Count | Should -Be 2
            ($result | Where-Object VMName -eq 'DC1').Status            | Should -Be 'Compliant'
            ($result | Where-Object VMName -eq 'DC1').ExceptionsApplied | Should -Be 3
            ($result | Where-Object VMName -eq 'SVR1').ErrorMessage     | Should -Be 'Connection refused'
        }

        It 'Returns empty array when VMs array is empty in JSON' {
            $tempPath = Join-Path $TestDrive 'compliance-empty.json'
            $json = @{
                LastUpdated = (Get-Date).ToString('o')
                VMs = @()
            } | ConvertTo-Json -Depth 5
            Set-Content -Path $tempPath -Value $json -Encoding UTF8

            $result = Get-LabSTIGCompliance -CachePath $tempPath

            @($result).Count | Should -Be 0
        }
    }

    Context 'Malformed JSON cache' {

        It 'Returns empty array gracefully when JSON is malformed' {
            $tempPath = Join-Path $TestDrive 'compliance-malformed.json'
            Set-Content -Path $tempPath -Value '{ this is not valid json !!!{' -Encoding UTF8

            $result = Get-LabSTIGCompliance -CachePath $tempPath

            @($result).Count | Should -Be 0
        }
    }

    Context 'Comment-based help' {

        It 'Has .SYNOPSIS defined' {
            $help = Get-Help Get-LabSTIGCompliance -ErrorAction SilentlyContinue
            $help.Synopsis | Should -Not -BeNullOrEmpty
        }

        It 'Has .DESCRIPTION defined' {
            $help = Get-Help Get-LabSTIGCompliance -Full -ErrorAction SilentlyContinue
            $help.description | Should -Not -BeNullOrEmpty
        }

        It 'Has at least one .EXAMPLE defined' {
            $help = Get-Help Get-LabSTIGCompliance -Full -ErrorAction SilentlyContinue
            $help.examples.example.Count | Should -BeGreaterOrEqual 1
        }
    }

    Context '-CachePath parameter override' {

        It 'Reads from custom -CachePath when provided' {
            $customPath = Join-Path $TestDrive 'custom-compliance.json'
            $json = @{
                LastUpdated = (Get-Date).ToString('o')
                VMs = @(
                    @{
                        VMName            = 'CUSTOM-VM'
                        Role              = 'MS'
                        STIGVersion       = '2022'
                        Status            = 'Compliant'
                        ExceptionsApplied = 1
                        LastChecked       = (Get-Date).ToString('o')
                        ErrorMessage      = $null
                    }
                )
            } | ConvertTo-Json -Depth 5
            Set-Content -Path $customPath -Value $json -Encoding UTF8

            $result = Get-LabSTIGCompliance -CachePath $customPath

            @($result).Count | Should -Be 1
            $result[0].VMName | Should -Be 'CUSTOM-VM'
        }
    }

    Context 'Default path from Get-LabSTIGConfig' {

        It 'Uses default path from Get-LabSTIGConfig when -CachePath not specified' {
            $tempPath = Join-Path $TestDrive 'default-compliance.json'
            $json = @{
                LastUpdated = (Get-Date).ToString('o')
                VMs = @(
                    @{
                        VMName            = 'DEFAULT-VM'
                        Role              = 'DC'
                        STIGVersion       = '2019'
                        Status            = 'Compliant'
                        ExceptionsApplied = 0
                        LastChecked       = (Get-Date).ToString('o')
                        ErrorMessage      = $null
                    }
                )
            } | ConvertTo-Json -Depth 5
            Set-Content -Path $tempPath -Value $json -Encoding UTF8

            Mock Get-LabSTIGConfig {
                [pscustomobject]@{
                    Enabled             = $true
                    AutoApplyOnDeploy   = $true
                    ComplianceCachePath = $tempPath
                    Exceptions          = @{}
                }
            }

            $result = Get-LabSTIGCompliance

            @($result).Count | Should -Be 1
            $result[0].VMName | Should -Be 'DEFAULT-VM'
        }
    }
}

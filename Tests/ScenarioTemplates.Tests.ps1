BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Test-LabTemplateData.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabScenarioTemplate.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabScenarioResourceEstimate.ps1')
    $templatesRoot = Join-Path $repoRoot '.planning/templates'
}

Describe 'Scenario Template JSON Files' {

    Context 'SecurityLab' {
        BeforeAll {
            $filePath = Join-Path $templatesRoot 'SecurityLab.json'
            $template = Get-Content -Path $filePath -Raw | ConvertFrom-Json
        }

        It 'File exists' {
            Test-Path $filePath | Should -BeTrue
        }

        It 'Has valid JSON with name property' {
            $template.name | Should -Be 'SecurityLab'
        }

        It 'Has a description' {
            $template.description | Should -Not -BeNullOrEmpty
        }

        It 'Has a vms array' {
            @($template.vms).Count | Should -BeGreaterThan 0
        }

        It 'Has exactly 3 VMs' {
            @($template.vms).Count | Should -Be 3
        }

        It 'Contains DC role' {
            @($template.vms).role | Should -Contain 'DC'
        }

        It 'Contains Client role' {
            @($template.vms).role | Should -Contain 'Client'
        }

        It 'Contains Ubuntu role' {
            @($template.vms).role | Should -Contain 'Ubuntu'
        }

        It 'Each VM has required properties' {
            foreach ($vm in $template.vms) {
                $vm.name | Should -Not -BeNullOrEmpty
                $vm.role | Should -Not -BeNullOrEmpty
                $vm.ip | Should -Not -BeNullOrEmpty
                $vm.memoryGB | Should -BeGreaterThan 0
                $vm.processors | Should -BeGreaterThan 0
            }
        }

        It 'All IPs match 10.0.10.x pattern' {
            foreach ($vm in $template.vms) {
                $vm.ip | Should -Match '^10\.0\.10\.\d+$'
            }
        }
    }

    Context 'MultiTierApp' {
        BeforeAll {
            $filePath = Join-Path $templatesRoot 'MultiTierApp.json'
            $template = Get-Content -Path $filePath -Raw | ConvertFrom-Json
        }

        It 'File exists' {
            Test-Path $filePath | Should -BeTrue
        }

        It 'Has valid JSON with name property' {
            $template.name | Should -Be 'MultiTierApp'
        }

        It 'Has a description' {
            $template.description | Should -Not -BeNullOrEmpty
        }

        It 'Has exactly 4 VMs' {
            @($template.vms).Count | Should -Be 4
        }

        It 'Contains DC, SQL, IIS, Client roles' {
            $roles = @($template.vms).role
            $roles | Should -Contain 'DC'
            $roles | Should -Contain 'SQL'
            $roles | Should -Contain 'IIS'
            $roles | Should -Contain 'Client'
        }

        It 'Each VM has required properties' {
            foreach ($vm in $template.vms) {
                $vm.name | Should -Not -BeNullOrEmpty
                $vm.role | Should -Not -BeNullOrEmpty
                $vm.ip | Should -Not -BeNullOrEmpty
                $vm.memoryGB | Should -BeGreaterThan 0
                $vm.processors | Should -BeGreaterThan 0
            }
        }

        It 'All IPs match 10.0.10.x pattern' {
            foreach ($vm in $template.vms) {
                $vm.ip | Should -Match '^10\.0\.10\.\d+$'
            }
        }
    }

    Context 'MinimalAD' {
        BeforeAll {
            $filePath = Join-Path $templatesRoot 'MinimalAD.json'
            $template = Get-Content -Path $filePath -Raw | ConvertFrom-Json
        }

        It 'File exists' {
            Test-Path $filePath | Should -BeTrue
        }

        It 'Has valid JSON with name property' {
            $template.name | Should -Be 'MinimalAD'
        }

        It 'Has a description' {
            $template.description | Should -Not -BeNullOrEmpty
        }

        It 'Has exactly 1 VM' {
            @($template.vms).Count | Should -Be 1
        }

        It 'Single VM has DC role' {
            $template.vms[0].role | Should -Be 'DC'
        }

        It 'VM has required properties' {
            $vm = $template.vms[0]
            $vm.name | Should -Not -BeNullOrEmpty
            $vm.role | Should -Not -BeNullOrEmpty
            $vm.ip | Should -Not -BeNullOrEmpty
            $vm.memoryGB | Should -BeGreaterThan 0
            $vm.processors | Should -BeGreaterThan 0
        }

        It 'IP matches 10.0.10.x pattern' {
            $template.vms[0].ip | Should -Match '^10\.0\.10\.\d+$'
        }
    }
}

Describe 'Get-LabScenarioTemplate' {

    Context 'Valid scenarios' {
        It 'Returns 3 VM definitions for SecurityLab' {
            $result = Get-LabScenarioTemplate -Scenario SecurityLab -TemplatesRoot $templatesRoot
            @($result).Count | Should -Be 3
        }

        It 'Returns 4 VM definitions for MultiTierApp' {
            $result = Get-LabScenarioTemplate -Scenario MultiTierApp -TemplatesRoot $templatesRoot
            @($result).Count | Should -Be 4
        }

        It 'Returns 1 VM definition for MinimalAD' {
            $result = Get-LabScenarioTemplate -Scenario MinimalAD -TemplatesRoot $templatesRoot
            @($result).Count | Should -Be 1
        }

        It 'Each returned object has Name, Role, Ip, MemoryGB, Processors properties' {
            $result = Get-LabScenarioTemplate -Scenario SecurityLab -TemplatesRoot $templatesRoot
            foreach ($vm in $result) {
                $vm.PSObject.Properties.Name | Should -Contain 'Name'
                $vm.PSObject.Properties.Name | Should -Contain 'Role'
                $vm.PSObject.Properties.Name | Should -Contain 'Ip'
                $vm.PSObject.Properties.Name | Should -Contain 'MemoryGB'
                $vm.PSObject.Properties.Name | Should -Contain 'Processors'
            }
        }
    }

    Context 'Error handling' {
        It 'Throws on invalid scenario name' {
            { Get-LabScenarioTemplate -Scenario 'NonExistent' -TemplatesRoot $templatesRoot } | Should -Throw
        }

        It 'Error message contains available scenario names' {
            try {
                Get-LabScenarioTemplate -Scenario 'NonExistent' -TemplatesRoot $templatesRoot
            }
            catch {
                $_.Exception.Message | Should -Match 'SecurityLab'
                $_.Exception.Message | Should -Match 'MultiTierApp'
                $_.Exception.Message | Should -Match 'MinimalAD'
            }
        }

        It 'Throws on missing TemplatesRoot directory' {
            { Get-LabScenarioTemplate -Scenario 'SecurityLab' -TemplatesRoot '/nonexistent/path' } | Should -Throw
        }
    }
}

Describe 'Get-LabScenarioResourceEstimate' {

    Context 'SecurityLab resources' {
        BeforeAll {
            $estimate = Get-LabScenarioResourceEstimate -Scenario SecurityLab -TemplatesRoot $templatesRoot
        }

        It 'TotalRAMGB equals 10' {
            $estimate.TotalRAMGB | Should -Be 10
        }

        It 'VMCount equals 3' {
            $estimate.VMCount | Should -Be 3
        }

        It 'TotalProcessors equals 8' {
            $estimate.TotalProcessors | Should -Be 8
        }
    }

    Context 'MultiTierApp resources' {
        BeforeAll {
            $estimate = Get-LabScenarioResourceEstimate -Scenario MultiTierApp -TemplatesRoot $templatesRoot
        }

        It 'TotalRAMGB equals 20' {
            $estimate.TotalRAMGB | Should -Be 20
        }

        It 'VMCount equals 4' {
            $estimate.VMCount | Should -Be 4
        }

        It 'TotalProcessors equals 12' {
            $estimate.TotalProcessors | Should -Be 12
        }
    }

    Context 'MinimalAD resources' {
        BeforeAll {
            $estimate = Get-LabScenarioResourceEstimate -Scenario MinimalAD -TemplatesRoot $templatesRoot
        }

        It 'TotalRAMGB equals 2' {
            $estimate.TotalRAMGB | Should -Be 2
        }

        It 'VMCount equals 1' {
            $estimate.VMCount | Should -Be 1
        }

        It 'TotalProcessors equals 2' {
            $estimate.TotalProcessors | Should -Be 2
        }
    }

    Context 'Output shape' {
        BeforeAll {
            $estimate = Get-LabScenarioResourceEstimate -Scenario SecurityLab -TemplatesRoot $templatesRoot
        }

        It 'Returns Scenario property' {
            $estimate.Scenario | Should -Be 'SecurityLab'
        }

        It 'Returns VMCount property' {
            $estimate.VMCount | Should -BeOfType [int]
        }

        It 'Returns TotalRAMGB property' {
            $estimate.TotalRAMGB | Should -BeOfType [int]
        }

        It 'Returns TotalDiskGB as positive integer' {
            $estimate.TotalDiskGB | Should -BeGreaterThan 0
        }

        It 'Returns TotalProcessors property' {
            $estimate.TotalProcessors | Should -BeOfType [int]
        }

        It 'Returns VMs array' {
            @($estimate.VMs).Count | Should -BeGreaterThan 0
        }
    }

    Context 'Disk estimation' {
        It 'TotalDiskGB is positive for all scenarios' {
            foreach ($scenario in @('SecurityLab', 'MultiTierApp', 'MinimalAD')) {
                $est = Get-LabScenarioResourceEstimate -Scenario $scenario -TemplatesRoot $templatesRoot
                $est.TotalDiskGB | Should -BeGreaterThan 0
            }
        }
    }

    Context 'Error handling' {
        It 'Throws on invalid scenario name' {
            { Get-LabScenarioResourceEstimate -Scenario 'NonExistent' -TemplatesRoot $templatesRoot } | Should -Throw
        }
    }
}

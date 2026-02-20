BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Test-LabTemplateData.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabScenarioTemplate.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabScenarioResourceEstimate.ps1')
    . (Join-Path $repoRoot 'Private/Get-ActiveTemplateConfig.ps1')
    $templatesRoot = Join-Path $repoRoot '.planning/templates'
}

Describe 'Deploy.ps1 Scenario Parameter' {
    BeforeAll {
        $deployContent = Get-Content -Path (Join-Path $repoRoot 'Deploy.ps1') -Raw
    }

    It 'Deploy.ps1 has a Scenario parameter' {
        $cmd = Get-Command (Join-Path $repoRoot 'Deploy.ps1')
        $cmd.Parameters.Keys | Should -Contain 'Scenario'
    }

    It 'Deploy.ps1 dot-sources Get-LabScenarioTemplate helper' {
        $match = Select-String -InputObject $deployContent -Pattern 'Get-LabScenarioTemplate\.ps1'
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Deploy.ps1 dot-sources Get-LabScenarioResourceEstimate helper' {
        $match = Select-String -InputObject $deployContent -Pattern 'Get-LabScenarioResourceEstimate\.ps1'
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Deploy.ps1 calls Get-LabScenarioResourceEstimate when Scenario is provided' {
        $match = Select-String -InputObject $deployContent -Pattern 'Get-LabScenarioResourceEstimate\s+-Scenario'
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Deploy.ps1 calls Get-LabScenarioTemplate when Scenario is provided' {
        $match = Select-String -InputObject $deployContent -Pattern 'Get-LabScenarioTemplate\s+-Scenario'
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Deploy.ps1 prints resource estimate header with scenario name' {
        $match = Select-String -InputObject $deployContent -Pattern 'Scenario Resource Requirements'
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Deploy.ps1 prints VM count in resource estimate' {
        $match = Select-String -InputObject $deployContent -Pattern '\$estimate\.VMCount'
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Deploy.ps1 prints RAM in resource estimate' {
        $match = Select-String -InputObject $deployContent -Pattern '\$estimate\.TotalRAMGB'
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Deploy.ps1 prints disk in resource estimate' {
        $match = Select-String -InputObject $deployContent -Pattern '\$estimate\.TotalDiskGB'
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Deploy.ps1 prints CPU count in resource estimate' {
        $match = Select-String -InputObject $deployContent -Pattern '\$estimate\.TotalProcessors'
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Scenario override takes precedence over active template' {
        # When Scenario is set, the active template path should be skipped
        $match = Select-String -InputObject $deployContent -Pattern 'IsNullOrWhiteSpace\(\$Scenario\).*\$templateConfig\s*=\s*\$null' -AllMatches
        # The conditional structure wraps the active template lookup
        $scenarioBlock = Select-String -InputObject $deployContent -Pattern 'if\s*\(\[string\]::IsNullOrWhiteSpace\(\$Scenario\)\)'
        $scenarioBlock | Should -Not -BeNullOrEmpty
    }
}

Describe 'OpenCodeLab-App.ps1 Scenario Parameter' {
    BeforeAll {
        $appContent = Get-Content -Path (Join-Path $repoRoot 'OpenCodeLab-App.ps1') -Raw
    }

    It 'App has a Scenario parameter' {
        $cmd = Get-Command (Join-Path $repoRoot 'OpenCodeLab-App.ps1')
        $cmd.Parameters.Keys | Should -Contain 'Scenario'
    }

    It 'App passes Scenario to Invoke-LabOrchestrationActionCore' {
        $match = Select-String -InputObject $appContent -Pattern 'Scenario.*\$Scenario'
        $match | Should -Not -BeNullOrEmpty
    }

    It 'App conditionally passes Scenario only when bound' {
        $match = Select-String -InputObject $appContent -Pattern "PSBoundParameters\.ContainsKey\('Scenario'\)"
        $match | Should -Not -BeNullOrEmpty
    }
}

Describe 'Invoke-LabOrchestrationActionCore Scenario Parameter' {
    BeforeAll {
        $actionCoreContent = Get-Content -Path (Join-Path $repoRoot 'Private/Invoke-LabOrchestrationActionCore.ps1') -Raw
    }

    It 'Function has Scenario parameter' {
        $match = Select-String -InputObject $actionCoreContent -Pattern '\[string\]\$Scenario'
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Function passes Scenario to deploy invocation arguments' {
        $match = Select-String -InputObject $actionCoreContent -Pattern "'-Scenario'"
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Function only adds Scenario when non-empty' {
        $match = Select-String -InputObject $actionCoreContent -Pattern 'IsNullOrWhiteSpace\(\$Scenario\)'
        $match | Should -Not -BeNullOrEmpty
    }
}

Describe 'End-to-End Scenario Resolution' {

    Context 'SecurityLab scenario' {
        It 'Get-LabScenarioTemplate returns 3 VMs with roles DC, Client, Ubuntu' {
            $vms = Get-LabScenarioTemplate -Scenario SecurityLab -TemplatesRoot $templatesRoot
            @($vms).Count | Should -Be 3
            @($vms).Role | Should -Contain 'DC'
            @($vms).Role | Should -Contain 'Client'
            @($vms).Role | Should -Contain 'Ubuntu'
        }

        It 'Get-LabScenarioResourceEstimate returns TotalRAMGB = 10, TotalProcessors = 8' {
            $estimate = Get-LabScenarioResourceEstimate -Scenario SecurityLab -TemplatesRoot $templatesRoot
            $estimate.TotalRAMGB | Should -Be 10
            $estimate.TotalProcessors | Should -Be 8
        }
    }

    Context 'MultiTierApp scenario' {
        It 'Get-LabScenarioTemplate returns 4 VMs with roles DC, SQL, IIS, Client' {
            $vms = Get-LabScenarioTemplate -Scenario MultiTierApp -TemplatesRoot $templatesRoot
            @($vms).Count | Should -Be 4
            @($vms).Role | Should -Contain 'DC'
            @($vms).Role | Should -Contain 'SQL'
            @($vms).Role | Should -Contain 'IIS'
            @($vms).Role | Should -Contain 'Client'
        }

        It 'Get-LabScenarioResourceEstimate returns TotalRAMGB = 20, TotalProcessors = 12' {
            $estimate = Get-LabScenarioResourceEstimate -Scenario MultiTierApp -TemplatesRoot $templatesRoot
            $estimate.TotalRAMGB | Should -Be 20
            $estimate.TotalProcessors | Should -Be 12
        }
    }

    Context 'MinimalAD scenario' {
        It 'Get-LabScenarioTemplate returns 1 VM with role DC' {
            $vms = Get-LabScenarioTemplate -Scenario MinimalAD -TemplatesRoot $templatesRoot
            @($vms).Count | Should -Be 1
            @($vms)[0].Role | Should -Be 'DC'
        }

        It 'Get-LabScenarioResourceEstimate returns TotalRAMGB = 2, TotalProcessors = 2' {
            $estimate = Get-LabScenarioResourceEstimate -Scenario MinimalAD -TemplatesRoot $templatesRoot
            $estimate.TotalRAMGB | Should -Be 2
            $estimate.TotalProcessors | Should -Be 2
        }
    }

    Context 'Invalid scenario' {
        It 'Throws with descriptive error message' {
            { Get-LabScenarioTemplate -Scenario 'NonExistentScenario' -TemplatesRoot $templatesRoot } | Should -Throw '*not found*'
        }

        It 'Error message lists available scenario names' {
            try {
                Get-LabScenarioTemplate -Scenario 'NonExistentScenario' -TemplatesRoot $templatesRoot
            }
            catch {
                $_.Exception.Message | Should -Match 'SecurityLab'
                $_.Exception.Message | Should -Match 'MultiTierApp'
                $_.Exception.Message | Should -Match 'MinimalAD'
            }
        }
    }
}

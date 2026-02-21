Describe 'Lab Workflow Management' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module "$moduleRoot\SimpleLab\SimpleLab.psd1" -Force

        . "$moduleRoot\Private\Get-LabWorkflowConfig.ps1"
        . "$moduleRoot\Public\Save-LabWorkflow.ps1"
        . "$moduleRoot\Public\Get-LabWorkflow.ps1"

        $testWorkflowPath = Join-Path $moduleRoot '.planning\workflows'

        function New-TestWorkflow {
            param([string]$Name, [hashtable[]]$Steps)
            Save-LabWorkflow -Name $Name -Description "Test workflow $Name" -Steps $Steps -Force
        }

        function Remove-TestWorkflow {
            param([string]$Name)
            $filePath = Join-Path $testWorkflowPath "$Name.json"
            if (Test-Path $filePath) {
                Remove-Item -Path $filePath -Force
            }
        }
    }

    BeforeEach {
        if (-not (Test-Path $testWorkflowPath)) {
            New-Item -Path $testWorkflowPath -ItemType Directory -Force | Out-Null
        }
    }

    AfterEach {
        Get-ChildItem -Path $testWorkflowPath -Filter 'test-*.json' -ErrorAction SilentlyContinue | Remove-Item -Force
    }

    Context 'Save-LabWorkflow' {
        It 'Creates workflow JSON file' {
            $steps = @(
                @{ Operation = 'Start'; VMName = @('dc1') }
            )

            $result = Save-LabWorkflow -Name 'test-workflow' -Description 'Test' -Steps $steps -Force

            $result.Status | Should -Be 'Created'
            $result.Path | Should -Exist
        }

        It 'Stores workflow steps correctly' {
            $steps = @(
                @{ Operation = 'Start'; VMName = @('dc1', 'svr1'); DelaySeconds = 10 },
                @{ Operation = 'Stop'; VMName = @('cli1') }
            )

            Save-LabWorkflow -Name 'test-steps' -Steps $steps -Force

            $workflow = Get-LabWorkflow -Name 'test-steps'
            $workflow.StepCount | Should -Be 2
            $workflow.Steps[0].Operation | Should -Be 'Start'
            $workflow.Steps[0].VMName.Count | Should -Be 2
            $workflow.Steps[0].DelaySeconds | Should -Be 10
        }

        It 'Rejects duplicate names without Force' {
            $steps = @{ Operation = 'Start'; VMName = @('vm1') }

            Save-LabWorkflow -Name 'test-dup' -Steps $steps -Force
            { Save-LabWorkflow -Name 'test-dup' -Steps $steps } | Should -Throw
        }
    }

    Context 'Get-LabWorkflow' {
        It 'Lists all workflows when Name not specified' {
            New-TestWorkflow -Name 'test-a' -Steps @{ Operation = 'Start'; VMName = @() }
            New-TestWorkflow -Name 'test-b' -Steps @{ Operation = 'Stop'; VMName = @() }

            $workflows = Get-LabWorkflow
            $workflows.Count | Should -BeGreaterOrEqual 2
        }

        It 'Retrieves specific workflow by Name' {
            New-TestWorkflow -Name 'test-specific' -Steps @{ Operation = 'Start'; VMName = @('dc1') }

            $workflow = Get-LabWorkflow -Name 'test-specific'
            $workflow.Name | Should -Be 'test-specific'
            $workflow.StepCount | Should -Be 1
        }

        It 'Returns empty for missing workflow' {
            $workflow = Get-LabWorkflow -Name 'nonexistent'
            $workflow | Should -BeNullOrEmpty
        }
    }
}

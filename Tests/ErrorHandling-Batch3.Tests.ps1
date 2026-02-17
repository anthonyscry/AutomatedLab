# ErrorHandling-Batch3.Tests.ps1
# Verifies that all 14 resolution, policy, and menu functions (Batch 3)
# have outer try-catch blocks with function-name-prefixed error messages.

BeforeAll {
    Set-StrictMode -Version Latest
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
}

Describe 'ErrorHandling-Batch3: Resolution functions have try-catch' {

    Context 'Resolve-LabActionRequest' {
        BeforeAll { $script:content1 = Get-Content -Raw -Path (Join-Path $script:repoRoot 'Private/Resolve-LabActionRequest.ps1') }
        It 'has a try block' { $script:content1 | Should -Match '\btry\s*\{' }
        It 'has a catch block' { $script:content1 | Should -Match '\bcatch\s*\{' }
        It 'throw prefixes message with function name' { $script:content1 | Should -Match 'throw\s+"Resolve-LabActionRequest:' }
    }

    Context 'Resolve-LabCoordinatorPolicy' {
        BeforeAll { $script:content2 = Get-Content -Raw -Path (Join-Path $script:repoRoot 'Private/Resolve-LabCoordinatorPolicy.ps1') }
        It 'has a try block' { $script:content2 | Should -Match '\btry\s*\{' }
        It 'has a catch block' { $script:content2 | Should -Match '\bcatch\s*\{' }
        It 'throw prefixes message with function name' { $script:content2 | Should -Match 'throw\s+"Resolve-LabCoordinatorPolicy:' }
    }

    Context 'Resolve-LabDispatchMode' {
        BeforeAll { $script:content3 = Get-Content -Raw -Path (Join-Path $script:repoRoot 'Private/Resolve-LabDispatchMode.ps1') }
        It 'has a try block' { $script:content3 | Should -Match '\btry\s*\{' }
        It 'has a catch block' { $script:content3 | Should -Match '\bcatch\s*\{' }
        It 'throw prefixes message with function name' { $script:content3 | Should -Match 'throw\s+"Resolve-LabDispatchMode:' }
    }

    Context 'Resolve-LabDispatchPlan' {
        BeforeAll { $script:content4 = Get-Content -Raw -Path (Join-Path $script:repoRoot 'Private/Resolve-LabDispatchPlan.ps1') }
        It 'has a try block' { $script:content4 | Should -Match '\btry\s*\{' }
        It 'has a catch block' { $script:content4 | Should -Match '\bcatch\s*\{' }
        It 'throw prefixes message with function name' { $script:content4 | Should -Match 'throw\s+"Resolve-LabDispatchPlan:' }
    }

    Context 'Resolve-LabModeDecision' {
        BeforeAll { $script:content5 = Get-Content -Raw -Path (Join-Path $script:repoRoot 'Private/Resolve-LabModeDecision.ps1') }
        It 'has a try block' { $script:content5 | Should -Match '\btry\s*\{' }
        It 'has a catch block' { $script:content5 | Should -Match '\bcatch\s*\{' }
        It 'throw prefixes message with function name' { $script:content5 | Should -Match 'throw\s+"Resolve-LabModeDecision:' }
    }

    Context 'Resolve-LabNoExecuteStateOverride' {
        BeforeAll { $script:content6 = Get-Content -Raw -Path (Join-Path $script:repoRoot 'Private/Resolve-LabNoExecuteStateOverride.ps1') }
        It 'has a try block' { $script:content6 | Should -Match '\btry\s*\{' }
        It 'has a catch block' { $script:content6 | Should -Match '\bcatch\s*\{' }
        It 'throw prefixes message with function name' { $script:content6 | Should -Match 'throw\s+"Resolve-LabNoExecuteStateOverride:' }
    }

    Context 'Resolve-LabOperationIntent' {
        BeforeAll { $script:content7 = Get-Content -Raw -Path (Join-Path $script:repoRoot 'Private/Resolve-LabOperationIntent.ps1') }
        It 'has a try block' { $script:content7 | Should -Match '\btry\s*\{' }
        It 'has a catch block' { $script:content7 | Should -Match '\bcatch\s*\{' }
        It 'throw prefixes message with function name' { $script:content7 | Should -Match 'throw\s+"Resolve-LabOperationIntent:' }
    }

    Context 'Resolve-LabOrchestrationIntent' {
        BeforeAll { $script:content8 = Get-Content -Raw -Path (Join-Path $script:repoRoot 'Private/Resolve-LabOrchestrationIntent.ps1') }
        It 'has a try block' { $script:content8 | Should -Match '\btry\s*\{' }
        It 'has a catch block' { $script:content8 | Should -Match '\bcatch\s*\{' }
        It 'throw prefixes message with function name' { $script:content8 | Should -Match 'throw\s+"Resolve-LabOrchestrationIntent:' }
    }
}

Describe 'ErrorHandling-Batch3: Menu functions have try-catch with Write-Warning' {

    Context 'Show-LabMenu' {
        BeforeAll { $script:menu1 = Get-Content -Raw -Path (Join-Path $script:repoRoot 'Private/Show-LabMenu.ps1') }
        It 'has a try block' { $script:menu1 | Should -Match '\btry\s*\{' }
        It 'has a catch block' { $script:menu1 | Should -Match '\bcatch\s*\{' }
        It 'Write-Warning prefixes message with function name' { $script:menu1 | Should -Match 'Write-Warning\s+"Show-LabMenu:' }
    }

    Context 'Invoke-LabInteractiveMenu' {
        BeforeAll { $script:menu2 = Get-Content -Raw -Path (Join-Path $script:repoRoot 'Private/Invoke-LabInteractiveMenu.ps1') }
        It 'has a try block' { $script:menu2 | Should -Match '\btry\s*\{' }
        It 'has a catch block' { $script:menu2 | Should -Match '\bcatch\s*\{' }
        It 'Write-Warning prefixes message with function name' { $script:menu2 | Should -Match 'Write-Warning\s+"Invoke-LabInteractiveMenu:' }
    }

    Context 'Invoke-LabAddVMMenu' {
        BeforeAll { $script:menu3 = Get-Content -Raw -Path (Join-Path $script:repoRoot 'Private/Invoke-LabAddVMMenu.ps1') }
        It 'has a try block' { $script:menu3 | Should -Match '\btry\s*\{' }
        It 'has a catch block' { $script:menu3 | Should -Match '\bcatch\s*\{' }
        It 'Write-Warning prefixes message with function name' { $script:menu3 | Should -Match 'Write-Warning\s+"Invoke-LabAddVMMenu:' }
    }

    Context 'Invoke-LabAddVMWizard' {
        BeforeAll { $script:menu4 = Get-Content -Raw -Path (Join-Path $script:repoRoot 'Private/Invoke-LabAddVMWizard.ps1') }
        It 'has a try block' { $script:menu4 | Should -Match '\btry\s*\{' }
        It 'has a catch block' { $script:menu4 | Should -Match '\bcatch\s*\{' }
        It 'Write-Warning prefixes message with function name' { $script:menu4 | Should -Match 'Write-Warning\s+"Invoke-LabAddVMWizard:' }
    }

    Context 'Invoke-LabConfigureRoleMenu' {
        BeforeAll { $script:menu5 = Get-Content -Raw -Path (Join-Path $script:repoRoot 'Private/Invoke-LabConfigureRoleMenu.ps1') }
        It 'has a try block' { $script:menu5 | Should -Match '\btry\s*\{' }
        It 'has a catch block' { $script:menu5 | Should -Match '\bcatch\s*\{' }
        It 'Write-Warning prefixes message with function name' { $script:menu5 | Should -Match 'Write-Warning\s+"Invoke-LabConfigureRoleMenu:' }
    }

    Context 'Invoke-LabSetupMenu' {
        BeforeAll { $script:menu6 = Get-Content -Raw -Path (Join-Path $script:repoRoot 'Private/Invoke-LabSetupMenu.ps1') }
        It 'has a try block' { $script:menu6 | Should -Match '\btry\s*\{' }
        It 'has a catch block' { $script:menu6 | Should -Match '\bcatch\s*\{' }
        It 'Write-Warning prefixes message with function name' { $script:menu6 | Should -Match 'Write-Warning\s+"Invoke-LabSetupMenu:' }
    }
}

Describe 'ErrorHandling-Batch3: All 14 files exist' {

    It 'Resolve-LabActionRequest.ps1 exists' {
        Test-Path (Join-Path $script:repoRoot 'Private/Resolve-LabActionRequest.ps1') | Should -Be $true
    }
    It 'Resolve-LabCoordinatorPolicy.ps1 exists' {
        Test-Path (Join-Path $script:repoRoot 'Private/Resolve-LabCoordinatorPolicy.ps1') | Should -Be $true
    }
    It 'Resolve-LabDispatchMode.ps1 exists' {
        Test-Path (Join-Path $script:repoRoot 'Private/Resolve-LabDispatchMode.ps1') | Should -Be $true
    }
    It 'Resolve-LabDispatchPlan.ps1 exists' {
        Test-Path (Join-Path $script:repoRoot 'Private/Resolve-LabDispatchPlan.ps1') | Should -Be $true
    }
    It 'Resolve-LabModeDecision.ps1 exists' {
        Test-Path (Join-Path $script:repoRoot 'Private/Resolve-LabModeDecision.ps1') | Should -Be $true
    }
    It 'Resolve-LabNoExecuteStateOverride.ps1 exists' {
        Test-Path (Join-Path $script:repoRoot 'Private/Resolve-LabNoExecuteStateOverride.ps1') | Should -Be $true
    }
    It 'Resolve-LabOperationIntent.ps1 exists' {
        Test-Path (Join-Path $script:repoRoot 'Private/Resolve-LabOperationIntent.ps1') | Should -Be $true
    }
    It 'Resolve-LabOrchestrationIntent.ps1 exists' {
        Test-Path (Join-Path $script:repoRoot 'Private/Resolve-LabOrchestrationIntent.ps1') | Should -Be $true
    }
    It 'Show-LabMenu.ps1 exists' {
        Test-Path (Join-Path $script:repoRoot 'Private/Show-LabMenu.ps1') | Should -Be $true
    }
    It 'Invoke-LabInteractiveMenu.ps1 exists' {
        Test-Path (Join-Path $script:repoRoot 'Private/Invoke-LabInteractiveMenu.ps1') | Should -Be $true
    }
    It 'Invoke-LabAddVMMenu.ps1 exists' {
        Test-Path (Join-Path $script:repoRoot 'Private/Invoke-LabAddVMMenu.ps1') | Should -Be $true
    }
    It 'Invoke-LabAddVMWizard.ps1 exists' {
        Test-Path (Join-Path $script:repoRoot 'Private/Invoke-LabAddVMWizard.ps1') | Should -Be $true
    }
    It 'Invoke-LabConfigureRoleMenu.ps1 exists' {
        Test-Path (Join-Path $script:repoRoot 'Private/Invoke-LabConfigureRoleMenu.ps1') | Should -Be $true
    }
    It 'Invoke-LabSetupMenu.ps1 exists' {
        Test-Path (Join-Path $script:repoRoot 'Private/Invoke-LabSetupMenu.ps1') | Should -Be $true
    }
}

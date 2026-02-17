BeforeAll {
    Set-StrictMode -Version Latest
}

# TestCases must be defined at discovery time (outside BeforeAll) for Pester 5 data-driven tests.
# Import-LabScriptTree.ps1 contains Get-LabScriptFiles (not Import-LabScriptTree).
$functionCases = @(
    @{ File = 'Private/Invoke-LabOrchestrationActionCore.ps1'; FuncName = 'Invoke-LabOrchestrationActionCore' }
    @{ File = 'Private/Invoke-LabOneButtonReset.ps1';          FuncName = 'Invoke-LabOneButtonReset' }
    @{ File = 'Private/Invoke-LabSetup.ps1';                   FuncName = 'Invoke-LabSetup' }
    @{ File = 'Private/Invoke-LabQuickDeploy.ps1';             FuncName = 'Invoke-LabQuickDeploy' }
    @{ File = 'Private/Invoke-LabLogRetention.ps1';            FuncName = 'Invoke-LabLogRetention' }
    @{ File = 'Private/Import-LabScriptTree.ps1';              FuncName = 'Get-LabScriptFiles' }
    @{ File = 'Private/Ensure-VMsReady.ps1';                   FuncName = 'Ensure-VMsReady' }
    @{ File = 'Private/Clear-LabSSHKnownHosts.ps1';            FuncName = 'Clear-LabSSHKnownHosts' }
    @{ File = 'Private/Write-LabRunArtifacts.ps1';             FuncName = 'Write-LabRunArtifacts' }
    @{ File = 'Private/New-LabDeploymentReport.ps1';           FuncName = 'New-LabDeploymentReport' }
)

Describe 'Error Handling - Batch 1: Orchestration & Lifecycle' {

    It '<FuncName> has try-catch error handling' -TestCases $functionCases {
        param($File, $FuncName)
        $filePath = Join-Path $PSScriptRoot "..\$File"
        $content = Get-Content $filePath -Raw
        $content | Should -Match 'try\s*\{' -Because "$FuncName must have try-catch"
        $content | Should -Match 'catch\s*\{' -Because "$FuncName must have catch block"
    }

    It '<FuncName> error message includes function name' -TestCases $functionCases {
        param($File, $FuncName)
        $filePath = Join-Path $PSScriptRoot "..\$File"
        $content = Get-Content $filePath -Raw
        $content | Should -Match ([regex]::Escape($FuncName) + ':') -Because "error messages must include function name for grep-ability (ERR-03)"
    }
}

# ErrorHandling-Batch2.Tests.ps1
# Tests verifying error handling pattern for 10 configuration and data-building Private functions

BeforeAll {
    Set-StrictMode -Version Latest

    $script:repoRoot = Split-Path -Parent $PSScriptRoot

    $script:functions = @(
        'Private/Get-LabDomainConfig.ps1',
        'Private/Get-LabNetworkConfig.ps1',
        'Private/Get-LabVMConfig.ps1',
        'Private/Get-GitIdentity.ps1',
        'Private/Get-HostInfo.ps1',
        'Private/Get-LabGuiDestructiveGuard.ps1',
        'Private/New-LabAppArgumentList.ps1',
        'Private/New-LabCoordinatorPlan.ps1',
        'Private/New-LabUnattendXml.ps1',
        'Private/Resolve-LabSqlPassword.ps1'
    )
}

Describe 'Error Handling - Batch 2: Configuration & Data-Building Functions' {

    It '<funcName> has try-catch error handling' -TestCases @(
        @{ funcName = 'Get-LabDomainConfig';        relPath = 'Private/Get-LabDomainConfig.ps1' }
        @{ funcName = 'Get-LabNetworkConfig';       relPath = 'Private/Get-LabNetworkConfig.ps1' }
        @{ funcName = 'Get-LabVMConfig';            relPath = 'Private/Get-LabVMConfig.ps1' }
        @{ funcName = 'Get-GitIdentity';            relPath = 'Private/Get-GitIdentity.ps1' }
        @{ funcName = 'Get-HostInfo';               relPath = 'Private/Get-HostInfo.ps1' }
        @{ funcName = 'Get-LabGuiDestructiveGuard'; relPath = 'Private/Get-LabGuiDestructiveGuard.ps1' }
        @{ funcName = 'New-LabAppArgumentList';     relPath = 'Private/New-LabAppArgumentList.ps1' }
        @{ funcName = 'New-LabCoordinatorPlan';     relPath = 'Private/New-LabCoordinatorPlan.ps1' }
        @{ funcName = 'New-LabUnattendXml';         relPath = 'Private/New-LabUnattendXml.ps1' }
        @{ funcName = 'Resolve-LabSqlPassword';     relPath = 'Private/Resolve-LabSqlPassword.ps1' }
    ) {
        param($funcName, $relPath)
        $filePath = Join-Path $script:repoRoot $relPath
        $content = Get-Content $filePath -Raw
        $content | Should -Match 'try\s*\{' -Because "$funcName must have try-catch"
        $content | Should -Match 'catch\s*\{' -Because "$funcName must have catch block"
    }

    It '<funcName> error message includes function name' -TestCases @(
        @{ funcName = 'Get-LabDomainConfig';        relPath = 'Private/Get-LabDomainConfig.ps1' }
        @{ funcName = 'Get-LabNetworkConfig';       relPath = 'Private/Get-LabNetworkConfig.ps1' }
        @{ funcName = 'Get-LabVMConfig';            relPath = 'Private/Get-LabVMConfig.ps1' }
        @{ funcName = 'Get-GitIdentity';            relPath = 'Private/Get-GitIdentity.ps1' }
        @{ funcName = 'Get-HostInfo';               relPath = 'Private/Get-HostInfo.ps1' }
        @{ funcName = 'Get-LabGuiDestructiveGuard'; relPath = 'Private/Get-LabGuiDestructiveGuard.ps1' }
        @{ funcName = 'New-LabAppArgumentList';     relPath = 'Private/New-LabAppArgumentList.ps1' }
        @{ funcName = 'New-LabCoordinatorPlan';     relPath = 'Private/New-LabCoordinatorPlan.ps1' }
        @{ funcName = 'New-LabUnattendXml';         relPath = 'Private/New-LabUnattendXml.ps1' }
        @{ funcName = 'Resolve-LabSqlPassword';     relPath = 'Private/Resolve-LabSqlPassword.ps1' }
    ) {
        param($funcName, $relPath)
        $filePath = Join-Path $script:repoRoot $relPath
        $content = Get-Content $filePath -Raw
        $content | Should -Match ([regex]::Escape($funcName) + ':') -Because "error messages must include function name for grep-ability (ERR-03)"
    }
}

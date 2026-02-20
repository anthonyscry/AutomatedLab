BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $appContent = Get-Content -Path (Join-Path $repoRoot 'OpenCodeLab-App.ps1') -Raw
    $deployContent = Get-Content -Path (Join-Path $repoRoot 'Deploy.ps1') -Raw
}

Describe 'OpenCodeLab-App.ps1 validate action' {

    It '-Action parameter ValidateSet includes validate' {
        $match = Select-String -InputObject $appContent -Pattern "'validate'"
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Action switch block contains validate case' {
        $match = Select-String -InputObject $appContent -Pattern "'validate'\s*\{"
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Validate action calls Test-LabConfigValidation' {
        $match = Select-String -InputObject $appContent -Pattern 'Test-LabConfigValidation'
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Validate action conditionally passes -Scenario parameter' {
        $match = Select-String -InputObject $appContent -Pattern "PSBoundParameters\.ContainsKey\('Scenario'\).*validateSplat"
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Validate action formats output with colored status indicators' {
        $match = Select-String -InputObject $appContent -Pattern 'Write-Host.*ForegroundColor.*statusColor'
        $match | Should -Not -BeNullOrEmpty
    }
}

Describe 'Deploy.ps1 pre-deploy validation' {

    It 'Deploy.ps1 dot-sources Test-LabConfigValidation.ps1' {
        $match = Select-String -InputObject $deployContent -Pattern 'Test-LabConfigValidation\.ps1'
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Deploy.ps1 dot-sources Get-LabHostResourceInfo.ps1' {
        $match = Select-String -InputObject $deployContent -Pattern 'Get-LabHostResourceInfo\.ps1'
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Deploy.ps1 calls Test-LabConfigValidation when scenario is specified' {
        $match = Select-String -InputObject $deployContent -Pattern 'Test-LabConfigValidation\s+-Scenario'
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Deploy.ps1 halts on validation failure' {
        $match = Select-String -InputObject $deployContent -Pattern "throw.*Pre-deploy validation failed"
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Deploy.ps1 prints pre-deploy validation passed on success' {
        $match = Select-String -InputObject $deployContent -Pattern 'Pre-deploy validation passed'
        $match | Should -Not -BeNullOrEmpty
    }
}

Describe 'Function wiring' {

    It 'Private/Test-LabConfigValidation.ps1 exists and parses without error' {
        $filePath = Join-Path $repoRoot 'Private/Test-LabConfigValidation.ps1'
        Test-Path $filePath | Should -BeTrue
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It 'Private/Get-LabHostResourceInfo.ps1 exists and parses without error' {
        $filePath = Join-Path $repoRoot 'Private/Get-LabHostResourceInfo.ps1'
        Test-Path $filePath | Should -BeTrue
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It 'Test-LabConfigValidation function is defined with -Scenario parameter' {
        $content = Get-Content -Path (Join-Path $repoRoot 'Private/Test-LabConfigValidation.ps1') -Raw
        $match = Select-String -InputObject $content -Pattern '\[string\]\$Scenario'
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Test-LabConfigValidation function is defined with -TemplatesRoot parameter' {
        $content = Get-Content -Path (Join-Path $repoRoot 'Private/Test-LabConfigValidation.ps1') -Raw
        $match = Select-String -InputObject $content -Pattern '\[string\]\$TemplatesRoot'
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Get-LabHostResourceInfo function is defined with -DiskPath parameter' {
        $content = Get-Content -Path (Join-Path $repoRoot 'Private/Get-LabHostResourceInfo.ps1') -Raw
        $match = Select-String -InputObject $content -Pattern '\[string\]\$DiskPath'
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Test-LabConfigValidation calls Get-LabHostResourceInfo' {
        $content = Get-Content -Path (Join-Path $repoRoot 'Private/Test-LabConfigValidation.ps1') -Raw
        $match = Select-String -InputObject $content -Pattern 'Get-LabHostResourceInfo'
        $match | Should -Not -BeNullOrEmpty
    }

    It 'Test-LabConfigValidation produces checks with Remediation field' {
        $content = Get-Content -Path (Join-Path $repoRoot 'Private/Test-LabConfigValidation.ps1') -Raw
        $match = Select-String -InputObject $content -Pattern 'Remediation' -AllMatches
        $match | Should -Not -BeNullOrEmpty
    }
}

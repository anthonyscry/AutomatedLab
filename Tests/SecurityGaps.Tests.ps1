# SecurityGaps.Tests.ps1
# Verifies all 4 security production gaps (S1-S4) are closed

BeforeAll {
    Set-StrictMode -Version Latest

    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:PrivatePath = Join-Path $script:RepoRoot 'Private'
    $script:PublicPath = Join-Path $script:RepoRoot 'Public'
    $script:ScriptsPath = Join-Path $script:RepoRoot 'Scripts'

    # Dot-source the function for S4 test
    . (Join-Path $script:PrivatePath 'New-LabUnattendXml.ps1')
}

Describe "S1 - No hardcoded default password in Initialize-LabVMs" {
    It "Should not contain hardcoded default password 'SimpleLab123!'" {
        $initializeLabVMsPath = Join-Path $script:PublicPath 'Initialize-LabVMs.ps1'
        $content = Get-Content $initializeLabVMsPath -Raw

        $content | Should -Not -Match "SimpleLab123!" -Because "hardcoded default passwords are a security risk"
    }

    It "Should use GlobalLabConfig.Credentials.AdminPassword" {
        $initializeLabVMsPath = Join-Path $script:PublicPath 'Initialize-LabVMs.ps1'
        $matches = Select-String -Path $initializeLabVMsPath -Pattern '\$GlobalLabConfig\.Credentials\.AdminPassword'

        $matches | Should -Not -BeNullOrEmpty -Because "password should come from config"
    }

    It "Should use empty string as fallback (not hardcoded password)" {
        $initializeLabVMsPath = Join-Path $script:PublicPath 'Initialize-LabVMs.ps1'
        $content = Get-Content $initializeLabVMsPath -Raw

        # Line 109: $defaultPassword = if (Test-Path variable:GlobalLabConfig) { $GlobalLabConfig.Credentials.AdminPassword } else { '' }
        $content | Should -Match "else\s*\{\s*''\s*\}" -Because "fallback should be empty string, not a hardcoded password"
    }
}

Describe "S2 - StrictHostKeyChecking=accept-new everywhere (no StrictHostKeyChecking=no)" {
    It "Should not use StrictHostKeyChecking=no anywhere in codebase" {
        $testsDir = Join-Path $script:RepoRoot 'Tests'
        $allPsFiles = Get-ChildItem -Path $script:RepoRoot -Filter "*.ps1" -Recurse -File |
            Where-Object { $_.FullName -notlike "*$([IO.Path]::DirectorySeparatorChar)Tests$([IO.Path]::DirectorySeparatorChar)*" -and $_.DirectoryName -ne $testsDir }

        $badMatches = @()
        foreach ($file in $allPsFiles) {
            $fileMatches = Select-String -Path $file.FullName -Pattern 'StrictHostKeyChecking=no' -ErrorAction SilentlyContinue
            if ($fileMatches) {
                $badMatches += $fileMatches
            }
        }

        $badMatches.Count | Should -Be 0 -Because "StrictHostKeyChecking=no disables host key verification and is insecure"
    }

    It "Should use StrictHostKeyChecking=accept-new in SSH calls" {
        $testsDir = Join-Path $script:RepoRoot 'Tests'
        $allPsFiles = Get-ChildItem -Path $script:RepoRoot -Filter "*.ps1" -Recurse -File |
            Where-Object { $_.FullName -notlike "*$([IO.Path]::DirectorySeparatorChar)Tests$([IO.Path]::DirectorySeparatorChar)*" -and $_.DirectoryName -ne $testsDir }

        $goodMatches = @()
        foreach ($file in $allPsFiles) {
            $matches = Select-String -Path $file.FullName -Pattern 'StrictHostKeyChecking=accept-new' -ErrorAction SilentlyContinue
            if ($matches) {
                $goodMatches += $matches
            }
        }

        $goodMatches.Count | Should -BeGreaterThan 0 -Because "accept-new is the secure alternative that validates known hosts"
    }
}

Describe "S3 - Git installer SHA256 validation in Deploy.ps1" {
    It "Should use Get-FileHash for checksum validation" {
        $deployPath = Join-Path $script:RepoRoot 'Deploy.ps1'
        $matches = Select-String -Path $deployPath -Pattern 'Get-FileHash'

        $matches | Should -Not -BeNullOrEmpty -Because "downloads must be validated with checksums"
    }

    It "Should reject downloads when no checksum is provided" {
        $deployPath = Join-Path $script:RepoRoot 'Deploy.ps1'
        $content = Get-Content $deployPath -Raw

        $content | Should -Match "no checksum provided" -Because "rejecting unsigned downloads prevents supply-chain attacks"
    }

    It "Should reference SoftwarePackages.Git.Sha256 config" {
        $deployPath = Join-Path $script:RepoRoot 'Deploy.ps1'
        $matches = Select-String -Path $deployPath -Pattern 'SoftwarePackages\.Git\.Sha256'

        $matches | Should -Not -BeNullOrEmpty -Because "SHA256 checksum should come from configuration"
    }
}

Describe "S4 - Plaintext password warning in New-LabUnattendXml" {
    It "Should emit Write-Warning about plaintext password storage" {
        $warnings = @()
        $xml = New-LabUnattendXml -ComputerName "test" -AdministratorPassword "P@ss" -OSType "Server2019" -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings | Should -Not -BeNullOrEmpty -Because "users must be warned about plaintext password storage"
    }

    It "Should include 'plaintext' in the warning message" {
        $warnings = @()
        $xml = New-LabUnattendXml -ComputerName "test" -AdministratorPassword "P@ss" -OSType "Server2019" -WarningVariable warnings -WarningAction SilentlyContinue

        $warnings[0] | Should -Match "plaintext" -Because "the warning should explicitly mention plaintext storage"
    }

    It "Should still return valid XML output" {
        $xml = New-LabUnattendXml -ComputerName "test" -AdministratorPassword "P@ss" -OSType "Server2019" -WarningAction SilentlyContinue

        $xml | Should -Not -BeNullOrEmpty -Because "function must still return XML"
        $xml | Should -Match '<unattend' -Because "output must be valid unattend.xml"
    }
}

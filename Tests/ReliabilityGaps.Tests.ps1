# ReliabilityGaps.Tests.ps1
# Verifies all 4 reliability production gaps (R1-R4) are closed

BeforeAll {
    Set-StrictMode -Version Latest

    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:PrivatePath = Join-Path $script:RepoRoot 'Private'
    $script:PublicPath = Join-Path $script:RepoRoot 'Public'
}

Describe "R1 - Test-DCPromotionPrereqs always runs network check" {
    It "Should not contain early return inside check blocks (before Check 5)" {
        $filePath = Join-Path $script:PrivatePath 'Test-DCPromotionPrereqs.ps1'
        $content = Get-Content $filePath -Raw

        # The function should have exactly 2 return $result occurrences:
        # one at the end of the try block and one in the outer catch
        $returnMatches = [regex]::Matches($content, 'return \$result')

        $returnMatches.Count | Should -Be 2 -Because "there should be exactly 2 return statements (end of try block and outer catch), not one per check"
    }

    It "Should use canProceedToVMChecks flag to control in-VM check flow" {
        $filePath = Join-Path $script:PrivatePath 'Test-DCPromotionPrereqs.ps1'
        $matches = Select-String -Path $filePath -Pattern 'canProceedToVMChecks'

        $matches | Should -Not -BeNullOrEmpty -Because "a guard flag is required to control whether in-VM checks are skipped without early return"
    }

    It "Should include a NetworkConnectivity check result" {
        $filePath = Join-Path $script:PrivatePath 'Test-DCPromotionPrereqs.ps1'
        $matches = Select-String -Path $filePath -Pattern 'NetworkConnectivity'

        $matches | Should -Not -BeNullOrEmpty -Because "Check 5 (network) must always be recorded in the Checks array"
    }

    It "Should calculate CanPromote from accumulated check results at the end" {
        $filePath = Join-Path $script:PrivatePath 'Test-DCPromotionPrereqs.ps1'
        $matches = Select-String -Path $filePath -Pattern 'CanPromote\s*=\s*\('

        $matches | Should -Not -BeNullOrEmpty -Because "CanPromote must be derived from accumulated check results, not set during individual check"
    }
}

Describe "R2 - Ensure-VMsReady uses return instead of exit 0" {
    It "Should not contain any 'exit' calls" {
        $filePath = Join-Path $script:PrivatePath 'Ensure-VMsReady.ps1'
        $exitMatches = Select-String -Path $filePath -Pattern '\bexit\b' -ErrorAction SilentlyContinue

        $exitMatches | Should -BeNullOrEmpty -Because "exit terminates the PowerShell host; return is the correct way to exit a function"
    }

    It "Should contain 'return' for early exit logic" {
        $filePath = Join-Path $script:PrivatePath 'Ensure-VMsReady.ps1'
        $returnMatches = Select-String -Path $filePath -Pattern '\breturn\b'

        $returnMatches | Should -Not -BeNullOrEmpty -Because "early function exit must use return, not exit"
    }
}

Describe "R3 - IP address and CIDR prefix validation" {
    It "Set-VMStaticIP should validate IP address format with ValidatePattern" {
        $filePath = Join-Path $script:PrivatePath 'Set-VMStaticIP.ps1'
        $matches = Select-String -Path $filePath -Pattern 'ValidatePattern'

        $matches | Should -Not -BeNullOrEmpty -Because "IP address format must be validated with a ValidatePattern attribute"
    }

    It "Set-VMStaticIP should validate PrefixLength range with ValidateRange" {
        $filePath = Join-Path $script:PrivatePath 'Set-VMStaticIP.ps1'
        $matches = Select-String -Path $filePath -Pattern 'ValidateRange'

        $matches | Should -Not -BeNullOrEmpty -Because "prefix length must be validated as 1-32 with a ValidateRange attribute"
    }

    It "New-LabNAT should have ValidatePattern on GatewayIP" {
        $filePath = Join-Path $script:PublicPath 'New-LabNAT.ps1'
        $matches = Select-String -Path $filePath -Pattern 'ValidatePattern'

        $matches | Should -Not -BeNullOrEmpty -Because "gateway IP format must be validated with a pattern"
    }

    It "New-LabNAT should validate CIDR prefix length after extraction" {
        $filePath = Join-Path $script:PublicPath 'New-LabNAT.ps1'
        $matches = Select-String -Path $filePath -Pattern 'Invalid CIDR prefix length'

        $matches | Should -Not -BeNullOrEmpty -Because "extracted prefix length must be validated as 1-32 before use"
    }
}

Describe "R4 - Config-based paths instead of hardcoded values" {
    It "New-LabSSHKey should use GlobalLabConfig.Linux.SSHKeyDir" {
        $filePath = Join-Path $script:PublicPath 'New-LabSSHKey.ps1'
        $matches = Select-String -Path $filePath -Pattern 'GlobalLabConfig\.Linux\.SSHKeyDir'

        $matches | Should -Not -BeNullOrEmpty -Because "SSH key directory must be resolved from GlobalLabConfig, not hardcoded"
    }

    It "New-LabSSHKey should not use old Get-LabConfig pattern for SSH key path resolution" {
        $filePath = Join-Path $script:PublicPath 'New-LabSSHKey.ps1'
        $content = Get-Content $filePath -Raw

        # The old pattern used labConfig.LabSettings.SSHKeyDir
        $content | Should -Not -Match 'labConfig\.LabSettings\.SSHKeyDir' -Because "old Get-LabConfig lookup must be replaced with GlobalLabConfig"
    }

    It "Initialize-LabVMs should use GlobalLabConfig.Paths.LabRoot for VHD base path" {
        $filePath = Join-Path $script:PublicPath 'Initialize-LabVMs.ps1'
        $matches = Select-String -Path $filePath -Pattern 'GlobalLabConfig\.Paths\.LabRoot'

        $matches | Should -Not -BeNullOrEmpty -Because "VHD base path must be resolved from GlobalLabConfig, not hardcoded"
    }
}

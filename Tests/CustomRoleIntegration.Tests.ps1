Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot   = Split-Path $PSScriptRoot -Parent
    $script:PrivateDir = Join-Path $script:RepoRoot 'Private'
    . (Join-Path $script:PrivateDir 'Test-LabCustomRoleSchema.ps1')
    . (Join-Path $script:PrivateDir 'Get-LabCustomRole.ps1')

    $script:LabBuilderDir       = Join-Path $script:RepoRoot 'LabBuilder'
    $script:BuildScript         = Join-Path $script:LabBuilderDir 'Build-LabFromSelection.ps1'
    $script:InvokeScript        = Join-Path $script:LabBuilderDir 'Invoke-LabBuilder.ps1'
    $script:SelectScript        = Join-Path $script:LabBuilderDir 'Select-LabRoles.ps1'
    $script:ExampleRolePath     = Join-Path $script:RepoRoot '.planning'
    $script:ExampleRolePath     = Join-Path $script:ExampleRolePath 'roles'
    $script:ExampleRolePath     = Join-Path $script:ExampleRolePath 'example-role.json'
}

# =============================================================================
# Static analysis: Invoke-LabBuilder validation integration
# =============================================================================
Describe 'Custom Role Integration - Invoke-LabBuilder validation' {

    Context 'Get-LabCustomRole reference in Invoke-LabBuilder.ps1' {

        It 'contains a Get-LabCustomRole call to expand validTags' {
            $matches = Select-String -Path $script:InvokeScript -Pattern 'Get-LabCustomRole'
            $matches | Should -Not -BeNullOrEmpty -Because 'Invoke-LabBuilder must call Get-LabCustomRole to include custom roles in validation'
        }

        It 'still defines the built-in validTags array' {
            $matches = Select-String -Path $script:InvokeScript -Pattern '\$validTags\s*='
            $matches | Should -Not -BeNullOrEmpty -Because 'built-in validTags array must still exist alongside custom role expansion'
        }
    }
}

# =============================================================================
# Static analysis: Build-LabFromSelection pipeline integration
# =============================================================================
Describe 'Custom Role Integration - Build-LabFromSelection pipeline' {

    Context 'Get-LabCustomRole reference in Build-LabFromSelection.ps1' {

        It 'contains a Get-LabCustomRole call to load custom role definitions' {
            $matches = Select-String -Path $script:BuildScript -Pattern 'Get-LabCustomRole'
            $matches | Should -Not -BeNullOrEmpty -Because 'Build-LabFromSelection must call Get-LabCustomRole to load custom role defs'
        }

        It 'handles IsCustomRole flag for custom role detection' {
            $matches = Select-String -Path $script:BuildScript -Pattern 'IsCustomRole'
            $matches | Should -Not -BeNullOrEmpty -Because 'Build-LabFromSelection must check IsCustomRole to route custom roles to the provisioning block'
        }

        It 'handles ProvisioningSteps for custom role execution' {
            $matches = Select-String -Path $script:BuildScript -Pattern 'ProvisioningSteps'
            $matches | Should -Not -BeNullOrEmpty -Because 'Build-LabFromSelection must iterate ProvisioningSteps to execute custom role provisioning'
        }
    }
}

# =============================================================================
# Static analysis: Select-LabRoles menu integration
# =============================================================================
Describe 'Custom Role Integration - Select-LabRoles menu' {

    Context 'Get-LabCustomRole reference in Select-LabRoles.ps1' {

        It 'contains a Get-LabCustomRole call to append custom roles to the menu' {
            $matches = Select-String -Path $script:SelectScript -Pattern 'Get-LabCustomRole'
            $matches | Should -Not -BeNullOrEmpty -Because 'Select-LabRoles must call Get-LabCustomRole to add custom roles to the interactive menu'
        }

        It 'contains a Custom Roles separator for the menu section' {
            $matches = Select-String -Path $script:SelectScript -Pattern 'Custom Roles'
            $matches | Should -Not -BeNullOrEmpty -Because 'Select-LabRoles must display a Custom Roles separator to distinguish custom from built-in roles'
        }
    }
}

# =============================================================================
# End-to-end: Discovery to role definition
# =============================================================================
Describe 'Custom Role End-to-End - Discovery to Role Def' {

    Context 'Get-LabCustomRole -Name returns a full role definition hashtable' {

        It 'returns a hashtable with all standard role definition keys when given a valid JSON in TestDrive' {
            # Create a minimal valid role JSON in TestDrive
            $roleJson = @'
{
  "name": "TestRole",
  "tag": "TestRole",
  "description": "Integration test role",
  "os": "windows",
  "resources": {
    "memory": "2GB",
    "minMemory": "1GB",
    "maxMemory": "4GB",
    "processors": 2
  },
  "provisioningSteps": [
    { "name": "install-feature", "type": "windowsFeature", "value": "Telnet-Client" }
  ],
  "vmNameDefault": "TEST1",
  "autoLabRoles": []
}
'@
            $rolesPath = Join-Path $TestDrive 'roles'
            $null = New-Item -Path $rolesPath -ItemType Directory -Force
            Set-Content -Path (Join-Path $rolesPath 'testrole.json') -Value $roleJson -Encoding UTF8

            $mockConfig = @{
                VMNames    = @{ TestRole = 'TEST1' }
                IPPlan     = @{ TestRole = '192.168.10.50'; DC = '192.168.10.10' }
                Network    = @{ Gateway = '192.168.10.1'; SwitchName = 'LabSwitch' }
                DomainName = 'lab.local'
                ServerOS   = 'Windows Server 2022 Datacenter'
            }

            $result = Get-LabCustomRole -Name 'TestRole' -Config $mockConfig -RolesPath $rolesPath

            $result             | Should -Not -BeNullOrEmpty
            $result.Tag         | Should -Be 'TestRole'
            $result.VMName      | Should -Be 'TEST1'
            $result.OS          | Should -Not -BeNullOrEmpty
            $result.IP          | Should -Not -BeNullOrEmpty
            $result.Memory      | Should -BeGreaterThan 0
            $result.MinMemory   | Should -BeGreaterThan 0
            $result.MaxMemory   | Should -BeGreaterThan 0
            $result.Processors  | Should -Be 2
            $result.DomainName  | Should -Be 'lab.local'
            $result.Network     | Should -Be 'LabSwitch'
            $result.IsCustomRole | Should -Be $true
            $result.ProvisioningSteps | Should -Not -BeNullOrEmpty
        }

        It 'returns list metadata with expected properties when given a valid JSON in TestDrive' {
            $roleJson = @'
{
  "name": "ListTestRole",
  "tag": "ListTestRole",
  "description": "A role for list testing",
  "os": "windows",
  "resources": {
    "memory": "4GB",
    "minMemory": "2GB",
    "maxMemory": "8GB",
    "processors": 4
  },
  "provisioningSteps": [
    { "name": "step1", "type": "powershellScript", "value": "Write-Host done" }
  ],
  "vmNameDefault": "LSTTEST1",
  "autoLabRoles": []
}
'@
            $rolesPath = Join-Path $TestDrive 'listroles'
            $null = New-Item -Path $rolesPath -ItemType Directory -Force
            Set-Content -Path (Join-Path $rolesPath 'listtestrole.json') -Value $roleJson -Encoding UTF8

            $result = Get-LabCustomRole -List -RolesPath $rolesPath

            $result                          | Should -Not -BeNullOrEmpty
            $result.Count                    | Should -Be 1
            $result[0].Name                  | Should -Be 'ListTestRole'
            $result[0].Tag                   | Should -Be 'ListTestRole'
            $result[0].Description           | Should -Not -BeNullOrEmpty
            $result[0].OS                    | Should -Be 'windows'
            $result[0].Resources             | Should -Not -BeNullOrEmpty
            $result[0].ProvisioningStepCount | Should -Be 1
        }

        It 'loads the example-role.json from .planning/roles/ via -List' {
            if (-not (Test-Path $script:ExampleRolePath)) {
                Set-ItResult -Skipped -Because ".planning/roles/example-role.json not found in repo"
                return
            }

            $exampleRolesPath = Split-Path $script:ExampleRolePath -Parent
            $result = Get-LabCustomRole -List -RolesPath $exampleRolesPath

            $result       | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterOrEqual 1
            $result[0].Name | Should -Not -BeNullOrEmpty
            $result[0].Tag  | Should -Not -BeNullOrEmpty
        }
    }
}

# =============================================================================
# Static analysis: Provisioning step types in Build-LabFromSelection
# =============================================================================
Describe 'Custom Role Provisioning Step Types' {

    Context 'Switch statement covers expected step types' {

        It 'recognizes windowsFeature step type in Build-LabFromSelection.ps1' {
            $matches = Select-String -Path $script:BuildScript -Pattern "'windowsFeature'"
            $matches | Should -Not -BeNullOrEmpty -Because "windowsFeature step type must be handled in the switch statement"
        }

        It 'recognizes powershellScript step type in Build-LabFromSelection.ps1' {
            $matches = Select-String -Path $script:BuildScript -Pattern "'powershellScript'"
            $matches | Should -Not -BeNullOrEmpty -Because "powershellScript step type must be handled in the switch statement"
        }

        It 'produces a Write-Warning for unknown step types in Build-LabFromSelection.ps1' {
            $matches = Select-String -Path $script:BuildScript -Pattern 'Write-Warning.*Unknown provisioning step type'
            $matches | Should -Not -BeNullOrEmpty -Because "unknown provisioning step types must log a warning rather than silently skip"
        }
    }
}

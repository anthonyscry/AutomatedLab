Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot  = Split-Path $PSScriptRoot -Parent
    $script:PrivateDir = Join-Path $script:RepoRoot 'Private'
    . (Join-Path $script:PrivateDir 'Test-LabCustomRoleSchema.ps1')
    . (Join-Path $script:PrivateDir 'Get-LabCustomRole.ps1')

    # Build a valid role hashtable used as a baseline throughout tests
    $script:ValidStep = @{
        name  = 'Install-SNMP'
        type  = 'windowsFeature'
        value = 'SNMP-Service'
    }

    $script:ValidRole = @{
        name              = 'MonitoringServer'
        tag               = 'MonitoringServer'
        description       = 'A test monitoring server role'
        os                = 'windows'
        resources         = @{
            memory     = '4GB'
            minMemory  = '2GB'
            maxMemory  = '8GB'
            processors = 2
        }
        provisioningSteps = @($script:ValidStep)
        vmNameDefault     = 'MON1'
        autoLabRoles      = @()
    }

    # Path to the actual .planning/roles directory in the repo
    $script:RealRolesPath = Join-Path $script:RepoRoot '.planning\roles'
}

# ═══════════════════════════════════════════════════════════════════════════════
# Test-LabCustomRoleSchema
# ═══════════════════════════════════════════════════════════════════════════════
Describe 'Test-LabCustomRoleSchema' {

    Context 'Valid role data' {

        It 'returns Valid=$true and empty errors for a complete valid role' {
            $result = Test-LabCustomRoleSchema -RoleData $script:ValidRole -FilePath 'test.json'
            $result.Valid   | Should -Be $true
            $result.Errors  | Should -HaveCount 0
        }
    }

    Context 'Missing required top-level fields' {

        It 'returns Valid=$false with error mentioning "name" when name is missing' {
            $role = $script:ValidRole.Clone()
            $role.Remove('name')
            $result = Test-LabCustomRoleSchema -RoleData $role -FilePath 'test.json'
            $result.Valid  | Should -Be $false
            $result.Errors | Should -Contain ($result.Errors | Where-Object { $_ -match "'name'" } | Select-Object -First 1)
            $result.Errors -join ' ' | Should -Match "'name'"
        }

        It 'returns error mentioning "tag" when tag is missing' {
            $role = $script:ValidRole.Clone()
            $role.Remove('tag')
            $result = Test-LabCustomRoleSchema -RoleData $role -FilePath 'test.json'
            $result.Valid            | Should -Be $false
            $result.Errors -join ' ' | Should -Match "'tag'"
        }

        It 'returns error mentioning "description" when description is missing' {
            $role = $script:ValidRole.Clone()
            $role.Remove('description')
            $result = Test-LabCustomRoleSchema -RoleData $role -FilePath 'test.json'
            $result.Valid            | Should -Be $false
            $result.Errors -join ' ' | Should -Match "'description'"
        }

        It 'returns error mentioning "os" when os is missing' {
            $role = $script:ValidRole.Clone()
            $role.Remove('os')
            $result = Test-LabCustomRoleSchema -RoleData $role -FilePath 'test.json'
            $result.Valid            | Should -Be $false
            $result.Errors -join ' ' | Should -Match "'os'"
        }
    }

    Context 'Tag format validation' {

        It 'returns error when tag contains spaces' {
            $role = $script:ValidRole.Clone()
            $role['tag'] = 'My Custom Role'
            $result = Test-LabCustomRoleSchema -RoleData $role -FilePath 'test.json'
            $result.Valid            | Should -Be $false
            $result.Errors -join ' ' | Should -Match "'tag'"
        }

        It 'accepts tags with hyphens and underscores' {
            $role = $script:ValidRole.Clone()
            $role['tag'] = 'My-Custom_Role123'
            $result = Test-LabCustomRoleSchema -RoleData $role -FilePath 'test.json'
            $result.Valid | Should -Be $true
        }
    }

    Context 'OS field validation' {

        It 'returns error when os is not windows or linux' {
            $role = $script:ValidRole.Clone()
            $role['os'] = 'bsd'
            $result = Test-LabCustomRoleSchema -RoleData $role -FilePath 'test.json'
            $result.Valid            | Should -Be $false
            $result.Errors -join ' ' | Should -Match "'os'"
        }

        It 'accepts os=windows' {
            $role = $script:ValidRole.Clone()
            $role['os'] = 'windows'
            $result = Test-LabCustomRoleSchema -RoleData $role -FilePath 'test.json'
            $result.Valid | Should -Be $true
        }

        It 'accepts os=linux' {
            $role = $script:ValidRole.Clone()
            $role['os'] = 'linux'
            $result = Test-LabCustomRoleSchema -RoleData $role -FilePath 'test.json'
            $result.Valid | Should -Be $true
        }
    }

    Context 'provisioningSteps validation' {

        It 'returns error when provisioningSteps is missing' {
            $role = $script:ValidRole.Clone()
            $role.Remove('provisioningSteps')
            $result = Test-LabCustomRoleSchema -RoleData $role -FilePath 'test.json'
            $result.Valid            | Should -Be $false
            $result.Errors -join ' ' | Should -Match "'provisioningSteps'"
        }

        It 'returns error when provisioningSteps is an empty array' {
            $role = $script:ValidRole.Clone()
            $role['provisioningSteps'] = @()
            $result = Test-LabCustomRoleSchema -RoleData $role -FilePath 'test.json'
            $result.Valid            | Should -Be $false
            $result.Errors -join ' ' | Should -Match "'provisioningSteps'"
        }

        It 'returns error when a step is missing the type field' {
            $step = @{ name = 'Install-X'; value = 'X' }   # no 'type'
            $role = $script:ValidRole.Clone()
            $role['provisioningSteps'] = @($step)
            $result = Test-LabCustomRoleSchema -RoleData $role -FilePath 'test.json'
            $result.Valid            | Should -Be $false
            $result.Errors -join ' ' | Should -Match "'type'"
        }

        It 'returns error when a step has an invalid type value' {
            $step = @{ name = 'Install-X'; type = 'dockerCommand'; value = 'X' }
            $role = $script:ValidRole.Clone()
            $role['provisioningSteps'] = @($step)
            $result = Test-LabCustomRoleSchema -RoleData $role -FilePath 'test.json'
            $result.Valid            | Should -Be $false
            $result.Errors -join ' ' | Should -Match "'type'"
        }

        It 'accepts valid step types: windowsFeature, powershellScript, linuxCommand' {
            foreach ($stepType in @('windowsFeature', 'powershellScript', 'linuxCommand')) {
                $step = @{ name = "Step-$stepType"; type = $stepType; value = 'something' }
                $role = $script:ValidRole.Clone()
                $role['provisioningSteps'] = @($step)
                $result = Test-LabCustomRoleSchema -RoleData $role -FilePath 'test.json'
                $result.Valid | Should -Be $true -Because "step type '$stepType' should be valid"
            }
        }
    }

    Context 'Multiple errors' {

        It 'returns multiple errors when multiple required fields are missing' {
            $result = Test-LabCustomRoleSchema -RoleData @{ name = 'x' } -FilePath 'multi.json'
            $result.Valid        | Should -Be $false
            $result.Errors.Count | Should -BeGreaterThan 1
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Get-LabCustomRole
# ═══════════════════════════════════════════════════════════════════════════════
Describe 'Get-LabCustomRole' {

    # ── Fixtures ──────────────────────────────────────────────────────────────
    BeforeAll {
        # Write a valid role JSON to TestDrive for isolated tests
        $script:ValidRoleJson = @'
{
  "name": "TestRole",
  "tag": "TestRole",
  "description": "A test role for Pester",
  "os": "windows",
  "resources": {
    "memory": "2GB",
    "minMemory": "1GB",
    "maxMemory": "4GB",
    "processors": 2
  },
  "provisioningSteps": [
    { "name": "Install-IIS", "type": "windowsFeature", "value": "Web-Server" }
  ],
  "vmNameDefault": "TEST1",
  "autoLabRoles": []
}
'@
        $script:ValidRoleJson2 = @'
{
  "name": "AnotherRole",
  "tag": "AnotherRole",
  "description": "Another test role sorted second",
  "os": "linux",
  "resources": {
    "memory": "512MB",
    "minMemory": "256MB",
    "maxMemory": "1GB",
    "processors": 1
  },
  "provisioningSteps": [
    { "name": "Install-nginx", "type": "linuxCommand", "value": "apt-get install -y nginx" }
  ],
  "vmNameDefault": "NGX1",
  "autoLabRoles": []
}
'@
        $script:BadJson = 'this is { not valid json }'
    }

    Context '-List mode' {

        It 'returns role objects with the correct properties for valid JSON files' {
            $rolesDir = Join-Path $TestDrive 'roles-list'
            New-Item -ItemType Directory -Path $rolesDir | Out-Null
            $script:ValidRoleJson | Set-Content -LiteralPath (Join-Path $rolesDir 'TestRole.json')

            $result = @(Get-LabCustomRole -List -RolesPath $rolesDir)
            $result.Count          | Should -Be 1
            $result[0].Name        | Should -Be 'TestRole'
            $result[0].Tag         | Should -Be 'TestRole'
            $result[0].Description | Should -Not -BeNullOrEmpty
            $result[0].OS          | Should -Be 'windows'
            $result[0].FilePath    | Should -Not -BeNullOrEmpty
            $result[0].ProvisioningStepCount | Should -Be 1
        }

        It 'returns an empty array when the roles directory does not exist' {
            $result = @(Get-LabCustomRole -List -RolesPath (Join-Path $TestDrive 'nonexistent'))
            $result.Count | Should -Be 0
        }

        It 'skips invalid JSON files with a warning and continues' {
            $rolesDir = Join-Path $TestDrive 'roles-invalid'
            New-Item -ItemType Directory -Path $rolesDir | Out-Null
            $script:ValidRoleJson | Set-Content -LiteralPath (Join-Path $rolesDir 'valid.json')
            $script:BadJson       | Set-Content -LiteralPath (Join-Path $rolesDir 'bad.json')

            $warnings = @()
            $result   = @(Get-LabCustomRole -List -RolesPath $rolesDir -WarningVariable warnings)

            $result.Count     | Should -Be 1
            $result[0].Name   | Should -Be 'TestRole'
            $warnings.Count   | Should -BeGreaterThan 0
        }

        It 'returns roles sorted alphabetically by Name' {
            $rolesDir = Join-Path $TestDrive 'roles-sorted'
            New-Item -ItemType Directory -Path $rolesDir | Out-Null
            $script:ValidRoleJson  | Set-Content -LiteralPath (Join-Path $rolesDir 'z-test.json')
            $script:ValidRoleJson2 | Set-Content -LiteralPath (Join-Path $rolesDir 'a-another.json')

            $result = @(Get-LabCustomRole -List -RolesPath $rolesDir)
            $result.Count  | Should -Be 2
            $result[0].Name | Should -Be 'AnotherRole'
            $result[1].Name | Should -Be 'TestRole'
        }
    }

    Context '-Name mode' {

        BeforeAll {
            $script:NameRolesDir = Join-Path $TestDrive 'roles-name'
            New-Item -ItemType Directory -Path $script:NameRolesDir | Out-Null
            $script:ValidRoleJson | Set-Content -LiteralPath (Join-Path $script:NameRolesDir 'TestRole.json')
        }

        It 'returns a hashtable matching the role by name (case-insensitive)' {
            $result = Get-LabCustomRole -Name 'testrole' -RolesPath $script:NameRolesDir
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [hashtable]
        }

        It 'returns $null when the named role does not exist' {
            $result = Get-LabCustomRole -Name 'NonExistentRole' -RolesPath $script:NameRolesDir
            $result | Should -BeNullOrEmpty
        }

        It 'returned hashtable has IsCustomRole=$true' {
            $result = Get-LabCustomRole -Name 'TestRole' -RolesPath $script:NameRolesDir
            $result.IsCustomRole | Should -Be $true
        }

        It 'returned hashtable has a ProvisioningSteps array' {
            $result = Get-LabCustomRole -Name 'TestRole' -RolesPath $script:NameRolesDir
            $result.ProvisioningSteps | Should -Not -BeNullOrEmpty
            @($result.ProvisioningSteps).Count | Should -BeGreaterThan 0
        }

        It 'returned hashtable has Tag, VMName, Memory, MinMemory, MaxMemory, Processors' {
            $result = Get-LabCustomRole -Name 'TestRole' -RolesPath $script:NameRolesDir
            $result.Tag        | Should -Be 'TestRole'
            $result.VMName     | Should -Be 'TEST1'       # vmNameDefault
            $result.Memory     | Should -BeGreaterThan 0
            $result.MinMemory  | Should -BeGreaterThan 0
            $result.MaxMemory  | Should -BeGreaterThan 0
            $result.Processors | Should -Be 2
        }

        It 'returned hashtable has a SourceFile path' {
            $result = Get-LabCustomRole -Name 'TestRole' -RolesPath $script:NameRolesDir
            $result.SourceFile | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Memory string parsing' {

        BeforeAll {
            $script:MemRolesDir = Join-Path $TestDrive 'roles-memory'
            New-Item -ItemType Directory -Path $script:MemRolesDir | Out-Null
        }

        It 'correctly parses GB memory strings' {
            $roleJson = @'
{
  "name": "GBRole","tag": "GBRole","description": "GB test","os": "windows",
  "resources": {"memory":"4GB","minMemory":"2GB","maxMemory":"8GB","processors":1},
  "provisioningSteps": [{"name":"S","type":"windowsFeature","value":"SNMP-Service"}],
  "vmNameDefault":"GB1","autoLabRoles":[]
}
'@
            $roleJson | Set-Content -LiteralPath (Join-Path $script:MemRolesDir 'GBRole.json')
            $result = Get-LabCustomRole -Name 'GBRole' -RolesPath $script:MemRolesDir
            $result.Memory    | Should -Be (4 * 1GB)
            $result.MinMemory | Should -Be (2 * 1GB)
            $result.MaxMemory | Should -Be (8 * 1GB)
        }

        It 'correctly parses MB memory strings' {
            $roleJson = @'
{
  "name": "MBRole","tag": "MBRole","description": "MB test","os": "linux",
  "resources": {"memory":"512MB","minMemory":"256MB","maxMemory":"1024MB","processors":1},
  "provisioningSteps": [{"name":"S","type":"linuxCommand","value":"echo ok"}],
  "vmNameDefault":"MB1","autoLabRoles":[]
}
'@
            $roleJson | Set-Content -LiteralPath (Join-Path $script:MemRolesDir 'MBRole.json')
            $result = Get-LabCustomRole -Name 'MBRole' -RolesPath $script:MemRolesDir
            $result.Memory    | Should -Be (512 * 1MB)
            $result.MinMemory | Should -Be (256 * 1MB)
            $result.MaxMemory | Should -Be (1024 * 1MB)
        }
    }

    Context 'Real example role in .planning/roles/' {

        It 'example-role.json parses successfully and appears in -List output' {
            if (-not (Test-Path -LiteralPath $script:RealRolesPath -PathType Container)) {
                Set-ItResult -Skipped -Because '.planning/roles/ directory not found in repo'
                return
            }

            $result = @(Get-LabCustomRole -List -RolesPath $script:RealRolesPath)
            $result.Count | Should -BeGreaterThan 0
        }

        It 'Get-LabCustomRole -Name MonitoringServer returns IsCustomRole=$true' {
            if (-not (Test-Path -LiteralPath $script:RealRolesPath -PathType Container)) {
                Set-ItResult -Skipped -Because '.planning/roles/ directory not found in repo'
                return
            }

            $result = Get-LabCustomRole -Name 'MonitoringServer' -RolesPath $script:RealRolesPath
            $result           | Should -Not -BeNullOrEmpty
            $result.IsCustomRole | Should -Be $true
        }
    }
}

BeforeAll {
    # Dot-source the functions to test
    . "$PSScriptRoot/../Private/Save-LabTemplate.ps1"
    . "$PSScriptRoot/../Private/Get-ActiveTemplateConfig.ps1"
    . "$PSScriptRoot/../Private/Test-LabTemplateData.ps1"

    # Test helper to create a temporary repo directory
    function New-TestRepoRoot {
        $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) "LabTemplateTest_$(New-Guid)"
        New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
        return $tempPath
    }

    # Test helper to clean up repo directory
    function Remove-TestRepoRoot {
        param([string]$Path)
        if (Test-Path $Path) {
            Remove-Item -Path $Path -Recurse -Force
        }
    }
}

Describe 'Save-LabTemplate' {
    Context 'Template name validation' {
        It 'throws on invalid template name with special characters' {
            $repoRoot = New-TestRepoRoot
            try {
                { Save-LabTemplate -RepoRoot $repoRoot -Name 'invalid@name!' -VMs @(@{ name='VM1'; ip='10.0.0.1'; role='DC'; memoryGB=4; processors=2 }) } |
                    Should -Throw -ExpectedMessage '*Template name*contains invalid characters*'
            }
            finally {
                Remove-TestRepoRoot $repoRoot
            }
        }
    }

    Context 'VM validation' {
        It 'throws when no VMs provided' {
            $repoRoot = New-TestRepoRoot
            try {
                { Save-LabTemplate -RepoRoot $repoRoot -Name 'test' -VMs @() } |
                    Should -Throw -ExpectedMessage '*At least one VM is required*'
            }
            finally {
                Remove-TestRepoRoot $repoRoot
            }
        }

        It 'throws on invalid IP address' {
            $repoRoot = New-TestRepoRoot
            try {
                { Save-LabTemplate -RepoRoot $repoRoot -Name 'test' -VMs @(@{ name='VM1'; ip='999.1.2.3'; role='DC'; memoryGB=4; processors=2 }) } |
                    Should -Throw -ExpectedMessage '*Invalid IP*'
            }
            finally {
                Remove-TestRepoRoot $repoRoot
            }
        }

        It 'throws on IP with octets out of range' {
            $repoRoot = New-TestRepoRoot
            try {
                { Save-LabTemplate -RepoRoot $repoRoot -Name 'test' -VMs @(@{ name='VM1'; ip='10.0.256.1'; role='DC'; memoryGB=4; processors=2 }) } |
                    Should -Throw -ExpectedMessage '*Octets must be 0-255*'
            }
            finally {
                Remove-TestRepoRoot $repoRoot
            }
        }

        It 'throws on unknown role' {
            $repoRoot = New-TestRepoRoot
            try {
                { Save-LabTemplate -RepoRoot $repoRoot -Name 'test' -VMs @(@{ name='VM1'; ip='10.0.0.1'; role='WebServer'; memoryGB=4; processors=2 }) } |
                    Should -Throw -ExpectedMessage '*Unknown role*'
            }
            finally {
                Remove-TestRepoRoot $repoRoot
            }
        }

        It 'throws on duplicate VM name' {
            $repoRoot = New-TestRepoRoot
            try {
                { Save-LabTemplate -RepoRoot $repoRoot -Name 'test' -VMs @(
                    @{ name='VM1'; ip='10.0.0.1'; role='DC'; memoryGB=4; processors=2 }
                    @{ name='VM1'; ip='10.0.0.2'; role='SQL'; memoryGB=8; processors=4 }
                ) } | Should -Throw -ExpectedMessage '*Duplicate VM name*'
            }
            finally {
                Remove-TestRepoRoot $repoRoot
            }
        }

        It 'throws on duplicate IP address' {
            $repoRoot = New-TestRepoRoot
            try {
                { Save-LabTemplate -RepoRoot $repoRoot -Name 'test' -VMs @(
                    @{ name='VM1'; ip='10.0.0.1'; role='DC'; memoryGB=4; processors=2 }
                    @{ name='VM2'; ip='10.0.0.1'; role='SQL'; memoryGB=8; processors=4 }
                ) } | Should -Throw -ExpectedMessage '*Duplicate IP*'
            }
            finally {
                Remove-TestRepoRoot $repoRoot
            }
        }

        It 'throws on VM name exceeding 15 characters' {
            $repoRoot = New-TestRepoRoot
            try {
                { Save-LabTemplate -RepoRoot $repoRoot -Name 'test' -VMs @(@{ name='this-is-way-too-long-name'; ip='10.0.0.1'; role='DC'; memoryGB=4; processors=2 }) } |
                    Should -Throw -ExpectedMessage '*is invalid*'
            }
            finally {
                Remove-TestRepoRoot $repoRoot
            }
        }

        It 'throws on memory below minimum (1 GB)' {
            $repoRoot = New-TestRepoRoot
            try {
                { Save-LabTemplate -RepoRoot $repoRoot -Name 'test' -VMs @(@{ name='VM1'; ip='10.0.0.1'; role='DC'; memoryGB=0; processors=2 }) } |
                    Should -Throw -ExpectedMessage '*Memory*must be between 1 and 64*'
            }
            finally {
                Remove-TestRepoRoot $repoRoot
            }
        }

        It 'throws on memory above maximum (64 GB)' {
            $repoRoot = New-TestRepoRoot
            try {
                { Save-LabTemplate -RepoRoot $repoRoot -Name 'test' -VMs @(@{ name='VM1'; ip='10.0.0.1'; role='DC'; memoryGB=128; processors=2 }) } |
                    Should -Throw -ExpectedMessage '*Memory*must be between 1 and 64*'
            }
            finally {
                Remove-TestRepoRoot $repoRoot
            }
        }

        It 'throws on processors below minimum (1)' {
            $repoRoot = New-TestRepoRoot
            try {
                { Save-LabTemplate -RepoRoot $repoRoot -Name 'test' -VMs @(@{ name='VM1'; ip='10.0.0.1'; role='DC'; memoryGB=4; processors=0 }) } |
                    Should -Throw -ExpectedMessage '*Processors*must be between 1 and 16*'
            }
            finally {
                Remove-TestRepoRoot $repoRoot
            }
        }

        It 'throws on processors above maximum (16)' {
            $repoRoot = New-TestRepoRoot
            try {
                { Save-LabTemplate -RepoRoot $repoRoot -Name 'test' -VMs @(@{ name='VM1'; ip='10.0.0.1'; role='DC'; memoryGB=4; processors=32 }) } |
                    Should -Throw -ExpectedMessage '*Processors*must be between 1 and 16*'
            }
            finally {
                Remove-TestRepoRoot $repoRoot
            }
        }
    }

    Context 'Valid template saving' {
        It 'saves a valid template successfully' {
            $repoRoot = New-TestRepoRoot
            try {
                $result = Save-LabTemplate -RepoRoot $repoRoot -Name 'test' -Description 'Test template' -VMs @(
                    @{ name='DC1'; ip='10.0.0.10'; role='DC'; memoryGB=4; processors=2 }
                    @{ name='SQL1'; ip='10.0.0.20'; role='SQL'; memoryGB=8; processors=4 }
                )

                $result.Success | Should -Be $true
                $result.Message | Should -Match 'saved successfully'

                # Verify file was created
                $templatePath = Join-Path (Join-Path (Join-Path $repoRoot '.planning') 'templates') 'test.json'
                Test-Path $templatePath | Should -Be $true

                # Verify JSON content
                $content = Get-Content $templatePath -Raw | ConvertFrom-Json
                $content.name | Should -Be 'test'
                $content.description | Should -Be 'Test template'
                $content.vms.Count | Should -Be 2
                $content.vms[0].name | Should -Be 'DC1'
                $content.vms[1].name | Should -Be 'SQL1'
            }
            finally {
                Remove-TestRepoRoot $repoRoot
            }
        }

        It 'accepts empty role as valid' {
            $repoRoot = New-TestRepoRoot
            try {
                $result = Save-LabTemplate -RepoRoot $repoRoot -Name 'test' -VMs @(
                    @{ name='GenericVM'; ip='10.0.0.50'; role=''; memoryGB=4; processors=2 }
                )

                $result.Success | Should -Be $true
            }
            finally {
                Remove-TestRepoRoot $repoRoot
            }
        }
    }
}

Describe 'Get-ActiveTemplateConfig' {
    Context 'Template loading and validation' {
        It 'throws on invalid JSON in template file' {
            $repoRoot = New-TestRepoRoot
            try {
                # Create config.json with ActiveTemplate
                $configDir = Join-Path $repoRoot '.planning'
                New-Item -ItemType Directory -Path $configDir -Force | Out-Null
                @{ ActiveTemplate = 'broken' } | ConvertTo-Json | Set-Content (Join-Path $configDir 'config.json')

                # Create broken template file
                $templatesDir = Join-Path $configDir 'templates'
                New-Item -ItemType Directory -Path $templatesDir -Force | Out-Null
                '{ "name": "broken", "vms": [ this is not valid json' | Set-Content (Join-Path $templatesDir 'broken.json')

                { Get-ActiveTemplateConfig -RepoRoot $repoRoot } |
                    Should -Throw -ExpectedMessage '*invalid JSON*'
            }
            finally {
                Remove-TestRepoRoot $repoRoot
            }
        }

        It 'throws when template has invalid VM data' {
            $repoRoot = New-TestRepoRoot
            try {
                # Create config.json with ActiveTemplate
                $configDir = Join-Path $repoRoot '.planning'
                New-Item -ItemType Directory -Path $configDir -Force | Out-Null
                @{ ActiveTemplate = 'invalid' } | ConvertTo-Json | Set-Content (Join-Path $configDir 'config.json')

                # Create template with invalid IP
                $templatesDir = Join-Path $configDir 'templates'
                New-Item -ItemType Directory -Path $templatesDir -Force | Out-Null
                @{
                    name = 'invalid'
                    description = 'Invalid template'
                    vms = @(
                        @{ name='VM1'; ip='999.999.999.999'; role='DC'; memoryGB=4; processors=2 }
                    )
                } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $templatesDir 'invalid.json')

                { Get-ActiveTemplateConfig -RepoRoot $repoRoot } |
                    Should -Throw -ExpectedMessage '*Invalid IP*'
            }
            finally {
                Remove-TestRepoRoot $repoRoot
            }
        }

        It 'throws when template has empty VMs array' {
            $repoRoot = New-TestRepoRoot
            try {
                # Create config.json with ActiveTemplate
                $configDir = Join-Path $repoRoot '.planning'
                New-Item -ItemType Directory -Path $configDir -Force | Out-Null
                @{ ActiveTemplate = 'empty' } | ConvertTo-Json | Set-Content (Join-Path $configDir 'config.json')

                # Create template with no VMs
                $templatesDir = Join-Path $configDir 'templates'
                New-Item -ItemType Directory -Path $templatesDir -Force | Out-Null
                @{
                    name = 'empty'
                    description = 'Empty template'
                    vms = @()
                } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $templatesDir 'empty.json')

                { Get-ActiveTemplateConfig -RepoRoot $repoRoot } |
                    Should -Throw -ExpectedMessage '*At least one VM is required*'
            }
            finally {
                Remove-TestRepoRoot $repoRoot
            }
        }

        It 'returns null when no active template is set' {
            $repoRoot = New-TestRepoRoot
            try {
                # Create config.json without ActiveTemplate
                $configDir = Join-Path $repoRoot '.planning'
                New-Item -ItemType Directory -Path $configDir -Force | Out-Null
                @{ SomeOtherKey = 'value' } | ConvertTo-Json | Set-Content (Join-Path $configDir 'config.json')

                $result = Get-ActiveTemplateConfig -RepoRoot $repoRoot
                $result | Should -BeNullOrEmpty
            }
            finally {
                Remove-TestRepoRoot $repoRoot
            }
        }

        It 'loads and validates a valid template successfully' {
            $repoRoot = New-TestRepoRoot
            try {
                # Create config.json with ActiveTemplate
                $configDir = Join-Path $repoRoot '.planning'
                New-Item -ItemType Directory -Path $configDir -Force | Out-Null
                @{ ActiveTemplate = 'valid' } | ConvertTo-Json | Set-Content (Join-Path $configDir 'config.json')

                # Create valid template
                $templatesDir = Join-Path $configDir 'templates'
                New-Item -ItemType Directory -Path $templatesDir -Force | Out-Null
                @{
                    name = 'valid'
                    description = 'Valid template'
                    vms = @(
                        @{ name='DC1'; ip='10.0.0.10'; role='DC'; memoryGB=4; processors=2 }
                        @{ name='SQL1'; ip='10.0.0.20'; role='SQL'; memoryGB=8; processors=4 }
                    )
                } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $templatesDir 'valid.json')

                $result = Get-ActiveTemplateConfig -RepoRoot $repoRoot
                $result | Should -Not -BeNullOrEmpty
                $result.Count | Should -Be 2
                $result[0].Name | Should -Be 'DC1'
                $result[1].Name | Should -Be 'SQL1'
            }
            finally {
                Remove-TestRepoRoot $repoRoot
            }
        }
    }
}

Describe 'Test-LabTemplateData' {
    Context 'Structure validation' {
        It 'throws when vms array is missing' {
            $template = @{ name = 'test'; description = 'test' }
            { Test-LabTemplateData -Template $template } |
                Should -Throw -ExpectedMessage "*At least one VM is required*"
        }

        It 'throws when vms array is empty' {
            $template = @{ name = 'test'; description = 'test'; vms = @() }
            { Test-LabTemplateData -Template $template } |
                Should -Throw -ExpectedMessage '*At least one VM is required*'
        }
    }

    Context 'Field validation' {
        It 'throws when VM is missing name field' {
            $template = @{ vms = @(@{ ip='10.0.0.1'; role='DC'; memoryGB=4; processors=2 }) }
            { Test-LabTemplateData -Template $template } |
                Should -Throw -ExpectedMessage "*missing 'name' field*"
        }

        It 'throws when VM is missing ip field' {
            $template = @{ vms = @(@{ name='VM1'; role='DC'; memoryGB=4; processors=2 }) }
            { Test-LabTemplateData -Template $template } |
                Should -Throw -ExpectedMessage "*missing 'ip' field*"
        }
    }

    Context 'Role validation' {
        It 'accepts all known roles' {
            $validRoles = @('DC', 'SQL', 'IIS', 'WSUS', 'DHCP', 'FileServer', 'PrintServer', 'DSC', 'Jumpbox', 'Client', 'Ubuntu', 'WebServerUbuntu', 'DatabaseUbuntu', 'DockerUbuntu', 'K8sUbuntu')

            foreach ($role in $validRoles) {
                $template = @{ vms = @(@{ name='VM1'; ip='10.0.0.1'; role=$role; memoryGB=4; processors=2 }) }
                { Test-LabTemplateData -Template $template } | Should -Not -Throw
            }
        }

        It 'accepts empty role' {
            $template = @{ vms = @(@{ name='VM1'; ip='10.0.0.1'; role=''; memoryGB=4; processors=2 }) }
            { Test-LabTemplateData -Template $template } | Should -Not -Throw
        }

        It 'accepts null role' {
            $template = @{ vms = @(@{ name='VM1'; ip='10.0.0.1'; role=$null; memoryGB=4; processors=2 }) }
            { Test-LabTemplateData -Template $template } | Should -Not -Throw
        }
    }
}

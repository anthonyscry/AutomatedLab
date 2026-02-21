Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot      = Split-Path $PSScriptRoot -Parent
    $script:TemplatesRoot = Join-Path $script:RepoRoot '.planning/templates'
    . (Join-Path $script:RepoRoot 'Private/Test-LabTemplateData.ps1')
    . (Join-Path $script:RepoRoot 'Private/Get-LabScenarioTemplate.ps1')
    . (Join-Path $script:RepoRoot 'Private/Get-LabScenarioResourceEstimate.ps1')
}

# =============================================================================
# MixedOSLab Scenario Template
# =============================================================================
Describe 'MixedOSLab Scenario Template' {

    Context 'Template structure' {

        It 'MixedOSLab.json exists in templates directory' {
            $templatePath = Join-Path $script:TemplatesRoot 'MixedOSLab.json'
            Test-Path $templatePath | Should -BeTrue
        }

        It 'template parses as valid JSON with required fields' {
            $templatePath = Join-Path $script:TemplatesRoot 'MixedOSLab.json'
            $template     = Get-Content $templatePath -Raw | ConvertFrom-Json
            $template.name        | Should -Not -BeNullOrEmpty
            $template.description | Should -Not -BeNullOrEmpty
            $template.vms         | Should -Not -BeNullOrEmpty
        }

        It 'defines exactly 4 VMs' {
            $templatePath = Join-Path $script:TemplatesRoot 'MixedOSLab.json'
            $template     = Get-Content $templatePath -Raw | ConvertFrom-Json
            @($template.vms).Count | Should -Be 4
        }

        It 'contains both Windows and Linux roles' {
            $templatePath = Join-Path $script:TemplatesRoot 'MixedOSLab.json'
            $template     = Get-Content $templatePath -Raw | ConvertFrom-Json
            $roles = @($template.vms).role
            $roles | Should -Contain 'DC'
            $roles | Should -Contain 'IIS'
            # At least one Linux role present
            $linuxRoles = @($roles | Where-Object { $_ -in @('Ubuntu', 'WebServerUbuntu', 'DatabaseUbuntu', 'CentOS', 'DockerUbuntu', 'K8sUbuntu') })
            $linuxRoles.Count | Should -BeGreaterThan 0
        }

        It 'all VM IPs are in 10.0.10.0/24 subnet' {
            $templatePath = Join-Path $script:TemplatesRoot 'MixedOSLab.json'
            $template     = Get-Content $templatePath -Raw | ConvertFrom-Json
            foreach ($vm in $template.vms) {
                $vm.ip | Should -Match '^10\.0\.10\.\d+'
            }
        }

        It 'all role tags match known LabBuilder roles' {
            $templatePath  = Join-Path $script:TemplatesRoot 'MixedOSLab.json'
            $template      = Get-Content $templatePath -Raw | ConvertFrom-Json
            $rolesDir      = Join-Path $script:RepoRoot 'LabBuilder/Roles'
            $roleFiles     = Get-ChildItem -Path $rolesDir -Filter '*.ps1' -File |
                             Where-Object { $_.BaseName -ne 'LinuxRoleBase' }
            $knownTags     = @()
            foreach ($f in $roleFiles) {
                $tagMatch = Select-String -Path $f.FullName -Pattern "Tag\s*=\s*'([^']+)'" | Select-Object -First 1
                if ($tagMatch) {
                    $tagValue = ($tagMatch.Matches[0].Value -replace "Tag\s*=\s*'", '' -replace "'", '').Trim()
                    $knownTags += $tagValue
                }
            }
            foreach ($vm in $template.vms) {
                $vm.role | Should -BeIn $knownTags -Because "Role '$($vm.role)' for VM '$($vm.name)' must exist as a LabBuilder role"
            }
        }
    }

    Context 'Scenario resolution' {

        It 'Get-LabScenarioTemplate resolves MixedOSLab' {
            $vms = Get-LabScenarioTemplate -Scenario MixedOSLab -TemplatesRoot $script:TemplatesRoot
            @($vms).Count | Should -Be 4
        }

        It 'returned objects have Name, Role, Ip, MemoryGB, Processors properties' {
            $vms  = Get-LabScenarioTemplate -Scenario MixedOSLab -TemplatesRoot $script:TemplatesRoot
            $first = @($vms)[0]
            $first.PSObject.Properties.Name | Should -Contain 'Name'
            $first.PSObject.Properties.Name | Should -Contain 'Role'
            $first.PSObject.Properties.Name | Should -Contain 'Ip'
            $first.PSObject.Properties.Name | Should -Contain 'MemoryGB'
            $first.PSObject.Properties.Name | Should -Contain 'Processors'
        }

        It 'resource estimate returns correct VM count' {
            $estimate = Get-LabScenarioResourceEstimate -Scenario MixedOSLab -TemplatesRoot $script:TemplatesRoot
            $estimate.VMCount | Should -Be 4
        }

        It 'resource estimate includes Linux disk sizes (not default fallback)' {
            $estimate = Get-LabScenarioResourceEstimate -Scenario MixedOSLab -TemplatesRoot $script:TemplatesRoot
            # If all 4 VMs used 60GB default, TotalDiskGB would be 240.
            # With Linux-specific estimates (DC=80, IIS=60, WebServerUbuntu=40, DatabaseUbuntu=50) = 230.
            $allDefaultDisk = 4 * 60
            $estimate.TotalDiskGB | Should -Not -Be $allDefaultDisk
            # Linux Ubuntu roles contribute 40+50=90GB (not 60+60=120GB default)
            $estimate.TotalDiskGB | Should -Be 230
        }
    }
}

# =============================================================================
# Cross-OS Provisioning Flow
# =============================================================================
Describe 'Cross-OS Provisioning Flow' {

    BeforeAll {
        $script:BuildScript = Join-Path $script:RepoRoot 'LabBuilder/Build-LabFromSelection.ps1'
        $script:NetworkScript = Join-Path $script:RepoRoot 'Public/Initialize-LabNetwork.ps1'
        $script:NetworkConfigScript = Join-Path $script:RepoRoot 'Private/Get-LabNetworkConfig.ps1'
    }

    Context 'Build-LabFromSelection handles mixed roles' {

        It 'Build-LabFromSelection separates Windows and Linux roles' {
            $match = Select-String -Path $script:BuildScript -Pattern 'IsLinux'
            $match | Should -Not -BeNullOrEmpty -Because 'Build-LabFromSelection must check IsLinux to separate Windows and Linux VM handling'
        }

        It 'Linux VMs created in background (Phase 10-pre)' {
            $match = Select-String -Path $script:BuildScript -Pattern 'Phase 10-pre'
            $match | Should -Not -BeNullOrEmpty -Because 'Build-LabFromSelection must launch Linux VM creation in background before Install-Lab'
        }

        It 'Linux post-installs run after Windows post-installs' {
            $content = Get-Content $script:BuildScript -Raw
            $windowsIndex = $content.IndexOf('Windows roles (not DC) in parallel')
            $linuxIndex   = $content.IndexOf('Linux post-installs run after')
            $windowsIndex | Should -BeGreaterThan -1 -Because 'Windows parallel post-install block must exist'
            $linuxIndex   | Should -BeGreaterThan -1 -Because 'Linux post-install block must exist'
            $linuxIndex   | Should -BeGreaterThan $windowsIndex -Because 'Linux post-installs must come after Windows post-installs in the script'
        }

        It 'Build manifest includes IsLinux flag' {
            $match = Select-String -Path $script:BuildScript -Pattern 'IsLinux\s*=\s*\[bool\]'
            if (-not $match) {
                $match = Select-String -Path $script:BuildScript -Pattern "IsLinux\s*=.*\`$rd\.IsLinux"
            }
            $match | Should -Not -BeNullOrEmpty -Because 'Build summary manifest must record IsLinux flag per VM'
        }
    }

    Context 'Network setup supports mixed OS' {

        It 'Initialize-LabNetwork handles multi-subnet config' {
            $match = Select-String -Path $script:NetworkScript -Pattern 'Switches'
            $match | Should -Not -BeNullOrEmpty -Because 'Initialize-LabNetwork must handle Switches array for multi-subnet configs'
        }

        It 'Get-LabNetworkConfig returns VMAssignments for IP planning' {
            $match = Select-String -Path $script:NetworkConfigScript -Pattern 'VMAssignments'
            $match | Should -Not -BeNullOrEmpty -Because 'Get-LabNetworkConfig must return VMAssignments for per-VM switch/IP planning'
        }
    }
}

# =============================================================================
# Updated Scenario Templates
# =============================================================================
Describe 'Updated Scenario Templates' {

    It 'SecurityLab template includes switch field on VMs' {
        $templatePath = Join-Path $script:TemplatesRoot 'SecurityLab.json'
        $template     = Get-Content $templatePath -Raw | ConvertFrom-Json
        $firstVm      = @($template.vms)[0]
        $firstVm.PSObject.Properties.Name | Should -Contain 'switch' -Because 'SecurityLab VMs must have a switch field for topology documentation'
    }

    It 'MultiTierApp template includes switch field on VMs' {
        $templatePath = Join-Path $script:TemplatesRoot 'MultiTierApp.json'
        $template     = Get-Content $templatePath -Raw | ConvertFrom-Json
        $firstVm      = @($template.vms)[0]
        $firstVm.PSObject.Properties.Name | Should -Contain 'switch' -Because 'MultiTierApp VMs must have a switch field for topology documentation'
    }

    It 'MixedOSLab appears in available scenarios list' {
        $jsonFiles = Get-ChildItem -Path $script:TemplatesRoot -Filter '*.json' -File
        $names = $jsonFiles | ForEach-Object { $_.BaseName }
        $names | Should -Contain 'MixedOSLab'
    }
}

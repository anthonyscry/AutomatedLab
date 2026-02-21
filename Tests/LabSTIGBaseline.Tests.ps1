Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Get-LabSTIGConfig.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabSTIGProfile.ps1')
    . (Join-Path $repoRoot 'Private/Test-PowerStigInstallation.ps1')
    . (Join-Path $repoRoot 'Private/Write-LabSTIGCompliance.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabSTIGBaselineCore.ps1')

    # Stub DSC cmdlets that don't exist on the test host (needed for Pester Mock)
    if (-not (Get-Command Start-DscConfiguration -ErrorAction SilentlyContinue)) {
        function global:Start-DscConfiguration {
            [CmdletBinding()]
            param([string]$ComputerName, [switch]$Wait, [switch]$Force, [string]$Path)
        }
    }
    if (-not (Get-Command Test-DscConfiguration -ErrorAction SilentlyContinue)) {
        function global:Test-DscConfiguration {
            [CmdletBinding()]
            param([string]$CimSession)
            return $true
        }
    }
    if (-not (Get-Command Get-DscConfigurationStatus -ErrorAction SilentlyContinue)) {
        function global:Get-DscConfigurationStatus {
            [CmdletBinding()]
            param([string]$CimSession, $ErrorAction)
            return [pscustomobject]@{ Status = 'Success' }
        }
    }

    # Helper to build a valid STIG config - defined in BeforeAll for Pester 5 scope
    function script:New-TestSTIGConfig {
        param([bool]$Enabled = $true, [hashtable]$Exceptions = @{})
        [pscustomobject]@{
            Enabled             = $Enabled
            AutoApplyOnDeploy   = $true
            ComplianceCachePath = '.planning/stig-compliance.json'
            Exceptions          = $Exceptions
        }
    }
}

Describe 'Invoke-LabSTIGBaselineCoreCore' {

    Context 'No-op scenarios' {

        It 'Returns no-op result when STIG is disabled (Enabled=false)' {
            Mock Get-LabSTIGConfig { script:New-TestSTIGConfig -Enabled $false }

            $result = Invoke-LabSTIGBaselineCore
            $result.VMsProcessed | Should -Be 0
            $result.VMsSucceeded | Should -Be 0
            $result.VMsFailed    | Should -Be 0
        }

        It 'Returns no-op when no target VMs specified and no lab VMs found' {
            Mock Get-LabSTIGConfig { script:New-TestSTIGConfig }
            # Ensure $GlobalLabConfig has no CoreVMNames
            if (Test-Path variable:global:GlobalLabConfig) { Remove-Variable GlobalLabConfig -Scope Global -ErrorAction SilentlyContinue }

            $result = Invoke-LabSTIGBaselineCore
            $result.VMsProcessed | Should -Be 0
        }
    }

    Context 'PowerSTIG installation' {

        BeforeEach {
            Mock Get-LabSTIGConfig { script:New-TestSTIGConfig }
            Mock Write-LabSTIGCompliance { }
            Mock Test-DscConfiguration { $true }
            Mock Get-DscConfigurationStatus { [pscustomobject]@{ Status = 'Success' } }
            Mock Start-DscConfiguration { }
            $script:installCalled = $false
            Mock Invoke-Command {
                param($ComputerName, $ScriptBlock, $ArgumentList)
                $scriptText = $ScriptBlock.ToString()
                if ($scriptText -match 'Install-Module') {
                    $script:installCalled = $true
                    return $null
                }
                if ($scriptText -match 'Win32_OperatingSystem') { return '10.0.17763.1234' }
                if ($scriptText -match 'DomainRole') { return 3 }
                if ($scriptText -match 'MaxEnvelopeSizekb') { return $null }
                return $null
            }
        }

        It 'Installs PowerSTIG on target VM when Test-PowerStigInstallation returns Installed=false' {
            Mock Test-PowerStigInstallation {
                [pscustomobject]@{ Installed = $false; Version = $null; MissingModules = @('PowerSTIG'); ComputerName = 'TestVM' }
            }
            $script:installCalled = $false

            Invoke-LabSTIGBaselineCore -VMName 'TestVM'

            $script:installCalled | Should -Be $true
        }

        It 'Skips installation when PowerSTIG already installed' {
            Mock Test-PowerStigInstallation {
                [pscustomobject]@{ Installed = $true; Version = '4.28.0'; MissingModules = @(); ComputerName = 'TestVM' }
            }
            $script:installCalled = $false

            Invoke-LabSTIGBaselineCore -VMName 'TestVM'

            $script:installCalled | Should -Be $false
        }
    }

    Context 'WinRM envelope size' {

        BeforeEach {
            Mock Get-LabSTIGConfig { script:New-TestSTIGConfig }
            Mock Write-LabSTIGCompliance { }
            Mock Test-PowerStigInstallation {
                [pscustomobject]@{ Installed = $true; Version = '4.28.0'; MissingModules = @(); ComputerName = $ComputerName }
            }
            Mock Test-DscConfiguration { $true }
            Mock Get-DscConfigurationStatus { [pscustomobject]@{ Status = 'Success' } }
            Mock Start-DscConfiguration { }
            $script:envelopeSizeSet = $false
            Mock Invoke-Command {
                param($ComputerName, $ScriptBlock, $ArgumentList)
                $scriptText = $ScriptBlock.ToString()
                if ($scriptText -match 'MaxEnvelopeSizekb') {
                    $script:envelopeSizeSet = $true
                    return $null
                }
                if ($scriptText -match 'Win32_OperatingSystem') { return '10.0.17763.1234' }
                if ($scriptText -match 'DomainRole') { return 3 }
                return $null
            }
        }

        It 'Raises WinRM MaxEnvelopeSizekb to 8192 before DSC operations' {
            Invoke-LabSTIGBaselineCore -VMName 'TestVM'
            $script:envelopeSizeSet | Should -Be $true
        }
    }

    Context 'Role and profile detection' {

        BeforeEach {
            Mock Get-LabSTIGConfig { script:New-TestSTIGConfig }
            Mock Write-LabSTIGCompliance { }
            Mock Test-PowerStigInstallation {
                [pscustomobject]@{ Installed = $true; Version = '4.28.0'; MissingModules = @(); ComputerName = $ComputerName }
            }
            Mock Test-DscConfiguration { $true }
            Mock Get-DscConfigurationStatus { [pscustomobject]@{ Status = 'Success' } }
            Mock Start-DscConfiguration { }
            $script:profileCallArgs = $null
            Mock Get-LabSTIGProfile {
                param($OsRole, $OsVersionBuild)
                $script:profileCallArgs = @{ OsRole = $OsRole; OsVersionBuild = $OsVersionBuild }
                [pscustomobject]@{
                    Technology      = 'WindowsServer'
                    StigVersion     = '2019'
                    OsRole          = $OsRole
                    OsVersionString = $OsVersionBuild
                }
            }
        }

        It 'Calls Get-LabSTIGProfile with OsRole DC for domain controller VM' {
            Mock Invoke-Command {
                param($ComputerName, $ScriptBlock, $ArgumentList)
                $scriptText = $ScriptBlock.ToString()
                if ($scriptText -match 'Win32_OperatingSystem') { return '10.0.17763.1234' }
                if ($scriptText -match 'DomainRole') { return 5 }  # 4 or 5 = DC
                if ($scriptText -match 'MaxEnvelopeSizekb') { return $null }
                return $null
            }

            Invoke-LabSTIGBaselineCore -VMName 'DC1'

            $script:profileCallArgs | Should -Not -BeNullOrEmpty
            $script:profileCallArgs.OsRole | Should -Be 'DC'
        }

        It 'Calls Get-LabSTIGProfile with OsRole MS for member server VM' {
            Mock Invoke-Command {
                param($ComputerName, $ScriptBlock, $ArgumentList)
                $scriptText = $ScriptBlock.ToString()
                if ($scriptText -match 'Win32_OperatingSystem') { return '10.0.17763.1234' }
                if ($scriptText -match 'DomainRole') { return 3 }  # Member server
                if ($scriptText -match 'MaxEnvelopeSizekb') { return $null }
                return $null
            }

            Invoke-LabSTIGBaselineCore -VMName 'SVR1'

            $script:profileCallArgs | Should -Not -BeNullOrEmpty
            $script:profileCallArgs.OsRole | Should -Be 'MS'
        }

        It 'Calls Get-LabSTIGProfile with correct OsVersionBuild' {
            Mock Invoke-Command {
                param($ComputerName, $ScriptBlock, $ArgumentList)
                $scriptText = $ScriptBlock.ToString()
                if ($scriptText -match 'Win32_OperatingSystem') { return '10.0.20348.500' }
                if ($scriptText -match 'DomainRole') { return 3 }
                if ($scriptText -match 'MaxEnvelopeSizekb') { return $null }
                return $null
            }

            Invoke-LabSTIGBaselineCore -VMName 'SVR2022'

            $script:profileCallArgs.OsVersionBuild | Should -Be '10.0.20348.500'
        }

        It 'Skips VM when Get-LabSTIGProfile returns null (unsupported OS)' {
            Mock Get-LabSTIGProfile { return $null }
            Mock Invoke-Command {
                param($ComputerName, $ScriptBlock, $ArgumentList)
                $scriptText = $ScriptBlock.ToString()
                if ($scriptText -match 'Win32_OperatingSystem') { return '10.0.99999.0' }
                if ($scriptText -match 'DomainRole') { return 3 }
                if ($scriptText -match 'MaxEnvelopeSizekb') { return $null }
                return $null
            }

            $result = Invoke-LabSTIGBaselineCore -VMName 'UnsupportedVM'
            $result.VMsProcessed | Should -Be 1
            $result.VMsSucceeded | Should -Be 0
        }
    }

    Context 'Exception overrides' {

        BeforeEach {
            Mock Test-PowerStigInstallation {
                [pscustomobject]@{ Installed = $true; Version = '4.28.0'; MissingModules = @(); ComputerName = $ComputerName }
            }
            Mock Test-DscConfiguration { $true }
            Mock Get-DscConfigurationStatus { [pscustomobject]@{ Status = 'Success' } }
            Mock Start-DscConfiguration { }
            Mock Invoke-Command {
                param($ComputerName, $ScriptBlock, $ArgumentList)
                $scriptText = $ScriptBlock.ToString()
                if ($scriptText -match 'Win32_OperatingSystem') { return '10.0.17763.1234' }
                if ($scriptText -match 'DomainRole') { return 3 }
                if ($scriptText -match 'MaxEnvelopeSizekb') { return $null }
                return $null
            }
            $script:complianceCallArgs = $null
            Mock Write-LabSTIGCompliance {
                param($CachePath, $VMName, $Role, $STIGVersion, $Status, $ExceptionsApplied, $ErrorMessage)
                $script:complianceCallArgs = @{
                    VMName            = $VMName
                    Role              = $Role
                    Status            = $Status
                    ExceptionsApplied = $ExceptionsApplied
                    ErrorMessage      = $ErrorMessage
                }
            }
        }

        It 'Passes exception count to Write-LabSTIGCompliance when VM has exception entries in config' {
            Mock Get-LabSTIGConfig {
                script:New-TestSTIGConfig -Exceptions @{ 'TestVM' = @('V-12345', 'V-67890') }
            }

            Invoke-LabSTIGBaselineCore -VMName 'TestVM'

            $script:complianceCallArgs.ExceptionsApplied | Should -Be 2
        }

        It 'Passes zero exception count when VM has no exception entries in config' {
            Mock Get-LabSTIGConfig {
                script:New-TestSTIGConfig -Exceptions @{}
            }

            Invoke-LabSTIGBaselineCore -VMName 'TestVM'

            $script:complianceCallArgs.ExceptionsApplied | Should -Be 0
        }
    }

    Context 'DSC operations' {

        BeforeEach {
            Mock Get-LabSTIGConfig { script:New-TestSTIGConfig }
            Mock Test-PowerStigInstallation {
                [pscustomobject]@{ Installed = $true; Version = '4.28.0'; MissingModules = @(); ComputerName = $ComputerName }
            }
            Mock Invoke-Command {
                param($ComputerName, $ScriptBlock, $ArgumentList)
                $scriptText = $ScriptBlock.ToString()
                if ($scriptText -match 'Win32_OperatingSystem') { return '10.0.17763.1234' }
                if ($scriptText -match 'DomainRole') { return 3 }
                if ($scriptText -match 'MaxEnvelopeSizekb') { return $null }
                return $null
            }
            $script:dscApplied = $false
            Mock Start-DscConfiguration {
                $script:dscApplied = $true
            }
        }

        It 'Applies MOF via Start-DscConfiguration in push mode' {
            Mock Write-LabSTIGCompliance { }
            Mock Test-DscConfiguration { $true }
            Mock Get-DscConfigurationStatus { [pscustomobject]@{ Status = 'Success' } }

            Invoke-LabSTIGBaselineCore -VMName 'TestVM'

            $script:dscApplied | Should -Be $true
        }

        It 'Calls Write-LabSTIGCompliance with Compliant on success' {
            $script:complianceStatus = $null
            Mock Write-LabSTIGCompliance {
                param($CachePath, $VMName, $Role, $STIGVersion, $Status, $ExceptionsApplied, $ErrorMessage)
                $script:complianceStatus = $Status
            }
            Mock Test-DscConfiguration { $true }
            Mock Get-DscConfigurationStatus { [pscustomobject]@{ Status = 'Success' } }

            Invoke-LabSTIGBaselineCore -VMName 'TestVM'

            $script:complianceStatus | Should -Be 'Compliant'
        }

        It 'Calls Write-LabSTIGCompliance with Failed and error message on DSC application failure' {
            $script:complianceStatus = $null
            $script:complianceError  = $null
            Mock Write-LabSTIGCompliance {
                param($CachePath, $VMName, $Role, $STIGVersion, $Status, $ExceptionsApplied, $ErrorMessage)
                $script:complianceStatus = $Status
                $script:complianceError  = $ErrorMessage
            }
            Mock Start-DscConfiguration { throw 'DSC push failed: LCM error' }
            Mock Test-DscConfiguration { $false }
            Mock Get-DscConfigurationStatus { [pscustomobject]@{ Status = 'Failure' } }

            Invoke-LabSTIGBaselineCore -VMName 'TestVM'

            $script:complianceStatus | Should -Be 'Failed'
            $script:complianceError  | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Per-VM error isolation' {

        It 'Handles per-VM failure gracefully and continues processing remaining VMs' {
            $script:processedVMs = [System.Collections.Generic.List[string]]::new()
            Mock Get-LabSTIGConfig { script:New-TestSTIGConfig }
            Mock Test-PowerStigInstallation {
                param($ComputerName, $MinimumVersion)
                [pscustomobject]@{ Installed = $true; Version = '4.28.0'; MissingModules = @(); ComputerName = $ComputerName }
            }
            Mock Invoke-Command {
                param($ComputerName, $ScriptBlock, $ArgumentList)
                $scriptText = $ScriptBlock.ToString()
                # VM1 throws on OS discovery, VM2 succeeds
                if ($scriptText -match 'Win32_OperatingSystem') {
                    if ($ComputerName -eq 'VM1') { throw 'WinRM connection failed' }
                    return '10.0.17763.1234'
                }
                if ($scriptText -match 'DomainRole') { return 3 }
                if ($scriptText -match 'MaxEnvelopeSizekb') { return $null }
                return $null
            }
            Mock Write-LabSTIGCompliance {
                param($CachePath, $VMName, $Role, $STIGVersion, $Status, $ExceptionsApplied, $ErrorMessage)
                $script:processedVMs.Add($VMName)
            }
            Mock Start-DscConfiguration { }
            Mock Test-DscConfiguration { $true }
            Mock Get-DscConfigurationStatus { [pscustomobject]@{ Status = 'Success' } }

            $result = Invoke-LabSTIGBaselineCore -VMName @('VM1', 'VM2')

            # VM2 should still be processed despite VM1 failing
            $result.VMsProcessed | Should -Be 2
            $result.VMsFailed    | Should -Be 1
            $result.VMsSucceeded | Should -Be 1
            $script:processedVMs | Should -Contain 'VM2'
        }
    }

    Context 'Audit trail' {

        BeforeEach {
            Mock Get-LabSTIGConfig { script:New-TestSTIGConfig }
            Mock Write-LabSTIGCompliance { }
            Mock Test-PowerStigInstallation {
                [pscustomobject]@{ Installed = $true; Version = '4.28.0'; MissingModules = @(); ComputerName = $ComputerName }
            }
            Mock Invoke-Command {
                param($ComputerName, $ScriptBlock, $ArgumentList)
                $scriptText = $ScriptBlock.ToString()
                if ($scriptText -match 'Win32_OperatingSystem') { return '10.0.17763.1234' }
                if ($scriptText -match 'DomainRole') { return 3 }
                if ($scriptText -match 'MaxEnvelopeSizekb') { return $null }
                return $null
            }
            Mock Start-DscConfiguration { }
            Mock Test-DscConfiguration { $true }
            Mock Get-DscConfigurationStatus { [pscustomobject]@{ Status = 'Success' } }
        }

        It 'Returns audit PSCustomObject with VMsProcessed, VMsSucceeded, VMsFailed, Repairs, RemainingIssues, DurationSeconds' {
            $result = Invoke-LabSTIGBaselineCore -VMName 'TestVM'

            $props = $result.PSObject.Properties.Name
            $props | Should -Contain 'VMsProcessed'
            $props | Should -Contain 'VMsSucceeded'
            $props | Should -Contain 'VMsFailed'
            $props | Should -Contain 'Repairs'
            $props | Should -Contain 'RemainingIssues'
            $props | Should -Contain 'DurationSeconds'
        }

        It 'DurationSeconds is a non-negative integer' {
            $result = Invoke-LabSTIGBaselineCore -VMName 'TestVM'
            $result.DurationSeconds | Should -BeGreaterOrEqual 0
        }

        It 'Repairs array contains VM name on successful application' {
            $result = Invoke-LabSTIGBaselineCore -VMName 'TestVM'
            $result.Repairs.Count | Should -BeGreaterOrEqual 1
        }

        It 'RemainingIssues array contains entry on failed VM' {
            Mock Start-DscConfiguration { throw 'DSC push failed' }
            Mock Write-LabSTIGCompliance { }

            $result = Invoke-LabSTIGBaselineCore -VMName 'FailVM'
            $result.RemainingIssues.Count | Should -BeGreaterOrEqual 1
        }
    }

    Context 'Override ComplianceCachePath' {

        It 'Uses ComplianceCachePath from parameter when provided' {
            $customPath = '.planning/custom-compliance.json'
            $script:usedCachePath = $null
            Mock Get-LabSTIGConfig { script:New-TestSTIGConfig }
            Mock Test-PowerStigInstallation {
                [pscustomobject]@{ Installed = $true; Version = '4.28.0'; MissingModules = @(); ComputerName = $ComputerName }
            }
            Mock Invoke-Command {
                param($ComputerName, $ScriptBlock, $ArgumentList)
                $scriptText = $ScriptBlock.ToString()
                if ($scriptText -match 'Win32_OperatingSystem') { return '10.0.17763.1234' }
                if ($scriptText -match 'DomainRole') { return 3 }
                if ($scriptText -match 'MaxEnvelopeSizekb') { return $null }
                return $null
            }
            Mock Write-LabSTIGCompliance {
                param($CachePath, $VMName, $Role, $STIGVersion, $Status, $ExceptionsApplied, $ErrorMessage)
                $script:usedCachePath = $CachePath
            }
            Mock Start-DscConfiguration { }
            Mock Test-DscConfiguration { $true }
            Mock Get-DscConfigurationStatus { [pscustomobject]@{ Status = 'Success' } }

            Invoke-LabSTIGBaselineCore -VMName 'TestVM' -ComplianceCachePath $customPath

            $script:usedCachePath | Should -Be $customPath
        }
    }
}

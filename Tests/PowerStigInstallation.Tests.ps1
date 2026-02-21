Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Test-PowerStigInstallation.ps1')
}

Describe 'Test-PowerStigInstallation' {

    Context 'PowerSTIG installed and meets minimum version' {
        BeforeEach {
            Mock Invoke-Command {
                return @{
                    Modules = @{ 'PowerSTIG' = '4.28.0' }
                    Missing = @()
                }
            }
        }

        It 'Returns Installed = true when PowerSTIG and all dependencies found' {
            $result = Test-PowerStigInstallation -ComputerName 'server01'
            $result.Installed | Should -BeTrue
        }

        It 'Returns Version string when PowerSTIG found' {
            $result = Test-PowerStigInstallation -ComputerName 'server01'
            $result.Version | Should -Be '4.28.0'
        }

        It 'Returns empty MissingModules array when all present' {
            $result = Test-PowerStigInstallation -ComputerName 'server01'
            $result.MissingModules | Should -HaveCount 0
        }

        It 'Returns ComputerName matching the input' {
            $result = Test-PowerStigInstallation -ComputerName 'server01'
            $result.ComputerName | Should -Be 'server01'
        }
    }

    Context 'PowerSTIG version exceeds minimum' {
        BeforeEach {
            Mock Invoke-Command {
                return @{
                    Modules = @{ 'PowerSTIG' = '5.0.0' }
                    Missing = @()
                }
            }
        }

        It 'Returns Installed = true when PowerSTIG version exceeds minimum' {
            $result = Test-PowerStigInstallation -ComputerName 'server01'
            $result.Installed | Should -BeTrue
        }

        It 'Returns the installed version string' {
            $result = Test-PowerStigInstallation -ComputerName 'server01'
            $result.Version | Should -Be '5.0.0'
        }
    }

    Context 'PowerSTIG not installed' {
        BeforeEach {
            Mock Invoke-Command {
                return @{
                    Modules = @{}
                    Missing = @('PowerSTIG')
                }
            }
        }

        It 'Returns Installed = false when PowerSTIG is not found' {
            $result = Test-PowerStigInstallation -ComputerName 'server01'
            $result.Installed | Should -BeFalse
        }

        It 'Returns MissingModules list containing PowerSTIG' {
            $result = Test-PowerStigInstallation -ComputerName 'server01'
            $result.MissingModules | Should -Contain 'PowerSTIG'
        }

        It 'Returns Version as null when PowerSTIG not found' {
            $result = Test-PowerStigInstallation -ComputerName 'server01'
            $result.Version | Should -BeNullOrEmpty
        }
    }

    Context 'PowerSTIG version below minimum' {
        BeforeEach {
            Mock Invoke-Command {
                return @{
                    Modules = @{}
                    Missing = @('PowerSTIG')
                }
            }
        }

        It 'Returns Installed = false when PowerSTIG version below minimum' {
            $result = Test-PowerStigInstallation -ComputerName 'server01' -MinimumVersion '4.28.0'
            $result.Installed | Should -BeFalse
        }

        It 'Lists PowerSTIG in MissingModules when below minimum version' {
            $result = Test-PowerStigInstallation -ComputerName 'server01' -MinimumVersion '4.28.0'
            $result.MissingModules | Should -Contain 'PowerSTIG'
        }
    }

    Context 'Key dependency modules checked' {
        BeforeEach {
            Mock Invoke-Command {
                return @{
                    Modules = @{ 'PowerSTIG' = '4.28.0' }
                    Missing = @('AuditPolicyDsc', 'SecurityPolicyDsc')
                }
            }
        }

        It 'Returns Installed = false when dependencies are missing' {
            $result = Test-PowerStigInstallation -ComputerName 'server01'
            $result.Installed | Should -BeFalse
        }

        It 'Returns missing dependency names in MissingModules' {
            $result = Test-PowerStigInstallation -ComputerName 'server01'
            $result.MissingModules | Should -Contain 'AuditPolicyDsc'
            $result.MissingModules | Should -Contain 'SecurityPolicyDsc'
        }
    }

    Context 'Output object structure' {
        BeforeEach {
            Mock Invoke-Command {
                return @{
                    Modules = @{ 'PowerSTIG' = '4.28.0' }
                    Missing = @()
                }
            }
        }

        It 'Returns a PSCustomObject' {
            $result = Test-PowerStigInstallation -ComputerName 'server01'
            $result | Should -BeOfType [pscustomobject]
        }

        It 'Has Installed property (bool)' {
            $result = Test-PowerStigInstallation -ComputerName 'server01'
            $result.PSObject.Properties.Name | Should -Contain 'Installed'
            $result.Installed | Should -BeOfType [bool]
        }

        It 'Has Version property' {
            $result = Test-PowerStigInstallation -ComputerName 'server01'
            $result.PSObject.Properties.Name | Should -Contain 'Version'
        }

        It 'Has MissingModules property (array)' {
            $result = Test-PowerStigInstallation -ComputerName 'server01'
            $result.PSObject.Properties.Name | Should -Contain 'MissingModules'
        }

        It 'Has ComputerName property' {
            $result = Test-PowerStigInstallation -ComputerName 'server01'
            $result.PSObject.Properties.Name | Should -Contain 'ComputerName'
        }
    }

    Context 'Remote check failure (connection error)' {
        BeforeEach {
            Mock Invoke-Command {
                throw 'The WinRM client cannot complete the operation within the time specified.'
            }
        }

        It 'Returns Installed = false when remote check throws' {
            $result = Test-PowerStigInstallation -ComputerName 'unreachable01' -WarningAction SilentlyContinue
            $result.Installed | Should -BeFalse
        }

        It 'Returns MissingModules with failure indicator when remote check throws' {
            $result = Test-PowerStigInstallation -ComputerName 'unreachable01' -WarningAction SilentlyContinue
            $result.MissingModules | Should -HaveCount 1
        }

        It 'Returns Version as null when remote check throws' {
            $result = Test-PowerStigInstallation -ComputerName 'unreachable01' -WarningAction SilentlyContinue
            $result.Version | Should -BeNullOrEmpty
        }

        It 'Returns ComputerName even when remote check throws' {
            $result = Test-PowerStigInstallation -ComputerName 'unreachable01' -WarningAction SilentlyContinue
            $result.ComputerName | Should -Be 'unreachable01'
        }

        It 'Emits a warning when remote check throws' {
            $warnings = @()
            Test-PowerStigInstallation -ComputerName 'unreachable01' -WarningVariable warnings -WarningAction SilentlyContinue
            $warnings.Count | Should -BeGreaterThan 0
        }
    }

    Context 'StrictMode compliance' {
        BeforeEach {
            Mock Invoke-Command {
                return @{
                    Modules = @{ 'PowerSTIG' = '4.28.0' }
                    Missing = @()
                }
            }
        }

        It 'Does not throw under Set-StrictMode -Version Latest' {
            { Test-PowerStigInstallation -ComputerName 'server01' } | Should -Not -Throw
        }
    }
}

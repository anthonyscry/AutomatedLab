Set-StrictMode -Version Latest

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Get-LabSTIGProfile.ps1')
}

Describe 'Get-LabSTIGProfile' {

    Context 'DC role on Server 2019' {
        It 'Returns Technology = WindowsServer for DC on 2019' {
            $result = Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '10.0.17763'
            $result.Technology | Should -Be 'WindowsServer'
        }

        It 'Returns StigVersion containing 2019 for Server 2019 build' {
            $result = Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '10.0.17763'
            $result.StigVersion | Should -Be '2019'
        }

        It 'Returns OsRole = DC for DC role on Server 2019' {
            $result = Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '10.0.17763'
            $result.OsRole | Should -Be 'DC'
        }
    }

    Context 'DC role on Server 2022' {
        It 'Returns Technology = WindowsServer for DC on 2022' {
            $result = Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '10.0.20348'
            $result.Technology | Should -Be 'WindowsServer'
        }

        It 'Returns StigVersion containing 2022 for Server 2022 build' {
            $result = Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '10.0.20348'
            $result.StigVersion | Should -Be '2022'
        }

        It 'Returns OsRole = DC for DC role on Server 2022' {
            $result = Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '10.0.20348'
            $result.OsRole | Should -Be 'DC'
        }
    }

    Context 'Member Server role on Server 2019' {
        It 'Returns Technology = WindowsServer for MS on 2019' {
            $result = Get-LabSTIGProfile -OsRole 'MS' -OsVersionBuild '10.0.17763'
            $result.Technology | Should -Be 'WindowsServer'
        }

        It 'Returns StigVersion 2019 for member server on Server 2019' {
            $result = Get-LabSTIGProfile -OsRole 'MS' -OsVersionBuild '10.0.17763'
            $result.StigVersion | Should -Be '2019'
        }

        It 'Returns OsRole = MS for member server on Server 2019' {
            $result = Get-LabSTIGProfile -OsRole 'MS' -OsVersionBuild '10.0.17763'
            $result.OsRole | Should -Be 'MS'
        }
    }

    Context 'Member Server role on Server 2022' {
        It 'Returns StigVersion 2022 for member server on Server 2022' {
            $result = Get-LabSTIGProfile -OsRole 'MS' -OsVersionBuild '10.0.20348'
            $result.StigVersion | Should -Be '2022'
        }

        It 'Returns OsRole = MS for member server on Server 2022' {
            $result = Get-LabSTIGProfile -OsRole 'MS' -OsVersionBuild '10.0.20348'
            $result.OsRole | Should -Be 'MS'
        }
    }

    Context 'Role normalization' {
        It 'Returns OsRole = DC when input role is DC (exact match)' {
            $result = Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '10.0.17763'
            $result.OsRole | Should -Be 'DC'
        }

        It 'Returns OsRole = MS when input role is Server' {
            $result = Get-LabSTIGProfile -OsRole 'Server' -OsVersionBuild '10.0.17763'
            $result.OsRole | Should -Be 'MS'
        }

        It 'Returns OsRole = MS when input role is MS' {
            $result = Get-LabSTIGProfile -OsRole 'MS' -OsVersionBuild '10.0.17763'
            $result.OsRole | Should -Be 'MS'
        }

        It 'Returns OsRole = MS when input role is member or other default' {
            $result = Get-LabSTIGProfile -OsRole 'member' -OsVersionBuild '10.0.17763'
            $result.OsRole | Should -Be 'MS'
        }
    }

    Context 'Unsupported OS versions' {
        It 'Returns null with warning when OS version is unrecognized' {
            $result = Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '10.0.99999' -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
        }

        It 'Throws a parameter binding error when OS version build is empty string' {
            { Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '' -WarningAction SilentlyContinue } | Should -Throw
        }

        It 'Emits a warning for unsupported OS version' {
            $warnings = @()
            Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '6.1.7601' -WarningVariable warnings -WarningAction SilentlyContinue
            $warnings.Count | Should -BeGreaterThan 0
        }
    }

    Context 'Output object structure' {
        It 'Returns a PSCustomObject' {
            $result = Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '10.0.17763'
            $result | Should -BeOfType [pscustomobject]
        }

        It 'Has Technology property' {
            $result = Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '10.0.17763'
            $result.PSObject.Properties.Name | Should -Contain 'Technology'
        }

        It 'Has StigVersion property' {
            $result = Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '10.0.17763'
            $result.PSObject.Properties.Name | Should -Contain 'StigVersion'
        }

        It 'Has OsRole property' {
            $result = Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '10.0.17763'
            $result.PSObject.Properties.Name | Should -Contain 'OsRole'
        }

        It 'Has OsVersionString property' {
            $result = Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '10.0.17763'
            $result.PSObject.Properties.Name | Should -Contain 'OsVersionString'
        }

        It 'OsVersionString matches the input OsVersionBuild' {
            $result = Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '10.0.17763'
            $result.OsVersionString | Should -Be '10.0.17763'
        }
    }

    Context 'Build number mapping' {
        It 'Maps build 10.0.17763 to version year 2019' {
            $result = Get-LabSTIGProfile -OsRole 'MS' -OsVersionBuild '10.0.17763'
            $result.StigVersion | Should -Be '2019'
        }

        It 'Maps build 10.0.20348 to version year 2022' {
            $result = Get-LabSTIGProfile -OsRole 'MS' -OsVersionBuild '10.0.20348'
            $result.StigVersion | Should -Be '2022'
        }

        It 'Build number with additional patch level still resolves correctly for 2019' {
            $result = Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '10.0.17763.1234'
            $result.StigVersion | Should -Be '2019'
        }

        It 'Build number with additional patch level still resolves correctly for 2022' {
            $result = Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '10.0.20348.5678'
            $result.StigVersion | Should -Be '2022'
        }
    }

    Context 'StrictMode compliance' {
        It 'Does not throw under Set-StrictMode -Version Latest for valid input' {
            { Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '10.0.17763' } | Should -Not -Throw
        }

        It 'Does not throw under Set-StrictMode -Version Latest for invalid OS' {
            { Get-LabSTIGProfile -OsRole 'DC' -OsVersionBuild '10.0.99999' -WarningAction SilentlyContinue } | Should -Not -Throw
        }
    }
}

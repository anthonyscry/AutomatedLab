BeforeAll {
    Set-StrictMode -Version Latest

    # Dot-source the helper
    . "$PSScriptRoot/../Private/Protect-LabLogString.ps1"
}

Describe "Protect-LabLogString" {
    Context "Empty and null input handling" {
        It "Returns empty string unchanged" {
            $result = Protect-LabLogString -InputString ""
            $result | Should -BeExactly ""
        }

        It "Returns null unchanged" {
            $result = Protect-LabLogString -InputString $null
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Known default password scrubbing" {
        It "Scrubs 'SimpleLab123!' from input string" {
            $input = "Password is SimpleLab123! for this account"
            $result = Protect-LabLogString -InputString $input
            $result | Should -Be "Password is ***REDACTED*** for this account"
        }

        It "Scrubs 'SimpleLabSqlSa123!' from input string" {
            $input = "SQL SA password: SimpleLabSqlSa123!"
            $result = Protect-LabLogString -InputString $input
            $result | Should -Be "SQL SA password: ***REDACTED***"
        }

        It "Handles strings with multiple credential occurrences" {
            $input = "First: SimpleLab123!, Second: SimpleLab123!"
            $result = Protect-LabLogString -InputString $input
            $result | Should -Be "First: ***REDACTED***, Second: ***REDACTED***"
        }
    }

    Context "Environment variable scrubbing" {
        BeforeEach {
            # Set test env vars
            $env:OPENCODELAB_ADMIN_PASSWORD = "TestEnvPassword123"
            $env:LAB_ADMIN_PASSWORD = "AnotherEnvPwd456"
        }

        AfterEach {
            # Clean up env vars
            Remove-Item -Path env:OPENCODELAB_ADMIN_PASSWORD -ErrorAction SilentlyContinue
            Remove-Item -Path env:LAB_ADMIN_PASSWORD -ErrorAction SilentlyContinue
        }

        It "Scrubs OPENCODELAB_ADMIN_PASSWORD value when set" {
            $input = "Password is TestEnvPassword123 here"
            $result = Protect-LabLogString -InputString $input
            $result | Should -Be "Password is ***REDACTED*** here"
        }

        It "Scrubs LAB_ADMIN_PASSWORD value when set" {
            $input = "Using password AnotherEnvPwd456 for connection"
            $result = Protect-LabLogString -InputString $input
            $result | Should -Be "Using password ***REDACTED*** for connection"
        }
    }

    Context "GlobalLabConfig password scrubbing" {
        BeforeEach {
            # Create mock GlobalLabConfig
            $script:GlobalLabConfig = [PSCustomObject]@{
                Credentials = [PSCustomObject]@{
                    AdminPassword = "ConfigAdminPwd789"
                    SqlSaPassword = "ConfigSqlPwd999"
                }
            }
        }

        AfterEach {
            # Clean up
            if (Test-Path variable:GlobalLabConfig) {
                Remove-Variable -Name GlobalLabConfig -Scope Script -ErrorAction SilentlyContinue
            }
        }

        It "Scrubs AdminPassword from GlobalLabConfig" {
            $input = "Admin password is ConfigAdminPwd789"
            $result = Protect-LabLogString -InputString $input
            $result | Should -Be "Admin password is ***REDACTED***"
        }

        It "Scrubs SqlSaPassword from GlobalLabConfig" {
            $input = "SQL password: ConfigSqlPwd999"
            $result = Protect-LabLogString -InputString $input
            $result | Should -Be "SQL password: ***REDACTED***"
        }
    }

    Context "Non-matching strings" {
        It "Leaves non-matching strings unchanged" {
            $input = "This is a normal log message with no credentials"
            $result = Protect-LabLogString -InputString $input
            $result | Should -BeExactly $input
        }

        It "Leaves strings with similar but non-matching patterns unchanged" {
            $input = "Password: SomethingElse123!"
            $result = Protect-LabLogString -InputString $input
            $result | Should -BeExactly $input
        }
    }

    Context "Replacement marker" {
        It "Uses '***REDACTED***' as replacement marker" {
            $input = "Password is SimpleLab123! here"
            $result = Protect-LabLogString -InputString $input
            $result | Should -Match '\*\*\*REDACTED\*\*\*'
        }
    }
}

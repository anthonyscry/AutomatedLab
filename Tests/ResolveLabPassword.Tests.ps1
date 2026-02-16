# Resolve-LabPassword tests -- Password resolution chain validation

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Resolve-LabPassword.ps1')
    . (Join-Path $repoRoot 'Private/Resolve-LabSqlPassword.ps1')

    # Load Lab-Config.ps1 to make GlobalLabConfig available
    . (Join-Path $repoRoot 'Lab-Config.ps1')
}

Describe 'Resolve-LabPassword' {
    BeforeEach {
        # Clear environment variable before each test
        if (Test-Path env:OPENCODELAB_ADMIN_PASSWORD) {
            Remove-Item env:OPENCODELAB_ADMIN_PASSWORD
        }
        if (Test-Path env:LAB_ADMIN_PASSWORD) {
            Remove-Item env:LAB_ADMIN_PASSWORD
        }
    }

    Context 'Priority 1: Explicit password parameter' {
        It 'returns explicit non-empty password' {
            $result = Resolve-LabPassword -Password 'ExplicitPassword123!'

            $result | Should -Be 'ExplicitPassword123!'
        }

        It 'skips empty password and checks env var' {
            $env:OPENCODELAB_ADMIN_PASSWORD = 'EnvPassword123!'

            $result = Resolve-LabPassword -Password ''

            $result | Should -Be 'EnvPassword123!'
        }

        It 'skips null password and checks env var' {
            $env:OPENCODELAB_ADMIN_PASSWORD = 'EnvPassword123!'

            $result = Resolve-LabPassword -Password $null

            $result | Should -Be 'EnvPassword123!'
        }
    }

    Context 'Priority 2: Environment variable' {
        It 'returns environment variable value when password is empty' {
            $env:OPENCODELAB_ADMIN_PASSWORD = 'EnvPassword123!'

            $result = Resolve-LabPassword -Password ''

            $result | Should -Be 'EnvPassword123!'
        }

        It 'uses custom EnvVarName parameter' {
            $env:CUSTOM_PASSWORD_VAR = 'CustomEnvPassword123!'

            $result = Resolve-LabPassword -Password '' -EnvVarName 'CUSTOM_PASSWORD_VAR'

            $result | Should -Be 'CustomEnvPassword123!'
        }
    }

    Context 'Priority 3: Interactive prompt and error handling' {
        # Note: Interactive prompt behavior with [Environment]::UserInteractive and Read-Host
        # is difficult to test in Pester without creating actual interactive sessions.
        # The interactive path (Priority 3) is designed for manual operator use and has been
        # validated manually. Tests here focus on the final error path.

        It 'eventually throws descriptive error when password cannot be resolved' -Skip:([Environment]::UserInteractive) {
            # This test only runs in truly non-interactive environments (CI pipelines)
            # In interactive test runs, the function will prompt the user, which we skip
            { Resolve-LabPassword -Password '' -ErrorAction Stop } | Should -Throw "*is required*"
        }
    }

    Context 'Warning on default password' {
        It 'emits warning when resolved password matches default' {
            # Suppress the warning output in test results
            $result = Resolve-LabPassword -Password 'SimpleLab123!' -DefaultPassword 'SimpleLab123!' -WarningAction SilentlyContinue -WarningVariable warnings

            $result | Should -Be 'SimpleLab123!'
            $warnings | Should -Not -BeNullOrEmpty
            $warnings[0] | Should -Match "Using default.*SimpleLab123!"
        }

        It 'does not warn when password differs from default' {
            $result = Resolve-LabPassword -Password 'DifferentPassword123!' -DefaultPassword 'SimpleLab123!' -WarningAction SilentlyContinue -WarningVariable warnings

            $result | Should -Be 'DifferentPassword123!'
            $warnings | Should -BeNullOrEmpty
        }

        It 'does not warn when DefaultPassword is not provided' {
            $result = Resolve-LabPassword -Password 'SimpleLab123!' -WarningAction SilentlyContinue -WarningVariable warnings

            $result | Should -Be 'SimpleLab123!'
            $warnings | Should -BeNullOrEmpty
        }

        It 'includes custom PasswordLabel in warning message' {
            $result = Resolve-LabPassword -Password 'TestDefault' -DefaultPassword 'TestDefault' -PasswordLabel 'SqlSaPassword' -WarningAction SilentlyContinue -WarningVariable warnings

            $warnings | Should -Not -BeNullOrEmpty
            $warnings[0] | Should -Match "SqlSaPassword"
        }
    }

    Context 'Error handling' {
        # Note: Error message validation tests are skipped in interactive environments
        # because Resolve-LabPassword will prompt interactively before throwing.
        # These tests validate that the error messages are correctly formatted when
        # they do occur (in non-interactive/CI environments).

        It 'throws descriptive error when no password available non-interactively' -Skip:([Environment]::UserInteractive) {
            { Resolve-LabPassword -Password '' } | Should -Throw "*AdminPassword is required*"
        }

        It 'includes custom PasswordLabel in error message' -Skip:([Environment]::UserInteractive) {
            { Resolve-LabPassword -Password '' -PasswordLabel 'SqlSaPassword' } | Should -Throw "*SqlSaPassword is required*"
        }

        It 'includes custom EnvVarName in error message' -Skip:([Environment]::UserInteractive) {
            { Resolve-LabPassword -Password '' -EnvVarName 'CUSTOM_VAR' } | Should -Throw "*CUSTOM_VAR*"
        }
    }
}

Describe 'Resolve-LabSqlPassword' {
    BeforeEach {
        # Clear environment variables before each test
        if (Test-Path env:LAB_ADMIN_PASSWORD) {
            Remove-Item env:LAB_ADMIN_PASSWORD
        }
    }

    It 'delegates to Resolve-LabPassword with SQL-specific defaults' {
        $result = Resolve-LabSqlPassword -Password 'SqlPassword123!'

        $result | Should -Be 'SqlPassword123!'
    }

    It 'uses LAB_ADMIN_PASSWORD env var from config' {
        $env:LAB_ADMIN_PASSWORD = 'EnvSqlPassword123!'

        $result = Resolve-LabSqlPassword -Password ''

        $result | Should -Be 'EnvSqlPassword123!'
    }

    It 'warns when using default SQL SA password' {
        $result = Resolve-LabSqlPassword -Password 'SimpleLabSqlSa123!' -WarningAction SilentlyContinue -WarningVariable warnings

        $result | Should -Be 'SimpleLabSqlSa123!'
        $warnings | Should -Not -BeNullOrEmpty
        $warnings[0] | Should -Match "SqlSaPassword"
        $warnings[0] | Should -Match "SimpleLabSqlSa123!"
    }

    It 'throws with SqlSaPassword label when no password available' -Skip:([Environment]::UserInteractive) {
        { Resolve-LabSqlPassword -Password '' } | Should -Throw "*SqlSaPassword is required*"
    }
}

Set-StrictMode -Version Latest

Describe 'Run lock' {
    BeforeAll {
        $enterPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Core/Public/Enter-LabRunLock.ps1'
        $exitPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../src/OpenCodeLab.Core/Public/Exit-LabRunLock.ps1'

        if (Test-Path -Path $enterPath) {
            . $enterPath
        }

        if (Test-Path -Path $exitPath) {
            . $exitPath
        }
    }

    It 'blocks second acquisition while lock exists' {
        $path = Join-Path -Path $TestDrive -ChildPath 'run.lock'

        Enter-LabRunLock -LockPath $path | Out-Null
        try {
            { Enter-LabRunLock -LockPath $path } | Should -Throw -ExpectedMessage 'PolicyBlocked: active run lock exists'
        }
        finally {
            Exit-LabRunLock -LockPath $path
        }
    }

    It 'removes lock file on release' {
        $path = Join-Path -Path $TestDrive -ChildPath 'run.lock'

        Enter-LabRunLock -LockPath $path | Out-Null
        Exit-LabRunLock -LockPath $path

        Test-Path -Path $path | Should -BeFalse
    }

    It 'allows safe release when lock file is absent' {
        $path = Join-Path -Path $TestDrive -ChildPath 'missing.lock'

        { Exit-LabRunLock -LockPath $path } | Should -Not -Throw
    }
}

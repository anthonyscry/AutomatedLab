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

        $lockHandle = Enter-LabRunLock -LockPath $path
        try {
            { Enter-LabRunLock -LockPath $path } | Should -Throw -ExpectedMessage 'PolicyBlocked: active run lock exists'
        }
        finally {
            Exit-LabRunLock -LockHandle $lockHandle
        }
    }

    It 'removes lock file on release' {
        $path = Join-Path -Path $TestDrive -ChildPath 'run.lock'

        $lockHandle = Enter-LabRunLock -LockPath $path
        Exit-LabRunLock -LockHandle $lockHandle

        Test-Path -Path $path | Should -BeFalse
    }

    It 'only allows the owner token to release a lock' {
        $path = Join-Path -Path $TestDrive -ChildPath 'run.lock'
        $lockHandle = Enter-LabRunLock -LockPath $path

        $otherHandle = [pscustomobject]@{
            Path = $path
            OwnerToken = 'not-owner-token'
        }

        try {
            { Exit-LabRunLock -LockHandle $otherHandle } | Should -Throw -ExpectedMessage 'PolicyBlocked: run lock owner token mismatch'
            Test-Path -Path $path | Should -BeTrue
        }
        finally {
            Exit-LabRunLock -LockHandle $lockHandle
        }
    }

    It 'reclaims stale lock from dead local process' {
        $path = Join-Path -Path $TestDrive -ChildPath 'run.lock'
        $staleToken = [guid]::NewGuid().ToString('N')
        $staleMetadata = [pscustomobject]@{
            host = [System.Environment]::MachineName
            pid = 2147483647
            token = $staleToken
            createdAt = [DateTimeOffset]::UtcNow.ToString('o')
        }

        Set-Content -Path $path -Value ($staleMetadata | ConvertTo-Json -Compress) -Encoding utf8

        $lockHandle = Enter-LabRunLock -LockPath $path
        try {
            $lockHandle.OwnerToken | Should -Not -Be $staleToken
            $currentMetadata = Get-Content -Path $path -Raw | ConvertFrom-Json
            $currentMetadata.token | Should -Be $lockHandle.OwnerToken
        }
        finally {
            Exit-LabRunLock -LockHandle $lockHandle
        }
    }

    It 'does not mask unrelated I/O failures as contention' {
        $path = Join-Path -Path $TestDrive -ChildPath 'run.lock'
        $null = New-Item -Path $path -ItemType Directory -Force

        try {
            $thrown = $null
            try {
                Enter-LabRunLock -LockPath $path | Out-Null
            }
            catch {
                $thrown = $_
            }

            $thrown | Should -Not -BeNullOrEmpty
            $thrown.Exception.Message | Should -Not -Be 'PolicyBlocked: active run lock exists'
        }
        finally {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'allows safe release when lock file is absent' {
        $path = Join-Path -Path $TestDrive -ChildPath 'missing.lock'
        $lockHandle = [pscustomobject]@{
            Path = $path
            OwnerToken = [guid]::NewGuid().ToString('N')
        }

        { Exit-LabRunLock -LockHandle $lockHandle } | Should -Not -Throw
    }
}

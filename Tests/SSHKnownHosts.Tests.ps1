BeforeAll {
    Set-StrictMode -Version Latest
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    . (Join-Path $repoRoot 'Lab-Config.ps1')
    . (Join-Path $repoRoot 'Private\Clear-LabSSHKnownHosts.ps1')
}

Describe 'SSH Known Hosts Configuration' {
    Context 'No UserKnownHostsFile=NUL in codebase' {
        It 'should not contain UserKnownHostsFile=NUL in any PowerShell file' {
            $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $matches = Get-ChildItem -Path $repoRoot -Filter '*.ps1' -Recurse -File |
                Where-Object { $_.FullName -notmatch '[\\/]\.planning-archive[\\/]' } |
                Select-String -Pattern 'UserKnownHostsFile=NUL' -SimpleMatch

            $matches | Should -BeNullOrEmpty -Because "all SSH operations should use lab-specific known_hosts path"
        }
    }

    Context 'GlobalLabConfig SSH settings' {
        It 'should have SSH.KnownHostsPath configured' {
            $GlobalLabConfig.SSH | Should -Not -BeNullOrEmpty
            $GlobalLabConfig.SSH.KnownHostsPath | Should -Not -BeNullOrEmpty
        }

        It 'should point KnownHostsPath to SSHKeys directory' {
            $GlobalLabConfig.SSH.KnownHostsPath | Should -BeLike '*SSHKeys*lab_known_hosts'
        }
    }

    Context 'All SSH operations use lab-specific known_hosts' {
        It 'should use lab_known_hosts in all SSH/SCP calls' {
            $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $sshFiles = @(
                'Private\Linux\Invoke-LinuxSSH.ps1'
                'Private\Linux\Copy-LinuxFile.ps1'
                'Scripts\Test-OpenCodeLabHealth.ps1'
                'Scripts\Install-Ansible.ps1'
                'LabBuilder\Roles\LinuxRoleBase.ps1'
            )

            foreach ($file in $sshFiles) {
                $fullPath = Join-Path $repoRoot $file
                if (Test-Path $fullPath) {
                    $content = Get-Content $fullPath -Raw
                    $content | Should -Match 'UserKnownHostsFile.*GlobalLabConfig\.SSH\.KnownHostsPath' -Because "$file should use GlobalLabConfig.SSH.KnownHostsPath"
                }
            }
        }
    }

    Context 'StrictHostKeyChecking preserved' {
        It 'should still use accept-new for all SSH operations' {
            $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $sshFiles = Get-ChildItem -Path $repoRoot -Filter '*.ps1' -Recurse -File |
                Where-Object { $_.FullName -notmatch '[\\/]\.planning-archive[\\/]' } |
                Where-Object { $_.FullName -notmatch '[\\/]Tests[\\/]' }

            $acceptNewCount = 0
            foreach ($file in $sshFiles) {
                $matches = Select-String -Path $file.FullName -Pattern 'StrictHostKeyChecking=accept-new' -SimpleMatch
                $acceptNewCount += $matches.Count
            }

            $acceptNewCount | Should -BeGreaterThan 0 -Because "StrictHostKeyChecking=accept-new should be preserved in SSH calls"
        }
    }

    Context 'Clear-LabSSHKnownHosts helper' {
        It 'should remove the known_hosts file when it exists' {
            $testPath = Join-Path $TestDrive 'test_known_hosts'
            'test data' | Set-Content $testPath -Force

            # Mock the config to point to test file
            $originalPath = $GlobalLabConfig.SSH.KnownHostsPath
            $GlobalLabConfig.SSH.KnownHostsPath = $testPath

            try {
                Clear-LabSSHKnownHosts
                Test-Path $testPath | Should -Be $false
            }
            finally {
                $GlobalLabConfig.SSH.KnownHostsPath = $originalPath
            }
        }

        It 'should not error when known_hosts file does not exist' {
            $testPath = Join-Path $TestDrive 'nonexistent_known_hosts'

            # Mock the config to point to nonexistent file
            $originalPath = $GlobalLabConfig.SSH.KnownHostsPath
            $GlobalLabConfig.SSH.KnownHostsPath = $testPath

            try {
                { Clear-LabSSHKnownHosts -Verbose } | Should -Not -Throw
            }
            finally {
                $GlobalLabConfig.SSH.KnownHostsPath = $originalPath
            }
        }

        It 'should warn when KnownHostsPath is not configured' {
            $originalPath = $GlobalLabConfig.SSH.KnownHostsPath
            $GlobalLabConfig.SSH.KnownHostsPath = ''

            try {
                $warnings = @()
                Clear-LabSSHKnownHosts 3>&1 | ForEach-Object { $warnings += $_ }
                $warnings | Where-Object { $_ -match 'SSH.KnownHostsPath not configured' } | Should -Not -BeNullOrEmpty
            }
            finally {
                $GlobalLabConfig.SSH.KnownHostsPath = $originalPath
            }
        }
    }
}

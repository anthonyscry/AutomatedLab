# LinuxProfileParity.Tests.ps1 -- Pester 5 tests for Linux profile round-trip parity
# Covers: Save-LabProfile includes linuxVmCount, Load-LabProfile round-trips all
# Linux configuration sections (Linux, LinuxVM, SupportedDistros, Builder.VMNames).

BeforeAll {
    Set-StrictMode -Version Latest

    $script:repoRoot = Split-Path -Parent $PSScriptRoot

    . (Join-Path $script:repoRoot 'Private' 'Save-LabProfile.ps1')
    . (Join-Path $script:repoRoot 'Private' 'Load-LabProfile.ps1')

    # Create a temp directory for profile files
    $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "LabProfileTests_$(Get-Random)"
    $null = New-Item -ItemType Directory -Path $script:tempDir -Force

    # Full Linux-aware config for round-trip tests
    $script:linuxConfig = @{
        Lab = @{
            Name        = 'TestLab'
            CoreVMNames = @('dc1', 'svr1', 'ws1')
            DomainName  = 'test.local'
        }
        Builder = @{
            LinuxVM = @{
                Memory     = 2147483648   # 2GB as bytes
                MinMemory  = 1073741824   # 1GB
                MaxMemory  = 4294967296   # 4GB
                Processors = 2
            }
            Linux = @{
                User         = 'labadmin'
                SSHPublicKey = 'C:\LabSources\SSHKeys\id_ed25519.pub'
                LabShareMount = '/mnt/labshare'
            }
            SupportedDistros = @{
                Ubuntu2404 = @{
                    DisplayName = 'Ubuntu Server 24.04 LTS'
                    ISOPattern  = 'ubuntu-24.04*.iso'
                    CloudInit   = 'autoinstall'
                }
                Ubuntu2204 = @{
                    DisplayName = 'Ubuntu Server 22.04 LTS'
                    ISOPattern  = 'ubuntu-22.04*.iso'
                    CloudInit   = 'autoinstall'
                }
                Rocky9 = @{
                    DisplayName = 'Rocky Linux 9'
                    ISOPattern  = 'Rocky-9*.iso'
                    CloudInit   = 'nocloud'
                }
            }
            VMNames = @{
                DC              = 'DC1'
                Ubuntu          = 'LIN1'
                WebServerUbuntu = 'LINWEB1'
                DatabaseUbuntu  = 'LINDB1'
                DockerUbuntu    = 'LINDOCK1'
                K8sUbuntu       = 'LINK8S1'
            }
        }
    }
}

AfterAll {
    # Clean up temp directory
    if (Test-Path $script:tempDir) {
        Remove-Item -Path $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Save-LabProfile - Linux VM metadata' {
    It 'includes linuxVmCount field in saved profile' {
        $result = Save-LabProfile -Name 'test-linux-count' -Config $script:linuxConfig -RepoRoot $script:tempDir -Description 'Test'
        $result.Success | Should -BeTrue

        $profilePath = Join-Path (Join-Path $script:tempDir '.planning') 'profiles\test-linux-count.json'
        $raw = Get-Content -Path $profilePath -Raw
        $data = $raw | ConvertFrom-Json
        $data.PSObject.Properties.Name | Should -Contain 'linuxVmCount'
    }

    It 'counts 5 Linux VMs when all 5 Ubuntu VMNames keys are present' {
        $result = Save-LabProfile -Name 'test-linux-5' -Config $script:linuxConfig -RepoRoot $script:tempDir
        $result.Success | Should -BeTrue

        $profilePath = Join-Path (Join-Path $script:tempDir '.planning') 'profiles\test-linux-5.json'
        $raw = Get-Content -Path $profilePath -Raw
        $data = $raw | ConvertFrom-Json
        $data.linuxVmCount | Should -Be 5
    }

    It 'counts 0 Linux VMs when no Ubuntu VMNames keys are present' {
        $minimalConfig = @{
            Lab = @{
                Name        = 'Minimal'
                CoreVMNames = @('dc1')
                DomainName  = 'min.local'
            }
        }
        $result = Save-LabProfile -Name 'test-linux-zero' -Config $minimalConfig -RepoRoot $script:tempDir
        $result.Success | Should -BeTrue

        $profilePath = Join-Path (Join-Path $script:tempDir '.planning') 'profiles\test-linux-zero.json'
        $raw = Get-Content -Path $profilePath -Raw
        $data = $raw | ConvertFrom-Json
        $data.linuxVmCount | Should -Be 0
    }

    It 'falls back to linuxVmCount = 1 when only LinuxVM section present without VMNames' {
        $builderOnlyConfig = @{
            Lab = @{
                Name        = 'BuilderOnly'
                CoreVMNames = @('dc1')
                DomainName  = 'bo.local'
            }
            Builder = @{
                LinuxVM = @{
                    Memory     = 2147483648
                    Processors = 2
                }
                # No VMNames key — triggers the LinuxVM fallback
            }
        }
        $result = Save-LabProfile -Name 'test-linux-fallback' -Config $builderOnlyConfig -RepoRoot $script:tempDir
        $result.Success | Should -BeTrue

        $profilePath = Join-Path (Join-Path $script:tempDir '.planning') 'profiles\test-linux-fallback.json'
        $raw = Get-Content -Path $profilePath -Raw
        $data = $raw | ConvertFrom-Json
        $data.linuxVmCount | Should -Be 1
    }

    It 'includes vmCount alongside linuxVmCount in metadata' {
        $result = Save-LabProfile -Name 'test-both-counts' -Config $script:linuxConfig -RepoRoot $script:tempDir
        $result.Success | Should -BeTrue

        $profilePath = Join-Path (Join-Path $script:tempDir '.planning') 'profiles\test-both-counts.json'
        $raw = Get-Content -Path $profilePath -Raw
        $data = $raw | ConvertFrom-Json
        $data.PSObject.Properties.Name | Should -Contain 'vmCount'
        $data.PSObject.Properties.Name | Should -Contain 'linuxVmCount'
        $data.vmCount | Should -Be 3   # CoreVMNames: dc1, svr1, ws1
        $data.linuxVmCount | Should -Be 5
    }
}

Describe 'Load-LabProfile - Linux config round-trip fidelity' {
    BeforeAll {
        # Save one profile to use for all load tests in this Describe
        $null = Save-LabProfile -Name 'round-trip-linux' -Config $script:linuxConfig -RepoRoot $script:tempDir -Description 'Round-trip test'
    }

    It 'round-trips Builder.Linux.User correctly' {
        $loaded = Load-LabProfile -Name 'round-trip-linux' -RepoRoot $script:tempDir
        $loaded['Builder']['Linux']['User'] | Should -Be 'labadmin'
    }

    It 'round-trips Builder.Linux.SSHPublicKey correctly' {
        $loaded = Load-LabProfile -Name 'round-trip-linux' -RepoRoot $script:tempDir
        $loaded['Builder']['Linux']['SSHPublicKey'] | Should -Be 'C:\LabSources\SSHKeys\id_ed25519.pub'
    }

    It 'round-trips Builder.LinuxVM.Memory correctly' {
        $loaded = Load-LabProfile -Name 'round-trip-linux' -RepoRoot $script:tempDir
        $loaded['Builder']['LinuxVM']['Memory'] | Should -Be 2147483648
    }

    It 'round-trips Builder.LinuxVM.Processors correctly' {
        $loaded = Load-LabProfile -Name 'round-trip-linux' -RepoRoot $script:tempDir
        $loaded['Builder']['LinuxVM']['Processors'] | Should -Be 2
    }

    It 'round-trips SupportedDistros nested hashtable (Ubuntu2404.DisplayName)' {
        $loaded = Load-LabProfile -Name 'round-trip-linux' -RepoRoot $script:tempDir
        $loaded['Builder']['SupportedDistros']['Ubuntu2404']['DisplayName'] | Should -Be 'Ubuntu Server 24.04 LTS'
    }

    It 'round-trips SupportedDistros nested hashtable (Rocky9.CloudInit)' {
        $loaded = Load-LabProfile -Name 'round-trip-linux' -RepoRoot $script:tempDir
        $loaded['Builder']['SupportedDistros']['Rocky9']['CloudInit'] | Should -Be 'nocloud'
    }

    It 'round-trips all 5 Linux VM name entries in Builder.VMNames' {
        $loaded = Load-LabProfile -Name 'round-trip-linux' -RepoRoot $script:tempDir
        $vmNames = $loaded['Builder']['VMNames']
        $vmNames['Ubuntu'] | Should -Be 'LIN1'
        $vmNames['WebServerUbuntu'] | Should -Be 'LINWEB1'
        $vmNames['DatabaseUbuntu'] | Should -Be 'LINDB1'
        $vmNames['DockerUbuntu'] | Should -Be 'LINDOCK1'
        $vmNames['K8sUbuntu'] | Should -Be 'LINK8S1'
    }

    It 'returns a hashtable (not PSCustomObject) for the loaded config' {
        $loaded = Load-LabProfile -Name 'round-trip-linux' -RepoRoot $script:tempDir
        $loaded | Should -BeOfType [hashtable]
    }

    It 'round-trips nested SupportedDistros as hashtable (not PSCustomObject)' {
        $loaded = Load-LabProfile -Name 'round-trip-linux' -RepoRoot $script:tempDir
        $loaded['Builder']['SupportedDistros'] | Should -BeOfType [hashtable]
        $loaded['Builder']['SupportedDistros']['Ubuntu2404'] | Should -BeOfType [hashtable]
    }
}

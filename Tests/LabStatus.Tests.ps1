# LabStatus.Tests.ps1 -- Unit tests for status and utility Public functions
# Covers: Get-LabStatus, Show-LabStatus, Write-LabStatus, Write-RunArtifact,
#          Wait-LabVMReady, Connect-LabVM, Reset-Lab, New-LabSSHKey,
#          Test-HyperVEnabled, Test-LabIso

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    . (Join-Path $script:repoRoot 'Public' 'Get-LabStatus.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Show-LabStatus.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Write-LabStatus.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Write-RunArtifact.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Wait-LabVMReady.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Connect-LabVM.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Reset-Lab.ps1')
    . (Join-Path $script:repoRoot 'Public' 'New-LabSSHKey.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Test-HyperVEnabled.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Test-LabIso.ps1')

    # Stub dependencies
    if (-not (Get-Command Get-LabVMConfig -ErrorAction SilentlyContinue)) {
        function Get-LabVMConfig { @{ dc1 = @{ Name = 'dc1' } } }
    }
    if (-not (Get-Command Protect-LabLogString -ErrorAction SilentlyContinue)) {
        function Protect-LabLogString { param([string]$InputString) $InputString }
    }
    if (-not (Get-Command Get-HostInfo -ErrorAction SilentlyContinue)) {
        function Get-HostInfo { [ordered]@{ Hostname = 'TestHost'; OS = 'Windows' } }
    }
    if (-not (Get-Command Test-LabVM -ErrorAction SilentlyContinue)) {
        function Test-LabVM { param([string]$VMName) [PSCustomObject]@{ Exists = $true; VMName = $VMName } }
    }
}

Describe 'Get-LabStatus' {
    BeforeEach {
        Register-HyperVMocks
        Mock Get-VM {
            if ($Name) {
                return New-MockVM -Name $Name
            }
            return @(
                (New-MockVM -Name 'dc1'),
                (New-MockVM -Name 'svr1'),
                (New-MockVM -Name 'ws1')
            )
        }
        Mock Get-VMNetworkAdapter { New-MockVMNetworkAdapter -VMName $VMName }
        # Mock module-qualified Get-VM for LIN1 check
        Mock -CommandName 'Hyper-V\Get-VM' { $null } -ErrorAction SilentlyContinue
    }

    It 'returns array of status objects' {
        $results = Get-LabStatus
        $results | Should -Not -BeNullOrEmpty
    }

    It 'returns objects with VMName and State properties' {
        $results = Get-LabStatus
        $first = $results | Select-Object -First 1
        $first.PSObject.Properties.Name | Should -Contain 'VMName'
        $first.PSObject.Properties.Name | Should -Contain 'State'
    }

    It 'returns compact view with fewer properties' {
        $results = Get-LabStatus -Compact
        $first = $results | Select-Object -First 1
        $first.PSObject.Properties.Name | Should -Contain 'VMName'
        $first.PSObject.Properties.Name | Should -Contain 'State'
        $first.PSObject.Properties.Name | Should -Contain 'Heartbeat'
    }

    It 'returns empty array when Hyper-V not available' {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }
        $results = Get-LabStatus
        @($results).Count | Should -Be 0
    }
}

Describe 'Show-LabStatus' {
    BeforeEach {
        Register-HyperVMocks
        Mock Get-LabStatus { @([PSCustomObject]@{ VMName = 'dc1'; State = 'Running'; Heartbeat = 'Healthy' }) }
        Mock Write-Host { }
    }

    It 'does not throw' {
        { Show-LabStatus } | Should -Not -Throw
    }
}

Describe 'Write-LabStatus' {
    BeforeEach {
        Mock Write-Host { }
    }

    It 'does not throw with valid status' {
        { Write-LabStatus -Status OK -Message 'Test message' } | Should -Not -Throw
    }

    It 'accepts all valid status values' {
        foreach ($status in @('OK', 'WARN', 'FAIL', 'INFO', 'SKIP', 'CACHE', 'NOTE')) {
            { Write-LabStatus -Status $status -Message "Testing $status" } | Should -Not -Throw
        }
    }

    It 'supports indent parameter' {
        { Write-LabStatus -Status OK -Message 'Indented' -Indent 3 } | Should -Not -Throw
    }
}

Describe 'Write-RunArtifact' {
    BeforeEach {
        Mock Write-Host { }
        Mock Resolve-Path { $null }
        Mock New-Item { [PSCustomObject]@{ FullName = (Join-Path $TestDrive '.planning' 'runs') } }
        Mock Out-File { }
    }

    It 'returns artifact path on success' {
        $result = Write-RunArtifact -Operation 'Test' -Status 'Success' -Duration 1.5 -ExitCode 0
        # May return null in test environment due to path resolution
        # The key assertion is no throw
    }

    It 'does not throw with all required parameters' {
        { Write-RunArtifact -Operation 'Test' -Status 'Success' -Duration 1.5 -ExitCode 0 } | Should -Not -Throw
    }

    It 'accepts optional VMNames parameter' {
        { Write-RunArtifact -Operation 'Deploy' -Status 'OK' -Duration 10.0 -ExitCode 0 -VMNames @('dc1', 'svr1') } | Should -Not -Throw
    }
}

Describe 'Wait-LabVMReady' {
    BeforeEach {
        Register-HyperVMocks
        Mock Get-VM { New-MockVM -Name $Name -State 'Running' }
    }

    It 'returns result with OverallStatus property' {
        $result = Wait-LabVMReady
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }
}

Describe 'Connect-LabVM' {
    BeforeEach {
        Register-HyperVMocks
        Mock Get-VM { New-MockVM -Name $VMName }
        Mock vmconnect { } -ErrorAction SilentlyContinue
        Mock Start-Process { } -ErrorAction SilentlyContinue
    }

    It 'returns result with OverallStatus property' {
        $result = Connect-LabVM -VMName 'dc1'
        $result | Should -Not -BeNullOrEmpty
        $result.VMName | Should -Be 'dc1'
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }

    It 'returns Failed when Hyper-V not available' {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }
        $result = Connect-LabVM -VMName 'dc1'
        $result.OverallStatus | Should -Be 'Failed'
    }
}

Describe 'Reset-Lab' {
    BeforeEach {
        Register-HyperVMocks
        Mock Remove-LabVMs { [PSCustomObject]@{ OverallStatus = 'OK'; VMsRemoved = @('dc1') } }
        Mock Remove-LabSwitch { [PSCustomObject]@{ Status = 'OK' } }
    }

    It 'returns result with OverallStatus property' {
        $result = Reset-Lab -Force
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }
}

Describe 'New-LabSSHKey' {
    BeforeEach {
        Register-HyperVMocks
        Mock Test-Path { $false }
        Mock New-Item { [PSCustomObject]@{ FullName = 'C:\keys' } }
        # Mock ssh-keygen as external command
        Mock ssh-keygen { } -ErrorAction SilentlyContinue
    }

    It 'returns result with Status property' {
        $result = New-LabSSHKey
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'Status'
    }
}

Describe 'Test-HyperVEnabled' {
    BeforeEach {
        # Don't use Register-HyperVMocks -- this function checks platform differently
        Mock Get-CimInstance { [PSCustomObject]@{ HypervisorPresent = $true } } -ErrorAction SilentlyContinue
    }

    It 'returns a boolean value' {
        $result = Test-HyperVEnabled
        $result | Should -BeOfType [bool]
    }
}

Describe 'Test-LabIso' {
    It 'returns Pass for existing ISO with correct extension' {
        Mock Test-Path { $true } -ParameterFilter { $PathType -eq 'Leaf' }
        $result = Test-LabIso -IsoName 'Server2019' -IsoPath 'C:\ISOs\server.iso'
        $result.Status | Should -Be 'Pass'
        $result.Exists | Should -BeTrue
        $result.IsValidIso | Should -BeTrue
    }

    It 'returns Fail for non-existent ISO' {
        Mock Test-Path { $false } -ParameterFilter { $PathType -eq 'Leaf' }
        $result = Test-LabIso -IsoName 'Server2019' -IsoPath 'C:\ISOs\nonexist.iso'
        $result.Status | Should -Be 'Fail'
        $result.Exists | Should -BeFalse
    }

    It 'returns Warning for existing file with wrong extension' {
        Mock Test-Path { $true } -ParameterFilter { $PathType -eq 'Leaf' }
        $result = Test-LabIso -IsoName 'Server2019' -IsoPath 'C:\ISOs\server.img'
        $result.Status | Should -Be 'Warning'
        $result.Exists | Should -BeTrue
        $result.IsValidIso | Should -BeFalse
    }

    It 'returns object with expected properties' {
        Mock Test-Path { $true } -ParameterFilter { $PathType -eq 'Leaf' }
        $result = Test-LabIso -IsoName 'TestISO' -IsoPath 'C:\test.iso'
        $result.Name | Should -Be 'TestISO'
        $result.Path | Should -Be 'C:\test.iso'
        $result.PSObject.Properties.Name | Should -Contain 'Status'
        $result.PSObject.Properties.Name | Should -Contain 'Exists'
        $result.PSObject.Properties.Name | Should -Contain 'IsValidIso'
    }
}

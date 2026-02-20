# DomainSetup.Tests.ps1 -- Unit tests for domain setup Public functions
# Covers: Initialize-LabDNS, Initialize-LabDomain, Join-LabDomain, Test-LabDomainHealth

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')

    . (Join-Path $script:repoRoot 'Public' 'Initialize-LabDNS.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Initialize-LabDomain.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Join-LabDomain.ps1')
    . (Join-Path $script:repoRoot 'Public' 'Test-LabDomainHealth.ps1')

    # Stub dependencies
    if (-not (Get-Command Write-LabStatus -ErrorAction SilentlyContinue)) {
        function Write-LabStatus { param($Status, $Message, $Indent) }
    }
    if (-not (Get-Command Get-LabVMConfig -ErrorAction SilentlyContinue)) {
        function Get-LabVMConfig { @{ dc1 = @{ Name = 'dc1' } } }
    }
    if (-not (Get-Command Test-LabVM -ErrorAction SilentlyContinue)) {
        function Test-LabVM { param([string]$VMName) [PSCustomObject]@{ Exists = $true; VMName = $VMName } }
    }
}

Describe 'Initialize-LabDNS' {
    BeforeEach {
        Register-HyperVMocks
        Mock Invoke-Command { [PSCustomObject]@{ Success = $true } }
    }

    It 'returns result with OverallStatus property' {
        $result = Initialize-LabDNS
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }

    It 'returns Failed when Hyper-V not available' {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }
        $result = Initialize-LabDNS
        $result.OverallStatus | Should -Be 'Failed'
    }
}

Describe 'Initialize-LabDomain' {
    BeforeEach {
        Register-HyperVMocks
        Mock Invoke-Command { [PSCustomObject]@{ Success = $true } }
    }

    It 'returns result with OverallStatus property' {
        $result = Initialize-LabDomain
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }

    It 'returns Failed when Hyper-V not available' {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }
        $result = Initialize-LabDomain
        $result.OverallStatus | Should -Be 'Failed'
    }
}

Describe 'Join-LabDomain' {
    BeforeEach {
        Register-HyperVMocks
        Mock Invoke-Command { [PSCustomObject]@{ Success = $true } }
    }

    It 'returns result with OverallStatus property' {
        $result = Join-LabDomain
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'OverallStatus'
    }

    It 'returns Failed when Hyper-V not available' {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }
        $result = Join-LabDomain
        $result.OverallStatus | Should -Be 'Failed'
    }
}

Describe 'Test-LabDomainHealth' {
    BeforeEach {
        Register-HyperVMocks
        Mock Invoke-Command { [PSCustomObject]@{ Success = $true; DomainName = 'lab.local'; DnsResolves = $true } }
    }

    It 'returns result object' {
        $result = Test-LabDomainHealth
        $result | Should -Not -BeNullOrEmpty
    }

    It 'returns Failed when Hyper-V not available' {
        Mock Get-Module { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'Hyper-V' }
        $result = Test-LabDomainHealth
        $result.OverallStatus | Should -Be 'Failed'
    }
}

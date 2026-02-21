# Wait-LabADReady tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Wait-LabADReady.ps1')

    # Create a script-level variable for call counting in tests
    $script:MockCallCount = 0
}

Describe 'Wait-LabADReady' {
    BeforeEach {
        # Mock Get-ADDomain as global function so Pester can mock it
        function Get-ADDomain { param($Identity) }

        # Reset call counter
        $script:MockCallCount = 0
    }

    AfterEach {
        # Clean up mocks
        Remove-Item -Path Function:\Get-ADDomain -Force -ErrorAction SilentlyContinue
    }

    It 'returns Ready=true when ADWS is immediately responsive' {
        Mock Get-ADDomain {
            return @{ DNSRoot = 'testlab.local' }
        }

        $result = Wait-LabADReady -DomainName 'testlab.local'

        $result.Ready | Should -BeTrue
        $result.WaitSeconds | Should -Be 0
        $result.DomainName | Should -Be 'testlab.local'
    }

    It 'returns Ready=false after timeout when domain never responds' {
        Mock Get-ADDomain {
            throw 'The server was unable to process the request due to an internal error'
        }

        $result = Wait-LabADReady -DomainName 'testlab.local' -TimeoutSeconds 1 -RetryIntervalSeconds 1

        $result.Ready | Should -BeFalse
        $result.WaitSeconds | Should -BeGreaterOrEqual 1
        $result.DomainName | Should -Be 'testlab.local'
    }

    It 'returns actual wait time when ADWS becomes ready mid-loop' {
        Mock Get-ADDomain {
            $script:MockCallCount++
            if ($script:MockCallCount -lt 3) {
                throw 'Not ready yet'
            }
            return @{ DNSRoot = 'testlab.local' }
        }

        $result = Wait-LabADReady -DomainName 'testlab.local' -TimeoutSeconds 60 -RetryIntervalSeconds 1

        $result.Ready | Should -BeTrue
        $result.WaitSeconds | Should -BeGreaterOrEqual 2
        $result.WaitSeconds | Should -BeLessThan 10
    }

    It 'passes DomainName correctly to Get-ADDomain' {
        Mock Get-ADDomain {
            param($Identity)
            $Identity | Should -Be 'testlab.local'
            return @{ DNSRoot = 'testlab.local' }
        }

        Wait-LabADReady -DomainName 'testlab.local'

        Should -Invoke Get-ADDomain -Times 1 -Exactly
    }

    It 'respects custom TimeoutSeconds parameter' {
        Mock Get-ADDomain {
            throw 'Never ready'
        }

        $result = Wait-LabADReady -DomainName 'testlab.local' -TimeoutSeconds 2 -RetryIntervalSeconds 1

        $result.Ready | Should -BeFalse
        $result.WaitSeconds | Should -BeGreaterOrEqual 2
        $result.WaitSeconds | Should -BeLessThan 5
    }

    It 'respects custom RetryIntervalSeconds parameter' {
        Mock Get-ADDomain {
            $script:MockCallCount++
            if ($script:MockCallCount -lt 3) {
                throw 'Not ready'
            }
            return @{ DNSRoot = 'testlab.local' }
        }

        $result = Wait-LabADReady -DomainName 'testlab.local' -TimeoutSeconds 30 -RetryIntervalSeconds 1

        $result.Ready | Should -BeTrue
        $result.WaitSeconds | Should -BeGreaterOrEqual 2
        $result.WaitSeconds | Should -BeLessThan 5
    }
}

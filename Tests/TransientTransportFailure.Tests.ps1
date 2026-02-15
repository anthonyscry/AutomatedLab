# Test-LabTransientTransportFailure tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $targetFile = Join-Path $repoRoot 'Private/Test-LabTransientTransportFailure.ps1'
    if (Test-Path $targetFile) {
        . $targetFile
    }
}

Describe 'Test-LabTransientTransportFailure' {
    It 'returns true for common transient remoting and transport failures' -TestCases @(
        @{ Message = 'WinRM cannot complete the operation. Verify that the specified computer name is valid, that the computer is accessible over the network, and that a firewall exception for the WinRM service is enabled.' },
        @{ Message = 'The client cannot connect to the destination specified in the request. Verify that the service on the destination is running and is accepting requests. Error number: -2144108526 0x80338126' },
        @{ Message = 'The WinRM operation timed out while waiting for a response from the remote host.' },
        @{ Message = 'The WSMan provider host process did not return a proper response. The operation has timed out.' }
    ) {
        param($Message)

        Test-LabTransientTransportFailure -Message $Message | Should -BeTrue
    }

    It 'returns false for deterministic non-transient failures' -TestCases @(
        @{ Message = 'Access is denied.' },
        @{ Message = 'User declined scoped confirmation token prompt.' },
        @{ Message = 'Scoped confirmation token validation failed: run_scope_mismatch.' },
        @{ Message = 'Execution policy restricts running scripts on this system.' },
        @{ Message = 'WinRM cannot process the request. The following error occurred while using Kerberos authentication: Access is denied.' },
        @{ Message = 'The WSMan provider host process did not return a proper response. The client cannot connect because the server rejected the credentials.' },
        @{ Message = 'WinRM cannot process the request because authentication failed for the remote endpoint.' }
    ) {
        param($Message)

        Test-LabTransientTransportFailure -Message $Message | Should -BeFalse
    }

    It 'returns false when timeout and access denied signals are both present' {
        $message = 'The WinRM operation timed out while waiting for a response from the remote host. Access is denied.'

        Test-LabTransientTransportFailure -Message $message | Should -BeFalse
    }

    It 'returns false for null or empty input' -TestCases @(
        @{ Message = $null },
        @{ Message = '' },
        @{ Message = '   ' }
    ) {
        param($Message)

        Test-LabTransientTransportFailure -Message $Message | Should -BeFalse
    }
}

# Scoped confirmation token tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/New-LabScopedConfirmationToken.ps1')
    . (Join-Path $repoRoot 'Private/Test-LabScopedConfirmationToken.ps1')
}

Describe 'Scoped confirmation token' {
    It 'accepts a valid token for matching run, hosts, and operation hash' {
        $secret = 'test-secret-value'
        $runId = 'run-123'
        $hosts = @('hv-01', 'hv-02')
        $operationHash = 'op-hash-abc'

        $token = New-LabScopedConfirmationToken -RunId $runId -TargetHosts $hosts -OperationHash $operationHash -Secret $secret -TtlSeconds 300
        $result = Test-LabScopedConfirmationToken -Token $token -RunId $runId -TargetHosts $hosts -OperationHash $operationHash -Secret $secret

        $result.Valid | Should -BeTrue
        $result.Reason | Should -Be 'valid'
    }

    It 'rejects scope mismatch for run id, hosts, or operation hash' -TestCases @(
        @{ Name = 'run'; ExpectedReason = 'run_scope_mismatch'; RunId = 'run-999'; TargetHosts = @('hv-01', 'hv-02'); OperationHash = 'op-hash-abc' },
        @{ Name = 'hosts'; ExpectedReason = 'host_scope_mismatch'; RunId = 'run-123'; TargetHosts = @('hv-01'); OperationHash = 'op-hash-abc' },
        @{ Name = 'operation'; ExpectedReason = 'operation_scope_mismatch'; RunId = 'run-123'; TargetHosts = @('hv-01', 'hv-02'); OperationHash = 'op-hash-other' }
    ) {
        param($ExpectedReason, $RunId, $TargetHosts, $OperationHash)

        $secret = 'test-secret-value'
        $token = New-LabScopedConfirmationToken -RunId 'run-123' -TargetHosts @('hv-01', 'hv-02') -OperationHash 'op-hash-abc' -Secret $secret -TtlSeconds 300

        $result = Test-LabScopedConfirmationToken -Token $token -RunId $RunId -TargetHosts $TargetHosts -OperationHash $OperationHash -Secret $secret

        $result.Valid | Should -BeFalse
        $result.Reason | Should -Be $ExpectedReason
    }

    It 'rejects token when validation target has extra hosts (token is subset)' {
        $secret = 'test-secret-subset'
        $token = New-LabScopedConfirmationToken -RunId 'run-sub' -TargetHosts @('hv-01', 'hv-02') -OperationHash 'op-sub' -Secret $secret -TtlSeconds 300

        $result = Test-LabScopedConfirmationToken -Token $token -RunId 'run-sub' -TargetHosts @('hv-01', 'hv-02', 'hv-03') -OperationHash 'op-sub' -Secret $secret

        $result.Valid | Should -BeFalse
        $result.Reason | Should -Be 'host_scope_mismatch'
    }

    It 'rejects token when validation target is missing hosts (token is superset)' {
        $secret = 'test-secret-superset'
        $token = New-LabScopedConfirmationToken -RunId 'run-sup' -TargetHosts @('hv-01', 'hv-02', 'hv-03') -OperationHash 'op-sup' -Secret $secret -TtlSeconds 300

        $result = Test-LabScopedConfirmationToken -Token $token -RunId 'run-sup' -TargetHosts @('hv-01', 'hv-02') -OperationHash 'op-sup' -Secret $secret

        $result.Valid | Should -BeFalse
        $result.Reason | Should -Be 'host_scope_mismatch'
    }

    It 'validates successfully when hosts are provided in different order' {
        $secret = 'test-secret-order'
        $token = New-LabScopedConfirmationToken -RunId 'run-ord' -TargetHosts @('hv-03', 'hv-01', 'hv-02') -OperationHash 'op-ord' -Secret $secret -TtlSeconds 300

        $result = Test-LabScopedConfirmationToken -Token $token -RunId 'run-ord' -TargetHosts @('hv-02', 'hv-03', 'hv-01') -OperationHash 'op-ord' -Secret $secret

        $result.Valid | Should -BeTrue
        $result.Reason | Should -Be 'valid'
    }

    It 'validates successfully when hosts differ in casing' {
        $secret = 'test-secret-case'
        $token = New-LabScopedConfirmationToken -RunId 'run-case' -TargetHosts @('HV-01', 'HV-02') -OperationHash 'op-case' -Secret $secret -TtlSeconds 300

        $result = Test-LabScopedConfirmationToken -Token $token -RunId 'run-case' -TargetHosts @('hv-01', 'hv-02') -OperationHash 'op-case' -Secret $secret

        $result.Valid | Should -BeTrue
        $result.Reason | Should -Be 'valid'
    }

    It 'validates a single-host token correctly' {
        $secret = 'test-secret-single'
        $token = New-LabScopedConfirmationToken -RunId 'run-single' -TargetHosts @('hv-01') -OperationHash 'op-single' -Secret $secret -TtlSeconds 300

        $result = Test-LabScopedConfirmationToken -Token $token -RunId 'run-single' -TargetHosts @('hv-01') -OperationHash 'op-single' -Secret $secret

        $result.Valid | Should -BeTrue
        $result.Reason | Should -Be 'valid'
    }

    It 'rejects token with tampered payload' {
        $secret = 'test-secret-tamper'
        $token = New-LabScopedConfirmationToken -RunId 'run-tamper' -TargetHosts @('hv-01') -OperationHash 'op-tamper' -Secret $secret -TtlSeconds 300

        # Flip a character in the payload portion
        $parts = $token -split '\.'
        $tamperedPayload = $parts[1].Substring(0, $parts[1].Length - 1) + 'X'
        $tamperedToken = '{0}.{1}.{2}' -f $parts[0], $tamperedPayload, $parts[2]

        $result = Test-LabScopedConfirmationToken -Token $tamperedToken -RunId 'run-tamper' -TargetHosts @('hv-01') -OperationHash 'op-tamper' -Secret $secret

        $result.Valid | Should -BeFalse
        $result.Reason | Should -Be 'bad_signature'
    }

    It 'rejects expired tokens' {
        $secret = 'test-secret-value'
        $token = New-LabScopedConfirmationToken -RunId 'run-123' -TargetHosts @('hv-01') -OperationHash 'op-hash-abc' -Secret $secret -TtlSeconds 1

        Start-Sleep -Seconds 2
        $result = Test-LabScopedConfirmationToken -Token $token -RunId 'run-123' -TargetHosts @('hv-01') -OperationHash 'op-hash-abc' -Secret $secret

        $result.Valid | Should -BeFalse
        $result.Reason | Should -Be 'token_expired'
    }

    It 'rejects malformed token format' {
        $result = Test-LabScopedConfirmationToken -Token 'not-a-valid-token' -RunId 'run-123' -TargetHosts @('hv-01') -OperationHash 'op-hash-abc' -Secret 'test-secret-value'

        $result.Valid | Should -BeFalse
        $result.Reason | Should -Be 'malformed_token'
    }

    It 'rejects bad signatures' {
        $token = New-LabScopedConfirmationToken -RunId 'run-123' -TargetHosts @('hv-01') -OperationHash 'op-hash-abc' -Secret 'secret-a' -TtlSeconds 300
        $result = Test-LabScopedConfirmationToken -Token $token -RunId 'run-123' -TargetHosts @('hv-01') -OperationHash 'op-hash-abc' -Secret 'secret-b'

        $result.Valid | Should -BeFalse
        $result.Reason | Should -Be 'bad_signature'
    }
}

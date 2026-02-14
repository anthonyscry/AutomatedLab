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

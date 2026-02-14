# Resolve-LabCoordinatorPolicy tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Resolve-LabCoordinatorPolicy.ps1')
}

Describe 'Resolve-LabCoordinatorPolicy' {
    It 'fails closed when any host probe is unreachable' {
        $hostProbes = @(
            [pscustomobject]@{ Name = 'dc1'; Reachable = $true },
            [pscustomobject]@{ Name = 'ws1'; Reachable = $false }
        )

        $result = Resolve-LabCoordinatorPolicy -Action teardown -RequestedMode quick -HostProbes $hostProbes -SafetyRequiresFull $false

        $result.Allowed | Should -BeFalse
        $result.Outcome.GetType().Name | Should -Be 'LabCoordinatorPolicyOutcome'
        $result.Outcome.ToString() | Should -Be 'PolicyBlocked'
        $result.Reason | Should -Be 'host_probe_unreachable:ws1'
        $result.EffectiveMode | Should -Be 'quick'
    }

    It 'returns escalation required for quick teardown when safety requires full mode' {
        $hostProbes = @(
            [pscustomobject]@{ Name = 'dc1'; Reachable = $true },
            [pscustomobject]@{ Name = 'ws1'; Reachable = $true }
        )

        $result = Resolve-LabCoordinatorPolicy -Action teardown -RequestedMode quick -HostProbes $hostProbes -SafetyRequiresFull $true

        $result.Allowed | Should -BeFalse
        $result.Outcome.ToString() | Should -Be 'EscalationRequired'
        $result.Reason | Should -Be 'quick_teardown_requires_full'
        $result.EffectiveMode | Should -Be 'full'
    }

    It 'blocks full teardown without scoped confirmation' {
        $hostProbes = @(
            [pscustomobject]@{ Name = 'dc1'; Reachable = $true },
            [pscustomobject]@{ Name = 'ws1'; Reachable = $true }
        )

        $result = Resolve-LabCoordinatorPolicy -Action teardown -RequestedMode full -HostProbes $hostProbes -SafetyRequiresFull $true -HasScopedConfirmation $false

        $result.Allowed | Should -BeFalse
        $result.Outcome.ToString() | Should -Be 'PolicyBlocked'
        $result.Reason | Should -Be 'missing_scoped_confirmation'
        $result.EffectiveMode | Should -Be 'full'
    }

    It 'approves full teardown when probes are reachable and confirmation is present' {
        $hostProbes = @(
            [pscustomobject]@{ Name = 'dc1'; Reachable = $true },
            [pscustomobject]@{ Name = 'ws1'; Reachable = $true }
        )

        $result = Resolve-LabCoordinatorPolicy -Action teardown -RequestedMode full -HostProbes $hostProbes -SafetyRequiresFull $true -HasScopedConfirmation $true

        $result.Allowed | Should -BeTrue
        $result.Outcome.ToString() | Should -Be 'Approved'
        $result.Reason | Should -Be 'approved'
        $result.EffectiveMode | Should -Be 'full'
    }
}

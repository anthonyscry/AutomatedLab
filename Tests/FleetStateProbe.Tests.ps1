# Fleet state probe tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Invoke-LabRemoteProbe.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabFleetStateProbe.ps1')
}

Describe 'Invoke-LabRemoteProbe' {
    It 'executes probe locally for localhost without remoting' {
        Mock -CommandName Invoke-Command -MockWith { throw 'Invoke-Command should not be called for localhost' }

        $result = Invoke-LabRemoteProbe -HostName 'localhost' -ScriptBlock { 'local-ok' }

        $result | Should -Be 'local-ok'
        Should -Invoke -CommandName Invoke-Command -Times 0 -Exactly
    }

    It 'executes probe locally for current computer name without remoting' {
        $localHost = [Environment]::MachineName
        Mock -CommandName Invoke-Command -MockWith { throw 'Invoke-Command should not be called for local machine name' }

        $result = Invoke-LabRemoteProbe -HostName $localHost -ScriptBlock { 'local-machine-ok' }

        $result | Should -Be 'local-machine-ok'
        Should -Invoke -CommandName Invoke-Command -Times 0 -Exactly
    }

    It 'uses PowerShell remoting for remote hosts' {
        Mock -CommandName Invoke-Command -MockWith {
            param($ComputerName, $ScriptBlock)
            [pscustomobject]@{ ComputerName = $ComputerName; Value = (& $ScriptBlock) }
        }

        $result = Invoke-LabRemoteProbe -HostName 'hv-02' -ScriptBlock { 'remote-ok' }

        $result.ComputerName | Should -Be 'hv-02'
        $result.Value | Should -Be 'remote-ok'
        Should -Invoke -CommandName Invoke-Command -Times 1 -Exactly -ParameterFilter { $ComputerName -eq 'hv-02' }
    }

    It 'surfaces clear errors when remoting fails' {
        Mock -CommandName Invoke-Command -MockWith { throw 'WinRM unavailable' }

        {
            Invoke-LabRemoteProbe -HostName 'hv-03' -ScriptBlock { 'never-runs' }
        } | Should -Throw "Remote probe failed for host 'hv-03'*WinRM unavailable*"
    }
}

Describe 'Get-LabFleetStateProbe' {
    It 'returns one structured result per host' {
        Mock -CommandName Invoke-LabRemoteProbe -MockWith {
            param($HostName)
            [pscustomobject]@{ Marker = "probe-$HostName" }
        }

        $result = Get-LabFleetStateProbe -HostNames @('hv-01', 'hv-02') -LabName 'SimpleLab' -VMNames @('dc1') -SwitchName 'LabSwitch' -NatName 'LabNAT'

        $result.Count | Should -Be 2
        $result[0].PSObject.Properties.Name | Should -Contain 'HostName'
        $result[0].PSObject.Properties.Name | Should -Contain 'Reachable'
        $result[0].PSObject.Properties.Name | Should -Contain 'Probe'
        $result[0].PSObject.Properties.Name | Should -Contain 'Failure'
        $result[0].HostName | Should -Be 'hv-01'
        $result[0].Reachable | Should -BeTrue
        $result[0].Probe.Marker | Should -Be 'probe-hv-01'
        $result[0].Failure | Should -BeNullOrEmpty
        $result[1].HostName | Should -Be 'hv-02'
        $result[1].Reachable | Should -BeTrue
        $result[1].Probe.Marker | Should -Be 'probe-hv-02'
        $result[1].Failure | Should -BeNullOrEmpty
    }

    It 'captures a host failure and continues probing remaining hosts' {
        Mock -CommandName Invoke-LabRemoteProbe -ParameterFilter { $HostName -eq 'hv-02' } -MockWith {
            throw 'Unable to connect'
        }
        Mock -CommandName Invoke-LabRemoteProbe -ParameterFilter { $HostName -ne 'hv-02' } -MockWith {
            param($HostName)
            [pscustomobject]@{ Marker = "probe-$HostName" }
        }

        $result = Get-LabFleetStateProbe -HostNames @('hv-01', 'hv-02', 'hv-03') -LabName 'SimpleLab' -VMNames @('dc1') -SwitchName 'LabSwitch' -NatName 'LabNAT'

        $result.Count | Should -Be 3
        ($result | Where-Object HostName -eq 'hv-01').Reachable | Should -BeTrue
        ($result | Where-Object HostName -eq 'hv-01').Failure | Should -BeNullOrEmpty

        $failed = $result | Where-Object HostName -eq 'hv-02'
        $failed.Reachable | Should -BeFalse
        $failed.Probe | Should -BeNullOrEmpty
        $failed.Failure | Should -BeLike '*Unable to connect*'

        $afterFailure = $result | Where-Object HostName -eq 'hv-03'
        $afterFailure.Reachable | Should -BeTrue
        $afterFailure.Probe.Marker | Should -Be 'probe-hv-03'
    }
}

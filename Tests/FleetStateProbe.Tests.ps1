# Fleet state probe tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Invoke-LabRemoteProbe.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabFleetStateProbe.ps1')

    function Invoke-TestInIsolatedRunspace {
        param(
            [Parameter(Mandatory)]
            [scriptblock]$ScriptBlock,

            [Parameter()]
            [object[]]$ArgumentList = @()
        )

        $ps = [powershell]::Create()
        try {
            $null = $ps.AddScript($ScriptBlock.ToString(), $true)
            foreach ($argument in $ArgumentList) {
                $null = $ps.AddArgument($argument)
            }

            $output = $ps.Invoke()
            if ($ps.HadErrors -and $output.Count -eq 0) {
                throw $ps.Streams.Error[0].Exception
            }

            if ($output.Count -eq 1) {
                return $output[0]
            }

            return @($output)
        }
        finally {
            $ps.Dispose()
        }
    }
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
            param($ComputerName, $ScriptBlock, $ArgumentList)
            [pscustomobject]@{
                ComputerName = $ComputerName
                Value = Invoke-TestInIsolatedRunspace -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
            }
        }

        $result = Invoke-LabRemoteProbe -HostName 'hv-02' -ScriptBlock {
            param($Message)

            [pscustomobject]@{
                Message = $Message
            }
        } -ArgumentList @('remote-ok')

        $result.ComputerName | Should -Be 'hv-02'
        $result.Value.Message | Should -Be 'remote-ok'
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
    It 'returns one structured result per host from an isolated remote scriptblock' {
        Mock -CommandName Invoke-Command -MockWith {
            param($ScriptBlock, $ArgumentList)
            Invoke-TestInIsolatedRunspace -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
        }

        $result = Get-LabFleetStateProbe -HostNames @('hv-01', 'hv-02') -LabName 'SimpleLab' -VMNames @('dc1') -SwitchName 'LabSwitch' -NatName 'LabNAT'

        $result.Count | Should -Be 2
        $result[0].PSObject.Properties.Name | Should -Contain 'HostName'
        $result[0].PSObject.Properties.Name | Should -Contain 'Reachable'
        $result[0].PSObject.Properties.Name | Should -Contain 'Probe'
        $result[0].PSObject.Properties.Name | Should -Contain 'Failure'
        $result[0].HostName | Should -Be 'hv-01'
        $result[0].Reachable | Should -BeTrue
        $result[0].Probe.PSObject.Properties.Name | Should -Contain 'LabRegistered'
        $result[0].Probe.PSObject.Properties.Name | Should -Contain 'MissingVMs'
        $result[0].Probe.PSObject.Properties.Name | Should -Contain 'LabReadyAvailable'
        $result[0].Probe.PSObject.Properties.Name | Should -Contain 'SwitchPresent'
        $result[0].Probe.PSObject.Properties.Name | Should -Contain 'NatPresent'
        $result[0].Failure | Should -BeNullOrEmpty
        $result[1].HostName | Should -Be 'hv-02'
        $result[1].Reachable | Should -BeTrue
        $result[1].Probe.PSObject.Properties.Name | Should -Contain 'LabRegistered'
        $result[1].Failure | Should -BeNullOrEmpty
    }

    It 'captures a host failure and continues probing remaining hosts' {
        Mock -CommandName Invoke-Command -ParameterFilter { $ComputerName -eq 'hv-02' } -MockWith {
            throw 'Unable to connect'
        }
        Mock -CommandName Invoke-Command -ParameterFilter { $ComputerName -ne 'hv-02' } -MockWith {
            param($ScriptBlock, $ArgumentList)
            Invoke-TestInIsolatedRunspace -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
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
        $afterFailure.Probe.PSObject.Properties.Name | Should -Contain 'LabRegistered'
    }

    It 'returns structured failure when remote probe throws' {
        Mock Invoke-LabRemoteProbe {
            throw "Remote probe failed for host 'hv-fail': WinRM cannot complete the operation."
        }

        $results = Get-LabFleetStateProbe -HostNames @('hv-fail')

        @($results).Count | Should -Be 1
        $results[0].HostName | Should -Be 'hv-fail'
        $results[0].Reachable | Should -BeFalse
        $results[0].Probe | Should -BeNullOrEmpty
        $results[0].Failure | Should -BeLike "*hv-fail*WinRM*"
    }

    It 'returns mixed results for fleet with one reachable and one unreachable host' {
        Mock Invoke-LabRemoteProbe {
            param($HostName, $ScriptBlock, $ArgumentList)
            if ($HostName -eq 'hv-ok') {
                return [pscustomobject]@{
                    LabRegistered = $true
                    MissingVMs = @()
                    LabReadyAvailable = $true
                    SwitchPresent = $true
                    NatPresent = $true
                }
            }
            throw "Remote probe failed for host 'hv-down': Connection refused"
        }

        $results = Get-LabFleetStateProbe -HostNames @('hv-ok', 'hv-down')

        @($results).Count | Should -Be 2
        ($results | Where-Object { $_.HostName -eq 'hv-ok' }).Reachable | Should -BeTrue
        ($results | Where-Object { $_.HostName -eq 'hv-down' }).Reachable | Should -BeFalse
        ($results | Where-Object { $_.HostName -eq 'hv-down' }).Failure | Should -BeLike "*hv-down*Connection refused*"
    }
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'HostEnvironment.ps1')
}

Describe 'Test-OpenCodeLabLaunchPreconditions' {
    It 'blocks launch in WSL with actionable message' {
        $result = Test-OpenCodeLabLaunchPreconditions -WindowsHost:$false -WslHost:$true

        $result.CanLaunch | Should -BeFalse
        $result.Message | Should -Match 'powershell.exe'
    }

    It 'blocks non-elevated Windows launch' {
        $result = Test-OpenCodeLabLaunchPreconditions -WindowsHost:$true -WslHost:$false -ElevatedSession:$false

        $result.CanLaunch | Should -BeFalse
        $result.Message | Should -Match 'Administrator'
    }

    It 'allows elevated Windows launch' {
        $result = Test-OpenCodeLabLaunchPreconditions -WindowsHost:$true -WslHost:$false -ElevatedSession:$true

        $result.CanLaunch | Should -BeTrue
    }
}

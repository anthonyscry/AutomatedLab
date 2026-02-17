# TeardownIdempotency.Tests.ps1
# Tests for teardown completeness and bootstrap idempotency

BeforeAll {
    # $PSScriptRoot points to Tests/ directory
    # Parent directory is project root
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
    $OpenCodeLabAppPath = Join-Path $ProjectRoot 'OpenCodeLab-App.ps1'
    $BlowAwayPath = Join-Path $ProjectRoot 'Private/Invoke-LabBlowAway.ps1'
    $BootstrapPath = Join-Path $ProjectRoot 'Bootstrap.ps1'

    # Extracted in Batch 3 - now lives in Private/
    $OneButtonResetPath = Join-Path $ProjectRoot 'Private/Invoke-LabOneButtonReset.ps1'
}

Describe 'Invoke-LabBlowAway teardown completeness' {
    It 'function definition contains Clear-LabSSHKnownHosts call' {
        $content = Get-Content $BlowAwayPath -Raw
        $content | Should -Match 'function Invoke-LabBlowAway'
        $content | Should -Match 'Clear-LabSSHKnownHosts'
    }

    It 'Simulate mode includes SSH cleanup step in output' {
        $content = Get-Content $BlowAwayPath -Raw
        # Check that the simulate block mentions SSH known_hosts
        $content | Should -Match 'Would clear SSH known_hosts'
    }

    It 'NAT removal includes verification check' {
        $content = Get-Content $BlowAwayPath -Raw
        # Verify NAT removal verification exists after Remove-NetNat (now uses $LabConfig param)
        $content | Should -Match 'Remove-NetNat.*-Name.*LabConfig\.Network\.NatName'
        $content | Should -Match '\$natCheck.*Get-NetNat'
    }
}

Describe 'Bootstrap.ps1 idempotency' {
    It 'contains idempotency check for PSFramework module' {
        $content = Get-Content $BootstrapPath -Raw
        $content | Should -Match 'Get-Module -Name PSFramework -ListAvailable'
    }

    It 'contains idempotency check for SHiPS module' {
        $content = Get-Content $BootstrapPath -Raw
        $content | Should -Match 'Get-Module -Name SHiPS -ListAvailable'
    }

    It 'contains idempotency check for AutomatedLab module' {
        $content = Get-Content $BootstrapPath -Raw
        $content | Should -Match 'Get-Module -Name AutomatedLab -ListAvailable'
    }

    It 'vSwitch creation checks for existing switch before creating' {
        $content = Get-Content $BootstrapPath -Raw
        # Should check Get-VMSwitch before New-VMSwitch
        $content | Should -Match 'Get-VMSwitch.*-Name.*GlobalLabConfig\.Network\.SwitchName'
        $content | Should -Match 'if \(-not \$sw\)'
        $content | Should -Match 'New-VMSwitch'
    }

    It 'NAT creation checks for existing NAT before creating' {
        $content = Get-Content $BootstrapPath -Raw
        # Should check Get-NetNat before New-NetNat
        $content | Should -Match 'Get-NetNat.*-Name.*GlobalLabConfig\.Network\.NatName'
        $content | Should -Match 'if \(-not \$nat\)'
        $content | Should -Match 'New-NetNat'
    }

    It 'folder creation checks for existing folders before creating' {
        $content = Get-Content $BootstrapPath -Raw
        $content | Should -Match 'foreach.*\$folder.*in.*\$RequiredFolders'
        $content | Should -Match 'if \(-not \(Test-Path \$folder\)\)'
        $content | Should -Match 'New-Item.*-Path \$folder'
    }
}

Describe 'Invoke-LabOneButtonReset confirmation gates' {
    It 'requires confirmation unless Force or NonInteractive is set' {
        # Function extracted to Private/Invoke-LabOneButtonReset.ps1 in Batch 3
        $content = Get-Content $OneButtonResetPath -Raw
        # Should use Force/NonInteractive flags to control BypassPrompt
        $content | Should -Match 'function Invoke-LabOneButtonReset'
        $content | Should -Match '\$Force'
        $content | Should -Match '\$NonInteractive'
        $content | Should -Match 'BypassPrompt.*shouldBypassPrompt'
    }
}

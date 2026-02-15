# Deploy/bootstrap mode handoff tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $deployPath = Join-Path $repoRoot 'Deploy.ps1'
    $bootstrapPath = Join-Path $repoRoot 'Bootstrap.ps1'
    $appPath = Join-Path $repoRoot 'OpenCodeLab-App.ps1'

    $deployText = Get-Content -Raw -Path $deployPath
    $bootstrapText = Get-Content -Raw -Path $bootstrapPath
    $appText = Get-Content -Raw -Path $appPath
}

Describe 'Deploy and bootstrap mode defaults' {
    It 'Deploy.ps1 exposes Mode parameter with full default' {
        $deployText | Should -Match '\[ValidateSet\(''quick'',\s*''full''\)\]\s*\[string\]\$Mode\s*=\s*''full'''
    }

    It 'Bootstrap.ps1 exposes Mode parameter with full default' {
        $bootstrapText | Should -Match '\[ValidateSet\(''quick'',\s*''full''\)\]\s*\[string\]\$Mode\s*=\s*''full'''
    }

    It 'Bootstrap.ps1 passes explicit mode into Deploy.ps1' {
        $bootstrapText | Should -Match '\$deployArgs\s*=\s*@\(''-Mode'',\s*\$Mode\)'
        $bootstrapText | Should -Match '&\s+\$DeployScript\s+@deployArgs'
    }

    It 'Deploy.ps1 supports explicit subnet conflict auto-fix opt-in switch' {
        $deployText | Should -Match '\[switch\]\$AutoFixSubnetConflict'
    }

    It 'Bootstrap.ps1 supports and forwards subnet conflict auto-fix opt-in switch' {
        $bootstrapText | Should -Match '\[switch\]\$AutoFixSubnetConflict'
        $bootstrapText | Should -Match 'if\s*\(\$AutoFixSubnetConflict\)\s*\{\s*\$deployArgs\s*\+=\s*''-AutoFixSubnetConflict''\s*\}'
    }
}

Describe 'OpenCodeLab app deploy handoff' {
    It 'passes effective mode explicitly when launching Deploy.ps1' {
        $appText | Should -Match 'Get-DeployArgs\s+-Mode\s+\$EffectiveMode'
    }

    It 'passes effective mode explicitly into Bootstrap.ps1 for all bootstrap entry paths' {
        $matches = [regex]::Matches($appText, 'Get-BootstrapArgs\s+-Mode\s+\$EffectiveMode')
        $matches.Count | Should -Be 3
    }

    It 'Get-BootstrapArgs accepts mode and forwards it to Bootstrap.ps1' {
        $appText | Should -Match 'function\s+Get-BootstrapArgs\s*\{\s*param\('
        $appText | Should -Match 'Get-BootstrapArgs\s*\{[\s\S]*\$scriptArgs\s*\+=\s*@\(''-Mode'',\s*\$Mode\)'
    }

    It 'OpenCodeLab-App supports and forwards subnet conflict auto-fix opt-in switch' {
        $appText | Should -Match '\[switch\]\$AutoFixSubnetConflict'
        $appText | Should -Match 'Get-BootstrapArgs\s*\{[\s\S]*if\s*\(\$AutoFixSubnetConflict\)\s*\{\s*\$scriptArgs\s*\+=\s*''-AutoFixSubnetConflict''\s*\}'
        $appText | Should -Match 'Get-DeployArgs\s*\{[\s\S]*if\s*\(\$AutoFixSubnetConflict\)\s*\{\s*\$scriptArgs\s*\+=\s*''-AutoFixSubnetConflict''\s*\}'
        $appText | Should -Match '\$defaults\.AutoFixSubnetConflict'
    }
}

Describe 'Deploy mode semantics' {
    It 'explicitly handles quick mode fallback to full mode' {
        $deployText | Should -Match 'if\s*\(\$Mode\s*-eq\s*''quick''\)'
        $deployText | Should -Match '\$EffectiveMode\s*=\s*''full'''
        $deployText | Should -Match 'Write-LabStatus\s+-Status\s+WARN\s+-Message\s+".*quick.*full.*"'
    }

    It 'requires explicit subnet auto-fix switch before remediation' {
        $deployText | Should -Match '\$allowSubnetAutoFix\s*=\s*\$AutoFixSubnetConflict'
        $deployText | Should -Not -Match "Type 'fix' to remove conflicting vEthernet IP assignments and continue"
    }
}

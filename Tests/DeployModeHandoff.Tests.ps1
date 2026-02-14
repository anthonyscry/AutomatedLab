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
        $bootstrapText | Should -Match '\$DeployScript\s+-Mode\s+\$Mode'
    }
}

Describe 'OpenCodeLab app deploy handoff' {
    It 'passes effective mode explicitly when launching Deploy.ps1' {
        $appText | Should -Match 'Get-DeployArgs\s+-Mode\s+\$EffectiveMode'
    }
}

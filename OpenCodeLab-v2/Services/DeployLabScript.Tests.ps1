BeforeAll {
    $script:deployScriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Deploy-Lab.ps1'
    $script:deployScript = Get-Content -Raw -Path $script:deployScriptPath
}

Describe 'Deploy-Lab deployment modes' {
    It 'defines update-existing switch parameter' {
        $script:deployScript | Should -Match '\[switch\]\$UpdateExisting'
    }

    It 'contains update-existing branch before full cleanup branch' {
        $script:deployScript | Should -Match 'if \(\$UpdateExisting\)'
        $script:deployScript | Should -Match 'Skipping destructive recreate in update-existing mode'
    }

    It 'tracks summary buckets for reconcile planning' {
        $script:deployScript | Should -Match 'WillUpdateInPlace'
        $script:deployScript | Should -Match 'WillCreate'
        $script:deployScript | Should -Match 'RequiresRecreate'
        $script:deployScript | Should -Match 'Skipped'
    }
}

Describe 'Deploy-Lab internet policy orchestration' {
    It 'passes lab name into worker context and imports lab in worker' {
        $script:deployScript | Should -Match '\$labName\s*=\s*\[string\]\$item\.LabName'
        $script:deployScript | Should -Match 'Import-Lab\s+-Name\s+\$labName'
    }
}

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
    It 'does not orchestrate internet policy via parallel jobs' {
        $script:deployScript | Should -Not -Match 'Invoke-ParallelLabJobs\s+-Items\s+\$internetPolicyTargets'
    }

    It 'applies internet policy sequentially for each VM target' {
        $script:deployScript | Should -Match 'foreach\s*\(\$item\s+in\s+\$internetPolicyTargets\)\s*\{'
        $script:deployScript | Should -Match 'Set-VMInternetPolicy\s+-VmName\s+\$item\.VMName\s+-EnableHostInternet\s+\$item\.EnableHostInternet\s+-Gateway\s+\$item\.Gateway'
    }
}

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

    It 'defines running VM handling policy for update-existing mode' {
        $script:deployScript | Should -Match "\[ValidateSet\('abort'\s*,\s*'shutdown'\s*,\s*'skip'\)\]"
        $script:deployScript | Should -Match '\[string\]\$OnRunningVMs = ''abort''' 
        $script:deployScript | Should -Match 'Running VMs detected in update-existing mode'
    }

    It 'allows passwordless update-existing when no new VMs are created' {
        $script:deployScript | Should -Match '\$requiresAdminPassword = -not \$skipProvisioning'
        $script:deployScript | Should -Match 'No new VMs detected in update-existing mode\. Skipping AutomatedLab provisioning phases'
    }

    It 'accepts omitted AdminPassword and validates requirement inside script' {
        $script:deployScript | Should -Match '\[Parameter\(Mandatory=\$false\)\]\s*\[string\]\$AdminPassword'
        $script:deployScript | Should -Match 'if \(\$requiresAdminPassword -and \[string\]::IsNullOrWhiteSpace\(\$AdminPassword\)\)'
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

    It 'avoids PersistentStore-only default route writes' {
        $script:deployScript | Should -Not -Match 'New-NetRoute[^\r\n]+-PolicyStore\s+PersistentStore'
    }

    It 'verifies default route in ActiveStore with retries' {
        $script:deployScript | Should -Match '\$routeApplyRetries\s*=\s*3'
        $script:deployScript | Should -Match 'Get-NetRoute\s+-AddressFamily\s+IPv4\s+-DestinationPrefix\s+''0\.0\.0\.0/0''\s+-PolicyStore\s+ActiveStore'
    }
}

Describe 'Deploy-Lab host NAT readiness' {
    It 'defines host NAT ensure helper for lab network' {
        $script:deployScript | Should -Match 'function\s+Ensure-HostNatForLabNetwork'
        $script:deployScript | Should -Match 'Get-NetNat'
        $script:deployScript | Should -Match 'New-NetNat'
    }

    It 'ensures host NAT before applying internet policy when required' {
        $script:deployScript | Should -Match '\$requiresHostInternet\s*=\s+\$internetPolicyTargets\s*\|\s*Where-Object\s*\{\s*\$_.EnableHostInternet\s*\}'
        $script:deployScript | Should -Match 'Ensure-HostNatForLabNetwork\s+-LabName\s+\$LabName\s+-AddressPrefix\s+''192\.168\.10\.0/24'''
    }
}

Describe 'Deploy-Lab variable interpolation safety' {
    It 'avoids vmName drive-reference interpolation errors' {
        $script:deployScript | Should -Not -Match '\$vmName:\s'
        $script:deployScript | Should -Match '\$\{vmName\}:'
    }
}

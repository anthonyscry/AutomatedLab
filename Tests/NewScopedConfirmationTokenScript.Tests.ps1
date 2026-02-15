# Public token issuance script tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'Scripts/New-ScopedConfirmationToken.ps1'

    . (Join-Path $repoRoot 'Private/Test-LabScopedConfirmationToken.ps1')

    $script:originalConfirmationRunId = $env:OPENCODELAB_CONFIRMATION_RUN_ID
    $script:originalConfirmationSecret = $env:OPENCODELAB_CONFIRMATION_SECRET
}

AfterAll {
    if ($null -eq $script:originalConfirmationRunId) {
        Remove-Item Env:OPENCODELAB_CONFIRMATION_RUN_ID -ErrorAction SilentlyContinue
    }
    else {
        $env:OPENCODELAB_CONFIRMATION_RUN_ID = $script:originalConfirmationRunId
    }

    if ($null -eq $script:originalConfirmationSecret) {
        Remove-Item Env:OPENCODELAB_CONFIRMATION_SECRET -ErrorAction SilentlyContinue
    }
    else {
        $env:OPENCODELAB_CONFIRMATION_SECRET = $script:originalConfirmationSecret
    }
}

Describe 'Scripts/New-ScopedConfirmationToken.ps1' {
    It 'mints a valid teardown full token from run-scope and secret env vars' {
        $env:OPENCODELAB_CONFIRMATION_RUN_ID = 'run-script-001'
        $env:OPENCODELAB_CONFIRMATION_SECRET = 'script-secret-001'

        $token = & $scriptPath -TargetHosts @('hv-a') -Action 'teardown' -Mode 'full' -TtlSeconds 300
        $validation = Test-LabScopedConfirmationToken -Token $token -RunId 'run-script-001' -TargetHosts @('hv-a') -OperationHash 'teardown:full:teardown' -Secret 'script-secret-001'

        $validation.Valid | Should -BeTrue
        $validation.Reason | Should -Be 'valid'
    }
}

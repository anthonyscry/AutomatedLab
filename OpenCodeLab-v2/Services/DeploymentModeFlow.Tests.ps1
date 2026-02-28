BeforeAll {
    $script:repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:servicePath = Join-Path $script:repoRoot 'OpenCodeLab-v2/Services/LabDeploymentService.cs'
    $script:viewModelPath = Join-Path $script:repoRoot 'OpenCodeLab-v2/ViewModels/ActionsViewModel.cs'
    $script:modelPath = Join-Path $script:repoRoot 'OpenCodeLab-v2/Models/LabConfig.cs'
    $script:deployScriptPath = Join-Path $script:repoRoot 'OpenCodeLab-v2/Deploy-Lab.ps1'

    $script:serviceText = Get-Content -Raw $script:servicePath
    $script:viewModelText = Get-Content -Raw $script:viewModelPath
    $script:modelText = Get-Content -Raw $script:modelPath
    $script:deployText = Get-Content -Raw $script:deployScriptPath
}

Describe 'Deployment mode plumbing' {
    It 'propagates update-existing mode switch from service to script' {
        $script:serviceText | Should -Match 'deploymentMode\s*=\s*"full"'
        $script:serviceText | Should -Match 'allowedModes'
        $script:serviceText | Should -Match 'Falling back to non-destructive incremental mode'
        $script:serviceText | Should -Match 'switches\.Add\("Incremental"\)'
        $script:serviceText | Should -Match 'switches\.Add\("UpdateExisting"\)'
        $script:serviceText | Should -Match 'OnRunningVMs'
    }

    It 'offers update-existing mode and supports canceling deployment in viewmodel' {
        $script:viewModelText | Should -Match 'deploymentMode\s*=\s*"update-existing"'
        $script:viewModelText | Should -Match 'userCancelledDeploymentMode'
        $script:viewModelText | Should -Match 'if \(userCancelledDeploymentMode\)'
        $script:viewModelText | Should -Match 'onRunningVms\s*=\s*"abort"'
        $script:viewModelText | Should -Match 'Running VMs detected'
        $script:viewModelText | Should -Match 'requiresPassword'
    }

    It 'does not pass empty AdminPassword to Deploy-Lab invocation' {
        $script:serviceText | Should -Match 'if \(!string\.IsNullOrWhiteSpace\(pw\)\)'
        $script:serviceText | Should -Match 'args\["AdminPassword"\] = pw;'
    }

    It 'avoids offering destructive full redeploy when all VMs already exist' {
        $script:viewModelText | Should -Match 'keep existing VMs and disks unchanged'
        $script:viewModelText | Should -Not -Match 'redeploy everything from scratch'
    }

    It 'passes optional external internet switch settings to deployment script' {
        $script:serviceText | Should -Match 'EnableExternalInternetSwitch'
        $script:serviceText | Should -Match 'ExternalSwitchName'
    }

    It 'serializes bool arguments as PowerShell boolean literals' {
        $script:serviceText | Should -Match 'FormatPowerShellArgumentValue\(object\? value\)'
        $script:serviceText | Should -Match 'bool b\s*=>\s*b\s*\?\s*"\$true"\s*:\s*"\$false"'
        $script:serviceText | Should -Match 'sb\.Append\(\$" -\{kvp\.Key\} \{FormatPowerShellArgumentValue\(kvp\.Value\)\}"\)'
    }

    It 'persists external internet switch settings in lab model' {
        $script:modelText | Should -Match 'EnableExternalInternetSwitch\s*\{\s*get;\s*set;\s*\}\s*=\s*false;'
        $script:modelText | Should -Match 'ExternalSwitchName\s*\{\s*get;\s*set;\s*\}\s*=\s*"DefaultExternal";'
    }
}

Describe 'Update-existing script behavior' {
    It 'implements update-existing branch and reconcile actions' {
        $script:deployText | Should -Match 'if \(\$UpdateExisting\)'
        $script:deployText | Should -Match 'Update-ExistingVMSettings'
        $script:deployText | Should -Match 'Set-VMProcessor'
        $script:deployText | Should -Match 'Set-VMMemory'
        $script:deployText | Should -Match 'Connect-VMNetworkAdapter'
    }

    It 'tracks update summary buckets and non-destructive recreate reporting' {
        $script:deployText | Should -Match 'WillUpdateInPlace'
        $script:deployText | Should -Match 'WillCreate'
        $script:deployText | Should -Match 'RequiresRecreate'
        $script:deployText | Should -Match 'Skipped'
        $script:deployText | Should -Match 'Skipping destructive recreate in update-existing mode'
    }
}

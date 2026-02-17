# Tests/CLIActionRouting.Tests.ps1
# Validates that every CLI action in ValidateSet has a corresponding switch handler
# and that no legacy variable references remain in the orchestrator.

Set-StrictMode -Version Latest

BeforeAll {
    $ScriptPath = Join-Path $PSScriptRoot '..' 'OpenCodeLab-App.ps1'
    $ScriptContent = Get-Content $ScriptPath -Raw
}

Describe 'CLI Action Routing' {
    Context 'ValidateSet and Switch Completeness' {
        It 'Extracts ValidateSet action values from param block' {
            $validateSetMatch = [regex]::Match($ScriptContent, '(?s)\[ValidateSet\((.*?)\)\]\s*\[string\]\$Action')
            $validateSetMatch.Success | Should -Be $true

            $validateSetBlock = $validateSetMatch.Groups[1].Value
            $actions = [regex]::Matches($validateSetBlock, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }

            $actions.Count | Should -BeGreaterThan 20
        }

        It 'Extracts switch case values from action dispatch block' {
            # Extract the entire switch ($Action) block
            $switchPattern = '(?s)switch\s*\(\$Action\)\s*\{(.*?)\n    \}'
            $switchMatch = [regex]::Match($ScriptContent, $switchPattern)
            $switchMatch.Success | Should -Be $true

            $switchBlock = $switchMatch.Groups[1].Value
            # Match all case labels like '        'menu' {'
            $cases = [regex]::Matches($switchBlock, "^\s+'([^']+)'\s*\{", [System.Text.RegularExpressions.RegexOptions]::Multiline) | ForEach-Object { $_.Groups[1].Value }

            $cases.Count | Should -BeGreaterThan 20
        }

        It 'Every ValidateSet action has a matching switch case' {
            # Extract ValidateSet actions
            $validateSetMatch = [regex]::Match($ScriptContent, '(?s)\[ValidateSet\((.*?)\)\]\s*\[string\]\$Action')
            $validateSetBlock = $validateSetMatch.Groups[1].Value
            $validateSetActions = [regex]::Matches($validateSetBlock, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }

            # Extract switch cases
            $switchPattern = '(?s)switch\s*\(\$Action\)\s*\{(.*?)\n    \}'
            $switchMatch = [regex]::Match($ScriptContent, $switchPattern)
            $switchBlock = $switchMatch.Groups[1].Value
            $switchCases = [regex]::Matches($switchBlock, "^\s+'([^']+)'\s*\{", [System.Text.RegularExpressions.RegexOptions]::Multiline) | ForEach-Object { $_.Groups[1].Value }

            # Verify every ValidateSet action has a switch case
            $missing = @()
            foreach ($action in $validateSetActions) {
                if ($action -notin $switchCases) {
                    $missing += $action
                }
            }

            $missing | Should -BeNullOrEmpty -Because "All ValidateSet actions must have switch case handlers. Missing: $($missing -join ', ')"
        }

        It 'No switch case exists without a ValidateSet value' {
            # Extract ValidateSet actions
            $validateSetMatch = [regex]::Match($ScriptContent, '(?s)\[ValidateSet\((.*?)\)\]\s*\[string\]\$Action')
            $validateSetBlock = $validateSetMatch.Groups[1].Value
            $validateSetActions = [regex]::Matches($validateSetBlock, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }

            # Extract switch cases
            $switchPattern = '(?s)switch\s*\(\$Action\)\s*\{(.*?)\n    \}'
            $switchMatch = [regex]::Match($ScriptContent, $switchPattern)
            $switchBlock = $switchMatch.Groups[1].Value
            $switchCases = [regex]::Matches($switchBlock, "^\s+'([^']+)'\s*\{", [System.Text.RegularExpressions.RegexOptions]::Multiline) | ForEach-Object { $_.Groups[1].Value }

            # Verify no orphaned switch cases
            $orphaned = @()
            foreach ($case in $switchCases) {
                if ($case -notin $validateSetActions) {
                    $orphaned += $case
                }
            }

            $orphaned | Should -BeNullOrEmpty -Because "All switch cases must be in ValidateSet. Orphaned: $($orphaned -join ', ')"
        }
    }

    Context 'Legacy Variable References' {
        It 'Invoke-BulkAdditionalVMProvision does not reference $Server_Memory' {
            $bulkProvisionMatch = [regex]::Match($ScriptContent, '(?s)function Invoke-BulkAdditionalVMProvision\s*\{(.*?)\n\}')
            $bulkProvisionMatch.Success | Should -Be $true

            $functionBody = $bulkProvisionMatch.Groups[1].Value
            $functionBody | Should -Not -Match '\$Server_Memory' -Because 'Should use $GlobalLabConfig.VMSizing.Server.Memory'
        }

        It 'Invoke-BulkAdditionalVMProvision does not reference $Client_Memory' {
            $bulkProvisionMatch = [regex]::Match($ScriptContent, '(?s)function Invoke-BulkAdditionalVMProvision\s*\{(.*?)\n\}')
            $functionBody = $bulkProvisionMatch.Groups[1].Value
            $functionBody | Should -Not -Match '\$Client_Memory' -Because 'Should use $GlobalLabConfig.VMSizing.Client.Memory'
        }

        It 'Invoke-BulkAdditionalVMProvision does not reference $Server_Processors' {
            $bulkProvisionMatch = [regex]::Match($ScriptContent, '(?s)function Invoke-BulkAdditionalVMProvision\s*\{(.*?)\n\}')
            $functionBody = $bulkProvisionMatch.Groups[1].Value
            $functionBody | Should -Not -Match '\$Server_Processors' -Because 'Should use $GlobalLabConfig.VMSizing.Server.Processors'
        }

        It 'Invoke-BulkAdditionalVMProvision does not reference $Client_Processors' {
            $bulkProvisionMatch = [regex]::Match($ScriptContent, '(?s)function Invoke-BulkAdditionalVMProvision\s*\{(.*?)\n\}')
            $functionBody = $bulkProvisionMatch.Groups[1].Value
            $functionBody | Should -Not -Match '\$Client_Processors' -Because 'Should use $GlobalLabConfig.VMSizing.Client.Processors'
        }

        It 'No bare $LabName references outside strings and comments' {
            # Remove comments and strings from content
            $codeOnly = $ScriptContent -replace '#.*$', '' -replace '"[^"]*"', '' -replace "'[^']*'", ''

            # Look for bare $LabName references (not $LabName followed by 'd' which would be part of another variable)
            $bareLabName = [regex]::Matches($codeOnly, '\$LabName(?![a-zA-Z0-9_])')
            $bareLabName.Count | Should -Be 0 -Because 'Should use $GlobalLabConfig.Lab.Name instead of legacy $LabName'
        }

        It 'No bare $LabSwitch references outside strings and comments' {
            # Remove comments and strings from content
            $codeOnly = $ScriptContent -replace '#.*$', '' -replace '"[^"]*"', '' -replace "'[^']*'", ''

            # Look for bare $LabSwitch references (not $LabSwitchName)
            $bareLabSwitch = [regex]::Matches($codeOnly, '\$LabSwitch(?![a-zA-Z0-9_])')
            $bareLabSwitch.Count | Should -Be 0 -Because 'Should use $GlobalLabConfig.Network.SwitchName instead of legacy $LabSwitch'
        }

        It 'No bare $AdminPassword references outside strings and comments' {
            # Remove comments and strings from content
            $codeOnly = $ScriptContent -replace '#.*$', '' -replace '"[^"]*"', '' -replace "'[^']*'", ''

            # Look for bare $AdminPassword references
            $bareAdminPassword = [regex]::Matches($codeOnly, '\$AdminPassword(?![a-zA-Z0-9_])')
            $bareAdminPassword.Count | Should -Be 0 -Because 'Should use $GlobalLabConfig.Credentials.AdminPassword instead of legacy $AdminPassword'
        }
    }

    Context 'Quick Mode Functions' {
        It 'Invoke-QuickDeploy function is defined' {
            $ScriptContent | Should -Match 'function Invoke-QuickDeploy' -Because 'Quick mode deploy function must exist'
        }

        It 'Invoke-QuickTeardown function is defined' {
            $ScriptContent | Should -Match 'function Invoke-QuickTeardown' -Because 'Quick mode teardown function must exist'
        }

        It 'Invoke-QuickDeploy calls Start-LabDay' {
            $quickDeployMatch = [regex]::Match($ScriptContent, '(?s)function Invoke-QuickDeploy\s*\{(.*?)\n\}')
            $quickDeployMatch.Success | Should -Be $true

            $functionBody = $quickDeployMatch.Groups[1].Value
            $functionBody | Should -Match "Start-LabDay|Invoke-RepoScript.*Start-LabDay" -Because 'Quick deploy should start lab VMs'
        }
    }
}

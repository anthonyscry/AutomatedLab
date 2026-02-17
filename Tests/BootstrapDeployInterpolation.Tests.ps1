# BootstrapDeployInterpolation.Tests.ps1 - validates string interpolation and legacy variable usage

Describe 'String Interpolation Validation' {
    BeforeAll {
        $RepoRoot = Split-Path -Parent $PSScriptRoot
        $DeployPath = Join-Path $RepoRoot 'Deploy.ps1'
        $BootstrapPath = Join-Path $RepoRoot 'Bootstrap.ps1'
    }

    Context 'Deploy.ps1' {
        It 'should parse without syntax errors' {
            { [scriptblock]::Create((Get-Content $DeployPath -Raw)) } | Should -Not -Throw
        }

        It 'should have valid parameter names (no dotted paths)' {
            $content = Get-Content $DeployPath -Raw
            $paramBlockMatch = [regex]::Match($content, '(?s)param\s*\((.*?)\)')
            if ($paramBlockMatch.Success) {
                $paramBlock = $paramBlockMatch.Groups[1].Value
                # Check for invalid parameter names with dots
                $paramBlock | Should -Not -Match '\$GlobalLabConfig\.'
            }
        }

        It 'should not have bare $GlobalLabConfig.X.Y in double-quoted strings' {
            $content = Get-Content $DeployPath -Raw
            # Pattern: "$GlobalLabConfig.X.Y" without $() wrapper
            # Allow $($GlobalLabConfig.X.Y) but reject bare $GlobalLabConfig.X.Y
            $bareInterpolations = Select-String -Path $DeployPath -Pattern '"[^"]*\$GlobalLabConfig\.\w+\.\w+[^)]' -AllMatches

            # Filter out false positives (already wrapped in subexpressions)
            $realIssues = $bareInterpolations | Where-Object {
                $line = $_.Line
                # Skip if it's already wrapped: $($GlobalLabConfig...)
                $line -notmatch '\$\(\$GlobalLabConfig\.'
            }

            if ($realIssues) {
                $issueLines = $realIssues | ForEach-Object { "Line $($_.LineNumber): $($_.Line.Trim())" }
                $issueLines | Should -BeNullOrEmpty -Because "Found bare interpolations: `n$($issueLines -join "`n")"
            }
        }

        It 'should not reference legacy variables (Server1_Ip, WSUS_Memory)' {
            $legacyVars = Select-String -Path $DeployPath -Pattern 'Get-Variable -Name (Server1_Ip|Server_Memory|Server_MinMemory|Server_MaxMemory|Server_Processors|WSUS_Memory|WSUS_MinMemory|WSUS_MaxMemory|WSUS_Processors)'
            $legacyVars | Should -BeNullOrEmpty -Because "Legacy variable fallbacks should be removed"
        }

        It 'should use $GlobalLabConfig for Git installer values' {
            $content = Get-Content $DeployPath -Raw
            # Should not have hardcoded Git URLs/hashes
            $content | Should -Not -Match 'https://github\.com/git-for-windows/git/releases/download/v\d+\.\d+\.\d+\.windows\.\d+/Git-'
            # Should reference GlobalLabConfig
            $content | Should -Match '\$GlobalLabConfig\.SoftwarePackages\.Git\.(Url|Sha256|LocalPath)'
        }
    }

    Context 'Bootstrap.ps1' {
        It 'should parse without syntax errors' {
            { [scriptblock]::Create((Get-Content $BootstrapPath -Raw)) } | Should -Not -Throw
        }

        It 'should not reference legacy variable names ($LabSwitch, $LabName, $LabSourcesRoot)' {
            $legacyVarReferences = Select-String -Path $BootstrapPath -Pattern '\$LabSwitch(?!\.)|Get-Variable -Name (LabSwitch|LabName|LabSourcesRoot|GatewayIp|NatName|AddressSpace|RequiredISOs)'

            # Filter out comments
            $realReferences = $legacyVarReferences | Where-Object {
                $_.Line -notmatch '^\s*#'
            }

            if ($realReferences) {
                $issueLines = $realReferences | ForEach-Object { "Line $($_.LineNumber): $($_.Line.Trim())" }
                $issueLines | Should -BeNullOrEmpty -Because "Found legacy variable references: `n$($issueLines -join "`n")"
            }
        }

        It 'should not have bare $GlobalLabConfig.X.Y in double-quoted strings' {
            $bareInterpolations = Select-String -Path $BootstrapPath -Pattern '"[^"]*\$GlobalLabConfig\.\w+\.\w+[^)]' -AllMatches

            # Filter out false positives (already wrapped in subexpressions)
            $realIssues = $bareInterpolations | Where-Object {
                $line = $_.Line
                # Skip if it's already wrapped: $($GlobalLabConfig...)
                $line -notmatch '\$\(\$GlobalLabConfig\.'
            }

            if ($realIssues) {
                $issueLines = $realIssues | ForEach-Object { "Line $($_.LineNumber): $($_.Line.Trim())" }
                $issueLines | Should -BeNullOrEmpty -Because "Found bare interpolations: `n$($issueLines -join "`n")"
            }
        }
    }

    Context 'Test-OpenCodeLabPreflight.ps1' {
        BeforeAll {
            $PreflightPath = Join-Path $RepoRoot 'Scripts\Test-OpenCodeLabPreflight.ps1'
        }

        It 'should not reference legacy variable fallbacks' {
            $legacyVars = Select-String -Path $PreflightPath -Pattern 'Get-Variable -Name (LabSourcesRoot|LabSwitch|NatName|AddressSpace|RequiredISOs)'
            $legacyVars | Should -BeNullOrEmpty -Because "Legacy variable fallbacks should be removed"
        }

        It 'should use $GlobalLabConfig exclusively' {
            $content = Get-Content $PreflightPath -Raw
            # Verify it uses GlobalLabConfig (should have multiple references)
            $content | Should -Match '\$GlobalLabConfig\.'
        }
    }

    Context 'Test-OpenCodeLabHealth.ps1' {
        BeforeAll {
            $HealthPath = Join-Path $RepoRoot 'Scripts\Test-OpenCodeLabHealth.ps1'
        }

        It 'should not reference legacy variable fallbacks' {
            $legacyVars = Select-String -Path $HealthPath -Pattern 'Get-Variable -Name (LabName|LabVMs|LinuxUser|LabSourcesRoot|DomainName|LIN1_Ip)'
            $legacyVars | Should -BeNullOrEmpty -Because "Legacy variable fallbacks should be removed"
        }

        It 'should use $GlobalLabConfig exclusively' {
            $content = Get-Content $HealthPath -Raw
            # Verify it uses GlobalLabConfig (should have multiple references)
            $content | Should -Match '\$GlobalLabConfig\.'
        }
    }
}

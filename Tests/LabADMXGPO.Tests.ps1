# Invoke-LabADMXImport GPO creation tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Invoke-LabADMXImport.ps1')
    . (Join-Path $repoRoot 'Private/Get-LabADMXConfig.ps1')
    . (Join-Path $repoRoot 'Private/ConvertTo-DomainDN.ps1')

    # Create script-level variable for call counting
    $script:MockCallCount = 0
}

Describe 'Invoke-LabADMXImport - GPO Creation' {
    BeforeEach {
        # Reset call counter
        $script:MockCallCount = 0

        # Default mocks - must be defined before each test
        Mock Get-LabADMXConfig {
            return @{
                Enabled            = $true
                CreateBaselineGPO  = $false
                ThirdPartyADMX     = @()
            }
        }

        Mock Invoke-Command {
            return 10
        }

        Mock Test-Path { return $true }
        Mock New-Item {}
        Mock Get-ChildItem { return @() }
        Mock Copy-Item {}
        Mock Join-Path {
            # This mock prevents Join-Path from being called on problematic UNC paths
            # Just return the second argument as-is for testing
            if ($args.Count -ge 2) {
                return $args[1]
            }
            return $args[0]
        }

        # Mock GroupPolicy cmdlets (stub as global functions for Pester 5 on non-Windows)
        function New-GPO { param([string]$Name) }
        function Set-GPRegistryValue { param([string]$Name, [string]$Key, [string]$ValueName, $Value, [string]$Type) }
        function New-GPLink { param([string]$Name, [string]$Target) }

        Mock New-GPO {}
        Mock Set-GPRegistryValue {}
        Mock New-GPLink {}
        Mock ConvertTo-DomainDN { return 'DC=simplelab,DC=local' }
    }

    It 'does not create GPOs when CreateBaselineGPO is false' {
        Mock Get-LabADMXConfig {
            return @{
                Enabled            = $true
                CreateBaselineGPO  = $false
                ThirdPartyADMX     = @()
            }
        }

        $result = Invoke-LabADMXImport -DCName 'DC01' -DomainName 'simplelab.local'

        $result.Success | Should -BeTrue
        Should -Invoke New-GPO -Times 0 -Exactly
    }

    It 'creates GPOs when CreateBaselineGPO is true' {
        Mock Get-LabADMXConfig {
            return @{
                Enabled            = $true
                CreateBaselineGPO  = $true
                ThirdPartyADMX     = @()
            }
        }

        Mock Get-ChildItem {
            return @(
                [pscustomobject]@{ Name = 'password-policy.json'; FullName = '/Templates/GPO/password-policy.json' }
                [pscustomobject]@{ Name = 'account-lockout.json'; FullName = '/Templates/GPO/account-lockout.json' }
                [pscustomobject]@{ Name = 'audit-policy.json'; FullName = '/Templates/GPO/audit-policy.json' }
                [pscustomobject]@{ Name = 'applocker.json'; FullName = '/Templates/GPO/applocker.json' }
            )
        }

        # Mock template content
        Mock Get-Content {
            return '{"Name":"Test GPO","LinkTarget":"DC=simplelab,DC=local","Settings":[]}'
        }

        $result = Invoke-LabADMXImport -DCName 'DC01' -DomainName 'simplelab.local'

        $result.Success | Should -BeTrue
        Should -Invoke New-GPO -Times 4 -Exactly
        Should -Invoke New-GPLink -Times 4 -Exactly
    }

    It 'applies all registry settings from template' {
        Mock Get-LabADMXConfig {
            return @{
                Enabled            = $true
                CreateBaselineGPO  = $true
                ThirdPartyADMX     = @()
            }
        }

        Mock Get-ChildItem {
            return @(
                [pscustomobject]@{ Name = 'password-policy.json'; FullName = '/Templates/GPO/password-policy.json' }
            )
        }

        # Template with 3 settings
        Mock Get-Content {
            return '{
                "Name":"Test GPO",
                "LinkTarget":"DC=simplelab,DC=local",
                "Settings":[
                    {"Key":"HKLM\\Software\\Test","ValueName":"Setting1","Value":1,"Type":"DWord"},
                    {"Key":"HKLM\\Software\\Test","ValueName":"Setting2","Value":2,"Type":"DWord"},
                    {"Key":"HKLM\\Software\\Test","ValueName":"Setting3","Value":3,"Type":"DWord"}
                ]
            }'
        }

        $result = Invoke-LabADMXImport -DCName 'DC01' -DomainName 'simplelab.local'

        $result.Success | Should -BeTrue
        Should -Invoke Set-GPRegistryValue -Times 3 -Exactly
    }

    It 'links GPO to domain root DN' {
        Mock Get-LabADMXConfig {
            return @{
                Enabled            = $true
                CreateBaselineGPO  = $true
                ThirdPartyADMX     = @()
            }
        }

        Mock Get-ChildItem {
            return @(
                [pscustomobject]@{ Name = 'test-gpo.json'; FullName = '/Templates/GPO/test-gpo.json' }
            )
        }

        Mock Get-Content {
            return '{"Name":"Test GPO","LinkTarget":"DC=test,DC=local","Settings":[]}'
        }

        Mock New-GPLink {
            # Capture the Target parameter
            $script:GpoLinkTarget = $Target
        }

        $result = Invoke-LabADMXImport -DCName 'DC01' -DomainName 'simplelab.local'

        $result.Success | Should -BeTrue
        $script:GpoLinkTarget | Should -Be 'DC=test,DC=local'
    }

    It 'continues processing after one GPO creation fails' {
        Mock Get-LabADMXConfig {
            return @{
                Enabled            = $true
                CreateBaselineGPO  = $true
                ThirdPartyADMX     = @()
            }
        }

        $script:MockCallCount = 0
        Mock Get-ChildItem {
            $script:MockCallCount++
            if ($script:MockCallCount -eq 1) {
                # First call returns 2 templates
                return @(
                    [pscustomobject]@{ Name = 'fail-gpo.json'; FullName = '/Templates/GPO/fail-gpo.json' }
                    [pscustomobject]@{ Name = 'success-gpo.json'; FullName = '/Templates/GPO/success-gpo.json' }
                )
            }
            return @()
        }

        # First template fails, second succeeds
        $script:GetContentCallCount = 0
        Mock Get-Content {
            $script:GetContentCallCount++
            if ($script:GetContentCallCount -eq 1) {
                return '{"Name":"Fail GPO","LinkTarget":"DC=test,DC=local","Settings":[]}'
            } else {
                return '{"Name":"Success GPO","LinkTarget":"DC=test,DC=local","Settings":[]}'
            }
        }

        # First New-GPO call throws
        Mock New-GPO {
            $script:GpoCallCount = if (Test-Path variable:script:GpoCallCount) { $script:GpoCallCount + 1 } else { 1 }
            if ($script:GpoCallCount -eq 1) {
                throw 'GPO creation failed'
            }
        }

        $result = Invoke-LabADMXImport -DCName 'DC01' -DomainName 'simplelab.local'

        $result.Success | Should -BeTrue
        $script:GpoCallCount | Should -Be 2
    }

    It 'skips GPO creation when template directory not found' {
        Mock Get-LabADMXConfig {
            return @{
                Enabled            = $true
                CreateBaselineGPO  = $true
                ThirdPartyADMX     = @()
            }
        }

        Mock Test-Path {
            if ($args[0] -like '*Templates*GPO*') {
                return $false
            }
            return $true
        }

        $result = Invoke-LabADMXImport -DCName 'DC01' -DomainName 'simplelab.local'

        $result.Success | Should -BeTrue
        Should -Invoke New-GPO -Times 0 -Exactly
    }

    It 'uses default domain DN when template LinkTarget is empty' {
        Mock Get-LabADMXConfig {
            return @{
                Enabled            = $true
                CreateBaselineGPO  = $true
                ThirdPartyADMX     = @()
            }
        }

        Mock Get-ChildItem {
            return @(
                [pscustomobject]@{ Name = 'test-gpo.json'; FullName = '/Templates/GPO/test-gpo.json' }
            )
        }

        # Template with null LinkTarget
        Mock Get-Content {
            return '{"Name":"Test GPO","LinkTarget":null,"Settings":[]}'
        }

        Mock ConvertTo-DomainDN { return 'DC=default,DC=local' }

        Mock New-GPLink {
            $script:GpoLinkTarget = $Target
        }

        $result = Invoke-LabADMXImport -DCName 'DC01' -DomainName 'simplelab.local'

        $result.Success | Should -BeTrue
        $script:GpoLinkTarget | Should -Be 'DC=default,DC=local'
        Should -Invoke ConvertTo-DomainDN -Times 1 -Exactly
    }

    It 'counts GPOs in FilesImported metric' {
        Mock Get-LabADMXConfig {
            return @{
                Enabled            = $true
                CreateBaselineGPO  = $true
                ThirdPartyADMX     = @()
            }
        }

        Mock Get-ChildItem {
            return @(
                [pscustomobject]@{ Name = 'gpo1.json'; FullName = '/Templates/GPO/gpo1.json' }
                [pscustomobject]@{ Name = 'gpo2.json'; FullName = '/Templates/GPO/gpo2.json' }
            )
        }

        Mock Get-Content {
            return '{"Name":"Test GPO","LinkTarget":"DC=test,DC=local","Settings":[]}'
        }

        Mock Invoke-Command {
            return 100  # Simulate 100 ADMX files from OS
        }

        $result = Invoke-LabADMXImport -DCName 'DC01' -DomainName 'simplelab.local'

        $result.FilesImported | Should -Be 102  # 100 from OS + 2 GPOs
        $result.Success | Should -BeTrue
    }
}

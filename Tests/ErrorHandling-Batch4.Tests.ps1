# ErrorHandling-Batch4.Tests.ps1
# Verifies that all 6 Public functions missing try-catch have been updated (ERR-02, ERR-03)

BeforeDiscovery {
    $repoRoot  = Split-Path -Parent $PSScriptRoot
    $publicPath = Join-Path $repoRoot 'Public'

    # The 3 infrastructure Public functions (terminating errors)
    $InfrastructureFunctions = @(
        @{ Name = 'Initialize-LabNetwork'; File = (Join-Path $publicPath 'Initialize-LabNetwork.ps1'); Context = 'failed to configure lab network';   CatchVerb = 'throw' }
        @{ Name = 'New-LabNAT';            File = (Join-Path $publicPath 'New-LabNAT.ps1');            Context = 'failed to create NAT configuration'; CatchVerb = 'throw' }
        @{ Name = 'New-LabSSHKey';         File = (Join-Path $publicPath 'New-LabSSHKey.ps1');         Context = 'failed to generate SSH key pair';     CatchVerb = 'throw' }
    )

    # The 3 display Public functions (mixed terminating / non-terminating)
    $DisplayFunctions = @(
        @{ Name = 'Show-LabStatus';        File = (Join-Path $publicPath 'Show-LabStatus.ps1');        Context = 'failed to display lab status';        CatchVerb = 'throw' }
        @{ Name = 'Test-LabNetworkHealth'; File = (Join-Path $publicPath 'Test-LabNetworkHealth.ps1'); Context = 'failed to run network health check';  CatchVerb = 'throw' }
        @{ Name = 'Write-LabStatus';       File = (Join-Path $publicPath 'Write-LabStatus.ps1');       Context = 'failed to write status message';      CatchVerb = 'Write-Warning' }
    )

    # Combined list for use in parameterized tests
    $AllPublicFunctions = $InfrastructureFunctions + $DisplayFunctions
}

Describe "ERR-02: All 6 Public functions have try-catch" {
    It "<Name> contains a try block" -TestCases $AllPublicFunctions {
        param($Name, $File, $Context, $CatchVerb)
        $content = Get-Content $File -Raw
        $content | Should -Match '\btry\b' -Because "$Name must wrap its body in try-catch"
    }

    It "<Name> contains a catch block" -TestCases $AllPublicFunctions {
        param($Name, $File, $Context, $CatchVerb)
        $content = Get-Content $File -Raw
        $content | Should -Match '\bcatch\b' -Because "$Name must have a catch handler"
    }

    It "<Name> catch block uses <CatchVerb> (correct error escalation policy)" -TestCases $AllPublicFunctions {
        param($Name, $File, $Context, $CatchVerb)
        $content = Get-Content $File -Raw
        $content | Should -Match "\b$([regex]::Escape($CatchVerb))\b" -Because "$Name must use $CatchVerb per its error handling policy"
    }
}

Describe "ERR-03: Error messages include function name prefix for grep-ability" {
    It "<Name> error message contains the function name" -TestCases $AllPublicFunctions {
        param($Name, $File, $Context, $CatchVerb)
        $content = Get-Content $File -Raw
        $content | Should -Match ([regex]::Escape($Name)) -Because "catch messages must be prefixed with the function name for log grep-ability"
    }

    It "<Name> error message contains the actionable context string" -TestCases $AllPublicFunctions {
        param($Name, $File, $Context, $CatchVerb)
        $content = Get-Content $File -Raw
        $content | Should -Match ([regex]::Escape($Context)) -Because "catch block must include context describing what operation failed"
    }
}

Describe "ERR-02: Infrastructure functions use terminating throw" {
    It "Initialize-LabNetwork uses throw in catch (infrastructure must halt)" {
        $filePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Public/Initialize-LabNetwork.ps1'
        $content = Get-Content $filePath -Raw
        $content | Should -Match '\bthrow\b' -Because "infrastructure functions must throw to halt pipeline on failure"
    }

    It "New-LabNAT uses throw in catch (infrastructure must halt)" {
        $filePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Public/New-LabNAT.ps1'
        $content = Get-Content $filePath -Raw
        $content | Should -Match '\bthrow\b' -Because "infrastructure functions must throw to halt pipeline on failure"
    }

    It "New-LabSSHKey uses throw in catch (infrastructure must halt)" {
        $filePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Public/New-LabSSHKey.ps1'
        $content = Get-Content $filePath -Raw
        $content | Should -Match '\bthrow\b' -Because "infrastructure functions must throw to halt pipeline on failure"
    }
}

Describe "ERR-02: Write-LabStatus uses non-terminating Write-Warning (console helper should not crash callers)" {
    It "Write-LabStatus uses Write-Warning in catch (non-terminating)" {
        $filePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Public/Write-LabStatus.ps1'
        $content = Get-Content $filePath -Raw
        $content | Should -Match '\bWrite-Warning\b' -Because "console output helpers must not crash callers on failure"
    }

    It "Write-LabStatus does not use throw in catch" {
        $filePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Public/Write-LabStatus.ps1'
        $content = Get-Content $filePath -Raw
        # The catch block should use Write-Warning, not throw
        # Check that the catch section contains Write-Warning (not throw)
        $catchBlock = [regex]::Match($content, '(?s)catch\s*\{[^}]+\}')
        $catchBlock.Value | Should -Match '\bWrite-Warning\b' -Because "Write-LabStatus catch must use Write-Warning, not throw"
    }
}

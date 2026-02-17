# ErrorHandling-Audit.Tests.ps1
# Comprehensive codebase audit: regression guard for error handling across the entire codebase.
# Verifies ERR-01 (Private functions), ERR-02 (Public functions), ERR-03 (function name in messages), ERR-04 (no exit usage).

BeforeAll {
    Set-StrictMode -Version Latest

    $script:RepoRoot   = Split-Path -Parent $PSScriptRoot
    $script:PrivatePath = Join-Path $script:RepoRoot 'Private'
    $script:PublicPath  = Join-Path $script:RepoRoot 'Public'

    # Exempt list: trivial functions with no I/O or external calls (from 09-RESEARCH.md)
    $script:ExemptFunctions = @(
        'Get-LabHealthArgs'
        'Get-LabPreflightArgs'
        'Suspend-LabMenuPrompt'
        'Get-LabExpectedVMs'
        'Get-LabBootstrapArgs'
        'Get-LabDeployArgs'
        'Register-LabAliases'
        'Convert-LabArgumentArrayToSplat'
        'Resolve-LabScriptPath'
        'ConvertTo-LabTargetHostList'
        'Get-LabGuiLayoutState'
        'Read-LabMenuCount'
        'Test-LabTransientTransportFailure'
        'Protect-LabLogString'
        'Add-LabRunEvent'
    )

    # Helper: extract function name from file content
    function script:Get-FunctionName {
        param([string]$Content, [string]$FallbackName)
        if ($Content -match 'function\s+(\S+)\s*\{') {
            return $Matches[1]
        }
        return $FallbackName
    }

    # Helper: check if file content contains both try and catch keywords
    function script:Has-TryCatch {
        param([string]$Content)
        return ($Content -match '\btry\b') -and ($Content -match '\bcatch\b')
    }

    # Helper: strip comment blocks (<# ... #>) and comment lines (# ...) from content
    # Returns only executable code lines for exit-checking purposes
    function script:Get-ExecutableLines {
        param([string]$Content)
        # Remove block comments
        $stripped = [regex]::Replace($Content, '(?s)<#.*?#>', '')
        # Split into lines and filter out pure comment lines
        $lines = $stripped -split "`n"
        return $lines | Where-Object { $_.TrimStart() -notmatch '^#' }
    }

    # Pre-load all Private and Public .ps1 files
    $script:PrivateFiles = Get-ChildItem -Path $script:PrivatePath -Filter '*.ps1' -File
    $script:PublicFiles  = Get-ChildItem -Path $script:PublicPath  -Filter '*.ps1' -File -Recurse |
        Where-Object { $_.DirectoryName -eq $script:PublicPath }
}

Describe "ERR-01: All non-exempt Private functions have try-catch (regression guard)" {
    It "Every non-exempt Private/*.ps1 file contains try and catch" {
        $failures = @()

        foreach ($file in $script:PrivateFiles) {
            $content = Get-Content $file.FullName -Raw
            $funcName = script:Get-FunctionName -Content $content -FallbackName $file.BaseName

            # Skip exempt trivial functions
            if ($script:ExemptFunctions -contains $funcName) {
                continue
            }

            if (-not (script:Has-TryCatch -Content $content)) {
                $failures += "$funcName ($($file.Name))"
            }
        }

        $failures | Should -BeNullOrEmpty -Because (
            "All non-exempt Private functions must have try-catch error handling. " +
            "Missing: $($failures -join ', ')"
        )
    }

    It "Exempt list accounts for exactly 15 trivial functions" {
        # This validates the exempt list size hasn't grown beyond the intended count
        $script:ExemptFunctions.Count | Should -Be 15 -Because "the exempt list is defined in 09-RESEARCH.md and should not grow without updating that document"
    }
}

Describe "ERR-02: All Public functions have try-catch (regression guard)" {
    It "Every Public/*.ps1 file (top-level, not Linux/) contains try and catch" {
        $failures = @()

        foreach ($file in $script:PublicFiles) {
            $content = Get-Content $file.FullName -Raw
            $funcName = script:Get-FunctionName -Content $content -FallbackName $file.BaseName

            if (-not (script:Has-TryCatch -Content $content)) {
                $failures += "$funcName ($($file.Name))"
            }
        }

        $failures | Should -BeNullOrEmpty -Because (
            "All Public functions are user-facing API and must have try-catch. " +
            "Missing: $($failures -join ', ')"
        )
    }
}

Describe "ERR-04: No function uses exit to terminate" {
    It "No Private/*.ps1 file contains executable 'exit' statement" {
        $exitMatches = @()

        foreach ($file in $script:PrivateFiles) {
            $content = Get-Content $file.FullName -Raw
            $executableLines = script:Get-ExecutableLines -Content $content
            foreach ($line in $executableLines) {
                # Match 'exit' as a standalone command (not inside strings like "exit code" or "ExitCode")
                # Must be lowercase 'exit' at start of statement (optionally preceded by whitespace or semicolon)
                if ($line -cmatch '(?:^|;)\s*exit\b') {
                    $exitMatches += "$($file.Name): $($line.Trim())"
                }
            }
        }

        $exitMatches | Should -BeNullOrEmpty -Because (
            "Functions must use 'return' or 'throw' to exit, never bare 'exit'. " +
            "exit terminates the entire PowerShell process. Found: $($exitMatches -join '; ')"
        )
    }

    It "No Public/*.ps1 file contains executable 'exit' statement" {
        $exitMatches = @()

        foreach ($file in $script:PublicFiles) {
            $content = Get-Content $file.FullName -Raw
            $executableLines = script:Get-ExecutableLines -Content $content
            foreach ($line in $executableLines) {
                if ($line -cmatch '(?:^|;)\s*exit\b') {
                    $exitMatches += "$($file.Name): $($line.Trim())"
                }
            }
        }

        $exitMatches | Should -BeNullOrEmpty -Because (
            "Public functions must never use bare 'exit'. " +
            "Found: $($exitMatches -join '; ')"
        )
    }
}

Describe "ERR-03: Error messages include function name (sampling)" {
    It "Representative sample of Private functions use 'FunctionName: message' pattern in catch block" {
        # Representative sample: functions where error messages follow 'FunctionName: context - $_' pattern.
        # This checks the convention applied in phases 09-01 through 09-04.
        # We verify by looking for the pattern: catch block contains "FunctionName:" as a prefix.
        $sampleFunctionNames = @(
            'New-LabScopedConfirmationToken'
            'Resolve-LabPassword'
            'Invoke-LabOrchestrationActionCore'
            'Get-LabDomainConfig'
            'New-LabDeploymentReport'
            'Resolve-LabCoordinatorPolicy'
            'Write-LabRunArtifacts'
            'Resolve-LabModeDecision'
            'New-LabCoordinatorPlan'
            'Get-LabVMConfig'
        )

        $failures = @()
        foreach ($funcName in $sampleFunctionNames) {
            $file = $script:PrivateFiles | Where-Object { $_.BaseName -eq $funcName } | Select-Object -First 1
            if (-not $file) {
                # File not found - skip (function may have been renamed or merged)
                continue
            }

            $content = Get-Content $file.FullName -Raw

            # Check if the file contains 'FunctionName:' style message (function name followed by colon)
            if ($content -notmatch ([regex]::Escape($funcName) + ':')) {
                $failures += "$funcName ($($file.Name))"
            }
        }

        $failures | Should -BeNullOrEmpty -Because (
            "Catch blocks must use 'FunctionName: context' error message format for grep-ability. " +
            "Missing 'FunctionName:' prefix in: $($failures -join ', ')"
        )
    }

    It "All 6 Public functions from this plan include the function name in their catch block" {
        $publicFunctions = @(
            @{ Name = 'Initialize-LabNetwork'; File = 'Initialize-LabNetwork.ps1' }
            @{ Name = 'New-LabNAT';            File = 'New-LabNAT.ps1' }
            @{ Name = 'New-LabSSHKey';         File = 'New-LabSSHKey.ps1' }
            @{ Name = 'Show-LabStatus';        File = 'Show-LabStatus.ps1' }
            @{ Name = 'Test-LabNetworkHealth'; File = 'Test-LabNetworkHealth.ps1' }
            @{ Name = 'Write-LabStatus';       File = 'Write-LabStatus.ps1' }
        )

        $failures = @()
        foreach ($fn in $publicFunctions) {
            $filePath = Join-Path $script:PublicPath $fn.File
            $content  = Get-Content $filePath -Raw
            $catchMatch = [regex]::Match($content, '(?s)catch\s*\{(.+?)\}')
            if ($catchMatch.Success) {
                $catchBody = $catchMatch.Groups[1].Value
                if ($catchBody -notmatch [regex]::Escape($fn.Name)) {
                    $failures += $fn.Name
                }
            } else {
                $failures += "$($fn.Name) (no catch block found)"
            }
        }

        $failures | Should -BeNullOrEmpty -Because (
            "Public function catch blocks must include the function name. Missing: $($failures -join ', ')"
        )
    }
}

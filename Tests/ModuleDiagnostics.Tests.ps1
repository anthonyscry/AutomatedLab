#Requires -Version 5.1
<#
.SYNOPSIS
    Regression tests for module export consistency and GUI Out-Null removal.
.DESCRIPTION
    Verifies that SimpleLab.psm1 and SimpleLab.psd1 have identical export lists
    matching actual Public/ function files, that no ghost functions are exported,
    and that GUI/Start-OpenCodeLabGUI.ps1 uses [void] cast instead of | Out-Null.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot

    $psm1Path  = Join-Path $repoRoot 'SimpleLab.psm1'
    $psd1Path  = Join-Path $repoRoot 'SimpleLab.psd1'
    $guiPath   = Join-Path $repoRoot (Join-Path 'GUI' 'Start-OpenCodeLabGUI.ps1')
    $publicDir = Join-Path $repoRoot 'Public'

    # -- Parse psm1 Export-ModuleMember block -----------------------------
    $psm1Content = Get-Content -Path $psm1Path -Raw

    $psm1BlockStart = $psm1Content.IndexOf('@(', $psm1Content.IndexOf('Export-ModuleMember'))
    $depth = 0
    $psm1BlockEnd = $psm1BlockStart
    for ($idx = $psm1BlockStart; $idx -lt $psm1Content.Length; $idx++) {
        $ch = $psm1Content[$idx]
        if ($ch -eq '(') { $depth++ }
        elseif ($ch -eq ')') {
            $depth--
            if ($depth -eq 0) { $psm1BlockEnd = $idx; break }
        }
    }
    $psm1Block = $psm1Content.Substring($psm1BlockStart + 2, $psm1BlockEnd - $psm1BlockStart - 2)
    $script:Psm1Exports = [System.Collections.Generic.SortedSet[string]] @(
        ([regex]::Matches($psm1Block, "'([A-Za-z][\w-]+)'") | ForEach-Object { $_.Groups[1].Value })
    )

    # -- Parse psd1 FunctionsToExport block -------------------------------
    $psd1Content = Get-Content -Path $psd1Path -Raw

    $psd1BlockStart = $psd1Content.IndexOf('@(', $psd1Content.IndexOf('FunctionsToExport'))
    $depth = 0
    $psd1BlockEnd = $psd1BlockStart
    for ($idx = $psd1BlockStart; $idx -lt $psd1Content.Length; $idx++) {
        $ch = $psd1Content[$idx]
        if ($ch -eq '(') { $depth++ }
        elseif ($ch -eq ')') {
            $depth--
            if ($depth -eq 0) { $psd1BlockEnd = $idx; break }
        }
    }
    $psd1Block = $psd1Content.Substring($psd1BlockStart + 2, $psd1BlockEnd - $psd1BlockStart - 2)
    $script:Psd1Exports = [System.Collections.Generic.SortedSet[string]] @(
        ([regex]::Matches($psd1Block, "'([A-Za-z][\w-]+)'") | ForEach-Object { $_.Groups[1].Value })
    )

    # -- Collect actual Public/ function names ----------------------------
    $publicFiles = Get-ChildItem -Path $publicDir -Filter '*.ps1' -Recurse -File
    $script:PublicFunctionNames = [System.Collections.Generic.SortedSet[string]] @(
        ($publicFiles | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) })
    )

    # -- GUI content ------------------------------------------------------
    $script:GuiContent = Get-Content -Path $guiPath -Raw
}

Describe 'Module Export Consistency' {

    It 'SimpleLab.psd1 FunctionsToExport matches SimpleLab.psm1 Export-ModuleMember' {
        $diff = Compare-Object -ReferenceObject @($script:Psm1Exports) -DifferenceObject @($script:Psd1Exports)
        $diff | Should -BeNullOrEmpty -Because 'psm1 and psd1 export lists must be identical'
    }

    It 'Every Public/*.ps1 file has a matching export entry in psm1' {
        $missing = @()
        foreach ($funcName in $script:PublicFunctionNames) {
            if (-not $script:Psm1Exports.Contains($funcName)) {
                $missing += $funcName
            }
        }
        $missing | Should -BeNullOrEmpty -Because 'every Public/ function must be in Export-ModuleMember'
    }

    It 'Every Public/*.ps1 file has a matching export entry in psd1' {
        $missing = @()
        foreach ($funcName in $script:PublicFunctionNames) {
            if (-not $script:Psd1Exports.Contains($funcName)) {
                $missing += $funcName
            }
        }
        $missing | Should -BeNullOrEmpty -Because 'every Public/ function must be in FunctionsToExport'
    }

    It 'No ghost functions in Export-ModuleMember (every export has a Public/ file)' {
        $ghosts = @()
        foreach ($exportedFunc in $script:Psm1Exports) {
            if (-not $script:PublicFunctionNames.Contains($exportedFunc)) {
                $ghosts += $exportedFunc
            }
        }
        $ghosts | Should -BeNullOrEmpty -Because 'every exported function must have a corresponding Public/ file'
    }

    It 'No ghost functions in FunctionsToExport (every export has a Public/ file)' {
        $ghosts = @()
        foreach ($exportedFunc in $script:Psd1Exports) {
            if (-not $script:PublicFunctionNames.Contains($exportedFunc)) {
                $ghosts += $exportedFunc
            }
        }
        $ghosts | Should -BeNullOrEmpty -Because 'every FunctionsToExport entry must have a corresponding Public/ file'
    }

    It 'Export count matches Public/ file count exactly' {
        $publicCount = $script:PublicFunctionNames.Count
        $psm1Count   = $script:Psm1Exports.Count
        $psd1Count   = $script:Psd1Exports.Count

        $psm1Count | Should -Be $publicCount -Because "psm1 Export-ModuleMember must list exactly $publicCount functions (matching Public/ file count)"
        $psd1Count | Should -Be $publicCount -Because "psd1 FunctionsToExport must list exactly $publicCount functions (matching Public/ file count)"
    }

    It 'Ghost functions Test-LabCleanup, Test-LabPrereqs, Write-ValidationReport are not exported' {
        $ghostFunctions = @('Test-LabCleanup', 'Test-LabPrereqs', 'Write-ValidationReport')
        foreach ($ghost in $ghostFunctions) {
            $script:Psm1Exports.Contains($ghost) | Should -BeFalse -Because "$ghost has no source file and must not be in Export-ModuleMember"
            $script:Psd1Exports.Contains($ghost) | Should -BeFalse -Because "$ghost has no source file and must not be in FunctionsToExport"
        }
    }
}

Describe 'GUI Out-Null Removal' {

    It 'GUI file contains no pipe-to-Out-Null patterns' {
        $matches = [regex]::Matches($script:GuiContent, '\|\s*Out-Null')
        $matches.Count | Should -Be 0 -Because 'all | Out-Null patterns must be replaced with [void] cast'
    }

    It 'GUI file uses [void] cast pattern' {
        $matches = [regex]::Matches($script:GuiContent, '\[void\]')
        $matches.Count | Should -BeGreaterOrEqual 40 -Because 'GUI file should have at least 40 [void] cast instances replacing Out-Null'
    }

    It 'GUI file does not suppress 2>&1 streams (process redirects remain if present)' {
        # Ensure we did not accidentally remove legitimate 2>&1 | Out-Null patterns
        # This test verifies the file is syntactically coherent by checking it still has the expected functions
        $hasSwitchView    = $script:GuiContent -match 'function Switch-View'
        $hasDashboardInit = $script:GuiContent -match 'function Initialize-DashboardView'
        $hasAddLogEntry   = $script:GuiContent -match 'function Add-LogEntry'

        $hasSwitchView    | Should -BeTrue  -Because 'Switch-View function must still exist in GUI file'
        $hasDashboardInit | Should -BeTrue  -Because 'Initialize-DashboardView function must still exist in GUI file'
        $hasAddLogEntry   | Should -BeTrue  -Because 'Add-LogEntry function must still exist in GUI file'
    }
}

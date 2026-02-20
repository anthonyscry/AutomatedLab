# PublicFunctionHelp.Tests.ps1 -- Repository-wide quality gate for Public function help coverage

Describe 'Public function comment-based help coverage' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $publicRoot = Join-Path $repoRoot 'Public'
        $script:publicFiles = Get-ChildItem -Path $publicRoot -Recurse -Filter '*.ps1' |
            Sort-Object FullName
    }

    Context 'Required help tokens (.SYNOPSIS, .DESCRIPTION, .EXAMPLE)' {
        It 'every Public file contains .SYNOPSIS' {
            $missing = @($script:publicFiles | Where-Object {
                (Get-Content $_.FullName -Raw) -notmatch '\.SYNOPSIS'
            })
            $report = ($missing | ForEach-Object { "  MISSING .SYNOPSIS: $($_.FullName)" }) -join "`n"
            $missing.Count | Should -Be 0 -Because "the following files lack .SYNOPSIS:`n$report"
        }

        It 'every Public file contains .DESCRIPTION' {
            $missing = @($script:publicFiles | Where-Object {
                (Get-Content $_.FullName -Raw) -notmatch '\.DESCRIPTION'
            })
            $report = ($missing | ForEach-Object { "  MISSING .DESCRIPTION: $($_.FullName)" }) -join "`n"
            $missing.Count | Should -Be 0 -Because "the following files lack .DESCRIPTION:`n$report"
        }

        It 'every Public file contains .EXAMPLE' {
            $missing = @($script:publicFiles | Where-Object {
                (Get-Content $_.FullName -Raw) -notmatch '\.EXAMPLE'
            })
            $report = ($missing | ForEach-Object { "  MISSING .EXAMPLE: $($_.FullName)" }) -join "`n"
            $missing.Count | Should -Be 0 -Because "the following files lack .EXAMPLE:`n$report"
        }
    }

    Context 'Parameter documentation (.PARAMETER required when declared parameters are present)' {
        It 'every Public file with declared parameters contains at least one .PARAMETER entry' {
            # Match param blocks that contain at least one declared parameter (non-empty param block).
            # An empty param() with no declared parameters (e.g. CmdletBinding-only functions)
            # does not require .PARAMETER documentation.
            $missing = @($script:publicFiles | Where-Object {
                $content = Get-Content $_.FullName -Raw
                # A declared parameter must have a [type] annotation or $Param name inside the block
                $hasDeclaredParams = $content -match 'param\s*\(\s*(\[[^\]]+\]|\$\w)'
                $hasDeclaredParams -and ($content -notmatch '\.PARAMETER')
            })
            $report = ($missing | ForEach-Object { "  MISSING .PARAMETER: $($_.FullName)" }) -join "`n"
            $missing.Count | Should -Be 0 -Because "the following files have declared parameters but no .PARAMETER docs:`n$report"
        }
    }
}

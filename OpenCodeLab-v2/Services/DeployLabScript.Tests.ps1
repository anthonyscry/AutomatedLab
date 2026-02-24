BeforeAll {
    $script:deployScriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Deploy-Lab.ps1'
    $script:deployScript = Get-Content -Raw -Path $script:deployScriptPath
}

Describe 'Deploy-Lab internet policy orchestration' {
    It 'passes lab name into internet policy worker item context' {
        $script:deployScript | Should -Match '\$labName\s*=\s*\[string\]\$item\.LabName'
    }
}

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot

    # Dot-source the public cmdlet under test
    . (Join-Path (Join-Path $repoRoot 'Public') 'Get-LabRunHistory.ps1')

    # Dot-source the private helper file that contains Get-LabRunArtifactPaths,
    # Get-LabLatestRunArtifactPath, and Get-LabRunArtifactSummary
    . (Join-Path (Join-Path $repoRoot 'Private') 'Get-LabRunArtifactSummary.ps1')

    # Test helper: create a fresh temporary log root directory
    function New-TestLogRoot {
        $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) "LabRunHistoryTest_$(New-Guid)"
        New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
        return $tempPath
    }

    # Test helper: remove the temp log root directory
    function Remove-TestLogRoot {
        param([string]$Path)
        if (Test-Path $Path) {
            Remove-Item -Path $Path -Recurse -Force
        }
    }

    # Test helper: create a realistic OpenCodeLab-Run-{RunId}.json artifact file
    function New-TestRunArtifact {
        param(
            [Parameter(Mandatory)]
            [string]$LogRoot,

            [Parameter(Mandatory)]
            [string]$RunId,

            [string]$Action = 'deploy',
            [bool]$Success = $true,
            [int]$DurationSeconds = 30,
            [string]$EndedUtc = ([datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')),
            [string]$DispatchMode = 'auto',
            [string]$RequestedMode = 'auto',
            [string]$EffectiveMode = 'quick',
            [string]$ErrorText = '',
            [string]$HostName = 'TESTHOST',
            [string]$UserName = 'testuser'
        )

        $startedUtc = ([datetime]::UtcNow.AddSeconds(-$DurationSeconds).ToString('yyyy-MM-ddTHH:mm:ssZ'))

        $payload = [pscustomobject]@{
            run_id            = $RunId
            action            = $Action
            dispatch_mode     = $DispatchMode
            execution_outcome = if ($Success) { 'success' } else { 'failure' }
            requested_mode    = $RequestedMode
            effective_mode    = $EffectiveMode
            started_utc       = $startedUtc
            ended_utc         = $EndedUtc
            duration_seconds  = $DurationSeconds
            success           = $Success
            error             = $ErrorText
            host              = $HostName
            user              = $UserName
            events            = @(
                [pscustomobject]@{ timestamp = $startedUtc; message = 'Run started' },
                [pscustomobject]@{ timestamp = $EndedUtc;   message = 'Run completed' }
            )
        }

        $artifactName = "OpenCodeLab-Run-$RunId.json"
        $artifactPath = Join-Path $LogRoot $artifactName
        $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $artifactPath -Encoding UTF8

        return $artifactPath
    }
}

Describe 'Get-LabRunHistory' {

    Context 'List mode' {

        It 'Returns empty array when log directory has no artifacts' {
            $logRoot = New-TestLogRoot
            try {
                $result = @(Get-LabRunHistory -LogRoot $logRoot)
                $result.Count | Should -Be 0
            }
            finally {
                Remove-TestLogRoot $logRoot
            }
        }

        It 'Returns summary objects with expected properties' {
            $logRoot = New-TestLogRoot
            try {
                $null = New-TestRunArtifact -LogRoot $logRoot -RunId 'abc001' -Action 'deploy' -Success $true -DurationSeconds 45

                $result = @(Get-LabRunHistory -LogRoot $logRoot)
                $result.Count | Should -Be 1

                $entry = $result[0]
                $entry.RunId           | Should -Not -BeNullOrEmpty
                $entry.Action          | Should -Be 'deploy'
                $entry.Mode            | Should -Not -BeNullOrEmpty
                $entry.Success         | Should -Be $true
                $entry.DurationSeconds | Should -Be 45
                $entry.EndedUtc        | Should -Not -BeNullOrEmpty
                ($entry | Get-Member -Name 'Error' -MemberType NoteProperty) | Should -Not -BeNullOrEmpty
            }
            finally {
                Remove-TestLogRoot $logRoot
            }
        }

        It 'Returns results sorted newest-first by EndedUtc' {
            $logRoot = New-TestLogRoot
            try {
                # Create three artifacts with clearly distinct timestamps
                $t1 = '2026-01-01T10:00:00Z'
                $t2 = '2026-01-02T10:00:00Z'
                $t3 = '2026-01-03T10:00:00Z'

                $null = New-TestRunArtifact -LogRoot $logRoot -RunId 'oldest01' -EndedUtc $t1
                $null = New-TestRunArtifact -LogRoot $logRoot -RunId 'middle02' -EndedUtc $t2
                $null = New-TestRunArtifact -LogRoot $logRoot -RunId 'newest03' -EndedUtc $t3

                $result = @(Get-LabRunHistory -LogRoot $logRoot)
                $result.Count | Should -Be 3

                # First result should be the newest — check RunId for ordering proof
                # (EndedUtc may be a locale-formatted string after ConvertFrom-Json DateTime coercion)
                $result[0].RunId | Should -Be 'newest03'
                $result[0].EndedUtc | Should -Not -BeNullOrEmpty

                # Last result should be the oldest
                $result[2].RunId | Should -Be 'oldest01'
                $result[2].EndedUtc | Should -Not -BeNullOrEmpty
            }
            finally {
                Remove-TestLogRoot $logRoot
            }
        }

        It 'Respects -Last parameter and returns only the requested count' {
            $logRoot = New-TestLogRoot
            try {
                # Create 5 artifacts with sequential timestamps
                for ($i = 1; $i -le 5; $i++) {
                    $ts = "2026-01-0${i}T12:00:00Z"
                    $null = New-TestRunArtifact -LogRoot $logRoot -RunId "run00$i" -EndedUtc $ts
                }

                $result = @(Get-LabRunHistory -LogRoot $logRoot -Last 2)
                $result.Count | Should -Be 2

                # Should contain the two most recent
                $result[0].RunId | Should -Be 'run005'
                $result[1].RunId | Should -Be 'run004'
            }
            finally {
                Remove-TestLogRoot $logRoot
            }
        }

        It 'Skips .txt files and only processes .json artifacts' {
            $logRoot = New-TestLogRoot
            try {
                # Create a valid .json artifact
                $null = New-TestRunArtifact -LogRoot $logRoot -RunId 'jsononly' -Action 'deploy'

                # Create a companion .txt file (simulating Write-LabRunArtifacts dual output)
                $txtPath = Join-Path $logRoot 'OpenCodeLab-Run-jsononly.txt'
                "run_id: jsononly`naction: deploy`nsuccess: true`neffective_mode: quick`nended_utc: 2026-01-01T00:00:00Z`nduration_seconds: 10" |
                    Set-Content -Path $txtPath -Encoding UTF8

                $result = @(Get-LabRunHistory -LogRoot $logRoot)

                # Should only return 1 entry (not 2) — the .txt duplicate is ignored
                $result.Count | Should -Be 1
                $result[0].RunId | Should -Be 'jsononly'
            }
            finally {
                Remove-TestLogRoot $logRoot
            }
        }
    }

    Context 'Detail mode' {

        It 'Returns full run data when -RunId matches an artifact' {
            $logRoot = New-TestLogRoot
            try {
                $null = New-TestRunArtifact -LogRoot $logRoot -RunId 'detail99' -Action 'teardown' -Success $false -DurationSeconds 120

                $result = Get-LabRunHistory -LogRoot $logRoot -RunId 'detail99'

                $result | Should -Not -BeNullOrEmpty
                $result.run_id  | Should -Be 'detail99'
                $result.action  | Should -Be 'teardown'
                $result.success | Should -Be $false
            }
            finally {
                Remove-TestLogRoot $logRoot
            }
        }

        It 'Returns object with all expected fields from the artifact' {
            $logRoot = New-TestLogRoot
            try {
                $null = New-TestRunArtifact -LogRoot $logRoot -RunId 'fullfields' -Action 'deploy' -Success $true -DurationSeconds 60 -EndedUtc '2026-01-15T08:30:00Z'

                $result = Get-LabRunHistory -LogRoot $logRoot -RunId 'fullfields'

                # Verify all HIST-01 required fields are present
                ($result | Get-Member -Name 'run_id'           -MemberType NoteProperty) | Should -Not -BeNullOrEmpty
                ($result | Get-Member -Name 'action'           -MemberType NoteProperty) | Should -Not -BeNullOrEmpty
                ($result | Get-Member -Name 'started_utc'      -MemberType NoteProperty) | Should -Not -BeNullOrEmpty
                ($result | Get-Member -Name 'ended_utc'        -MemberType NoteProperty) | Should -Not -BeNullOrEmpty
                ($result | Get-Member -Name 'duration_seconds' -MemberType NoteProperty) | Should -Not -BeNullOrEmpty
                ($result | Get-Member -Name 'success'          -MemberType NoteProperty) | Should -Not -BeNullOrEmpty
                ($result | Get-Member -Name 'events'           -MemberType NoteProperty) | Should -Not -BeNullOrEmpty
                ($result | Get-Member -Name 'host'             -MemberType NoteProperty) | Should -Not -BeNullOrEmpty
                ($result | Get-Member -Name 'user'             -MemberType NoteProperty) | Should -Not -BeNullOrEmpty

                # ended_utc may be a DateTime object (ConvertFrom-Json coercion) or ISO string
                # Verify it represents the correct date/time value regardless of string format
                $endedUtcValue = $result.ended_utc
                if ($endedUtcValue -is [datetime]) {
                    $endedUtcValue.Year  | Should -Be 2026
                    $endedUtcValue.Month | Should -Be 1
                    $endedUtcValue.Day   | Should -Be 15
                }
                else {
                    [string]$endedUtcValue | Should -Match '2026'
                }
                $result.duration_seconds | Should -Be 60
                $result.action           | Should -Be 'deploy'
            }
            finally {
                Remove-TestLogRoot $logRoot
            }
        }

        It 'Throws when -RunId does not match any artifact' {
            $logRoot = New-TestLogRoot
            try {
                $null = New-TestRunArtifact -LogRoot $logRoot -RunId 'existingrun'

                { Get-LabRunHistory -LogRoot $logRoot -RunId 'nonexistent999' } |
                    Should -Throw -ExpectedMessage "*not found*"
            }
            finally {
                Remove-TestLogRoot $logRoot
            }
        }
    }

    Context 'Error handling' {

        It 'Skips corrupt JSON files with Write-Warning and returns remaining valid entries' {
            $logRoot = New-TestLogRoot
            try {
                # Create one valid artifact
                $null = New-TestRunArtifact -LogRoot $logRoot -RunId 'valid01' -Action 'deploy' -Success $true

                # Create a corrupt JSON artifact
                $corruptPath = Join-Path $logRoot 'OpenCodeLab-Run-corrupt99.json'
                'THIS IS NOT VALID JSON {{{' | Set-Content -Path $corruptPath -Encoding UTF8

                # Should emit a warning but NOT throw, and still return the valid entry
                $warnings = @()
                $result = @(Get-LabRunHistory -LogRoot $logRoot -WarningVariable warnings)

                $result.Count   | Should -Be 1
                $result[0].RunId | Should -Be 'valid01'

                # Should have warned about the corrupt file
                $warnings.Count | Should -BeGreaterThan 0
                ($warnings | Where-Object { $_ -match 'corrupt' -or $_ -match 'corrupt99' -or $_ -match 'Skipping' }) |
                    Should -Not -BeNullOrEmpty
            }
            finally {
                Remove-TestLogRoot $logRoot
            }
        }

        It 'Returns empty array when LogRoot directory does not exist' {
            $nonExistentPath = Join-Path ([System.IO.Path]::GetTempPath()) "DoesNotExist_$(New-Guid)"

            # Should not throw — graceful empty result
            $result = @(Get-LabRunHistory -LogRoot $nonExistentPath)
            $result.Count | Should -Be 0
        }
    }
}

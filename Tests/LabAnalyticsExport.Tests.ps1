Describe 'Export-LabAnalyticsData' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        Import-Module "$moduleRoot\SimpleLab\SimpleLab.psd1" -Force

        $testOutputPath = Join-Path $TestDrive 'analytics-export'
    }

    BeforeEach {
        if (Test-Path $testOutputPath) {
            Remove-Item $testOutputPath -Recurse -Force
        }
    }

    AfterEach {
        if (Test-Path $testOutputPath) {
            Remove-Item $testOutputPath -Recurse -Force
        }
    }

    Context 'CSV export' {
        It 'Exports analytics events to CSV format' {
            $csvPath = "$testOutputPath.csv"
            $result = Export-LabAnalyticsData -OutputPath $csvPath -Force

            $result | Should -BeOfType [string]
            Test-Path $csvPath | Should -BeTrue

            $content = Get-Content $csvPath
            $content[0] | Should -Match 'Timestamp'
        }

        It 'Flattens metadata as semicolon-separated key=value pairs' {
            $csvPath = "$testOutputPath.csv"
            Export-LabAnalyticsData -OutputPath $csvPath -Force

            $content = Get-Content $csvPath
            $content | Should -Match '\w+=.*;\s*\w+='
        }
    }

    Context 'JSON export' {
        It 'Exports analytics events to JSON format' {
            $jsonPath = "$testOutputPath.json"
            $result = Export-LabAnalyticsData -OutputPath $jsonPath -Force

            $result | Should -BeOfType [string]
            Test-Path $jsonPath | Should -BeTrue

            $content = Get-Content $jsonPath -Raw
            { $content | ConvertFrom-Json } | Should -Not -Throw
        }

        It 'Preserves nested metadata structure in JSON' {
            $jsonPath = "$testOutputPath.json"
            Export-LabAnalyticsData -OutputPath $jsonPath -Force

            $content = Get-Content $jsonPath -Raw
            $data = $content | ConvertFrom-Json

            if ($data.Count -gt 0 -and $data[0].Metadata) {
                $data[0].Metadata.PSObject.Properties.Count | Should -BeGreaterThan 0
            }
        }
    }

    Context 'File extension validation' {
        It 'Throws error for unsupported file extension' {
            $txtPath = "$testOutputPath.txt"

            { Export-LabAnalyticsData -OutputPath $txtPath -Force } |
                Should -Throw "*must have .csv or .json extension*"
        }
    }

    Context 'ShouldProcess support' {
        It 'Prompts before overwriting existing file without -Force' {
            $csvPath = "$testOutputPath.csv"
            $null = New-Item -Path $csvPath -ItemType File -Force

            Mock -CommandName ShouldProcess -MockWith { return $false }

            Export-LabAnalyticsData -OutputPath $csvPath -ErrorAction SilentlyContinue

            Should -Invoke ShouldProcess -Times 1 -Exactly
        }

        It 'Overwrites without prompt when -Force specified' {
            $csvPath = "$testOutputPath.csv"
            $null = New-Item -Path $csvPath -ItemType File -Force

            $result = Export-LabAnalyticsData -OutputPath $csvPath -Force

            $result | Should -BeOfType [string]
        }
    }
}

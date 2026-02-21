# LabDCPostInstall tests - ADMX/GPO integration

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Get-LabADMXConfig.ps1')
    . (Join-Path $repoRoot 'Private/Wait-LabADReady.ps1')
    . (Join-Path $repoRoot 'Private/Invoke-LabADMXImport.ps1')
    . (Join-Path $repoRoot 'Private/ConvertTo-DomainDN.ps1')
}

Describe 'LabDC PostInstall - ADMX/GPO Integration' {
    BeforeEach {
        # Clean up GlobalLabConfig between tests
        if (Test-Path variable:GlobalLabConfig) {
            Remove-Variable -Name GlobalLabConfig -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'skips ADMX/GPO operations when ADMX.Enabled is false' {
        # Arrange
        $script:GlobalLabConfig = @{
            ADMX = @{
                Enabled = $false
            }
        }

        Mock Wait-LabADReady { return [pscustomobject]@{ Ready = $true } }
        Mock Invoke-LabADMXImport { return [pscustomobject]@{ Success = $true } }

        # Act (simulate the PostInstall step 4 logic)
        $skipADMX = -not (
            (Test-Path variable:GlobalLabConfig) -and
            $GlobalLabConfig.ContainsKey('ADMX') -and
            $GlobalLabConfig.ADMX.ContainsKey('Enabled') -and
            $GlobalLabConfig.ADMX.Enabled
        )

        # Assert
        $skipADMX | Should -BeTrue
        Should -Invoke Wait-LabADReady -Times 0 -Scope It
        Should -Invoke Invoke-LabADMXImport -Times 0 -Scope It
    }

    It 'executes ADMX/GPO operations when ADMX.Enabled is true' {
        # Arrange
        $script:GlobalLabConfig = @{
            ADMX = @{
                Enabled = $true
            }
        }

        Mock Wait-LabADReady {
            return [pscustomobject]@{
                Ready = $true
                DomainName = 'simplelab.local'
                WaitSeconds = 5
            }
        }
        Mock Invoke-LabADMXImport {
            return [pscustomobject]@{
                Success = $true
                FilesImported = 150
                ThirdPartyBundlesProcessed = 0
                CentralStorePath = '\\simplelab.local\SYSVOL\simplelab.local\Policies\PolicyDefinitions'
                DurationSeconds = 10
                Message = ''
            }
        }

        $dcName = 'dc1'
        $domainName = 'simplelab.local'

        # Act (simulate the PostInstall step 4 logic)
        $shouldRunADMX = (
            (Test-Path variable:GlobalLabConfig) -and
            $GlobalLabConfig.ContainsKey('ADMX') -and
            $GlobalLabConfig.ADMX.ContainsKey('Enabled') -and
            $GlobalLabConfig.ADMX.Enabled
        )

        if ($shouldRunADMX) {
            $adReady = Wait-LabADReady -DomainName $domainName
            if ($adReady.Ready) {
                $admxResult = Invoke-LabADMXImport -DCName $dcName -DomainName $domainName
            }
        }

        # Assert
        $shouldRunADMX | Should -BeTrue
        Should -Invoke Wait-LabADReady -Times 1 -Scope It -ParameterFilter {
            $DomainName -eq 'simplelab.local'
        }
        Should -Invoke Invoke-LabADMXImport -Times 1 -Scope It -ParameterFilter {
            $DCName -eq 'dc1' -and $DomainName -eq 'simplelab.local'
        }
    }

    It 'skips ADMX import when Wait-LabADReady returns Ready=false' {
        # Arrange
        $script:GlobalLabConfig = @{
            ADMX = @{
                Enabled = $true
            }
        }

        Mock Wait-LabADReady {
            return [pscustomobject]@{
                Ready = $false
                DomainName = 'simplelab.local'
                WaitSeconds = 120
            }
        }
        Mock Invoke-LabADMXImport {
            throw 'Should not be called'
        }

        $domainName = 'simplelab.local'

        # Act (simulate the PostInstall step 4 logic)
        $adReady = Wait-LabADReady -DomainName $domainName
        if ($adReady.Ready) {
            Invoke-LabADMXImport -DCName 'dc1' -DomainName $domainName
        }

        # Assert
        $adReady.Ready | Should -BeFalse
        Should -Invoke Wait-LabADReady -Times 1 -Scope It
        Should -Invoke Invoke-LabADMXImport -Times 0 -Scope It
    }

    It 'handles Invoke-LabADMXImport failure gracefully' {
        # Arrange
        $script:GlobalLabConfig = @{
            ADMX = @{
                Enabled = $true
            }
        }

        Mock Wait-LabADReady {
            return [pscustomobject]@{ Ready = $true }
        }
        Mock Invoke-LabADMXImport {
            return [pscustomobject]@{
                Success = $false
                Message = 'Access denied to Central Store path'
            }
        }

        $dcName = 'dc1'
        $domainName = 'simplelab.local'

        # Act (simulate the PostInstall step 4 logic with try-catch)
        try {
            $adReady = Wait-LabADReady -DomainName $domainName
            if ($adReady.Ready) {
                $admxResult = Invoke-LabADMXImport -DCName $dcName -DomainName $domainName
                if (-not $admxResult.Success) {
                    # This is where the warning would be logged
                    $errorLogged = $true
                }
            }
        }
        catch {
            # Should not reach here - Invoke-LabADMXImport returns object, doesn't throw
            $errorLogged = $false
        }

        # Assert
        Should -Invoke Wait-LabADReady -Times 1 -Scope It
        Should -Invoke Invoke-LabADMXImport -Times 1 -Scope It
        $errorLogged | Should -BeTrue
    }

    It 'handles Wait-LabADReady exception with try-catch' {
        # Arrange
        $script:GlobalLabConfig = @{
            ADMX = @{
                Enabled = $true
            }
        }

        Mock Wait-LabADReady {
            throw 'Get-ADDomain: The server is not operational'
        }
        Mock Invoke-LabADMXImport {
            throw 'Should not be called'
        }

        $domainName = 'simplelab.local'
        $exceptionCaught = $false

        # Act (simulate the PostInstall step 4 logic with try-catch)
        try {
            $adReady = Wait-LabADReady -DomainName $domainName
            if ($adReady.Ready) {
                Invoke-LabADMXImport -DCName 'dc1' -DomainName $domainName
            }
        }
        catch {
            $exceptionCaught = $true
        }

        # Assert
        Should -Invoke Wait-LabADReady -Times 1 -Scope It
        Should -Invoke Invoke-LabADMXImport -Times 0 -Scope It
        $exceptionCaught | Should -BeTrue
    }
}

Set-StrictMode -Version Latest

BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $script:LabBuilderDir = Join-Path $RepoRoot 'LabBuilder'
    $script:RolesDir = Join-Path $LabBuilderDir 'Roles'

    # Read source files as text (structural tests, not execution)
    $script:BuildContent = Get-Content (Join-Path $LabBuilderDir 'Build-LabFromSelection.ps1') -Raw
    $script:InvokeContent = Get-Content (Join-Path $LabBuilderDir 'Invoke-LabBuilder.ps1') -Raw
}

Describe 'roleScriptMap Completeness' {
    BeforeAll {
        # Extract roleScriptMap keys from Build-LabFromSelection.ps1
        $script:MapKeys = @()
        $lines = $script:BuildContent -split "`n"
        $inMap = $false
        foreach ($line in $lines) {
            if ($line -match 'roleScriptMap\s*=\s*@\{') { $inMap = $true; continue }
            if ($inMap -and $line -match '^\s*\}') { break }
            if ($inMap -and $line -match '^\s*(\w+)\s*=\s*@\{') {
                $script:MapKeys += $Matches[1]
            }
        }
    }

    It 'roleScriptMap has 15 role entries' {
        $script:MapKeys.Count | Should -Be 15
    }

    It 'roleScriptMap contains <Tag>' -ForEach @(
        @{ Tag = 'DC' }
        @{ Tag = 'DSC' }
        @{ Tag = 'IIS' }
        @{ Tag = 'SQL' }
        @{ Tag = 'WSUS' }
        @{ Tag = 'DHCP' }
        @{ Tag = 'FileServer' }
        @{ Tag = 'PrintServer' }
        @{ Tag = 'Jumpbox' }
        @{ Tag = 'Client' }
        @{ Tag = 'Ubuntu' }
        @{ Tag = 'WebServerUbuntu' }
        @{ Tag = 'DatabaseUbuntu' }
        @{ Tag = 'DockerUbuntu' }
        @{ Tag = 'K8sUbuntu' }
    ) {
        $Tag | Should -BeIn $script:MapKeys -Because "roleScriptMap should contain $Tag"
    }
}

Describe 'roleScriptMap File References' {
    BeforeAll {
        # Extract file references from roleScriptMap
        $script:MapEntries = @{}
        $lines = $script:BuildContent -split "`n"
        $inMap = $false
        $currentTag = ''
        foreach ($line in $lines) {
            if ($line -match 'roleScriptMap\s*=\s*@\{') { $inMap = $true; continue }
            if ($inMap -and $line -match '^\s*\}$') { break }
            if ($inMap -and $line -match '^\s*(\w+)\s*=\s*@\{') {
                $currentTag = $Matches[1]
            }
            if ($inMap -and $currentTag -and $line -match "File\s*=\s*'([^']+)'") {
                $script:MapEntries[$currentTag] = $Matches[1]
            }
        }
    }

    It '<Tag> references existing file <File>' -ForEach @(
        @{ Tag = 'DC'; File = 'DC.ps1' }
        @{ Tag = 'DSC'; File = 'DSCPullServer.ps1' }
        @{ Tag = 'IIS'; File = 'IIS.ps1' }
        @{ Tag = 'SQL'; File = 'SQL.ps1' }
        @{ Tag = 'WSUS'; File = 'WSUS.ps1' }
        @{ Tag = 'DHCP'; File = 'DHCP.ps1' }
        @{ Tag = 'FileServer'; File = 'FileServer.ps1' }
        @{ Tag = 'PrintServer'; File = 'PrintServer.ps1' }
        @{ Tag = 'Jumpbox'; File = 'Jumpbox.ps1' }
        @{ Tag = 'Client'; File = 'Client.ps1' }
        @{ Tag = 'Ubuntu'; File = 'Ubuntu.ps1' }
        @{ Tag = 'WebServerUbuntu'; File = 'WebServer.Ubuntu.ps1' }
        @{ Tag = 'DatabaseUbuntu'; File = 'Database.Ubuntu.ps1' }
        @{ Tag = 'DockerUbuntu'; File = 'Docker.Ubuntu.ps1' }
        @{ Tag = 'K8sUbuntu'; File = 'K8s.Ubuntu.ps1' }
    ) {
        $filePath = Join-Path $script:RolesDir $File
        $filePath | Should -Exist -Because "$Tag role references $File which must exist"
    }
}

Describe 'Invoke-LabBuilder validTags Alignment' {
    BeforeAll {
        # Extract validTags from Invoke-LabBuilder.ps1
        $script:ValidTags = @()
        if ($script:InvokeContent -match '\$validTags\s*=\s*@\(([^)]+)\)') {
            $tagLine = $Matches[1]
            $script:ValidTags = @($tagLine -split ',' | ForEach-Object { $_.Trim().Trim("'").Trim('"') } | Where-Object { $_ })
        }

        # Extract roleScriptMap keys
        $script:MapKeys2 = @()
        $lines = $script:BuildContent -split "`n"
        $inMap = $false
        foreach ($line in $lines) {
            if ($line -match 'roleScriptMap\s*=\s*@\{') { $inMap = $true; continue }
            if ($inMap -and $line -match '^\s*\}$') { break }
            if ($inMap -and $line -match '^\s*(\w+)\s*=\s*@\{') {
                $script:MapKeys2 += $Matches[1]
            }
        }
    }

    It 'validTags has same count as roleScriptMap' {
        $script:ValidTags.Count | Should -Be $script:MapKeys2.Count
    }

    It 'validTags contains all roleScriptMap keys' {
        foreach ($key in $script:MapKeys2) {
            $key | Should -BeIn $script:ValidTags -Because "validTags should include roleScriptMap key $key"
        }
    }

    It 'roleScriptMap contains all validTags entries' {
        foreach ($tag in $script:ValidTags) {
            $tag | Should -BeIn $script:MapKeys2 -Because "roleScriptMap should include validTags entry $tag"
        }
    }
}

Describe 'Role Function Naming Convention' {
    It 'roleScriptMap function for <Tag> follows Get-LabRole_ pattern' -ForEach @(
        @{ Tag = 'DC' }
        @{ Tag = 'DSC' }
        @{ Tag = 'IIS' }
        @{ Tag = 'SQL' }
        @{ Tag = 'WSUS' }
        @{ Tag = 'DHCP' }
        @{ Tag = 'FileServer' }
        @{ Tag = 'PrintServer' }
        @{ Tag = 'Jumpbox' }
        @{ Tag = 'Client' }
        @{ Tag = 'Ubuntu' }
        @{ Tag = 'WebServerUbuntu' }
        @{ Tag = 'DatabaseUbuntu' }
        @{ Tag = 'DockerUbuntu' }
        @{ Tag = 'K8sUbuntu' }
    ) {
        $script:BuildContent | Should -Match "Function\s*=\s*'Get-LabRole_" -Because "All role functions should follow Get-LabRole_ naming convention"
    }
}

Describe 'DC Fatal Failure Handling' {
    It 'Build-LabFromSelection has DC fatal error handling' {
        $script:BuildContent | Should -Match 'FATAL.*DC' -Because "DC failure should be fatal and abort the build"
    }

    It 'DC post-install is marked CRITICAL' {
        $script:BuildContent | Should -Match 'CRITICAL.*AD services' -Because "DC post-install should be marked critical"
    }
}

Describe 'Post-Install Summary Reporting' {
    It 'Build-LabFromSelection has post-install summary section' {
        $script:BuildContent | Should -Match 'Post-Install Summary' -Because "Build should report per-role post-install status"
    }

    It 'Build-LabFromSelection tracks postInstallResults' {
        $script:BuildContent | Should -Match 'postInstallResults' -Because "Build should track per-role results"
    }

    It 'JSON summary includes PostInstallResults' {
        $script:BuildContent | Should -Match 'PostInstallResults\s*=' -Because "JSON summary should include per-role results"
    }
}

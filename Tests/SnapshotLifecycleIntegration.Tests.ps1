BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $script:appContent = Get-Content (Join-Path $repoRoot 'OpenCodeLab-App.ps1') -Raw
    $script:statusContent = Get-Content (Join-Path (Join-Path $repoRoot 'Scripts') 'Lab-Status.ps1') -Raw
}

Describe 'Snapshot CLI Actions - OpenCodeLab-App.ps1' {
    It 'ValidateSet includes snapshot-list' {
        $script:appContent | Should -Match "snapshot-list"
    }

    It 'ValidateSet includes snapshot-prune' {
        $script:appContent | Should -Match "snapshot-prune"
    }

    It 'snapshot-list switch case exists and calls Get-LabSnapshotInventory' {
        $script:appContent | Should -Match "'snapshot-list'\s*\{"
        $script:appContent | Should -Match "Get-LabSnapshotInventory"
    }

    It 'snapshot-prune switch case exists and calls Remove-LabStaleSnapshots' {
        $script:appContent | Should -Match "'snapshot-prune'\s*\{"
        $script:appContent | Should -Match "Remove-LabStaleSnapshots"
    }

    It 'PruneDays parameter is declared' {
        $script:appContent | Should -Match '\[int\]\$PruneDays'
    }

    It 'snapshot-prune uses Write-LabStatus for output formatting' {
        # Find the switch case (contains opening brace), not the ValidateSet entry
        $pruneIndex = $script:appContent.IndexOf("'snapshot-prune' {")
        $pruneIndex | Should -BeGreaterThan -1
        $afterPrune = $script:appContent.Substring($pruneIndex, [Math]::Min(1500, $script:appContent.Length - $pruneIndex))
        $afterPrune | Should -Match 'Write-LabStatus'
    }
}

Describe 'Snapshot Status Integration - Lab-Status.ps1' {
    It 'Lab-Status.ps1 dot-sources Get-LabSnapshotInventory.ps1' {
        $script:statusContent | Should -Match 'Get-LabSnapshotInventory\.ps1'
    }

    It 'SNAPSHOTS section calls Get-LabSnapshotInventory' {
        $script:statusContent | Should -Match 'Get-LabSnapshotInventory'
    }

    It 'Status output includes oldest/newest summary' {
        $script:statusContent | Should -Match 'Oldest.*Newest'
    }

    It 'Status output includes stale count warning with snapshot-prune hint' {
        $script:statusContent | Should -Match "Stale.*snapshot-prune"
    }

    It 'Fallback exists for when inventory function is unavailable' {
        $script:statusContent | Should -Match 'catch'
        $script:statusContent | Should -Match 'Get-VMSnapshot'
    }
}

Describe 'Function Availability' {
    It 'Get-LabSnapshotInventory.ps1 exists in Private/' {
        $path = Join-Path $repoRoot 'Private/Get-LabSnapshotInventory.ps1'
        $path | Should -Exist
    }

    It 'Remove-LabStaleSnapshots.ps1 exists in Private/' {
        $path = Join-Path $repoRoot 'Private/Remove-LabStaleSnapshots.ps1'
        $path | Should -Exist
    }

    It 'Get-LabSnapshotInventory.ps1 can be dot-sourced without error' {
        { . (Join-Path $repoRoot 'Private/Get-LabSnapshotInventory.ps1') } | Should -Not -Throw
    }

    It 'Remove-LabStaleSnapshots.ps1 can be dot-sourced without error' {
        { . (Join-Path $repoRoot 'Private/Remove-LabStaleSnapshots.ps1') } | Should -Not -Throw
    }
}

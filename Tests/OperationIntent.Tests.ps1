# Resolve-LabOperationIntent tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Get-LabHostInventory.ps1')
    . (Join-Path $repoRoot 'Private/Resolve-LabOperationIntent.ps1')
}

Describe 'Resolve-LabOperationIntent' {
    It 'normalizes action and mode and resolves target hosts' {
        $inventoryPath = Join-Path $TestDrive 'inventory.json'
        @'
{
  "hosts": [
    { "name": "HV-01", "role": "primary", "connection": "winrm" },
    { "name": "HV-02", "role": "secondary", "connection": "winrm" }
  ]
}
'@ | Set-Content -LiteralPath $inventoryPath -Encoding UTF8

        $intent = Resolve-LabOperationIntent -Action '  DEPLOY ' -Mode ' QUICK ' -TargetHosts @('HV-01') -InventoryPath $inventoryPath

        $intent.Action | Should -Be 'deploy'
        $intent.RequestedMode | Should -Be 'quick'
        $intent.TargetHosts | Should -Be @('HV-01')
        $intent.InventorySource | Should -Be $inventoryPath
    }

    It 'returns default local inventory source and requestor context fields' {
        $intent = Resolve-LabOperationIntent -Action 'teardown' -Mode 'full'

        $intent.InventorySource | Should -Be 'default-local'
        $intent.TargetHosts.Count | Should -Be 1
        $intent.PSObject.Properties.Name | Should -Contain 'RequestorMachine'
        $intent.PSObject.Properties.Name | Should -Contain 'RequestorUser'
        $intent.RequestorMachine | Should -Be ([Environment]::MachineName)
        $intent.RequestorUser | Should -Not -BeNullOrEmpty
    }

    It 'throws for unsupported mode values' {
        {
            Resolve-LabOperationIntent -Action 'deploy' -Mode 'turbo'
        } | Should -Throw "*Unsupported mode*"
    }

    It 'throws for unsupported action values' {
        {
            Resolve-LabOperationIntent -Action 'destroy-all' -Mode 'quick'
        } | Should -Throw "*Unsupported action*"
    }
}

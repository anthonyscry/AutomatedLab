# Get-LabHostInventory tests

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'Private/Get-LabHostInventory.ps1')
}

Describe 'Get-LabHostInventory' {
    It 'returns default local host when inventory path is not provided' {
        $result = Get-LabHostInventory

        $result.Source | Should -Be 'default-local'
        $result.Hosts.Count | Should -Be 1
        $result.Hosts[0].Name | Should -Be ([Environment]::MachineName)
        $result.Hosts[0].Role | Should -Be 'primary'
        $result.Hosts[0].Connection | Should -Be 'local'
    }

    It 'applies target host filter to default local inventory' {
        $result = Get-LabHostInventory -TargetHosts @('not-this-host')

        $result.Source | Should -Be 'default-local'
        $result.Hosts | Should -Be @()
    }

    It 'reads json inventory and normalizes hosts' {
        $inventoryPath = Join-Path $TestDrive 'inventory.json'
        @'
{
  "hosts": [
    { "name": "HV-01", "role": "primary", "connection": "winrm" },
    { "name": "HV-02", "role": "secondary", "connection": "ssh" }
  ]
}
'@ | Set-Content -LiteralPath $inventoryPath -Encoding UTF8

        $result = Get-LabHostInventory -InventoryPath $inventoryPath

        $result.Source | Should -Be $inventoryPath
        $result.Hosts.Count | Should -Be 2
        $result.Hosts[0] | Should -BeOfType [pscustomobject]
        $result.Hosts[0].Name | Should -Be 'HV-01'
        $result.Hosts[0].Role | Should -Be 'primary'
        $result.Hosts[0].Connection | Should -Be 'winrm'
    }

    It 'applies target host filter to file inventory' {
        $inventoryPath = Join-Path $TestDrive 'inventory.json'
        @'
{
  "hosts": [
    { "name": "HV-01", "role": "primary", "connection": "winrm" },
    { "name": "HV-02", "role": "secondary", "connection": "ssh" }
  ]
}
'@ | Set-Content -LiteralPath $inventoryPath -Encoding UTF8

        $result = Get-LabHostInventory -InventoryPath $inventoryPath -TargetHosts @('hv-02')

        $result.Hosts.Count | Should -Be 1
        $result.Hosts[0].Name | Should -Be 'HV-02'
    }

    It 'throws robust error when inventory file cannot be read' {
        $missingPath = Join-Path $TestDrive 'missing.json'

        {
            Get-LabHostInventory -InventoryPath $missingPath
        } | Should -Throw "Failed to read inventory file*"
    }

    It 'throws robust error when inventory json is malformed' {
        $inventoryPath = Join-Path $TestDrive 'bad-inventory.json'
        '{ not json }' | Set-Content -LiteralPath $inventoryPath -Encoding UTF8

        {
            Get-LabHostInventory -InventoryPath $inventoryPath
        } | Should -Throw "Invalid inventory JSON*"
    }
}

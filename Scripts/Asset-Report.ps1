#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$OutputRoot = 'C:\LabSources\Reports',
    [string]$LabBuilderConfigPath,
    [switch]$IncludeSoftwareInventory
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot = Split-Path -Parent $ScriptDir

$labConfigPath = Join-Path $RepoRoot 'Lab-Config.ps1'
$labCommonPath = Join-Path $RepoRoot 'Lab-Common.ps1'
$defaultBuilderConfig = Join-Path $RepoRoot 'Lab-Config.ps1'

function Resolve-AssetReportBuilderConfig {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) {
        return $null
    }

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()

    if ($extension -eq '.ps1') {
        return (& {
            param([string]$ConfigScriptPath)
            . $ConfigScriptPath

            if (Get-Variable -Name LabBuilderConfig -ErrorAction SilentlyContinue) {
                return (Get-Variable -Name LabBuilderConfig -ValueOnly)
            }

            if (Get-Variable -Name GlobalLabConfig -ErrorAction SilentlyContinue) {
                $global = Get-Variable -Name GlobalLabConfig -ValueOnly
                if ($global -and $global.Builder) {
                    return $global.Builder
                }
            }

            return $null
        } -ConfigScriptPath $Path)
    }

    if ($extension -eq '.psd1') {
        $raw = Import-PowerShellDataFile -Path $Path
        if ($raw -and $raw.ContainsKey('LabBuilder')) {
            return $raw.LabBuilder
        }
        return $raw
    }

    return $null
}

function Write-InventoryCsv {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Headers,
        [Parameter(Mandatory)][object]$Rows
    )

    $rowsArray = @($Rows)
    if ($rowsArray.Count -gt 0) {
        $rowsArray | Select-Object -Property $Headers | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
        return
    }

    $headerLine = ($Headers | ForEach-Object { '"{0}"' -f $_ }) -join ','
    Set-Content -Path $Path -Value ($headerLine + "`r`n") -Encoding UTF8
}

if (Test-Path $labConfigPath) { . $labConfigPath }
if (Test-Path $labCommonPath) { . $labCommonPath }

if ([string]::IsNullOrWhiteSpace($LabBuilderConfigPath)) {
    $LabBuilderConfigPath = $defaultBuilderConfig
}

$builderConfig = $null
$builderConfig = Resolve-AssetReportBuilderConfig -Path $LabBuilderConfigPath

try {
    $null = Import-Module AutomatedLab -ErrorAction SilentlyContinue
    if ($GlobalLabConfig.Lab.Name) {
        Write-Verbose "Importing lab '$($GlobalLabConfig.Lab.Name)'..."
        $null = Import-Lab -Name $GlobalLabConfig.Lab.Name -ErrorAction SilentlyContinue
    }
} catch {
}

if (-not (Test-Path $OutputRoot)) {
    $null = New-Item -Path $OutputRoot -ItemType Directory -Force
    Write-Verbose "Created report output directory: $OutputRoot"
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

$roleByVm = @{}
$plannedIpByVm = @{}

if ($builderConfig) {
    foreach ($tag in $builderConfig.VMNames.Keys) {
        $vmName = [string]$builderConfig.VMNames[$tag]
        if (-not $roleByVm.ContainsKey($vmName)) {
            $roleByVm[$vmName] = New-Object System.Collections.Generic.List[string]
        }
        [void]$roleByVm[$vmName].Add($tag)

        if ($builderConfig.IPPlan.ContainsKey($tag)) {
            $plannedIpByVm[$vmName] = [string]$builderConfig.IPPlan[$tag]
        }
    }
}

if (@($GlobalLabConfig.Lab.CoreVMNames)) {
    foreach ($vm in @($GlobalLabConfig.Lab.CoreVMNames)) {
        $upper = $vm.ToUpperInvariant()
        if (-not $roleByVm.ContainsKey($upper)) {
            $roleByVm[$upper] = New-Object System.Collections.Generic.List[string]
            [void]$roleByVm[$upper].Add($upper)
        }
    }
}

$candidateNames = @()
$candidateNames += @($roleByVm.Keys)

if (@($GlobalLabConfig.Lab.CoreVMNames)) {
    foreach ($name in @($GlobalLabConfig.Lab.CoreVMNames)) {
        $candidateNames += $name
        $candidateNames += $name.ToUpperInvariant()
    }
}

$hypervVms = @(Hyper-V\Get-VM -ErrorAction SilentlyContinue)
if ($hypervVms.Count -gt 0) {
    foreach ($vm in $hypervVms) {
        if ($candidateNames -contains $vm.Name) {
            continue
        }
        if ($vm.Name -match '^(DC|SVR|WS|DSC|IIS|SQL|WSUS|FILE|PRN|JUMP|WIN|LIN)') {
            $candidateNames += $vm.Name
        }
    }
}

$candidateNames = @($candidateNames | Sort-Object -Unique)

$assetRows = @()
$vlanRows = @()
$softwareRows = @()
$featureRows = @()

foreach ($vmName in $candidateNames) {
    $vmObj = Hyper-V\Get-VM -Name $vmName -ErrorAction SilentlyContinue
    if (-not $vmObj) { continue }

    $adapters = @(Get-VMNetworkAdapter -VMName $vmName -ErrorAction SilentlyContinue)
    $primaryAdapter = $adapters | Select-Object -First 1

    $liveIp = ''
    if ($primaryAdapter -and ($primaryAdapter.PSObject.Properties.Name -contains 'IPAddresses')) {
        $liveIp = @($primaryAdapter.IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^169\.254\.' } | Select-Object -First 1)
        if ($liveIp -is [array]) { $liveIp = $liveIp[0] }
    }

    $plannedIp = ''
    if ($plannedIpByVm.ContainsKey($vmName)) {
        $plannedIp = $plannedIpByVm[$vmName]
    }

    $roles = @()
    if ($roleByVm.ContainsKey($vmName)) {
        $roles = @($roleByVm[$vmName])
    }
    if ($roles.Count -eq 0) {
        $roles = @('Unmapped')
    }

    $roleText = ($roles -join ',')

    $switchName = if ($primaryAdapter) { $primaryAdapter.SwitchName } else { '' }
    $vlanMode = 'None'
    $vlanId = ''

    try {
        $vlanInfo = Get-VMNetworkAdapterVlan -VMName $vmName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($vlanInfo) {
            if ($vlanInfo.AccessVlanId -gt 0) {
                $vlanMode = 'Access'
                $vlanId = [string]$vlanInfo.AccessVlanId
            } elseif ($vlanInfo.NativeVlanId -gt 0 -or $vlanInfo.AllowedVlanIdList) {
                $vlanMode = 'Trunk'
                if ($vlanInfo.NativeVlanId -gt 0) {
                    $vlanId = [string]$vlanInfo.NativeVlanId
                } elseif ($vlanInfo.AllowedVlanIdList) {
                    $vlanId = [string]$vlanInfo.AllowedVlanIdList
                }
            }
        }
    } catch {
    }

    $assetRows += [pscustomobject]@{
        VMName = $vmName
        Roles = $roleText
        State = [string]$vmObj.State
        PlannedIP = $plannedIp
        LiveIP = [string]$liveIp
        Switch = [string]$switchName
        VlanMode = $vlanMode
        VlanId = $vlanId
        MemoryGB = [math]::Round(($vmObj.MemoryAssigned / 1GB), 2)
        CPU = [int]$vmObj.ProcessorCount
    }

    $vlanRows += [pscustomobject]@{
        VMName = $vmName
        Switch = [string]$switchName
        VlanMode = $vlanMode
        VlanId = $vlanId
    }

    if ($IncludeSoftwareInventory -and (([string]$vmObj.State) -eq 'Running')) {
        $softwareEntries = @()
        try {
            $softwareEntries = Invoke-LabCommand -ComputerName $vmName -ActivityName 'Collect software inventory' -ScriptBlock {
                $result = @()
                $hives = @(
                    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
                    'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
                )
                foreach ($hive in $hives) {
                    if (-not (Test-Path $hive)) { continue }
                    foreach ($key in Get-ChildItem -Path $hive -ErrorAction SilentlyContinue) {
                        try {
                            $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                        } catch {
                            continue
                        }
                        if (-not $props) { continue }
                        $result += [pscustomobject]@{
                            Product = $props.DisplayName
                            Publisher = $props.Publisher
                            Version = $props.DisplayVersion
                            InstallDate = $props.InstallDate
                        }
                    }
                }
                $result
            } -ErrorAction SilentlyContinue -NoDisplay -PassThru
        } catch {
            $softwareEntries = @()
        }

        foreach ($entry in @($softwareEntries)) {
            if (-not $entry) { continue }
            $productName = [string]$entry.Product
            if ([string]::IsNullOrWhiteSpace($productName)) { continue }

            $installDate = [string]$entry.InstallDate
            if ($installDate -and ($installDate -match '^[0-9]{8}$')) {
                $installDate = '{0}-{1}-{2}' -f $installDate.Substring(0, 4), $installDate.Substring(4, 2), $installDate.Substring(6, 2)
            }

            $softwareRows += [pscustomobject]@{
                Hostname = $vmName
                Roles = $roleText
                Product = $productName
                Publisher = $entry.Publisher
                Version = $entry.Version
                InstallDate = $installDate
            }
        }

        $featureEntries = @()
        try {
            $featureEntries = Invoke-LabCommand -ComputerName $vmName -ActivityName 'Collect feature inventory' -ScriptBlock {
                if (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
                    Get-WindowsFeature |
                        Where-Object { $_.InstallState -eq 'Installed' } |
                        Select-Object
                            @{Name='FeatureName';Expression={$_.Name}},
                            @{Name='DisplayName';Expression={$_.DisplayName}},
                            @{Name='InstallState';Expression={$_.InstallState}}
                } elseif (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue) {
                    Get-WindowsOptionalFeature -Online |
                        Where-Object { $_.State -eq 'Enabled' } |
                        Select-Object
                            @{Name='FeatureName';Expression={$_.FeatureName}},
                            @{Name='DisplayName';Expression={$_.FeatureName}},
                            @{Name='InstallState';Expression={$_.State}}
                } else {
                    @()
                }
            } -ErrorAction SilentlyContinue -NoDisplay -PassThru
        } catch {
            $featureEntries = @()
        }

        foreach ($feature in @($featureEntries)) {
            if (-not $feature) { continue }
            if ([string]::IsNullOrWhiteSpace([string]$feature.FeatureName)) { continue }

            $featureRows += [pscustomobject]@{
                Hostname = $vmName
                Roles = $roleText
                FeatureName = $feature.FeatureName
                DisplayName = $feature.DisplayName
                InstallState = $feature.InstallState
            }
        }
    }
}

if ($IncludeSoftwareInventory) {
    $softwareRows = @($softwareRows | Sort-Object Hostname, Product, Version, Publisher, InstallDate -Unique)
    $featureRows = @($featureRows | Sort-Object Hostname, FeatureName, InstallState -Unique)
}

$networkAddress = if ($builderConfig) { $builderConfig.Network.AddressSpace } elseif ($GlobalLabConfig.Network.AddressSpace) { $GlobalLabConfig.Network.AddressSpace } else { '' }
$networkGateway = if ($builderConfig) { $builderConfig.Network.Gateway } elseif ($GlobalLabConfig.Network.GatewayIp) { $GlobalLabConfig.Network.GatewayIp } else { '' }
$networkSwitch = if ($builderConfig) { $builderConfig.Network.SwitchName } elseif ($GlobalLabConfig.Network.SwitchName) { $GlobalLabConfig.Network.SwitchName } else { '' }
$networkNat = if ($builderConfig) { $builderConfig.Network.NatName } elseif ($GlobalLabConfig.Network.NatName) { $GlobalLabConfig.Network.NatName } else { '' }

$jsonPath = Join-Path $OutputRoot ("AssetReport-{0}.json" -f $timestamp)
$csvPath = Join-Path $OutputRoot ("AssetReport-{0}.csv" -f $timestamp)
$mdPath = Join-Path $OutputRoot ("AssetReport-{0}.md" -f $timestamp)
$mmdPath = Join-Path $OutputRoot ("AssetReport-{0}.mmd" -f $timestamp)

$summary = [pscustomobject]@{
    GeneratedAt = (Get-Date).ToString('o')
    LabName = if ($builderConfig) { $builderConfig.LabName } elseif ($GlobalLabConfig.Lab.Name) { $GlobalLabConfig.Lab.Name } else { 'AutomatedLab' }
    DomainName = if ($builderConfig) { $builderConfig.DomainName } elseif ($GlobalLabConfig.Lab.DomainName) { $GlobalLabConfig.Lab.DomainName } else { '' }
    Network = [pscustomobject]@{
        SwitchName = $networkSwitch
        AddressSpace = $networkAddress
        Gateway = $networkGateway
        NatName = $networkNat
    }
    Assets = $assetRows
}

$summary | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8
$assetRows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

$diagramLines = @()
$diagramLines += 'graph TD'
$diagramLines += ("    NET[{0}<br/>{1}]" -f $networkSwitch, $networkAddress)
$diagramLines += ("    GW[{0}]" -f $networkGateway)
$diagramLines += '    GW --> NET'
foreach ($row in $assetRows) {
    $ip = if ([string]::IsNullOrWhiteSpace($row.LiveIP)) { $row.PlannedIP } else { $row.LiveIP }
    $vlanText = if ([string]::IsNullOrWhiteSpace($row.VlanId)) { $row.VlanMode } else { "$($row.VlanMode) $($row.VlanId)" }
    $safeName = ($row.VMName -replace '[^A-Za-z0-9_]', '_')
    $diagramLines += ("    {0}[{1}<br/>{2}<br/>{3}]" -f $safeName, $row.VMName, $ip, $row.Roles)
    $diagramLines += ("    NET -->|{0}| {1}" -f $vlanText, $safeName)
}

$diagram = $diagramLines -join "`n"
$diagram | Set-Content -Path $mmdPath -Encoding UTF8

$tableLines = @()
$tableLines += '| VM | Roles | State | Planned IP | Live IP | Switch | VLAN | CPU | MemoryGB |'
$tableLines += '|---|---|---|---|---|---|---|---:|---:|'
foreach ($row in $assetRows | Sort-Object VMName) {
    $vlanCell = if ([string]::IsNullOrWhiteSpace($row.VlanId)) { $row.VlanMode } else { "$($row.VlanMode) $($row.VlanId)" }
    $tableLines += ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} |" -f $row.VMName, $row.Roles, $row.State, $row.PlannedIP, $row.LiveIP, $row.Switch, $vlanCell, $row.CPU, $row.MemoryGB)
}

$md = @()
$md += '# Lab Asset Report'
$md += ''
$md += ('Generated: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$md += ''
$md += '## Network Settings'
$md += ''
$md += ('- Lab Name: `{0}`' -f $summary.LabName)
$md += ('- Domain: `{0}`' -f $summary.DomainName)
$md += ('- Switch: `{0}`' -f $networkSwitch)
$md += ('- Address Space: `{0}`' -f $networkAddress)
$md += ('- Gateway: `{0}`' -f $networkGateway)
$md += ('- NAT: `{0}`' -f $networkNat)
$md += ''
$md += '## Assets'
$md += ''
$md += $tableLines
$md += ''
$md += '## VLAN Settings'
$md += ''
$md += '| VM | Switch | VLAN Mode | VLAN ID |'
$md += '|---|---|---|---|'
foreach ($v in $vlanRows | Sort-Object VMName) {
    $md += ("| {0} | {1} | {2} | {3} |" -f $v.VMName, $v.Switch, $v.VlanMode, $v.VlanId)
}
$md += ''
$md += '## Network Diagram (Mermaid)'
$md += ''
$md += '```mermaid'
$md += $diagram
$md += '```'

$md -join "`n" | Set-Content -Path $mdPath -Encoding UTF8

$softwareCsvPath = $null
$featureCsvPath = $null
if ($IncludeSoftwareInventory) {
    $softwareCsvPath = Join-Path $OutputRoot ("SoftwareInventory-{0}.csv" -f $timestamp)
    $featureCsvPath = Join-Path $OutputRoot ("FeatureInventory-{0}.csv" -f $timestamp)
    $softwareHeaders = @('Hostname','Roles','Product','Publisher','Version','InstallDate')
    $featureHeaders = @('Hostname','Roles','FeatureName','DisplayName','InstallState')
    Write-InventoryCsv -Path $softwareCsvPath -Rows $softwareRows -Headers $softwareHeaders
    Write-InventoryCsv -Path $featureCsvPath -Rows $featureRows -Headers $featureHeaders
}

Write-Host ''
Write-Host ('[OK] Asset report JSON: {0}' -f $jsonPath) -ForegroundColor Green
Write-Host ('[OK] Asset report CSV:  {0}' -f $csvPath) -ForegroundColor Green
Write-Host ('[OK] Asset report MD:   {0}' -f $mdPath) -ForegroundColor Green
Write-Host ('[OK] Diagram file:      {0}' -f $mmdPath) -ForegroundColor Green

if ($IncludeSoftwareInventory) {
    Write-Host ('[OK] Software CSV: {0}' -f $softwareCsvPath) -ForegroundColor Green
    Write-Host ('[OK] Feature CSV:  {0}' -f $featureCsvPath) -ForegroundColor Green
}

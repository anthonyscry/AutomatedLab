function Invoke-DeployPreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LabName,
        [Parameter(Mandatory = $true)]
        [string]$VMsJsonFile,
        [Parameter(Mandatory = $true)]
        [array]$Subnets,
        [Parameter(Mandatory = $true)]
        [bool]$EnableExternalInternetSwitch,
        [Parameter(Mandatory = $true)]
        [string]$ExternalSwitchName
    )

    Write-DeployProgress -Percent 1 -Status 'Loading VM configuration...'

    if (-not (Test-Path $VMsJsonFile)) {
        throw "VM configuration file not found: $VMsJsonFile"
    }
    $vms = Get-Content $VMsJsonFile -Raw | ConvertFrom-Json

    if (-not $vms -or $vms.Count -eq 0) {
        throw 'No VMs defined in configuration file'
    }

    Write-DeployProgress -Percent 2 -Status 'Importing modules...'

    Import-Module AutomatedLab -ErrorAction Stop
    Import-Module Hyper-V -ErrorAction SilentlyContinue
    Write-Host '  AutomatedLab loaded' -ForegroundColor Green

    Write-DeployProgress -Percent 3 -Status 'Validating ISO files and OS images...'

    $isoDir = 'C:\LabSources\ISOs'
    $isos = Get-ChildItem $isoDir -Filter '*.iso' -ErrorAction SilentlyContinue
    if ($isos) {
        foreach ($iso in $isos) {
            Write-Host "  ISO: $($iso.Name) ($([math]::Round($iso.Length/1GB, 1))GB)" -ForegroundColor Cyan
        }
    }
    else {
        throw "No ISO files found in $isoDir. Place Windows Server/Client ISOs there."
    }

    Write-DeployProgress -Percent 4 -Status 'Scanning ISOs for available operating systems...'

    New-LabDefinition -Name '__IsoScan' -DefaultVirtualizationEngine HyperV -ErrorAction SilentlyContinue
    $availableOS = Get-LabAvailableOperatingSystem -ErrorAction SilentlyContinue
    Remove-Item 'C:\ProgramData\AutomatedLab\Labs\__IsoScan' -Recurse -Force -ErrorAction SilentlyContinue

    if ($availableOS) {
        Write-Host '  Available OS images:' -ForegroundColor Yellow
        foreach ($osItem in $availableOS) {
            Write-Host "    $($osItem.OperatingSystemName)" -ForegroundColor Cyan
        }

        $defaultOS = 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)'
        $osNameMap = @{
            'Client' = 'Windows 11 Enterprise Evaluation'
        }
        $availableOSNames = @($availableOS | ForEach-Object { $_.OperatingSystemName })

        $osErrors = @()
        foreach ($vm in $vms) {
            $requestedOS = if ($osNameMap.ContainsKey($vm.Role)) { $osNameMap[$vm.Role] } else { $defaultOS }
            $match = $availableOSNames | Where-Object { $_ -eq $requestedOS }
            if ($match) {
                Write-Host "    $($vm.Name) ($($vm.Role)): '$requestedOS' -> FOUND" -ForegroundColor Green
            }
            else {
                Write-Host "    $($vm.Name) ($($vm.Role)): '$requestedOS' -> NOT FOUND" -ForegroundColor Red
                $fuzzy = $availableOSNames | Where-Object { $_ -like "*$($requestedOS.Split(' ')[0..2] -join ' ')*" }
                if ($fuzzy) {
                    Write-Host "      Did you mean: $($fuzzy -join ', ')?" -ForegroundColor Yellow
                }
                $osErrors += "$($vm.Name): requested '$requestedOS' not found in ISOs"
            }
        }

        if ($osErrors.Count -gt 0) {
            throw "OS name mismatch - the following VMs request OS images not found in ISOs:`n$($osErrors -join "`n")`n`nAvailable OS images:`n$($availableOSNames -join "`n")`n`nEnsure your ISOs contain the correct Windows editions."
        }
    }
    else {
        Write-Host "  WARNING: Could not scan OS images. AutomatedLab may fail if ISOs don't match." -ForegroundColor Red
    }

    if ($EnableExternalInternetSwitch) {
        $externalSwitch = Get-VMSwitch -Name $ExternalSwitchName -ErrorAction SilentlyContinue
        if (-not $externalSwitch) {
            throw "External internet switch '$ExternalSwitchName' was not found. Create it first in Hyper-V Manager."
        }

        if ($externalSwitch.SwitchType -ne 'External') {
            throw "Switch '$ExternalSwitchName' exists but is '$($externalSwitch.SwitchType)'. External internet mode requires an External switch."
        }

        Write-Host "  External internet switch: $ExternalSwitchName (External)" -ForegroundColor Cyan
    }

    Write-DeployProgress -Percent 5 -Status 'Pre-flight checks passed'
    Write-DeployEvent -Type 'preflight.complete' -Status 'ok' -Message 'Preflight checks passed' -Properties @{ vmCount = $vms.Count }

    return @{
        VMs     = @($vms)
        Subnets = @($Subnets)
    }
}

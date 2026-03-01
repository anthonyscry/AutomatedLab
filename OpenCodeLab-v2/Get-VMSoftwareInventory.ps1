[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$VMName,

    [string]$LabName,

    [System.Management.Automation.PSCredential]$Credential,

    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

function New-InventoryResult {
    param(
        [string]$VMName,
        [string]$VMState = 'Unknown',
        [object[]]$Software = @(),
        [bool]$Success = $false,
        [string]$ErrorMessage = $null
    )
    [PSCustomObject]@{
        VMName       = $VMName
        VMState      = $VMState
        Software     = @($Software)
        ScannedAt    = (Get-Date).ToUniversalTime().ToString('o')
        Success      = $Success
        ErrorMessage = $ErrorMessage
    }
}

try {
    $vm = Get-VM -Name $VMName -ErrorAction Stop
    $vmState = $vm.State.ToString()

    if ($vm.State -ne 'Running') {
        $result = New-InventoryResult -VMName $VMName -VMState $vmState -ErrorMessage "VM is not running (state: $vmState)"
        if ($PassThru) { return $result }
        $result | ConvertTo-Json -Depth 5
        return
    }

    $queryBlock = {
        $paths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        $software = foreach ($path in $paths) {
            Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne '' } |
                Select-Object @{N='Name';E={$_.DisplayName.Trim()}},
                              @{N='Version';E={$_.DisplayVersion}},
                              @{N='Publisher';E={$_.Publisher}},
                              @{N='InstallDate';E={$_.InstallDate}}
        }
        $software | Group-Object { "$($_.Name)|$($_.Version)" } | ForEach-Object { $_.Group[0] } | Sort-Object Name
    }

    $commandResult = $null
    $useLabCommand = $false

    # Try AutomatedLab first if LabName is provided
    if ($LabName -and $LabName.Trim() -ne '') {
        try {
            Import-Lab -Name $LabName -NoValidation -ErrorAction Stop

            $commandRetries = 4
            $retryDelaySeconds = 10
            for ($attempt = 1; $attempt -le $commandRetries; $attempt++) {
                try {
                    $commandResult = @(Invoke-LabCommand -ComputerName $VMName -ScriptBlock $queryBlock -PassThru -ErrorAction Stop)
                    $useLabCommand = $true
                    break
                }
                catch {
                    if ($_.Exception.Message -match 'port is closed|WinRM|Access is denied') {
                        if ($attempt -lt $commandRetries) {
                            Start-Sleep -Seconds $retryDelaySeconds
                            continue
                        }
                    }
                    throw
                }
            }
        }
        catch {
            Write-Verbose "AutomatedLab failed: $($_.Exception.Message). Falling back to PowerShell Direct."
            $useLabCommand = $false
        }
    }

    # Fall back to PowerShell Direct
    if (-not $useLabCommand) {
        if (-not $Credential) {
            $result = New-InventoryResult -VMName $VMName -VMState $vmState -ErrorMessage 'Credentials required for PowerShell Direct (AutomatedLab not available)'
            if ($PassThru) { return $result }
            $result | ConvertTo-Json -Depth 5
            return
        }

        $commandRetries = 4
        $retryDelaySeconds = 10
        for ($attempt = 1; $attempt -le $commandRetries; $attempt++) {
            try {
                $commandResult = @(Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock $queryBlock -ErrorAction Stop)
                break
            }
            catch {
                if ($_.Exception.Message -match 'port is closed|WinRM|Access is denied|Hyper-V') {
                    if ($attempt -lt $commandRetries) {
                        Start-Sleep -Seconds $retryDelaySeconds
                        continue
                    }
                }
                # Check for unsupported OS (Linux VMs won't have registry)
                if ($_.Exception.Message -match 'registry|not recognized|Cannot find path.*HKLM') {
                    $result = New-InventoryResult -VMName $VMName -VMState $vmState -ErrorMessage 'Unsupported OS - registry not available'
                    if ($PassThru) { return $result }
                    $result | ConvertTo-Json -Depth 5
                    return
                }
                throw
            }
        }
    }

    # Process results
    if ($null -eq $commandResult -or $commandResult.Count -eq 0) {
        $result = New-InventoryResult -VMName $VMName -VMState $vmState -ErrorMessage 'Unsupported OS - registry not available'
        if ($PassThru) { return $result }
        $result | ConvertTo-Json -Depth 5
        return
    }

    $softwareList = @($commandResult | ForEach-Object {
        [PSCustomObject]@{
            Name        = if ($_.Name) { $_.Name } else { '' }
            Version     = if ($_.Version) { $_.Version } else { '' }
            Publisher   = if ($_.Publisher) { $_.Publisher } else { '' }
            InstallDate = if ($_.InstallDate) { $_.InstallDate } else { $null }
        }
    })

    $result = New-InventoryResult -VMName $VMName -VMState $vmState -Software $softwareList -Success $true
    if ($PassThru) { return $result }
    $result | ConvertTo-Json -Depth 5
}
catch {
    $errorVmState = if ($vmState) { $vmState } else { 'Unknown' }
    $result = New-InventoryResult -VMName $VMName -VMState $errorVmState -ErrorMessage $_.Exception.Message
    if ($PassThru) { return $result }
    $result | ConvertTo-Json -Depth 5
}

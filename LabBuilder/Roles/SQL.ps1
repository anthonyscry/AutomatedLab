function Get-LabRole_SQL {
    <#
    .SYNOPSIS
        Returns the SQL Server role definition for LabBuilder.
    .DESCRIPTION
        Uses AutomatedLab's built-in SQLServer2019 role for lean deployment.
        Optional post-install step applies SQL login mode + SA password.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $sqlSettings = if ($Config.ContainsKey('SQL') -and $Config.SQL) { $Config.SQL } else { @{} }
    $instanceName = if ($sqlSettings.ContainsKey('InstanceName') -and -not [string]::IsNullOrWhiteSpace([string]$sqlSettings.InstanceName)) { [string]$sqlSettings.InstanceName } else { 'MSSQLSERVER' }
    $features = if ($sqlSettings.ContainsKey('Features') -and -not [string]::IsNullOrWhiteSpace([string]$sqlSettings.Features)) { [string]$sqlSettings.Features } else { 'SQLENGINE' }
    $saPassword = if ($sqlSettings.ContainsKey('SaPassword') -and -not [string]::IsNullOrWhiteSpace([string]$sqlSettings.SaPassword)) { [string]$sqlSettings.SaPassword } else { '' }

    $netbios = ($Config.DomainName -split '\.')[0].ToUpperInvariant()
    $sqlRoleProperties = @{
        Features = $features
        InstanceName = $instanceName
        SQLSysAdminAccounts = @("$netbios\$($Config.CredentialUser)")
    }

    if ($sqlSettings.ContainsKey('Collation') -and -not [string]::IsNullOrWhiteSpace([string]$sqlSettings.Collation)) {
        $sqlRoleProperties['Collation'] = [string]$sqlSettings.Collation
    }

    $sqlRole = Get-LabMachineRoleDefinition -Role SQLServer2019 -Properties $sqlRoleProperties

    return @{
        Tag        = 'SQL'
        VMName     = $Config.VMNames.SQL
        Roles      = @($sqlRole)
        OS         = $Config.ServerOS
        IP         = $Config.IPPlan.SQL
        Gateway    = $Config.Network.Gateway
        DnsServer1 = $Config.IPPlan.DC
        Memory     = $Config.ServerVM.Memory
        MinMemory  = $Config.ServerVM.MinMemory
        MaxMemory  = $Config.ServerVM.MaxMemory
        Processors = $Config.ServerVM.Processors
        DomainName = $Config.DomainName
        Network    = $Config.Network.SwitchName

        PostInstall = {
            param([hashtable]$LabConfig)

            $sqlConfig = if ($LabConfig.ContainsKey('SQL') -and $LabConfig.SQL) { $LabConfig.SQL } else { @{} }
            $instanceName = if ($sqlConfig.ContainsKey('InstanceName') -and -not [string]::IsNullOrWhiteSpace([string]$sqlConfig.InstanceName)) { [string]$sqlConfig.InstanceName } else { 'MSSQLSERVER' }
            $saPassword = if ($sqlConfig.ContainsKey('SaPassword') -and -not [string]::IsNullOrWhiteSpace([string]$sqlConfig.SaPassword)) { [string]$sqlConfig.SaPassword } else { '' }

            if ([string]::IsNullOrWhiteSpace($saPassword)) {
                Write-Host '    [OK] SQL installed. SA password was not configured (empty value).' -ForegroundColor Green
                return
            }

            $serviceName = if ($instanceName -ieq 'MSSQLSERVER') { 'MSSQLSERVER' } else { "MSSQL`$$instanceName" }

            Invoke-LabCommand -ComputerName $LabConfig.VMNames.SQL -ActivityName 'SQL-Apply-SA-Password' -ScriptBlock {
                param(
                    [string]$InstanceName,
                    [string]$SaPassword,
                    [string]$ServiceName
                )

                $sqlcmdPath = (Get-Command sqlcmd.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
                if ([string]::IsNullOrWhiteSpace($sqlcmdPath)) {
                    Write-Warning 'sqlcmd.exe not found. Skipping SA password configuration.'
                    return
                }

                $targetInstance = if ($InstanceName -ieq 'MSSQLSERVER') { '.' } else { ".\$InstanceName" }
                $escapedPassword = $SaPassword -replace "'", "''"

                $query = @"
EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\\Microsoft\\MSSQLServer\\MSSQLServer', N'LoginMode', REG_DWORD, 2;
ALTER LOGIN [sa] ENABLE;
ALTER LOGIN [sa] WITH PASSWORD = '$escapedPassword';
"@

                & $sqlcmdPath -S $targetInstance -E -b -Q $query
                if ($LASTEXITCODE -ne 0) {
                    throw "sqlcmd exited with code $LASTEXITCODE while applying SA password."
                }

                Restart-Service -Name $ServiceName -ErrorAction SilentlyContinue
                Write-Host "    [OK] SQL mixed mode + SA password applied for $targetInstance." -ForegroundColor Green
            } -ArgumentList $instanceName, $saPassword, $serviceName -Retries 1 -RetryIntervalInSeconds 20
        }
    }
}

# Phase 5 Research: Domain Configuration

## Overview

Phase 5 focuses on automating Active Directory domain deployment in the SimpleLab environment. This includes promoting the SimpleDC VM to a domain controller, configuring DNS, and joining member servers to the domain.

## Key Concepts

### Active Directory Domain Services (AD DS)

- Domain promotion converts a standalone Windows Server into a domain controller
- Creates new forest with specified domain name (e.g., "simplelab.local")
- Installs DNS Server role automatically
- Requires reboot after promotion

### PowerShell Commands for Domain Promotion

**Install-ADDSForest** (New Forest):
```powershell
Install-ADDSForest -DomainName "simplelab.local" `
    -InstallDns:$true `
    -SafeModeAdministratorPassword (ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force) `
    -Force:$true `
    -NoRebootOnCompletion:$false
```

**Parameters:**
- `-DomainName`: FQDN for the new domain
- `-InstallDns`: Install DNS Server role (default: true)
- `-SafeModeAdministratorPassword`: Directory Services Restore Mode (DSRM) password
- `-Force`: Suppress confirmation prompts
- `-NoRebootOnCompletion`: Control reboot behavior (false = auto-reboot)

### Domain Join Commands

**Add-Computer** (Join Domain):
```powershell
Add-Computer -DomainName "simplelab.local" `
    -Credential (Get-Credential "simplelab\Administrator") `
    -Restart:$true
```

**Parameters:**
- `-DomainName`: Domain to join
- `-Credential`: Domain admin credentials
- `-Restart`: Reboot after joining
- `-NewName`: Optional new computer name

### DNS Configuration

DNS is automatically installed during DC promotion, but additional configuration may be needed:

- Set DNS forwarders for Internet resolution
- Configure reverse lookup zones
- Verify DNS functionality with `Test-DnsDnsServer`

### PowerShell Direct for In-VM Commands

Since SimpleLab uses PowerShell Direct for VM configuration:

```powershell
Invoke-Command -VMName "SimpleDC" -ScriptBlock {
    Install-ADDSForest -DomainName "simplelab.local" -InstallDns:$true -Force:$true
}
```

## Best Practices

### Domain Naming

- Use `.local` for lab environments (not routable on Internet)
- Keep domain name short and memorable
- Avoid using existing domain names

### Password Security

- Use consistent lab passwords (e.g., "SimpleLab123!")
- Store in environment variables for automation
- Document in SECRETS files (not in code)

### Reboot Handling

- DC promotion requires reboot
- Domain join requires reboot
- Use `-NoRebootOnCompletion:$false` for automatic reboot
- Wait for VM to come back online before next operations

### Error Handling

- Domain promotion can fail (duplicate IP, network issues)
- Domain join can fail (DC not reachable, credentials wrong)
- Test for AD services availability before proceeding

## Related Commands

**Test-ADDSForestInstallation** - Validate prerequisites before promotion:
```powershell
Test-ADDSForestInstallation -DomainName "simplelab.local"
```

**Get-Service** - Check AD DS service status:
```powershell
Get-Service -Name NTDS -ComputerName "SimpleDC"
```

**Get-ADDomain** - Verify domain exists:
```powershell
Get-ADDomain -Identity "simplelab.local"
```

## Automation Pattern

1. **Wait for VM to be running** - `Get-VM` check Heartbeat
2. **Test promotion prerequisites** - `Test-ADDSForestInstallation`
3. **Promote to DC** - `Install-ADDSForest` via PowerShell Direct
4. **Wait for reboot** - Poll until VM is back online
5. **Verify DC is functional** - Test AD services, DNS
6. **Proceed to next operations** (domain join)

## Configuration Options

### Domain Name

Default: `simplelab.local`

Can be configured via `config.json`:
```json
{
  "DomainConfiguration": {
    "DomainName": "simplelab.local",
    "NetBIOSName": "SIMPLELAB"
  }
}
```

### Credentials

- Domain Administrator: built-in "Administrator" account
- DS Restore Mode: configured during promotion

## References

- [Install-ADDSForest Documentation](https://learn.microsoft.com/en-us/powershell/module/addsdeployment/install-addsforest)
- [Add-Computer Documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/add-computer)
- [Active Directory Domain Services Overview](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/get-started/virtual-dc/active-directory-domain-services-overview)

## Success Criteria

1. DC promotes to "simplelab.local" domain controller
2. DNS service is running and resolving on domain controller
3. Member servers can be joined to the domain
4. Domain is functional after single build command completes

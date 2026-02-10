# Phase 5 Plan 03 Summary: Domain Join Automation

**Date:** 2026-02-09
**Status:** Completed
**Wave:** 1

## Overview

Automated domain join for member servers. Created functions to join SimpleServer and SimpleWin11 VMs to the simplelab.local domain using PowerShell Direct, handling credentials, reboots, and verification.

## Files Created

### SimpleLab/Private/Test-LabDomainJoin.ps1
- **Lines:** 227
- **Purpose:** Domain membership validation via PowerShell Direct
- **Parameters:** VMName (required), DomainName (optional), Credential (optional)
- **Returns:** PSCustomObject with comprehensive domain membership status

**Validation Checks:**
1. VM exists and is running
2. VM domain membership (Win32_ComputerSystem)
3. Domain trust channel (Test-ComputerSecureChannel)
4. Domain controller reachability

**Status Values:**
- Joined: VM is in domain with valid trust
- NoTrust: VM is joined but trust is failing
- NotJoined: VM is not in the target domain
- NotRunning: VM is not running
- NotFound: VM doesn't exist
- Error: PowerShell Direct connection failed

### SimpleLab/Public/Join-LabDomain.ps1
- **Lines:** 259
- **Purpose:** Domain join orchestrator for multiple VMs
- **Parameters:**
  - VMNames (string array, default: SimpleServer, SimpleWin11)
  - DomainName (string, optional)
  - Credential (pscredential, prompts if not provided)
  - OUPath (string, optional - for computer account placement)
  - Force (switch, rejoin if already in domain)
  - WaitTimeoutMinutes (int, default: 10)
- **Returns:** PSCustomObject with VMsJoined hashtable, FailedVMs, SkippedVMs, OverallStatus, Message, Duration

**Workflow Steps per VM:**
1. Verify VM exists and is running
2. Test if already joined to domain (skip if not Force)
3. Execute domain join via Add-Computer with -Restart
4. Wait for reboot to start (VM state goes to Off)
5. Wait for VM to return online (Running + Heartbeat Ok)
6. Verify domain membership with Test-LabDomainJoin

**Status Values:**
- OK: All VMs joined successfully
- Partial: Some VMs joined, some failed
- Failed: No VMs joined successfully

## Module Changes

### SimpleLab.psd1
- Updated module version to 0.5.0
- Added Join-LabDomain to FunctionsToExport

### SimpleLab.psm1
- Added Join-LabDomain to Export-ModuleMember

## Implementation Details

### Credential Handling

The function handles domain administrator credentials securely:
- Prompts via `Get-Credential` if not provided
- Accepts pscredential object for automation scenarios
- Creates default credential from config password if needed
- Passes credential securely to PowerShell Direct

### PowerShell Direct Usage

All domain operations use PowerShell Direct:
- Test-LabDomainJoin queries Win32_ComputerSystem for domain status
- Test-LabDomainJoin uses Test-ComputerSecureChannel for trust verification
- Join-LabDomain uses Add-Computer to join domain
- Credentials passed via -ArgumentList parameter

### Reboot Handling

The function implements robust reboot detection:
1. Waits for VM state to change to "Off" (reboot start)
2. Waits for VM to return to "Running" state
3. Waits for heartbeat to return to "Ok"
4. Waits additional 30 seconds for services to stabilize
5. Verifies domain membership after return online

### Multi-VM Orchestration

Processes VMs in order (servers before clients):
- Default VM order: SimpleServer, SimpleWin11
- Per-VM result tracking in VMsJoined hashtable
- Continues on individual VM failures
- OverallStatus reflects complete picture

## Configuration

### Default Domain

Default domain name is "simplelab.local" from Get-LabDomainConfig.

### Custom Domain

Users can specify a different domain:
```powershell
Join-LabDomain -DomainName "corp.local"
```

### Organizational Unit

Users can place computer accounts in specific OUs:
```powershell
Join-LabDomain -OUPath "OU=Servers,DC=simplelab,DC=local"
```

## Success Criteria Met

1. ✅ Tool joins member VMs to the simplelab.local domain
2. ✅ Tool handles domain join credentials securely with prompting (Get-Credential)
3. ✅ Tool reboots VMs after joining automatically (Add-Computer -Restart)
4. ✅ Tool verifies domain membership after reboot (Test-LabDomainJoin)
5. ✅ Single command (Join-LabDomain) joins all member servers

## Module Statistics

**SimpleLab v0.5.0 now includes:**
- 21 exported public functions (+1)
- 20 internal helper functions (+1)
- 5 Domain-related functions (3 public, 2 private)

## Deviations from Plan

**None.** Implementation exactly matches plan specification.

## Usage Examples

```powershell
# Join all member servers (will prompt for credentials)
Join-LabDomain

# Join specific VMs
Join-LabDomain -VMNames @("SimpleServer")

# Force rejoin if already in domain
Join-LabDomain -Force

# Join with custom credentials (for automation)
$cred = Get-Credential "simplelab\Administrator"
Join-LabDomain -Credential $cred

# Join to specific OU
Join-LabDomain -OUPath "OU=Servers,DC=simplelab,DC=local"

# Check if VM is joined to domain
Test-LabDomainJoin -VMName "SimpleServer"
```

## Complete Lab Setup Flow

With Phase 5 Plans 1-3 complete, users can now:

```powershell
# 1. Create VMs
Initialize-LabVMs

# 2. Start VMs
Start-LabVMs

# 3. Promote DC
Initialize-LabDomain

# 4. Configure DNS
Initialize-LabDNS

# 5. Join member servers
Join-LabDomain

# 6. Verify lab status
Get-LabStatus
```

## Next Steps

Proceed to **Phase 5 Plan 4: Domain Health Validation** which will include:
- Comprehensive domain health check function
- AD service validation
- Domain controller availability tests
- Lab-wide domain status reporting

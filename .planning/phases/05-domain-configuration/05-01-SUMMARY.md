# Phase 5 Plan 01 Summary: DC Promotion Automation

**Date:** 2026-02-09
**Status:** Completed
**Wave:** 1

## Overview

Automated domain controller promotion and Active Directory deployment. Created functions to promote SimpleDC VM to a domain controller with DNS services, establishing the "simplelab.local" forest.

## Files Created

### SimpleLab/Private/Get-LabDomainConfig.ps1
- **Lines:** 66
- **Purpose:** Domain configuration retrieval with defaults and config.json override
- **Parameters:** None (reads from config)
- **Returns:** PSCustomObject with DomainName, NetBIOSName, SafeModePassword, DnsServerAddress

**Default Configuration:**
- DomainName: "simplelab.local"
- NetBIOSName: "SIMPLELAB"
- SafeModePassword: "SimpleLab123!"
- DnsServerAddress: DC IP from network config

### SimpleLab/Private/Test-DCPromotionPrereqs.ps1
- **Lines:** 201
- **Purpose:** Validate DC promotion prerequisites via PowerShell Direct
- **Parameters:** VMName (default: "SimpleDC")
- **Returns:** PSCustomObject with VMName, CanPromote (bool), Status, Message, Checks array

**Validation Checks:**
1. Hyper-V module available
2. VM exists and is running
3. VM heartbeat is "Ok" (responsive)
4. ADDSDeployment module available inside VM
5. Network connectivity (basic test)

**Status Values:**
- Ready: All checks passed
- NotFound: VM doesn't exist
- NotRunning: VM not in Running state
- NoHeartbeat: VM not responsive
- MissingModule: ADDSDeployment not available
- NoNetwork: No network connectivity
- PowerShellDirectFailed: Cannot connect to VM

### SimpleLab/Public/Initialize-LabDomain.ps1
- **Lines:** 237
- **Purpose:** DC promotion orchestrator with complete workflow automation
- **Parameters:**
  - VMName (string, default: "SimpleDC")
  - SafeModePassword (securestring, optional)
  - DomainName (string, optional)
  - Force (switch, suppress confirmations)
  - WaitTimeoutMinutes (int, default: 15)
- **Returns:** PSCustomObject with VMName, Promoted (bool), Status, Message, Duration

**Workflow Steps:**
1. Get domain configuration
2. Test prerequisites
3. Check if already a DC
4. Execute promotion via Install-ADDSForest
5. Wait for reboot to start
6. Wait for VM to return online
7. Verify domain controller functionality

**Status Values:**
- OK: Promotion successful
- AlreadyDC: VM already a domain controller
- Failed: Promotion failed
- Timeout: VM didn't return online
- RebootTimeout: VM didn't start reboot
- VerificationFailed: Promotion succeeded but verification failed

## Module Changes

### SimpleLab.psd1
- Updated module version to 0.3.0
- Added Initialize-LabDomain to FunctionsToExport

### SimpleLab.psm1
- Added Initialize-LabDomain to Export-ModuleMember

## Implementation Details

### PowerShell Direct Usage

All in-VM operations use PowerShell Direct (`Invoke-Command -VMName`):
- Prerequisite validation
- ADDSDeployment module availability check
- Domain promotion execution
- Post-promotion verification

### Reboot Handling

The function implements sophisticated reboot detection:
1. Waits for VM state to change to "Off" (reboot start)
2. Waits for VM to return to "Running" state
3. Waits for heartbeat to return to "Ok"
4. Waits additional 30 seconds for AD services to stabilize
5. Verifies NTDS and DNS services are running

### Error Handling

- Per-step error handling with clear status messages
- "Already a DC" detection prevents duplicate promotion
- Timeout handling for long-running operations
- Graceful degradation for non-critical failures

## Configuration

### config.json Extension

Users can add DomainConfiguration section:

```json
{
  "DomainConfiguration": {
    "DomainName": "simplelab.local",
    "NetBIOSName": "SIMPLELAB",
    "SafeModePassword": "YourSecurePassword123!"
  }
}
```

### Environment Variable Override

Password can also be set via environment variable:

```powershell
$env:SIMPLELAB_SAFE_MODE_PASSWORD = "YourSecurePassword123!"
Initialize-LabDomain
```

## Success Criteria Met

1. ✅ Tool promotes SimpleDC VM to domain controller with "simplelab.local" domain
2. ✅ Tool installs DNS Server role during promotion automatically (Install-ADDSForest -InstallDns)
3. ✅ Tool reboots VM after promotion and waits for return online
4. ✅ Tool verifies domain controller is functional (Get-ADDomain check)
5. ✅ Single command (Initialize-LabDomain) performs complete DC promotion

## Module Statistics

**SimpleLab v0.3.0 now includes:**
- 18 exported public functions (+1)
- 17 internal helper functions (+2)
- 3 new domain-related functions

## Deviations from Plan

**None.** Implementation exactly matches plan specification.

## Next Steps

Proceed to **Phase 5 Plan 2: DNS Configuration** which will include:
- Configure DNS forwarders for Internet resolution
- Set up reverse lookup zones
- Validate DNS functionality
- Create Test-LabDNS function for DNS health checks

---
phase: 03-network-infrastructure
plan: 02
subsystem: networking
tags: [hyper-v, powershell-direct, static-ip, ip-configuration]

# Dependency graph
requires:
  - phase: 03-network-infrastructure/03-01
    provides: vSwitch creation (New-LabSwitch), vSwitch detection (Test-LabNetwork)
provides:
  - Get-LabNetworkConfig function for network configuration retrieval from config.json
  - Set-VMStaticIP function for in-VM IP configuration via PowerShell Direct
  - Initialize-LabNetwork orchestrator for multi-VM IP configuration
  - NetworkConfiguration section in config.json with IP assignments
affects: [03-03-network-configuration, 05-domain-configuration]

# Tech tracking
tech-stack:
  added: [PowerShell Direct (Invoke-Command -VMName), New-NetIPAddress, Set-DnsClientServerAddress, Get-NetAdapter]
  patterns: [orchestrator pattern with structured results, PSCustomObject status reporting, hashtable-based VM tracking]

key-files:
  created: [SimpleLab/Private/Get-LabNetworkConfig.ps1, SimpleLab/Private/Set-VMStaticIP.ps1, SimpleLab/Public/Initialize-LabNetwork.ps1]
  modified: [SimpleLab/SimpleLab.psm1, SimpleLab/SimpleLab.psd1, .planning/config.json]

key-decisions:
  - "Updated both PSM1 and PSD1 files for proper module exports (Rule 2 fix from 03-01)"
  - "Used PowerShell Direct (Invoke-Command -VMName) for in-VM configuration without network connectivity"

patterns-established:
  - "Pattern: Orchestrator functions track per-VM results in hashtables with OverallStatus aggregation"
  - "Pattern: Internal helper functions in Private/ use Get-LabConfig for configuration retrieval"

# Metrics
duration: 1min
completed: 2026-02-10
---

# Phase 03 Plan 02: Configure Static IP Addresses for Lab VMs Summary

**Get-LabNetworkConfig, Set-VMStaticIP, and Initialize-LabNetwork functions for configuring static IP addresses (DC: 10.0.0.1, Server: 10.0.0.2, Win11: 10.0.0.3) using PowerShell Direct with persistent configuration storage**

## Performance

- **Duration:** 1 min
- **Started:** 2026-02-10T00:20:51Z
- **Completed:** 2026-02-10T00:22:21Z
- **Tasks:** 5
- **Files modified:** 6

## Accomplishments

- Created Get-LabNetworkConfig internal helper function for network configuration retrieval from config.json
- Created Set-VMStaticIP function using PowerShell Direct for in-VM IP configuration without network requirements
- Created Initialize-LabNetwork orchestrator for multi-VM IP configuration with structured result tracking
- Added NetworkConfiguration section to config.json with IP assignments for all lab VMs
- Updated module exports in both PSM1 and PSD1 files

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Get-LabNetworkConfig helper for network configuration** - `a8f3ab6` (feat)
2. **Task 2: Create Set-VMStaticIP function for in-VM IP configuration** - `1b7c64d` (feat)
3. **Task 3: Create Initialize-LabNetwork orchestrator and update config** - `a9ed594` (feat)
4. **Task 4: Update config.json with NetworkConfiguration section** - `0dd56aa` (feat)
5. **Task 5: Update SimpleLab.psm1 to export Initialize-LabNetwork** - `2caa45e` (feat)

**Plan metadata:** [to be added in final commit]

## Files Created/Modified

### Created

- `SimpleLab/Private/Get-LabNetworkConfig.ps1` - Network configuration retrieval helper
  - Internal function (not exported)
  - Returns PSCustomObject with Subnet, PrefixLength, Gateway, DNSServers properties
  - Includes VMIPs hashtable: SimpleDC=10.0.0.1, SimpleServer=10.0.0.2, SimpleWin11=10.0.0.3
  - Uses Get-LabConfig to read config.json NetworkConfiguration section
  - Provides defaults if NetworkConfiguration not present

- `SimpleLab/Private/Set-VMStaticIP.ps1` - In-VM IP configuration function
  - Internal function (not exported)
  - Parameters: VMName (mandatory), IPAddress (mandatory), PrefixLength (default 24), InterfaceAlias (default Ethernet)
  - Uses PowerShell Direct (Invoke-Command -VMName) for in-VM execution
  - In-VM scriptblock: Get-NetAdapter, New-NetIPAddress, Remove-NetRoute, Set-DnsClientServerAddress
  - Returns PSCustomObject with VMName, IPAddress, Configured, Status, Message
  - Status values: OK, Failed, VMNotFound

- `SimpleLab/Public/Initialize-LabNetwork.ps1` - Network initialization orchestrator
  - Public function (exported)
  - Parameters: VMNames (string array, default: SimpleDC, SimpleServer, SimpleWin11)
  - Uses Get-LabNetworkConfig for IP assignments, calls Set-VMStaticIP for each VM
  - Returns PSCustomObject with VMConfigured (hashtable), FailedVMs (array), OverallStatus, Duration
  - OverallStatus values: OK (all configured), Partial (some failed), Failed (all failed)
  - Provides summary Message with success/failure counts

### Modified

- `SimpleLab/SimpleLab.psm1` - Added 'Initialize-LabNetwork' to Export-ModuleMember (alphabetical order)
- `SimpleLab/SimpleLab.psd1` - Added 'Initialize-LabNetwork' to FunctionsToExport (alphabetical order)
- `.planning/config.json` - Added NetworkConfiguration section with Subnet, PrefixLength, Gateway, DNSServers, VMIPs

## Function Signatures

### Get-LabNetworkConfig (internal)
```powershell
Get-LabNetworkConfig
```
**Returns:** PSCustomObject
- Subnet: string (default "10.0.0.0/24")
- PrefixLength: int (default 24)
- Gateway: string (empty for Internal switch)
- DNSServers: string array (empty initially)
- VMIPs: hashtable (SimpleDC=10.0.0.1, SimpleServer=10.0.0.2, SimpleWin11=10.0.0.3)

### Set-VMStaticIP (internal)
```powershell
Set-VMStaticIP [-VMName] <string> [-IPAddress] <string> [[-PrefixLength] <int>] [[-InterfaceAlias] <string>]
```
**Returns:** PSCustomObject
- VMName: The VM name
- IPAddress: Configured IP address
- Configured: bool (true if successful)
- Status: "OK" | "Failed" | "VMNotFound"
- Message: Description of operation result

### Initialize-LabNetwork (public)
```powershell
Initialize-LabNetwork [[-VMNames] <string[]>]
```
**Returns:** PSCustomObject
- VMConfigured: hashtable mapping VMName to configuration result
- FailedVMs: array of failed VM names
- OverallStatus: "OK" | "Partial" | "Failed"
- Duration: TimeSpan of operation
- Message: Summary of configuration results

## Configuration Schema

```json
{
  "NetworkConfiguration": {
    "Subnet": "10.0.0.0/24",
    "PrefixLength": 24,
    "Gateway": "",
    "DNSServers": [],
    "VMIPs": {
      "SimpleDC": "10.0.0.1",
      "SimpleServer": "10.0.0.2",
      "SimpleWin11": "10.0.0.3"
    }
  }
}
```

## Decisions Made

**Decision 1: Update both PSM1 and PSD1 for proper module exports**
- Following the pattern established in plan 03-01, both the PSM1 Export-ModuleMember and PSD1 FunctionsToExport arrays must be updated for proper module function exports
- This is a standard PowerShell module requirement - both files must stay in sync

**Decision 2: Use PowerShell Direct for in-VM configuration**
- PowerShell Direct (Invoke-Command -VMName) allows configuration inside VMs without network connectivity
- This is essential for isolated lab networks where VMs may not have initial network access
- Works even when VMs are on an Internal vSwitch with no default gateway

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] Updated PSD1 FunctionsToExport**
- **Found during:** Task 5 (Update SimpleLab.psm1 to export Initialize-LabNetwork)
- **Issue:** Plan only specified updating PSM1 Export-ModuleMember, but PSD1 FunctionsToExport also needed updating for proper module function exports
- **Fix:** Updated SimpleLab.psd1 FunctionsToExport array to include 'Initialize-LabNetwork' in alphabetical order
- **Files modified:** SimpleLab/SimpleLab.psd1
- **Verification:** Get-Command -Module SimpleLab shows Initialize-LabNetwork is exported
- **Committed in:** 2caa45e (Task 5 commit)

---

**Total deviations:** 1 auto-fixed (1 missing critical functionality)
**Impact on plan:** Auto-fix necessary for correct module operation. Function would not be properly exported without PSD1 update. No scope creep.

## Issues Encountered

None - all tasks completed successfully without issues.

## Test Results

All functions verified in WSL environment:

1. **Get-LabNetworkConfig** returns correct structure (from defaults, as config.json not loaded in WSL):
   - Subnet: "10.0.0.0/24"
   - PrefixLength: 24
   - Gateway: ""
   - DNSServers: (empty array)
   - VMIPs: hashtable with SimpleDC, SimpleServer, SimpleWin11 entries

2. **Set-VMStaticIP** returns correct structure for non-existent VM:
   - VMName: "TestVM"
   - IPAddress: "10.0.0.1"
   - Configured: false
   - Status: "VMNotFound"
   - Message: "VM 'TestVM' not found"

3. **Initialize-LabNetwork** returns correct structure:
   - VMConfigured: hashtable with VM results
   - FailedVMs: array of failed VM names
   - OverallStatus: "Failed" (expected when VMs don't exist)
   - Duration: TimeSpan
   - Message: Summary of configuration attempts

4. **Module exports** verified:
   - Initialize-LabNetwork (newly exported)
   - New-LabSwitch
   - Test-HyperVEnabled
   - Test-LabIso
   - Test-LabNetwork
   - Test-LabPrereqs
   - Write-RunArtifact
   - Write-ValidationReport

5. **Get-LabNetworkConfig and Set-VMStaticIP are NOT exported** (internal functions verified as required)

6. **config.json** verified to contain NetworkConfiguration section with correct structure

## Self-Check: PASSED

**Files created (in /home/ajt/projects/AutomatedLab):**
- SimpleLab/Private/Get-LabNetworkConfig.ps1 - FOUND
- SimpleLab/Private/Set-VMStaticIP.ps1 - FOUND
- SimpleLab/Public/Initialize-LabNetwork.ps1 - FOUND
- .planning/phases/03-network-infrastructure/03-02-SUMMARY.md - FOUND

**Commits verified:**
- a8f3ab6 - FOUND
- 1b7c64d - FOUND
- a9ed594 - FOUND
- 0dd56aa - FOUND
- 2caa45e - FOUND

**Configuration verified:**
- NetworkConfiguration section in config.json - FOUND

## Next Phase Readiness

- IP configuration functions ready for next phase
- PowerShell Direct pattern established for in-VM operations
- Network configuration stored persistently in config.json
- No blockers or concerns

---
*Phase: 03-network-infrastructure*
*Completed: 2026-02-10*

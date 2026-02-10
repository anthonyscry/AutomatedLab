---
phase: 04-vm-provisioning
plan: 03
title: "VM Startup and Initialization"
one-liner: "Multi-VM orchestrator for complete Windows domain lab provisioning with error aggregation and structured result tracking"
date-completed: 2026-02-10
duration-minutes: 2
tasks-completed: 3
tags: [orchestrator, vm-provisioning, hyper-v, multi-vm]

# Dependency Graph
requires:
  - plan: "04-01"
    provides: "Get-LabVMConfig for VM hardware specifications"
  - plan: "04-02"
    provides: "New-LabVM for single VM creation"
provides:
  - "Initialize-LabVMs orchestrator for complete lab VM creation"
affects:
  - phase: "05-domain-configuration"
    reason: "VMs must be created before domain configuration can begin"

# Tech Stack
added: []
patterns:
  - "Orchestrator pattern with per-VM result aggregation"
  - "Idempotent VM creation with Force parameter"
  - "Structured error handling with OverallStatus enumeration"
  - "VHD path management with automatic directory creation"

# Key Files
created:
  - path: "SimpleLab/Public/Initialize-LabVMs.ps1"
    purpose: "Multi-VM creation orchestrator for complete lab setup"
    lines: 154
    exports: ["Initialize-LabVMs"]
modified:
  - path: "SimpleLab/SimpleLab.psm1"
    changes: "Added Initialize-LabVMs to Export-ModuleMember"
  - path: "SimpleLab/SimpleLab.psd1"
    changes: "Added Initialize-LabVMs to FunctionsToExport"

# Decisions Made
decisions: []

# Deviations
deviations: []
---

# Phase 4 Plan 3: VM Startup and Initialization Summary

## Overview

Created the Initialize-LabVMs orchestrator to enable single-command creation of the complete Windows domain lab. The orchestrator manages the creation of all three VMs (SimpleDC, SimpleServer, SimpleWin11) with appropriate hardware configurations, ISO attachments, and error aggregation for reliable deployment.

## Files Created

### SimpleLab/Public/Initialize-LabVMs.ps1 (154 lines)

**Function signature:**
```powershell
Initialize-LabVMs [-SwitchName <string>] [-VHDBasePath <string>] [-Force]
```

**Return schema:**
```powershell
[PSCustomObject]@{
    OverallStatus = "OK" | "Partial" | "Failed"
    VMsCreated = @{
        "SimpleDC" = [PSCustomObject]@{ VMName, Created, Status, Message, VHDPath, MemoryGB, ProcessorCount }
        "SimpleServer" = [PSCustomObject]@{ ... }
        "SimpleWin11" = [PSCustomObject]@{ ... }
    }
    FailedVMs = @("SimpleDC", ...)  # Array of failed VM names
    Duration = [TimeSpan]
    Message = "Created 3 VM(s), failed 0 VM(s)"
}
```

**Key behaviors:**
- Retrieves VM configurations using Get-LabVMConfig (memory, CPU, disk, generation, ISO)
- Retrieves ISO paths from config.json via Get-LabConfig
- Creates VHDBasePath directory if it doesn't exist
- Orchestrates VM creation in dependency order: DC, Server, Win11
- Passes all VM parameters to New-LabVM for each VM
- Aggregates per-VM results into structured output
- Determines OverallStatus: OK (all), Partial (some), Failed (none)
- Supports Force parameter to recreate existing VMs

## Files Modified

### SimpleLab/SimpleLab.psm1
- Added 'Initialize-LabVMs' to Export-ModuleMember array (alphabetically ordered)

### SimpleLab/SimpleLab.psd1
- Added 'Initialize-LabVMs' to FunctionsToExport array

## Function Integrations

The Initialize-LabVMs orchestrator integrates with existing infrastructure:

1. **Get-LabVMConfig** (Plan 04-01): Retrieves VM hardware specifications
2. **Get-LabConfig** (Phase 2): Retrieves ISO paths from config.json
3. **New-LabVM** (Plan 04-02): Creates each individual VM
4. **SimpleLab vSwitch** (Phase 3): SwitchName parameter for network connectivity

## Verification Results

**Checkpoint verification approved by user.**

The implementation follows the correct patterns established in prior phases:
- Orchestrator pattern from Initialize-LabNetwork.ps1
- Idempotent VM creation with Force parameter
- Structured PSCustomObject results with status enumeration
- Duration measurement using New-TimeSpan
- Error aggregation with OverallStatus determination

Note: Actual VM creation cannot be verified in WSL environment (no Hyper-V), but the code structure and function signatures are correct for Windows PowerShell with Hyper-V module.

## Success Criteria Met

1. **User can run single command to build complete Windows domain lab** - Initialize-LabVMs orchestrates all 3 VMs
2. **Tool creates 3 VMs with appropriate RAM allocation (DC: 2GB, Server: 2GB, Win11: 4GB)** - Via Get-LabVMConfig defaults
3. **Tool attaches ISOs for bootable configuration** - IsoPath parameter passed to New-LabVM
4. **Tool returns structured result showing per-VM creation status** - VMsCreated hashtable with per-VM results
5. **Tool integrates with existing "SimpleLab" vSwitch from Phase 3** - SwitchName parameter (default "SimpleLab")

## Deviations from Plan

None - plan executed exactly as written.

## Next Steps

Phase 4 Plan 04: VM Teardown - Create Remove-LabVMs orchestrator for complete lab teardown

---
phase: 04-vm-provisioning
plan: 02
title: "VM Provisioning Functions"
one-liner: "New-LabVM and Remove-LabVM functions for Hyper-V VM lifecycle management using native Hyper-V cmdlets"
completed-date: 2026-02-10
duration: 2 minutes
---

# Phase 4 Plan 2: VM Provisioning Functions Summary

## Overview

Implemented the core VM lifecycle operations for creating and removing Hyper-V VMs with proper hardware configuration, ISO attachment for bootable installations, and idempotent patterns that prevent duplicate VM creation.

## Files Created

| File | Lines | Purpose |
| ---- | ----- | ------- |
| SimpleLab/Public/New-LabVM.ps1 | 120 | Single VM creation with idempotent pattern |
| SimpleLab/Public/Remove-LabVM.ps1 | 105 | VM removal with resource cleanup |

## Files Modified

| File | Changes |
| ---- | ------- |
| SimpleLab/SimpleLab.psm1 | Added New-LabVM and Remove-LabVM to Export-ModuleMember |
| SimpleLab/SimpleLab.psd1 | Added New-LabVM and Remove-LabVM to FunctionsToExport |

## Function Signatures

### New-LabVM

```powershell
New-LabVM [-VMName] <string> [-MemoryGB] <int> [-VHDPath] <string>
    [[-SwitchName] <string>] [[-IsoPath] <string>] [[-ProcessorCount] <int>]
    [[-Generation] <int>] [-Force] [<CommonParameters>]
```

**Parameters:**
- VMName (string, mandatory) - Name of the VM to create
- MemoryGB (int, mandatory) - Memory allocation in GB
- VHDPath (string, mandatory) - Path for VHDX file
- SwitchName (string, default "SimpleLab") - Virtual switch to connect
- IsoPath (string, optional) - Path to ISO file for bootable installation
- ProcessorCount (int, default 2) - Number of virtual processors
- Generation (int, default 2) - VM generation (1 or 2)
- Force (switch, default false) - Recreate VM if exists

**Return Schema (PSCustomObject):**
```powershell
@{
    VMName = "SimpleDC"
    Created = $true
    Status = "OK"  # OK, AlreadyExists, Failed, ISONotFound
    Message = "VM 'SimpleDC' created successfully"
    VHDPath = "C:\Lab\VMs\SimpleDC.vhdx"
    MemoryGB = 2
    ProcessorCount = 2
}
```

### Remove-LabVM

```powershell
Remove-LabVM [-VMName] <string> [-DeleteVHD] [<CommonParameters>]
```

**Parameters:**
- VMName (string, mandatory) - Name of the VM to remove
- DeleteVHD (switch, default false) - Also delete VHD files

**Return Schema (PSCustomObject):**
```powershell
@{
    VMName = "SimpleDC"
    Removed = $true
    Status = "OK"  # OK, NotFound, Failed
    Message = "VM 'SimpleDC' removed successfully"
    VHDDeleted = $false
}
```

## Key Implementation Details

1. **Idempotent Pattern**: New-LabVM uses Test-LabVM to check for existing VMs before creation
2. **Force Recreation**: When -Force is specified, existing VMs are removed and recreated
3. **Hardware Configuration**: Supports configurable memory, processor count, generation, and 60GB default disk
4. **ISO Attachment**: Validates ISO file existence before attaching with Add-VMDvdDrive
5. **Static Memory**: Disables dynamic memory for consistent lab behavior
6. **Safe Removal**: Stops running VMs before removal using Stop-VM -TurnOff -Force
7. **VHD Cleanup**: Optional VHD deletion with DeleteVHD parameter

## Deviations from Plan

**None** - Plan executed exactly as written.

## Test Results

All verification tests passed:
- New-LabVM returns structured PSCustomObject with all required properties
- Remove-LabVM returns structured PSCustomObject with all required properties
- Both functions handle Hyper-V unavailable scenario gracefully
- Module exports verified: New-LabVM and Remove-LabVM appear in Get-Command output
- Parameters follow PowerShell best practices with proper attributes

## Commits

- a1913d0: feat(04-02): create New-LabVM for single VM creation
- 45cea72: feat(04-02): create Remove-LabVM for VM removal
- 82db3c6: feat(04-02): export New-LabVM and Remove-LabVM from module

## Next Steps

Plan 04-03 will implement VM startup and initialization functions for managing VM power states and initial boot configuration.

## Self-Check: PASSED

All files created:
- SimpleLab/Public/New-LabVM.ps1 (120 lines, 3658 bytes)
- SimpleLab/Public/Remove-LabVM.ps1 (105 lines, 2989 bytes)
- .planning/phases/04-vm-provisioning/04-02-SUMMARY.md (3988 bytes)

All commits verified:
- a1913d0: feat(04-02): create New-LabVM for single VM creation
- 45cea72: feat(04-02): create Remove-LabVM for VM removal
- 82db3c6: feat(04-02): export New-LabVM and Remove-LabVM from module

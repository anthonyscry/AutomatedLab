# Phase 8: Snapshot Management - Research

**Date:** 2026-02-10
**Phase:** 8 of 9
**Focus:** Checkpoint creation and rollback

## Current State Analysis

### Already Implemented

The following checkpoint functions already exist from earlier phases:

#### Get-LabCheckpoint (Already Exists)
- **Purpose:** List checkpoints for lab VMs
- Returns array of checkpoint information

#### Save-LabCheckpoint (Already Exists)
- **Purpose:** Create checkpoint for one or all VMs
- Parameters: `VMName` (optional), `CheckpointName`
- Creates checkpoints for all VMs if no VMName specified

#### Restore-LabCheckpoint (Already Exists)
- **Purpose:** Restore VMs from checkpoint
- Parameters: `CheckpointName`, `VMName` (optional)
- Restores all VMs to checkpoint state

### Gaps Identified

**Missing: LabReady Checkpoint Automation**
- No automatic creation of "LabReady" checkpoint after domain configuration
- No convenience function for complete lab snapshot

## Requirements Mapping

From ROADMAP.md Phase 8 requirements:

| Req | Description | Status | Implementation |
|-----|-------------|--------|----------------|
| LIFE-07 | Create snapshot of lab at "LabReady" state | ❌ Missing | Need LabReady checkpoint automation |
| LIFE-08 | Rollback lab to previous snapshot | ✅ Complete | Restore-LabCheckpoint |
| LIFE-08 | Rollback completes in under 2 minutes | ✅ Complete | Restore-LabCheckpoint (fast) |
| LIFE-08 | List available snapshots | ✅ Complete | Get-LabCheckpoint |

## Technical Approach: LabReady Checkpoint

### When to Create LabReady Checkpoint

After domain configuration is complete and validated:
- After `Initialize-LabDomain` completes
- After `Initialize-LabDNS` completes
- After `Join-LabDomain` completes
- After `Test-LabDomainHealth` returns "Healthy"

### LabReady Checkpoint Function

Create a convenience orchestrator that:
1. Validates domain is healthy
2. Creates checkpoint named "LabReady" with timestamp
3. Returns result with checkpoint info

**Alternative:** Add `-CreateLabReady` switch to `Save-LabCheckpoint`

## Design Decision

Since the core snapshot functionality already exists, Phase 8 will be simplified:

**Single Plan: 08-01 - LabReady Checkpoint**
- Add convenience function for creating "LabReady" checkpoint
- Validate domain health before creating
- Include timestamp in checkpoint name
- Document existing snapshot functions

## Success Criteria (from ROADMAP)

All Phase 8 success criteria must be TRUE:

1. ✅ User can create snapshot of lab at "LabReady" state (need to add)
2. ✅ User can rollback lab to previous snapshot (already exists)
3. ✅ Rollback completes in under 2 minutes (already exists)
4. ✅ User sees list of available snapshots (already exists)

## Existing Functions Documentation

Need to document usage of existing snapshot functions:

```powershell
# List all checkpoints
Get-LabCheckpoint

# Create checkpoint for all VMs
Save-LabCheckpoint -CheckpointName "BeforeChanges"

# Create checkpoint for specific VM
Save-LabCheckpoint -VMName SimpleDC -CheckpointName "DC-Backup"

# Restore from checkpoint
Restore-LabCheckpoint -CheckpointName "LabReady"

# Restore specific VM
Restore-LabCheckpoint -CheckpointName "LabReady" -VMName SimpleDC
```

## Implementation Notes

- Phase 8 will be a single plan (08-01)
- Focus on LabReady automation and documentation
- No new snapshot functionality needed (already exists)

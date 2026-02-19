# Phase 9: User Experience - Final Phase

**Status:** Pending
**Wave:** 1
**Dependencies:** All previous phases complete ✅

## Overview

Phase 9 is the final phase that adds menu-driven interface and CLI argument support for complete user experience. Based on ROADMAP requirements, this phase needs to deliver both interactive and non-interactive modes.

## Requirements Analysis

From ROADMAP.md Phase 9 requirements:

| Req | Description | Current Status |
|-----|-------------|----------------|
| UX-02 | Menu-driven interface with numbered options | ❌ Missing |
| UX-04 | Non-interactive mode with CLI flags | ❌ Missing |
| UX-01 | Menu displays current lab status | ❌ Missing |
| UX-04 | Exit codes for automation | ❌ Missing |

## Current Entry Point

`SimpleLab/SimpleLab.ps1` currently exists as the entry point script. It needs to be enhanced with:
1. Interactive menu system
2. CLI argument parsing
3. Status display integration
4. Exit code handling

## Implementation Plan: Single Plan (09-01)

Since Phase 9 is about enhancing the existing entry point, a single comprehensive plan makes sense.

### File: SimpleLab/SimpleLab.ps1 (Enhanced)

**Features to Add:**

1. **CLI Arguments:**
   - `--build` - Complete lab build
   - `--start` - Start all VMs
   - `--stop` - Stop all VMs
   - `--status` - Show lab status
   - `--reset` - Complete lab teardown
   - `--help` - Show help
   - `--menu` - Show interactive menu (default)

2. **Interactive Menu:**
   ```
   SimpleLab Menu
   =============

   Current Lab Status:
   SimpleDC: Running (Healthy)
   SimpleServer: Running (Healthy)
   SimpleWin11: Off

   Options:
   1. Build Lab
   2. Start Lab
   3. Stop Lab
   4. Restart Lab
   5. Show Status
   6. Create LabReady Checkpoint
   7. Restore Checkpoint
   8. Reset Lab
   9. Exit

   Select option:
   ```

3. **Exit Codes:**
   - 0 = Success
   - 1 = General error
   - 2 = Validation failure
   - 3 = Operation cancelled

## Design Considerations

### Menu Display

- Show current lab status at top
- Color coding for status (Green=Running, Red=Stopped, Yellow=Other)
- Clear numbered options
- Return to main menu after operations

### Non-Interactive Mode

- All operations available via CLI flags
- Proper exit codes for automation
- Progress output without prompts
- Error messages to stderr

### Backward Compatibility

- No arguments = interactive menu (default)
- Existing function calls still work
- Module imports unchanged

## Success Criteria (from ROADMAP)

All Phase 9 success criteria must be TRUE:

1. User sees interactive menu with numbered options for all operations
2. User can run tool non-interactively with CLI flags
3. Menu displays current lab status at top
4. Non-interactive mode returns appropriate exit codes for automation

## Module Version

Final release: **v2.0.0** - Complete SimpleLab experience!

## Estimated Effort

~20 minutes for complete menu and CLI implementation

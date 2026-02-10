# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2025-02-09)

**Core value:** One command builds a Windows domain lab; one command tears it down.
**Current focus:** Phase 3: Lab Build

## Current Position

Phase: 3 of 9 (Network Infrastructure)
Plan: 3 of 3 in current phase
Status: Completed
Last activity: 2026-02-10 — Completed Phase 3 Plan 3: Network Configuration (Connectivity Validation)

Progress: [██████░░░░░] 33%

## Performance Metrics

**Velocity:**
- Total plans completed: 9
- Average duration: 6 min
- Total execution time: 0.9 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1. Project Foundation | 3 | 3 | 10 min |
| 2. Pre-flight Validation | 3 | 3 | 6 min |
| 3. Network Infrastructure | 3 | 3 | 1 min |

**Recent Trend:**
- Last 3 plans: 03-01, 03-02, 03-03
- Trend: Phase 3 complete - Network Infrastructure

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

**Phase 1 Implementation Decisions:**
- Used `Get-CimInstance Win32_ComputerSystem.HypervisorPresent` instead of `Get-ComputerInfo` for more direct Hyper-V detection
- SimpleLab module structure with Public/Private separation
- JSON run artifacts stored in `.planning/runs/` with `run-YYYYMMDD-HHmmss.json` naming

**Phase 2 Implementation Decisions:**
- ISO validation returns structured PSCustomObject with Name, Path, Exists, IsValidIso, Status properties
- Helper functions (Find-LabIso, Get-LabConfig, Initialize-LabConfig) remain internal in Private/
- Search depth limited to 2 levels for performance (Get-ChildItem -Depth 2)
- Used New-TimeSpan instead of Get-Date subtraction for cross-platform duration calculation
- Test-DiskSpace kept as private function (internal use only)
- Test-LabPrereqs continues checking even when individual checks fail (no early exit)
- Quiet mode added to Write-ValidationReport for automation integration
- Exit code signaling: 0 for pass, 2 for validation failure
- Special handling for ISO failures shows expected path and config edit instructions
- Hyper-V check skipped for Validate operation (already included in Test-LabPrereqs)

**Phase 3 Implementation Decisions:**
- Updated both PSM1 and PSD1 files for proper module exports (PowerShell module requirement)
- Internal vSwitch type provides VM-to-VM communication while isolating from host network
- Test-LabNetwork function uses Get-VMSwitch -Name "SimpleLab" -ErrorAction SilentlyContinue for detection
- New-LabSwitch function includes Force parameter for idempotent vSwitch recreation
- Used PowerShell Direct (Invoke-Command -VMName) for in-VM configuration without network connectivity
- Orchestrator pattern tracks per-VM results in hashtables with OverallStatus aggregation
- Used PowerShell Direct (Invoke-Command -VMName) for in-VM connectivity testing without network dependency
- Test-VMNetworkConnectivity kept as private function (internal use only)
- OverallStatus aggregation: OK (all pass), Partial (some pass), Failed (vSwitch missing or all fail), Warning (VMs not running)

### Pending Todos

None yet.

### Blockers/Concerns

None yet.

## Session Continuity

Last session: 2026-02-10 (Phase 3 Plan 3 execution)
Stopped at: Completed Phase 3 Plan 3: Network Configuration (Connectivity Validation)
Resume file: None

## Phase 1 Summary

**Completed:** 2026-02-09

**Plans Executed:**
- [x] 01-01: Project scaffolding and directory structure
- [x] 01-02: Hyper-V detection and validation
- [x] 01-03: Run artifact generation and error handling framework

**Artifacts Created:**
- SimpleLab/ module with Public/Private function separation
- Test-HyperVEnabled function for Hyper-V detection
- Write-RunArtifact function for JSON run artifact generation
- SimpleLab.ps1 entry point script with structured error handling
- .planning/phases/01-project-foundation/* summary documents

**Success Criteria Met:**
1. User receives clear error message when Hyper-V is not enabled ✓
2. Tool generates JSON report after each operation ✓
3. All operations use structured error handling ✓

## Phase 2 Summary

**Completed:** 2026-02-09

**Plans Executed:**
- [x] 02-01: ISO detection and validation
- [x] 02-02: Pre-flight check orchestration
- [x] 02-03: Validation error reporting and UX

**Artifacts Created:**
- Test-LabIso function for ISO file validation
- Find-LabIso function for multi-path ISO search
- Get-LabConfig and Initialize-LabConfig functions for config management
- .planning/config.json default configuration template
- Test-DiskSpace function for disk space validation
- Test-LabPrereqs orchestrator for pre-flight checks
- Write-ValidationReport function for color-coded validation output
- Validate operation in SimpleLab.ps1

**Success Criteria Met:**
1. Test-LabIso function validates file existence and .iso extension ✓
2. Find-LabIso function searches multiple directories for ISOs ✓
3. Configuration system creates default .planning/config.json ✓
4. User can specify custom ISO paths via config file ✓
5. All validation returns structured PSCustomObject results ✓
6. Test-LabPrereqs executes all prerequisite checks ✓
7. Each check returns structured result with Name, Status, Message ✓
8. OverallStatus accurately reflects whether all checks passed ✓
9. FailedChecks provides easy access to specific failures for error reporting ✓
10. Disk space validation prevents builds with insufficient storage ✓
11. User receives specific error message listing missing ISOs before build attempt ✓
12. Tool validates Windows Server 2019 and Windows 11 ISOs exist in configured location ✓
13. User sees clear pass/fail status for all pre-flight checks ✓
14. Color-coded output makes status immediately visible ✓
15. Failed checks include actionable fix instructions ✓
16. Exit code enables automation integration ✓

## Phase 3 Summary (Completed)

**Started:** 2026-02-10
**Completed:** 2026-02-10

**Plans Executed:**
- [x] 03-01: Internal vSwitch for Lab Network
- [x] 03-02: Configure Static IP Addresses for Lab VMs
- [x] 03-03: Network Configuration

**Artifacts Created:**
- Test-LabNetwork function for vSwitch detection
- New-LabSwitch function for idempotent vSwitch creation
- Get-LabNetworkConfig function for network configuration retrieval
- Set-VMStaticIP function for in-VM IP configuration via PowerShell Direct
- Initialize-LabNetwork orchestrator for multi-VM IP configuration
- NetworkConfiguration section in config.json with IP assignments
- Test-VMNetworkConnectivity function for VM-to-VM ping testing
- Test-LabNetworkHealth orchestrator for full lab network validation

**Success Criteria Met (Plan 03-01):**
1. Tool creates Internal vSwitch named "SimpleLab" with single command ✓
2. Tool reports clear status indicating switch creation or existing state ✓
3. Function handles missing Hyper-V module gracefully with error message ✓
4. vSwitch persists after creation (visible in Get-VMSwitch output) ✓

**Success Criteria Met (Plan 03-02):**
1. Tool configures static IP addresses: DC (10.0.0.1), Server (10.0.0.2), Win11 (10.0.0.3) ✓
2. IP configuration is stored in config.json for persistence ✓
3. Initialize-LabNetwork provides clear status feedback for each VM ✓
4. Function handles VM not found errors gracefully ✓

**Success Criteria Met (Plan 03-03):**
1. Tool provides single command to validate lab network health ✓
2. Tool reports clear pass/fail status for VM-to-VM connectivity ✓
3. Tool identifies which specific connections are failing ✓
4. User can verify network setup before proceeding to domain configuration ✓

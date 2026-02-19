# Phase 1: Project Foundation - Context

**Gathered:** 2025-02-09
**Status:** Ready for planning

## Phase Boundary

Establish project infrastructure with structured error handling and run artifact generation. This includes Hyper-V detection, error handling framework, JSON run reports, and project scaffolding. No feature work — pure infrastructure.

## Implementation Decisions

### Hyper-V Detection
- Use `Get-ComputerInfo` cmdlet to check Hyper-V status
- Check on every operation (not lazy evaluation)
- When Hyper-V is not enabled: Offer to enable with full command syntax
- Error message format: "Hyper-V is not enabled. Run: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All"

### Error Handling
- Combined approach: `try/catch/finally` blocks + `$ErrorActionPreference = 'Stop'` globally
- Surface errors using `Write-Error` for errors, `Write-Host` for user output
- Granular exit codes: 1=general error, 2=validation failure, 3=network error, 4=VM error, 5=domain error

### Run Artifacts
- Store as timestamped files (one per run): `run-YYYYMMDD-HHMMSS.json`
- Location: `.planning/runs/` directory
- Fields: Operation, Timestamp, Status, Duration, Error (if any), VM names, Phase info, Host info

### Project Structure
- Add new `SimpleLab/` folder to existing repository
- Modules organized by feature: `Network/`, `VM/`, `Domain/`, etc.
- Main entry point: `SimpleLab.ps1`

### Claude's Discretion
- Exact JSON schema details
- Module import patterns
- Whether to use PowerShell classes vs hashtables for data structures

## Specific Ideas

No specific requirements — open to standard PowerShell patterns

## Deferred Ideas

None — discussion stayed within phase scope

---

*Phase: 01-project-foundation*
*Context gathered: 2025-02-09*

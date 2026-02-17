# Phase 8: Orchestrator Extraction - Context

**Gathered:** 2026-02-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Extract 34 inline functions from OpenCodeLab-App.ps1 to Private/ helpers, making the orchestrator modular and independently testable. No observable behavior changes -- the app must work identically after extraction.

</domain>

<decisions>
## Implementation Decisions

### Extraction grouping
- One function per file -- each extracted function gets its own .ps1 file in Private/
- Matches existing project pattern (e.g., Test-DCPromotionPrereqs.ps1, Set-VMStaticIP.ps1)

### Naming convention
- File names match function names exactly: Show-LabMenu -> Show-LabMenu.ps1
- All extracted files go flat into Private/ alongside existing helpers (no subfolder)
- Lab-Common.ps1 auto-loads all Private/*.ps1 files; no explicit path registration needed

### Variable handling
- Script-scoped variables ($script:varName) converted to explicit parameters on extraction -- makes functions self-contained and testable
- $GlobalLabConfig: passed as parameter when function needs it, since it's available module-wide at runtime
- Interactive menu functions stay inline or get parameter-injected closures for Read-Host calls

### Testing strategy
- Unit tests added during extraction, not deferred -- each extracted function gets Pester tests in the same plan
- Existing 566+ tests must pass after every extraction batch (regression guard)

### Claude's Discretion
- Batch sizing: How many functions per plan (small vs large batches), based on dependency analysis
- Dependency grouping: Whether co-dependent functions are extracted together or individually
- What stays inline: Whether very small or UI-tightly-coupled functions remain in App.ps1
- Global state handling: Whether $GlobalLabConfig is passed as parameter or kept as module-level variable per function
- UI element handling: Whether interactive Read-Host functions are extracted with parameter injection or kept inline
- Behavior equivalence verification: Existing tests only vs additional smoke tests per batch
- Test depth: Minimal callable verification vs comprehensive input/output/edge case tests, based on function criticality

</decisions>

<specifics>
## Specific Ideas

- Lab-Common.ps1 auto-loads all Private/*.ps1 files via Get-LabScriptFiles -- extracted files are automatically sourced
- OpenCodeLab-App.ps1 is 2,012 lines with 34 inline functions -- the goal is to reduce it to a thin orchestrator (dispatch loop + main try/catch/finally)
- Some inline functions capture closure state via scriptblock .GetNewClosure() -- these are highest-risk
- Interactive menu functions use Read-Host extensively -- these need parameter injection or stay inline

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 08-orchestrator-extraction*
*Context gathered: 2026-02-17*

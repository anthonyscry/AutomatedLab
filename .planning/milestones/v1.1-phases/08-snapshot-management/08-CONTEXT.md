# Phase 8: Orchestrator Extraction - Context

**Gathered:** 2026-02-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Extract 31 inline functions from OpenCodeLab-App.ps1 to Private/ helpers, making the orchestrator modular and independently testable. No observable behavior changes — the app must work identically after extraction.

</domain>

<decisions>
## Implementation Decisions

### Extraction grouping
- One function per file — each extracted function gets its own .ps1 file in Private/
- Matches existing project pattern (e.g., Test-DCPromotionPrereqs.ps1, Set-VMStaticIP.ps1)

### Naming convention
- File names match function names exactly: Show-LabMenu → Show-LabMenu.ps1
- All extracted files go flat into Private/ alongside existing helpers (no subfolder)
- Each new file must be added to $OrchestrationHelperPaths array in Lab-Common.ps1 explicitly

### Variable handling
- Script-scoped variables ($script:varName) converted to explicit parameters on extraction — makes functions self-contained and testable
- $GlobalLabConfig: Claude's discretion on whether to keep as module-level read or pass as parameter (depends on whether function writes or only reads)
- WPF UI element references ($script:window, $script:textBox): Claude's discretion on whether to pass as parameters or keep tightly-coupled UI functions inline in App.ps1

### Testing strategy
- Unit tests added during extraction, not deferred — each extracted function gets Pester tests in the same plan
- Existing 566+ tests must pass after every extraction batch (regression guard)

### Claude's Discretion
- Batch sizing: How many functions per plan (small vs large batches), based on dependency analysis
- Dependency grouping: Whether co-dependent functions are extracted together or individually
- What stays inline: Whether very small or UI-tightly-coupled functions remain in App.ps1
- Global state handling: Whether $GlobalLabConfig is passed as parameter or kept as module-level variable per function
- UI element handling: Whether WPF-referencing functions are extracted with parameter injection or kept inline
- Behavior equivalence verification: Existing tests only vs additional smoke tests per batch
- Test depth: Minimal callable verification vs comprehensive input/output/edge case tests, based on function criticality

</decisions>

<specifics>
## Specific Ideas

- The existing $OrchestrationHelperPaths pattern in Lab-Common.ps1 is the canonical sourcing mechanism — all extracted files must be registered there
- OpenCodeLab-App.ps1 is 2,012 lines with 31 inline functions — the goal is to reduce it to a thin orchestrator (menu loop + dispatch + sourcing)
- Some inline functions reference script-scoped WPF variables — these are the highest-risk extractions and may need special handling

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 08-snapshot-management*
*Context gathered: 2026-02-17*

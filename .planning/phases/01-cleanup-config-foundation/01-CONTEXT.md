# Phase 1: Cleanup & Config Foundation - Context

**Gathered:** 2026-02-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Remove dead code, unify the configuration system, and standardize helper sourcing patterns — making the codebase clean and consistent before integration testing in later phases. No new features; this is housekeeping.

</domain>

<decisions>
## Implementation Decisions

### Dead code removal
- Delete `.archive/` directory entirely — it's in git history if needed
- Delete all leftover test/debug scripts (test-*.ps1, test.json) — they served their purpose
- `git rm` coverage.xml and .tools/powershell-lsp/ from tracking, update .gitignore to prevent re-addition
- Delete unreachable code paths aggressively — if it's not called, it's gone; git has history
- No reference copies, no "keep for later" — clean cut

### Config unification
- Kill legacy variables ($LabName, $LabSwitch, etc.) immediately — no deprecation period
- Update all consumers to use $GlobalLabConfig hashtable exclusively
- Config validation fails loudly — missing required fields = script stops with clear error message
- No fallback to defaults for required fields; script must tell user exactly what's missing

### Helper sourcing
- Fail fast on load errors — broken helper means broken app, surface it immediately
- No silent skipping of failed helpers

### Template/JSON validation
- Reject templates with invalid data (bad IP format, unknown role) — won't load until fixed
- Don't auto-correct; force the user to fix the source of truth

### Claude's Discretion
- Whether to split Lab-Config.ps1 into core + LabBuilder configs (evaluate coupling first)
- Which of the 3 helper sourcing patterns to standardize on (dynamic discovery vs explicit registration vs hybrid)
- How to replace $OrchestrationHelperPaths manual array (auto-discovery vs generated list)
- Template validation strictness level (schema vs field-level checks)
- Whether to use one shared JSON validator or separate validators per file type

</decisions>

<specifics>
## Specific Ideas

- User wants aggressive cleanup — "if it's not called, it's gone"
- Config errors should be loud and specific — tell the user exactly what field is missing/wrong
- Helper load failures should stop everything — no partial function availability
- Templates with bad data should be rejected, not auto-corrected

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-cleanup-config-foundation*
*Context gathered: 2026-02-16*

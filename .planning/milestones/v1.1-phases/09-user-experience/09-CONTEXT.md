# Phase 9: Error Handling - Context

**Gathered:** 2026-02-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Add try-catch error handling to all 39 functions currently missing it (28 Private, 11 Public), and standardize existing error handling to match the new pattern. No behavior changes — functions must produce the same outputs on success, but now explain failures with context-aware messages.

</domain>

<decisions>
## Implementation Decisions

### Error message style
- Always prefix with function name: `"[Function-Name] Failed to X: reason"`
- Include actionable context: what failed, why, and what to check/try next
- Always suggest fixes: every error message includes a "Check:" or "Try:" hint
- Always chain inner exceptions: use throw with InnerException or Write-Error -Exception to preserve original stack trace

### Failure behavior
- Throw for critical failures (can't create VM, can't reach DC, missing prerequisites); return with status object for recoverable issues (optional feature missing)
- Convert all remaining `exit` calls to `return` or `throw` — no function uses exit
- Write-Error vs throw: Claude's discretion based on PowerShell best practices per function
- Existing return-with-status-object patterns: Claude's discretion on keeping vs converting

### Error granularity
- One try-catch wrapping entire function body — simple, consistent, catches everything
- Standardize existing partial error handling to match new pattern (prefix, context, chaining)
- Finally blocks: Claude's discretion, only where actual cleanup is needed (files, temp resources, locks)

### Logging integration
- Write-Warning before throw — ensures error appears in warning stream even if caller catches and suppresses
- Run-artifacts integration: Claude's discretion on calling Add-LabRunEvent where $RunEvents is in scope
- Write-Verbose additions: Claude's discretion, minimal scope — only where it directly aids error diagnosis (Phase 10 handles broader verbose output)

### Claude's Discretion
- Write-Error vs throw selection per function based on PowerShell best practices
- Whether to keep existing return-with-status patterns or convert to throw
- Finally block placement — only where actual cleanup needed
- Run-artifacts integration — where $RunEvents is already available
- Verbose additions — minimal, only for error diagnosis context

</decisions>

<specifics>
## Specific Ideas

- Error message format: `"[Function-Name] Failed to {action}: {reason}. Check: {suggestion}."` with chained inner exception
- The 39 functions span both Private/ helpers and Public/ cmdlets — Public functions are user-facing and need the most actionable messages
- Phase 8 just extracted 34 functions to Private/ — many of these are among the 39 that need error handling
- Existing functions with partial error handling should be brought up to the new standard, not just left as-is

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 09-user-experience*
*Context gathered: 2026-02-17*

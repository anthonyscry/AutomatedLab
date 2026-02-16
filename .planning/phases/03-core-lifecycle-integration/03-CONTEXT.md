# Phase 3: Core Lifecycle Integration - Context

**Gathered:** 2026-02-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Bootstrap → Deploy → Use → Teardown completes end-to-end on a clean Windows host without errors. This covers the full lab lifecycle including network infrastructure (vSwitch, NAT, static IPs, DNS), VM provisioning, quick mode restore, health checks, and clean resource removal. All 25+ CLI actions work without unhandled errors. No new features — making existing lifecycle flows reliable.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
User explicitly deferred all implementation decisions to Claude. The following areas are open for Claude to determine the best approach based on codebase analysis:

**Error recovery behavior:**
- How to handle VM deployment failures (retry, skip, abort)
- How forgiving the lifecycle should be vs fail-fast
- Error message format and context-awareness
- Try-catch placement strategy for critical operations

**Confirmation gates:**
- Which destructive actions require confirmation tokens
- Token generation and validation mechanism
- CLI vs GUI confirmation flow differences
- Whether to use typed confirmation (e.g., "type lab name to confirm teardown")

**Health check diagnostics:**
- What gets checked (VMs, network, services, DNS, connectivity)
- Output format and detail level
- Actionable recommendations vs raw status
- How to report partial health (some VMs up, some down)

**Idempotency strictness:**
- How to handle existing resources on re-deploy (skip, recreate, fail)
- vSwitch and NAT creation idempotency
- Checkpoint management across deploy/teardown cycles
- Orphan detection and cleanup

**Network infrastructure:**
- vSwitch creation and validation approach
- NAT configuration and conflict detection
- Static IP assignment via PowerShell Direct
- DNS forwarder configuration and resolution validation

**CLI orchestrator:**
- Menu system routing and option display
- Action handler error boundaries
- Progress reporting during long operations

</decisions>

<specifics>
## Specific Ideas

- User wants "everything should just work end-to-end" — reliability over configurability
- The core workflow is: Bootstrap → Deploy → use VMs → Teardown
- Quick mode (LabReady snapshot restore + auto-heal) must work reliably for day-to-day use
- User hasn't tried end-to-end yet — this phase is where we find out what's broken
- "Done" = every button and action works in both CLI and GUI

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-core-lifecycle-integration*
*Context gathered: 2026-02-16*

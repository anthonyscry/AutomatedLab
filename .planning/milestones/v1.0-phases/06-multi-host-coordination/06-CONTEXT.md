# Phase 6: Multi-Host Coordination - Context

**Gathered:** 2026-02-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Coordinator dispatch routes operations to correct target hosts with scoped safety gates. Host inventory file loads and validates remote host entries. Dispatch modes (off/canary/enforced) behave as documented. Scoped confirmation tokens validate per-host safety gates. Remote operations handle connectivity failures gracefully with clear messages.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
User explicitly deferred all implementation decisions to Claude across all phases. The following areas are open for Claude to determine the best approach based on codebase analysis:

**Host inventory:**
- File format and validation rules for remote host entries
- Required vs optional fields per host entry
- How to handle duplicate or conflicting entries
- Whether to support host groups or tags

**Dispatch routing:**
- How coordinator determines which host receives each operation
- Error handling when target host is unreachable
- Retry logic for transient connectivity failures
- How to report partial success across multiple hosts

**Dispatch modes:**
- off: All operations local only
- canary: Test on single host before full rollout
- enforced: All operations route to designated hosts
- Mode switching and validation

**Safety gates:**
- Scoped confirmation token format and validation
- Per-host vs per-operation token granularity
- How tokens expire or are revoked
- Integration with existing CLI confirmation gate pattern

**Remote operations:**
- Protocol for remote command execution (PSSession, SSH, etc.)
- Timeout handling for long-running remote operations
- How to aggregate results from multiple hosts
- Logging and artifact collection from remote hosts

</decisions>

<specifics>
## Specific Ideas

- Multi-host infrastructure already exists in codebase — needs hardening, not new features
- Coordinator dispatch pattern should match existing CLI action routing
- Safety gates should use same confirmation token pattern as teardown/blow-away
- Connectivity failures need clear messages about which host failed and why
- Host inventory should be simple JSON/config format consistent with existing config system

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 06-multi-host-coordination*
*Context gathered: 2026-02-17*

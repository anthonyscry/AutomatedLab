# Phase 4: Role Provisioning - Context

**Gathered:** 2026-02-17
**Status:** Ready for planning

<domain>
## Phase Boundary

All 11 Windows/Linux roles provision successfully with graceful error handling. DC, SQL, IIS, WSUS, DHCP, FileServer, PrintServer, DSC, Jumpbox, Client roles install and configure correctly. All roles handle missing prerequisites gracefully with clear error messages. No new roles — making existing role scripts reliable.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
User explicitly deferred all implementation decisions to Claude. The following areas are open for Claude to determine the best approach based on codebase analysis:

**Role failure handling:**
- How to handle mid-install failures per role (retry, skip, abort)
- Dependency ordering (DC must be first, other roles depend on domain)
- Whether to continue provisioning other VMs if one role fails
- Error message format for role-specific failures
- Prerequisite checking before role installation begins

**Role verification:**
- What constitutes "role installed correctly" for each role type
- Service checks, port checks, or functional validation
- How to report partial success (role installed but service not running)
- Whether to add post-install smoke tests

**Linux role handling:**
- Per project decision: Linux VMs deprioritized — keep code but don't actively test
- Ensure Linux role scripts don't crash if called
- Don't spend significant effort on Ubuntu role testing
- Focus on Windows roles (DC, SQL, IIS, WSUS, DHCP, FileServer, PrintServer, DSC, Jumpbox, Client)

**LabBuilder role scripts:**
- How to handle the LabBuilder/Roles/ directory role definitions
- Whether role scripts need the same error handling treatment as core lifecycle
- Integration between LabBuilder role config and Deploy.ps1 role application

</decisions>

<specifics>
## Specific Ideas

- User wants "everything should just work" — roles that install cleanly without manual intervention
- DC role is the most critical — DNS, ADWS, domain services must all be running
- SQL role needs SA account configured correctly
- Client role needs domain join as workstation (not server)
- Error handling should be graceful — clear messages about what failed and why

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-role-provisioning*
*Context gathered: 2026-02-17*

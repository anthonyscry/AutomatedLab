# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-20)

**Core value:** Every function handles errors explicitly, surfaces clear diagnostics, and the codebase is modular enough that each piece can be tested and maintained independently.
**Current focus:** v1.5 Advanced Scenarios & Multi-OS — ready for Phase 22 planning

## Current Position

Phase: 24 (Linux VM Parity)
Plan: 2/2 plans — 24-02 complete
Status: In progress — 24-02 complete (SSH retry logic in Invoke-LinuxRolePostInstall, CentOS Stream 9 role)
Last activity: 2026-02-21 — completed 24-02 (configurable SSH retry, CentOS.ps1 role, Lab-Config CentOS entries, 57 new tests)

Progress: [████████████████████░░░░░░░░░░░░░░░░░░░░] 50% (23-01, 23-02, 24-01, 24-02 done)

## Performance Metrics

**v1.0 Brownfield Hardening & Integration:**
- 6 phases, 25 plans, 56 requirements

**v1.1 Production Robustness:**
- 4 phases, 13 plans, 19 requirements

**v1.2 Delivery Readiness:**
- 3 phases, 16 plans, 11 requirements
- 847+ Pester tests passing

**v1.3 Lab Scenarios & Operator Tooling:**
- 4 phases, 8 plans, 14 requirements
- ~189 new tests (unit + integration + E2E smoke)

**v1.4 Configuration Management & Reporting:**
- 4 phases, 8 plans, 13 requirements
- 74 new Pester tests

## Accumulated Context

### Decisions

Full log in PROJECT.md Key Decisions table.

**22-01:**
- Validator returns result object (not throw) so discovery can warn-and-skip invalid files
- Memory strings parsed to numeric bytes at load time matching Get-LabRole_* output shape
- PSCustomObject-to-hashtable helper uses [object] parameter type (PS5.1 strict mode binding fix)

**22-02:**
- Built-in role loop uses continue (not throw) for unknown tags; custom role section handles them separately
- Invoke-LabBuilder expands validTags at runtime via Get-LabCustomRole -List — new custom roles auto-accepted without code changes
- Custom role Phase 11 provisioning runs after Windows parallel jobs, before Linux post-installs

**23-01:**
- Switches array coexists with flat SwitchName/AddressSpace keys for full backward compat
- Get-LabNetworkConfig reads Switches in priority order: Get-LabConfig.NetworkConfiguration > GlobalLabConfig.Network > flat-key fallback
- NatName defaults to Name+NAT when omitted from Switches entries
- New-LabSwitch/New-LabNAT use ParameterSetName (Single/Multi/All) to cleanly separate modes
- Test-LabMultiSwitchSubnetOverlap is a new function in Test-LabVirtualSwitchSubnetConflict.ps1
- WSL/CI test environments: Hyper-V cmdlet stubs in BeforeAll allow Pester to Mock them

**23-02:**
- IPPlan hashtable format: per-VM @{IP; Switch; VlanId} with plain string backward compat
- Get-LabNetworkConfig returns VMAssignments (per-VM Switch/VlanId/PrefixLength) and Routing (mode/gateway config)
- New-LabVMNetworkAdapter: empty SwitchName = unconnected (not wrong-switch); no -Force needed
- Routing defaults: Mode=host, GatewayVM='', EnableForwarding=true when Routing block absent
- Invoke-LabGatewayForwarding wrapper: Pester cannot reliably mock Invoke-Command -VMName; named wrapper solves it

**24-01:**
- Backward-compat: when GlobalLabConfig absent, LIN1 fallback detection preserved (else branch, not removed)
- linuxVmCount prefers VMNames key count over LinuxVM section presence for accuracy
- Get-LabStateProbe needs no changes — it accepts VMNames as a parameter, Linux VMs included by callers

**24-02:**
- PSBoundParameters.ContainsKey used to distinguish explicit RetryCount from default — LabConfig.Timeouts override applies only when parameter not explicitly supplied
- $env:WINDIR null-guarded (defaults to 'C:\Windows') for cross-platform testability in CI/WSL
- CentOS post-install uses systemctl enable sshd (not ssh) matching RHEL service naming
- ISOPattern 'CentOS-Stream-9*.iso' differentiates from Ubuntu — same Invoke-LinuxRoleCreateVM function

### Pending Todos

- None

### Blockers/Concerns

- None currently.

## Session Continuity

Last session: 2026-02-21
Stopped at: Completed 24-02-PLAN.md (SSH retry, CentOS role, 57 new tests)
Resume file: None

---
*State initialized: 2026-02-17 for v1.1 milestone*
*Last updated: 2026-02-20 after v1.5 roadmap created*

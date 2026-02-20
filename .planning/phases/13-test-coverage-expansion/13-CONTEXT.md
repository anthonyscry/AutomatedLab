# Phase 13: Test Coverage Expansion - Context

**Gathered:** 2026-02-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Add unit tests for untested Public functions, wire up coverage reporting in CI, and create an E2E smoke test for the bootstrap/deploy/teardown lifecycle. No new features or runtime behavior changes.

</domain>

<decisions>
## Implementation Decisions

### Test Strategy for Public Functions
- Target all ~30 untested Public functions (exceeds TEST-01's 20+ requirement)
- Group tests into logical files: VMLifecycle.Tests.ps1, Checkpoints.Tests.ps1, NetworkInfra.Tests.ps1, DomainSetup.Tests.ps1, LinuxPublic.Tests.ps1, LabStatus.Tests.ps1
- All tests must mock Hyper-V cmdlets (Get-VM, Start-VM, Checkpoint-VM, etc.) — CI has no Hyper-V
- Establish shared mock patterns in a TestHelpers file, reuse across test files
- Each test validates: parameter handling, error paths, return types, correct cmdlet invocations via mock verification

### Coverage Reporting & Thresholds
- Use existing Run.Tests.ps1 JaCoCo output (coverage.xml already produced)
- Upload coverage.xml as PR artifact in pr-tests.yml
- Add coverage summary step that posts to PR checks
- Start with existing 15% threshold, raise incrementally after 13-01 lands (target 25-40%)
- Fail PR if coverage drops below threshold

### E2E Smoke Test Approach
- Simulation mode: mock Hyper-V/SSH layer but exercise full orchestration path through OpenCodeLab-App.ps1
- Verify: exit codes, run artifacts produced, expected log messages, state transitions in order
- Must run in CI without Hyper-V (pure PowerShell mocking)
- Keep wall-clock under 60 seconds
- Design test script to support both simulation and real Hyper-V modes (real mode deferred)

### Plan Ordering
- 13-01 first (tests must exist before coverage enforcement)
- 13-02 second (CI enforcement before E2E added)
- 13-03 last (depends on mock patterns from 13-01 and CI from 13-02)

### Claude's Discretion
- Exact mock helper implementation patterns
- Whether to use shared BeforeAll blocks or per-test mocking
- Coverage report GitHub Action choice
- E2E test structure (single file vs multiple describe blocks)

</decisions>

<specifics>
## Specific Ideas

- Shared Hyper-V mock infrastructure should be a reusable dot-sourceable file, not duplicated per test
- Coverage threshold should be realistic given heavy mocking — semantic coverage matters more than line percentage
- E2E smoke test should map assertions back to lifecycle requirements (LIFE-01 through LIFE-05)

</specifics>

<deferred>
## Deferred Ideas

- Self-hosted runner E2E with real Hyper-V — future milestone
- Coverage trend tracking service — not needed for single developer

</deferred>

---

*Phase: 13-test-coverage-expansion*
*Context gathered: 2026-02-20*

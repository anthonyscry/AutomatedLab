# Coordinator Execution Rollout Design

## Goal

Ship production-ready coordinator dispatch behavior with contract-first hardening.

This iteration prioritizes deterministic test pass and backward-compatible responses while preserving existing safety guarantees.

## Validated Constraints

- Existing response contracts must not break.
- Rollout remains feature-flagged through `DispatchMode` (`off`, `canary`, `enforced`).
- Safety policy remains fail-closed for destructive operations.
- Kill-switch rollback to `off` must remain immediate and deterministic.
- Success gate for this iteration is deterministic dispatch-focused test pass.

## Approaches Considered

### 1) Contract-First Hardening (selected)

- Stabilize additive response/artifact behavior first, then harden dispatch execution logic under that contract.
- Pros: strongest protection against regressions, directly aligned with no-contract-breaks goal.
- Cons: live canary confidence arrives later than execution-first approaches.

### 2) Canary-First Execution Validation

- Prioritize real canary dispatch behavior first, then tighten contracts.
- Pros: faster runtime proof.
- Cons: higher risk of contract drift during fast iteration.

### 3) Release-Gate Packaging First

- Build promotion/verification gates before implementation changes.
- Pros: strong operational rigor.
- Cons: slower delivery of behavior fixes.

## Architecture

Keep the control plane unchanged:

`intent -> inventory -> fleet probe -> policy -> plan`

Dispatch stays a separate data-plane step after policy approval.

- If policy is not `Approved`, execution remains `not_dispatched`.
- Existing top-level fields and semantics remain unchanged.
- Dispatch/execution metadata is additive and deterministic in all branches.
- `DispatchMode=off` remains the rollback kill switch and must short-circuit execution only.

## Component Design

- `Resolve-LabDispatchMode`
  - Resolves mode precedence (`parameter > environment > default`).
  - Normalizes values and surfaces source for observability.

- `Invoke-LabCoordinatorDispatch`
  - Owns canary selection, per-host execution status, retries, and action-based failure behavior.
  - Returns deterministic run-level and host-level execution metadata.

- `Test-LabTransientTransportFailure`
  - Classifies retry-eligible transient transport/remoting failures.
  - Prevents retries for deterministic non-transient classes.

- `OpenCodeLab-App.ps1` integration path
  - Keeps policy gate unchanged.
  - Invokes dispatch only when approved and execution-eligible.
  - Always emits deterministic additive execution fields.

## Data Flow

1. Resolve action, mode, target hosts, and `DispatchMode` once at startup.
2. Run existing policy pipeline unchanged.
3. If policy is not `Approved`, return non-execution response with additive defaults.
4. If execution is eligible, invoke dispatcher according to resolved mode.
5. In `canary`, dispatch exactly one eligible host and mark remaining hosts `not_dispatched`.
6. Merge host outcomes into response without renaming or removing existing fields.
7. Persist additive metadata to run artifacts in all code paths.

## Error Handling and Safety

- Fail closed for invalid/unresolved execution preconditions.
- Retry only transient transport/remoting failures with bounded attempts.
- Never retry policy/auth/scope-mismatch/logic failures.
- For destructive `teardown + full`, fail fast on first dispatched host failure and mark downstream hosts `skipped`.
- Preserve scoped confirmation and policy revalidation barriers for destructive flows.

## Contract and Artifact Invariants

Existing fields remain authoritative and unchanged:

- `PolicyOutcome`, `PolicyReason`, `HostOutcomes`, `BlastRadius`, `EffectiveMode`, `OperationIntent`.

Additive run-level fields remain deterministic:

- `DispatchMode`, `ExecutionOutcome`, `ExecutionStartedAt`, `ExecutionCompletedAt`.

Additive host-level fields remain deterministic:

- `DispatchStatus`, `AttemptCount`, `LastFailureClass`, `LastFailureMessage`.

Artifact invariants:

- Exactly one host outcome per resolved target host.
- `BlastRadius` remains authoritative for safety/audit scope.
- JSON/text artifacts always include additive dispatch/execution keys.

## Testing and Release Gates

Primary gate for this iteration: deterministic dispatch-focused suite pass.

Required coverage:

- Dispatch mode resolver precedence and validation.
- Transient transport failure classifier behavior.
- Dispatcher behavior for `off`, `canary`, and `enforced`.
- Action-based failure policy (destructive fail-fast, non-destructive continue).
- Additive contract checks for no-execute, blocked, and approved paths.
- Artifact key presence and deterministic defaults.

Acceptance criteria:

- All dispatch-focused suites pass with only expected environment-specific skips.
- No legacy field removals, renames, or semantic changes.
- Host outcome accounting remains deterministic across rollout modes.

## Rollout and Rollback

- Stage A: `off` baseline.
- Stage B: `canary` on single eligible host.
- Stage C: scoped expansion after evidence and gate pass.
- Stage D: `enforced` only after canary confidence and destructive-path safety validation.

Rollback is immediate by switching to `DispatchMode=off` while keeping policy and artifact behavior intact.

## Success Criteria

- Production readiness is achieved without contract breakage.
- Deterministic test-pass gate is satisfied.
- Operators can audit policy, blast radius, and execution outcomes per run.

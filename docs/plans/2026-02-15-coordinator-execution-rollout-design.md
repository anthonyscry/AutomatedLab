# Coordinator Execution Rollout Design

## Goal

Enable safe real execution for multi-host coordinator flows while preserving current safety guarantees and response contract stability.

## Context and Constraints

- Current coordinator control plane is implemented and validated in no-execute mode.
- First rollout milestone targets a single remote canary host.
- Failure policy is action-based: fail-fast for destructive teardown, contain and continue for non-destructive actions.
- Automatic retries are enabled for transient transport failures with bounded attempts.
- Existing `OpenCodeLab-App.ps1` output contracts must remain backward compatible.

## Approaches Considered

### 1) Feature-Flagged Dispatcher (selected)

- Add an execution dispatcher layer selected by rollout mode (`off`, `canary`, `enforced`).
- Keep policy and safety gating unchanged.
- Pros: safest staged rollout, fast rollback, clear separation of control and execution planes.
- Cons: adds a small amount of adapter/selection plumbing.

### 2) Direct In-App Cutover

- Wire real execution directly into current app routing.
- Pros: fewer new abstractions initially.
- Cons: tighter coupling, harder rollback, riskier production cutover.

### 3) Shadow-Then-Enforce Only

- Run shadow execution telemetry first, then later enable dispatch.
- Pros: strongest pre-cutover confidence.
- Cons: slower delivery for first usable canary.

## Architecture

Keep the existing control plane pipeline unchanged:

`intent -> inventory -> fleet probe -> policy -> plan`

Add a separate data plane dispatcher that executes only after policy approval:

- `NoExecuteAdapter`: current behavior, always safe baseline.
- `RemotingCanaryAdapter`: real execution for approved canary scope.
- `Invoke-LabCoordinatorDispatch`: shared dispatcher entrypoint.
- Rollout selector: config/flag/env choosing `off|canary|enforced`.

Safety invariants remain policy-owned:

- `EscalationRequired` and `PolicyBlocked` never dispatch.
- Destructive full teardown requires valid scoped confirmation token.
- Destructive paths re-probe and revalidate policy before dispatch.

## Execution Flow

1. Resolve operation intent and target hosts.
2. Probe fleet and evaluate policy.
3. If outcome is not `Approved`, return no-execute contract response.
4. If `Approved`, build execution plan and select dispatcher from rollout mode.
5. For destructive steps, re-probe and revalidate just before execution barrier.
6. Dispatch host actions and record attempt/result metadata.
7. Return stable top-level response with additive execution fields.

### Canary Scope Rules

- Real dispatch is limited to one explicitly targeted approved remote host.
- Additional resolved hosts remain `not_dispatched` and are still included in `HostOutcomes`.

## Failure Handling and Retry Policy

### Action-Based Failure Behavior

- Destructive teardown: fail-fast on first execution failure and stop remaining destructive steps.
- Non-destructive deploy/start: continue remaining hosts and return partial outcome when needed.

### Retry Policy

- Retry transient transport/remoting failures only.
- Use bounded retries with short exponential backoff (initial attempt plus two retries).
- Do not retry policy, auth, capability, or deterministic execution logic failures.

## Contract and Artifact Design

Maintain existing fields and semantics:

- `PolicyOutcome`, `PolicyReason`, `HostOutcomes`, `BlastRadius`, `EffectiveMode`, `OperationIntent`.

Additive fields for execution visibility:

- Run-level: `DispatchMode`, `ExecutionOutcome`, `ExecutionStartedAt`, `ExecutionCompletedAt`.
- Host-level: `DispatchStatus`, `AttemptCount`, `LastFailureClass`, `LastFailureMessage`.

Artifact invariants:

- Exactly one host outcome per resolved target host.
- `BlastRadius` remains the authoritative host set for safety/audit.
- Destructive runs record non-secret confirmation metadata (run scope + scope-match result).

## Testing Strategy

- Unit tests for dispatch selector, retry classifier, action-based failure policy, and additive contract defaults.
- Integration tests for single-host canary dispatch and mixed dispatch states (`dispatched` + `not_dispatched`).
- Regression tests proving destructive dispatch cannot occur without valid scoped confirmation and fresh revalidation.
- Contract compatibility tests ensuring existing top-level fields and meanings remain unchanged.

## Rollout Plan

1. **Stage A (`off`)**: keep no-execute baseline.
2. **Stage B (`canary`)**: single approved remote host, non-destructive actions first.
3. **Stage C (`canary+`)**: expand host/action scope after safety SLO gates pass.
4. **Stage D (`enforced`)**: permit destructive execution only after canary evidence and confirmation gate compliance.

Promotion gates between stages:

- Zero unauthorized destructive operations.
- Deterministic host outcome accounting.
- Retry behavior improves transient resiliency without masking persistent failures.

Rollback:

- Single kill switch returns dispatch mode to `off` immediately.
- Artifact contract remains stable across all modes.

## Success Criteria

- Real execution can be enabled progressively without weakening current safety guarantees.
- Existing consumers continue to function without contract breakage.
- Operators can audit policy and execution outcomes deterministically per run and per host.

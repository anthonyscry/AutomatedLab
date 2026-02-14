# Multi-Host Safety-First Quick/Full Orchestration Design

## Goal

Design a production-ready staged redesign of `deploy` and `teardown` orchestration for a 2-5 host environment using PowerShell Remoting, with safety-first behavior as the top priority.

## Decisions Captured

- Scope includes multi-host/remote orchestration now (not just local host).
- Primary transport is PowerShell Remoting.
- Safety is prioritized over speed or convenience.
- Backward compatibility can change if needed, but rollout must be staged and production-ready.

## Architecture

The redesign introduces a coordinator state machine that owns orchestration decisions and safety policy, while CLI and GUI remain intent ingress layers. `quick` and `full` are policy profiles on top of a single lifecycle model instead of separate routing stacks. Host-level execution is delegated to adapters that run the selected operations over local PowerShell or remoting.

### Coordinator Model

- Canonical host lifecycle: `Unknown -> Probed -> Ready -> Running -> TeardownPending -> TeardownComplete`.
- Transition rules are explicit and fail closed when data is missing or uncertain.
- Destructive transitions are never inferred; they require explicit authorization.

### Core Components

1. Intent ingress
   - Normalize CLI/GUI inputs into one operation request (`action`, `requested_mode`, `target_hosts`, `run_id`, requestor context).
2. Host inventory service
   - Resolve host metadata, role, trust/safety classification, and remoting endpoint.
3. Fleet probe
   - Probe all targeted hosts with bounded timeouts and structured health/state results.
4. Policy engine
   - Compute `effective_mode`, policy outcome, and safety gating decisions.
5. Plan builder
   - Build step graph with barriers before destructive phases.
6. Dispatcher
   - Execute remoting work with concurrency controls, retries for transient failures, and idempotency keys.
7. Artifact recorder
   - Persist run timeline and per-host outcomes under one run id.

## Data Flow

1. CLI/GUI submits operation intent.
2. Coordinator resolves host inventory and probe plan.
3. Fleet probe collects per-host state and capabilities.
4. Policy engine evaluates safety and mode transitions.
5. Plan builder generates execution graph (including destructive barriers).
6. Dispatcher executes host actions and records typed outcomes.
7. Artifact recorder writes summary and detailed timeline.

## Safety and Error Handling

- Fail closed by default for uncertain probe, inventory drift, policy errors, or remoting ambiguity.
- No silent escalation for destructive-capable flows; quick mode can return `EscalationRequired` with explicit next command.
- Full destructive operations require scoped confirmation token bound to `run_id`, target host set, and operation hash.
- Typed outcomes include: `PolicyBlocked`, `PreflightFailed`, `TransportUnreachable`, `CapabilityMismatch`, `ExecutionFailed`, `PartialSuccess`, `Completed`.
- Before destructive step execution, coordinator re-probes state and re-validates policy to prevent stale-plan execution.

## Testing Strategy

- State-machine transition tests for allowed/blocked paths.
- Policy-engine table tests for fail-closed behavior and token requirements.
- Remoting adapter tests for timeout, auth, and partial-host failures.
- Multi-host orchestration tests for barriers, containment, retries, and resumability.
- Artifact schema tests for run-level and host-level audit completeness.
- Regression tests that prove destructive transitions cannot run without valid scoped authorization.

## Migration and Rollout

### Phase 0: Contract freeze

- Define `OperationIntent` and coordinator response contracts.
- Keep legacy entry points as compatibility wrappers.

### Phase 1: Shadow coordinator

- Run coordinator in decision-only mode beside current execution.
- Compare decisions and artifact parity.

### Phase 2: Single-host cutover

- Route local host execution through coordinator with rollback switch.

### Phase 3: Remote canary

- Add one remote host, non-destructive paths first.

### Phase 4: Destructive enablement

- Enable full destructive transitions only with scoped token and fresh barrier reprobe.

### Phase 5: Fleet rollout (2-5 hosts)

- Expand host set gradually with safety SLO gates.
- Retire legacy direct routing only after safety and audit parity is proven.

## Success Criteria

- Zero unauthorized destructive operations in rollout window.
- Every policy block and destructive decision is explainable from artifacts.
- Quick-path remains available for non-destructive operations without weakening safety gates.

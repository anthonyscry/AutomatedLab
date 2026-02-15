# Architecture Notes

## Runtime model

The repository has two layers:

- **Module layer (`SimpleLab`)**: reusable commands in `Public/` and `Private/`, loaded via `SimpleLab.psm1`.
- **Orchestration layer**: app-like scripts (`OpenCodeLab-App.ps1`, `Bootstrap.ps1`, `Deploy.ps1`, `Scripts/*.ps1`) that compose module functions into workflows.

Dispatch-aware orchestration adds an execution-control layer:

- **Dispatcher layer**: action routing honors `DispatchMode` (`off`, `canary`, `enforced`) so operators can disable rollout, run one-host canaries, or enforce full dispatch.
- Dispatch controls are verified through `ExecutionOutcome` artifacts: `off` should report `not_dispatched`, `canary` should dispatch exactly one host while remaining hosts report `not_dispatched`, and `enforced` should show dispatched hosts or explicit policy-blocked outcomes.

## Core workflows

- **Bootstrap** (`Bootstrap.ps1`): installs dependencies and validates host prerequisites.
- **Deploy** (`Deploy.ps1`): creates/repairs core topology (DC1, SVR1, WS1), with optional LIN1 flow.
- **Operate** (`OpenCodeLab-App.ps1`): action router for setup, quick/full deploy and teardown, health, rollback, reset, and menu mode.
- **GUI wrapper** (`OpenCodeLab-GUI.ps1`): WinForms launcher that builds validated argument lists, starts app runs in a separate PowerShell process, and surfaces run artifact summaries.

## Quick/full orchestration model

- `deploy` and `teardown` are orchestration actions with two modes: `quick` and `full`.
- `Resolve-LabDispatchPlan` keeps these actions mode-aware and forces mode `full` for setup/reset/blow-away style actions.
- `Resolve-LabOperationIntent` combines `-TargetHosts` and optional `-InventoryPath` to compute validated host scope before orchestration runs.
- `Resolve-LabCoordinatorPolicy` enforces fail-closed safety decisions (`Approved`, `EscalationRequired`, `PolicyBlocked`) before execution.
- Dispatcher outcomes are action-based: unsupported or blocked action/host combinations return non-dispatch outcomes (`not_dispatched`) instead of attempting execution.
- Action-based failure policy keeps destructive actions fail-closed: when policy is unresolved or blocked, execution is denied and artifacts capture the policy reason.
- `Get-LabStateProbe` and `Resolve-LabModeDecision` gate `deploy -Mode quick`; if required state is missing, effective mode falls back to `full` with a reason.
- `Resolve-LabOrchestrationIntent` maps effective mode to runtime behavior:
  - `deploy + quick` -> start/status/health quick startup sequence
  - `deploy + full` -> full `Deploy.ps1` path
  - `teardown + quick` -> stop VMs and restore `LabReady` when available
  - `teardown + full` -> destructive blow-away flow
- `teardown -Mode full` requires scoped approval via `-ConfirmationToken`; missing or invalid tokens are blocked by policy (fail-closed).
- Operators can mint scoped confirmation tokens via `Scripts/New-ScopedConfirmationToken.ps1` using the same run-scope and secret contract consumed by `OpenCodeLab-App.ps1`.
- `EscalationRequired` is surfaced when quick teardown cannot be safely honored without a full teardown path.
- `Resolve-LabExecutionProfile` centralizes profile defaults and optional profile-file overrides for both operations.

## Run artifacts and observability

- `OpenCodeLab-App.ps1` writes per-run JSON and text artifacts under `C:\LabSources\Logs`.
- Artifacts include requested/effective mode, fallback reason, profile source, run flags, and step events.
- Coordinator-aware artifact fields include `policy_outcome`, `policy_reason`, `host_outcomes`, and `blast_radius` so operators can audit host scope and safety decisions after each run.
- `OpenCodeLab-GUI.ps1` reads the newest artifact from the current run window and appends an operator-friendly status line.

## Loading conventions

- `SimpleLab.psm1` and `Lab-Common.ps1` both use `Get-LabScriptFiles` (from `Private/Import-LabScriptTree.ps1`) to discover `Private/` then `Public/` scripts recursively in deterministic sorted order.
- Both entry points then dot-source those discovered files in caller scope so loaded functions are available to module consumers and standalone workflows.

## Design principles

- Keep operational scripts thin; centralize reusable logic in module functions.
- Prefer idempotent operations and explicit status output over implicit side effects.
- Keep topology naming consistent (`DC1`, `SVR1`, `WS1`, optional `LIN1`) across logs, prompts, and docs.

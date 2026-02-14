# Fast Deploy/Teardown + GUI Wrapper Design

## Goal

Provide operators with a predictable quick/full orchestration model for `deploy` and `teardown`, plus a lightweight GUI wrapper that safely launches `OpenCodeLab-App.ps1` and reports run outcomes.

## Scope

- In scope:
  - Mode-aware orchestration for `deploy` and `teardown`.
  - Automatic quick->full fallback when state checks fail.
  - GUI launcher for common actions/modes and key switches.
  - Run artifact visibility for CLI and GUI users.
- Out of scope:
  - New deployment mechanics beyond existing scripts.
  - Background service/daemon orchestration.
  - Remote multi-host control.

## Runtime Design

1. `OpenCodeLab-App.ps1` receives `-Action` and `-Mode`.
2. Dispatch helper resolves whether action participates in mode orchestration.
3. For orchestration actions (`deploy`, `teardown`), state probe checks lab readiness signals.
4. Mode decision computes requested vs effective mode and a fallback reason.
5. Orchestration intent maps effective mode to executable path:
   - `deploy/quick`: start -> status -> health
   - `deploy/full`: full `Deploy.ps1`
   - `teardown/quick`: stop -> optional `LabReady` restore
   - `teardown/full`: destructive blow-away flow
6. Run artifacts persist metadata/events for post-run diagnostics.

## Operator UX

- CLI operators can request `-Mode quick` without manually checking state first.
- If quick preconditions are not met, routing transparently falls back to full and records why.
- GUI operators get:
  - Command preview matching launch options.
  - One-click run start in a separate PowerShell process.
  - Latest artifact summary for run completion feedback.

## Safety and Constraints

- Full teardown remains explicit and supports `-DryRun`.
- `menu` remains interactive-only; noninteractive flows use explicit actions.
- Docs describe only current behavior implemented in `OpenCodeLab-App.ps1` and helper files.

## Validation Strategy

- Verify docs reference only actions present in `OpenCodeLab-App.ps1` `ValidateSet`.
- Verify docs mention only implemented mode values (`quick`, `full`).
- Verify GUI doc references only options/actions wired in `OpenCodeLab-GUI.ps1`.

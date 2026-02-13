# Architecture Notes

## Runtime model

The repository has two layers:

- **Module layer (`SimpleLab`)**: reusable commands in `Public/` and `Private/`, loaded via `SimpleLab.psm1`.
- **Orchestration layer**: app-like scripts (`OpenCodeLab-App.ps1`, `Bootstrap.ps1`, `Deploy.ps1`, `Scripts/*.ps1`) that compose module functions into workflows.

## Core workflows

- **Bootstrap** (`Bootstrap.ps1`): installs dependencies and validates host prerequisites.
- **Deploy** (`Deploy.ps1`): creates/repairs core topology (DC1, SVR1, WS1), with optional LIN1 flow.
- **Operate** (`OpenCodeLab-App.ps1`): action router for setup, start, health, rollback, reset, and menu mode.

## Loading conventions

- `SimpleLab.psm1` loads `Private/*.ps1` then `Public/*.ps1` in deterministic sorted order.
- `Lab-Common.ps1` provides the same deterministic loading behavior for standalone script execution.

## Design principles

- Keep operational scripts thin; centralize reusable logic in module functions.
- Prefer idempotent operations and explicit status output over implicit side effects.
- Keep topology naming consistent (`DC1`, `SVR1`, `WS1`, optional `LIN1`) across logs, prompts, and docs.

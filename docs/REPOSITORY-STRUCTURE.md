# Repository Structure

## Top-level directories

- `Public/`: exported module cmdlets used by users and orchestration scripts.
- `Public/Linux/`: Linux-focused exported helpers grouped under the main public API tree.
- `Private/`: internal helpers not exported from the module.
- `Private/Linux/`: Linux-focused internal helpers.
- `Scripts/`: operator-facing utility scripts (status, start day, push/test flows, LIN1 tasks).
- `LabBuilder/`: role selection and role template definitions.
- `Ansible/`: inventory template and playbooks for optional Linux-side automation.
- `Tests/`: Pester suites and test runner.
- `.planning/`: planning documents and local planning state.
- `docs/`: architecture and repository organization notes.

## Top-level files

- `SimpleLab.psd1`: module manifest and export contract metadata.
- `SimpleLab.psm1`: module root loader and explicit exported members.
- `Lab-Config.ps1`: environment-specific defaults (VM names, network, paths, timing).
- `Lab-Common.ps1`: script-loader shim for non-module workflows.
- `OpenCodeLab-App.ps1`: primary user entry point for action-driven operations.
- `Bootstrap.ps1`: machine/bootstrap prerequisites.
- `Deploy.ps1`: full deployment and post-deployment configuration.

## Hygiene conventions

- Keep generated test outputs and coverage artifacts out of git (`*.xml`, `coverage.xml`, `testResults.xml`).
- Add new reusable behavior to `Public/` or `Private/` first, then call it from orchestration scripts.
- Keep new docs under `docs/` unless they are day-to-day operator runbooks at root.
- Keep script loading logic centralized via `Private/Import-LabScriptTree.ps1` instead of duplicating import loops.

# Repository Structure

## Top-level directories

- `Public/`: exported module cmdlets used by users and orchestration scripts.
- `Public/Linux/`: Linux-focused exported helpers grouped under the main public API tree.
- `Private/`: internal helpers not exported from the module.
- `Private/Linux/`: Linux-focused internal helpers.
- `Scripts/`: operator-facing utility scripts (status, start day, push/test flows, LIN1 tasks, scoped confirmation token issuance).
- `LabBuilder/`: role selection and role template definitions.
- `Ansible/`: inventory template and playbooks for optional Linux-side automation.
- `Tests/`: Pester suites and test runner.
- `.planning/`: planning documents and local planning state.
- `docs/`: architecture and repository organization notes.
- `docs/plans/`: dated design and implementation plans for major workflow changes.

## Top-level files

- `SimpleLab.psd1`: module manifest and export contract metadata.
- `SimpleLab.psm1`: module root loader and explicit exported members.
- `Lab-Config.ps1`: environment-specific defaults (VM names, network, paths, timing).
- `Lab-Common.ps1`: script-loader shim for non-module workflows.
- `OpenCodeLab-App.ps1`: primary user entry point for action-driven operations.
- `OpenCodeLab-GUI.ps1`: WinForms wrapper for launching app actions with command preview/status output.
- `Bootstrap.ps1`: machine/bootstrap prerequisites.
- `Deploy.ps1`: full deployment and post-deployment configuration.

## Orchestration helpers

- `Private/Resolve-LabDispatchPlan.ps1`: normalizes requested action/mode before routing.
- `Private/Get-LabHostInventory.ps1`: resolves host inventory and validates target host selections.
- `Private/Resolve-LabOperationIntent.ps1`: computes orchestration intent from action/mode plus `-TargetHosts`/`-InventoryPath`.
- `Private/Resolve-LabCoordinatorPolicy.ps1`: fail-closed coordinator policy evaluator (`Approved`, `EscalationRequired`, `PolicyBlocked`).
- `Private/New-LabScopedConfirmationToken.ps1`: creates scoped confirmation tokens for destructive operations.
- `Private/Test-LabScopedConfirmationToken.ps1`: validates scoped confirmation tokens at execution time.
- `Private/Get-LabStateProbe.ps1`: probes lab registration, VM presence, LabReady snapshot, and network primitives.
- `Private/Resolve-LabModeDecision.ps1`: determines requested vs effective mode and fallback reason.
- `Private/Resolve-LabOrchestrationIntent.ps1`: maps effective mode to quick/full execution strategy.
- `Private/Resolve-LabExecutionProfile.ps1`: composes operation defaults with optional profile JSON overrides.
- `Private/New-LabAppArgumentList.ps1`: builds safe argument arrays for the GUI launcher.
- `Private/Get-LabRunArtifactSummary.ps1`: renders command preview and parses latest run artifacts for GUI status.

## Hygiene conventions

- Keep generated test outputs and coverage artifacts out of git (`*.xml`, `coverage.xml`, `testResults.xml`).
- Add new reusable behavior to `Public/` or `Private/` first, then call it from orchestration scripts.
- Keep new docs under `docs/` unless they are day-to-day operator runbooks at root.
- Keep script loading logic centralized via `Private/Import-LabScriptTree.ps1` instead of duplicating import loops.

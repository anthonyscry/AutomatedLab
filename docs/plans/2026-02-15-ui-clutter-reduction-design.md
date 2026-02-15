# UI Clutter Reduction Design

Date: 2026-02-15
Scope: `OpenCodeLab-GUI.ps1` and GUI helper behavior in `Private/*.ps1`
Decision Status: Approved by user

## Problem statement

The GUI currently presents all operational controls and status details at once, making it harder for operators to focus on quick actions. We want the same operational power with less cognitive load, while still preserving discoverability for destructive and policy-sensitive options.

## Chosen approach

Use **progressive disclosure**:

- Keep common actions and default-safe switches visible.
- Hide less-frequent controls under a collapsible "Advanced options" panel.
- Keep command preview and run artifact summaries compact by default, with an explicit details expansion.

This preserves power-user paths but prevents the initial form from feeling crowded.

## Architecture

- `OpenCodeLab-GUI.ps1` remains the runtime owner for layout, run lifecycle, and status rendering.
- `Private/New-LabAppArgumentList.ps1` and `Private/Get-LabGuiCommandPreview.ps1` remain the source of command-shaping logic.
- `Private/Get-LabGuiDestructiveGuard.ps1` drives auto-defaults for `NonInteractive` and confirmation gating.
- `Private/Get-LabRunArtifactSummary.ps1` remains the artifact parser and is reused to produce a compact summary line in normal mode.

Data flow:

1. User selects action/mode/options.
2. UI computes a visibility profile (`showAdvanced`, `showDetails` defaults).
3. Preview refresh runs from the same options hashtable used to build the launch arguments.
4. On Run, guard/confirmation checks continue as-is.
5. Process starts in a child PowerShell and poll loop watches completion.
6. Poll loop reads the newest artifact; compact summary is shown in the status area, with full artifact details deferred behind a details view.

## UI behavior

- Always visible core controls:
  - `Action`, `Mode`
  - `NonInteractive`, `Force`, `DryRun`
  - Command preview line
- Collapsible advanced area (initially hidden):
  - `RemoveNetwork`, `CoreOnly`
  - `ProfilePath`, `DefaultsFile`
  - `TargetHosts`, `ConfirmationToken`
- Guarded behavior:
  - For destructive combinations (`teardown full`, `blow-away`, `one-button-reset`, and profile-override quick teardown), `Advanced` opens automatically and `NonInteractive` defaults false.

## Error handling and feedback

- Preserve current guard/confirmation checks and their failure messages.
- Run startup failures still emit a single explicit error in the status box.
- Artifact parsing failures degrade to:
  - show compact summary with raw error reason and
  - keep a user-triggered path to view the raw artifact file when available.

## Testing strategy

- Unit-test helper behavior in `Tests/OpenCodeLabGuiHelpers.Tests.ps1`:
  - visibility decisions for advanced panel defaults
  - compact summary formatter for artifact objects/errors
  - command preview stability under core/advanced combinations
- Manual validation checklist:
  - non-destructive action path remains one-screen minimal
  - destructive action auto-opens advanced section and requires confirmation
  - status is readable in compact mode and full details remain available

## Acceptance criteria

- Default GUI startup shows fewer controls than today.
- Advanced section is intentionally hidden yet quickly discoverable.
- Command preview and status text are shorter in normal operation and still reflect exact launch semantics.
- No change to CLI behavior outside the GUI process (`OpenCodeLab-App.ps1` command semantics unchanged).

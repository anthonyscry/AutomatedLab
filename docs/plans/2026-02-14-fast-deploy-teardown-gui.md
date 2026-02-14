# Fast Deploy/Teardown + GUI Wrapper Documentation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update operator docs to accurately explain quick/full orchestration behavior and GUI wrapper usage without overstating capabilities.

**Architecture:** Documentation follows the runtime flow in `OpenCodeLab-App.ps1` and `Private/*` orchestration helpers. README remains operator-first, while architecture/structure docs capture internal boundaries and helper responsibilities. Changelog tracks new guidance and files under Unreleased.

**Tech Stack:** Markdown, PowerShell scripts (`OpenCodeLab-App.ps1`, `OpenCodeLab-GUI.ps1`), git.

---

### Task 1: Capture source-of-truth behavior

**Files:**
- Modify: `README.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/REPOSITORY-STRUCTURE.md`
- Modify: `CHANGELOG.md`
- Read-only references: `OpenCodeLab-App.ps1`, `OpenCodeLab-GUI.ps1`, `Private/Resolve-LabDispatchPlan.ps1`, `Private/Resolve-LabModeDecision.ps1`, `Private/Resolve-LabOrchestrationIntent.ps1`, `Private/Resolve-LabExecutionProfile.ps1`

**Step 1: Map action/mode behavior from code**

- Confirm orchestration actions are `deploy` and `teardown`.
- Confirm allowed modes are `quick` and `full`.
- Confirm quick deploy and quick teardown execution paths.

**Step 2: Map GUI behavior from code**

- Confirm supported GUI actions list.
- Confirm option switches and command preview behavior.
- Confirm run artifact summary behavior.

### Task 2: Update operator-facing docs

**Files:**
- Modify: `README.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/REPOSITORY-STRUCTURE.md`

**Step 1: Refresh README operations guidance**

- Add concise quick/full deploy/teardown examples.
- Add GUI wrapper invocation and behavior notes.
- Keep language operator-friendly and avoid implementation promises.

**Step 2: Refresh architecture and repository structure docs**

- Document orchestration decision pipeline and intent mapping.
- Document GUI wrapper role and helper ownership in `Private/`.

### Task 3: Add release-note and planning docs

**Files:**
- Modify: `CHANGELOG.md`
- Create: `docs/plans/2026-02-14-fast-deploy-teardown-gui-design.md`
- Create: `docs/plans/2026-02-14-fast-deploy-teardown-gui.md`

**Step 1: Update Unreleased changelog**

- Record quick/full orchestration and GUI wrapper additions.
- Record new docs/plans files.

**Step 2: Save design and implementation plan docs**

- Persist design rationale and scope in the design doc.
- Persist actionable documentation plan in this file.

### Task 4: Sanity-check docs against code

**Files:**
- Read-only references: `OpenCodeLab-App.ps1`, `OpenCodeLab-GUI.ps1`

**Step 1: Validate referenced actions and modes exist**

Run: `Select-String -Path .\OpenCodeLab-App.ps1 -Pattern "'deploy'|'teardown'|'quick'|'full'|'one-button-setup'|'blow-away'"`
Expected: Matches for all documented actions/modes.

**Step 2: Validate GUI script and options are present**

Run: `Select-String -Path .\OpenCodeLab-GUI.ps1, .\Private\New-LabAppArgumentList.ps1, .\Private\Get-LabRunArtifactSummary.ps1 -Pattern "New-LabAppArgumentList|New-LabGuiCommandPreview|Get-LabRunArtifactSummary|RemoveNetwork|DryRun|Force|NonInteractive"`
Expected: Matches for documented GUI wrapper behavior.

**Step 3: Commit docs changes**

Run:

```bash
git add README.md docs/ARCHITECTURE.md docs/REPOSITORY-STRUCTURE.md CHANGELOG.md docs/plans/2026-02-14-fast-deploy-teardown-gui-design.md docs/plans/2026-02-14-fast-deploy-teardown-gui.md
git commit -m "docs: add quick-full mode and gui operation guidance"
```

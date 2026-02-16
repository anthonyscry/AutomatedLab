# UI Clutter Reduction Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce visual and status clutter in `OpenCodeLab-GUI.ps1` using progressive disclosure while preserving full capability and existing command semantics.

**Architecture:** The GUI remains a thin launcher over `OpenCodeLab-App.ps1`, with `OpenCodeLab-GUI.ps1` controlling only layout/state and process lifecycle. Helper functions in `Private/` provide reusable state decisions, preview composition, and artifact parsing so the GUI can present a compact normal view and a detailed view on demand.

**Tech Stack:** PowerShell, WinForms, existing Pester tests

---

### Task 1: Add deterministic layout-state helper

**Files:**
- Create: `Private/Get-LabGuiLayoutState.ps1`
- Modify: `OpenCodeLab-GUI.ps1`
- Test: `Tests/OpenCodeLabGuiHelpers.Tests.ps1`

**Step 1: Write the failing test**

```powershell
Describe 'Get-LabGuiLayoutState' {
    It 'keeps advanced options hidden for non-destructive quick defaults' {
        $result = Get-LabGuiLayoutState -Action 'deploy' -Mode 'quick' -ProfilePath ''
        $result.ShowAdvanced | Should -BeFalse
        # Note: ShowDetails was replaced by a standalone checkbox ($chkShowArtifactDetails)
        # and HasTargetHosts property. See implementation for details.
    }

    It 'auto-opens advanced section for destructive-sensitive paths' {
        $result = Get-LabGuiLayoutState -Action 'teardown' -Mode 'full' -ProfilePath ''
        $result.ShowAdvanced | Should -BeTrue
        $result.AdvancedForDestructiveAction | Should -BeTrue
    }
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path .\Tests\OpenCodeLabGuiHelpers.Tests.ps1 -Output Detailed`

Expected: FAIL because `Get-LabGuiLayoutState` is missing.

**Step 3: Write minimal implementation**

```powershell
function Get-LabGuiLayoutState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][ValidateSet('quick', 'full')][string]$Mode,
        [string]$ProfilePath,
        [string[]]$TargetHosts
    )

    $guard = Get-LabGuiDestructiveGuard -Action $Action -Mode $Mode -ProfilePath $ProfilePath
    $hasActionTargets = -not [string]::IsNullOrWhiteSpace(($TargetHosts -join ''))

    # Implementation note: ShowDetails was replaced by a standalone
    # $chkShowArtifactDetails checkbox in the GUI. The helper instead
    # returns HasTargetHosts and RecommendedNonInteractiveDefault.
    return [pscustomobject]@{
        ShowAdvanced = $guard.RequiresConfirmation -or $hasActionTargets
        AdvancedForDestructiveAction = $guard.RequiresConfirmation
        HasTargetHosts = ($normalizedTargets.Count -gt 0)
        RecommendedNonInteractiveDefault = [bool]$guard.RecommendedNonInteractiveDefault
    }
}
```

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path .\Tests\OpenCodeLabGuiHelpers.Tests.ps1 -Output Detailed`

Expected: PASS.

**Step 5: Commit**

```bash
git add Private/Get-LabGuiLayoutState.ps1 OpenCodeLab-GUI.ps1 Tests/OpenCodeLabGuiHelpers.Tests.ps1
git commit -m "feat: add gui layout-state helper for progressive disclosure"
```

### Task 2: Collapse non-critical controls in the GUI

**Files:**
- Modify: `OpenCodeLab-GUI.ps1`

**Step 1: Write the failing test**

No executable UI automation exists in this repo; use helper-driven unit tests only. Confirm current tests still fail by expecting new layout properties to exist before wiring.

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path .\Tests\OpenCodeLabGuiHelpers.Tests.ps1 -Output Detailed`

Expected: PASS for helper tests from Task 1, then red/green remains open for runtime verification.

**Step 3: Write minimal implementation**

In `OpenCodeLab-GUI.ps1`:

- Dot-source `Private/Get-LabGuiLayoutState.ps1`.
- Add container panel for advanced inputs (`$pnlAdvanced`) and move:
  - `RemoveNetwork`
  - `CoreOnly`
  - `ProfilePath`
  - `DefaultsFile`
  - `TargetHosts`
  - `ConfirmationToken`
  - `DryRun`
  into it.
- Add toggle button/checkbox (e.g., `$btnToggleAdvanced`) above the panel and default hide.
- On action/mode/profile/target change, compute:
  `Get-LabGuiLayoutState -Action $cmbAction.SelectedItem -Mode $cmbMode.SelectedItem -ProfilePath $txtProfilePath.Text -TargetHosts $txtTargetHosts.Text`.
- If `ShowAdvanced` is true, set `$pnlAdvanced.Visible = $true` and auto-update `chkNonInteractive` default from guard result.

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path .\Tests\OpenCodeLabGuiHelpers.Tests.ps1 -Output Detailed`

Expected: PASS.

**Step 5: Commit**

```bash
git add OpenCodeLab-GUI.ps1
git commit -m "feat: introduce collapsible advanced panel in gui"
```

### Task 3: Add compact status summary with details gate

**Files:**
- Modify: `OpenCodeLab-GUI.ps1`
- Optional: `Private/Get-LabRunArtifactSummary.ps1` (if helper refactor needed)
- Test: `Tests/OpenCodeLabGuiHelpers.Tests.ps1`

**Step 1: Write the failing test**

```powershell
Describe 'UI status summary formatting' {
    It 'creates a compact run summary line' {
        $payload = @{ run_id = '20260101-020202'; action = 'deploy'; effective_mode = 'quick'; success = $true; duration_seconds = 13 }
        $summary = Get-LabRunArtifactSummary -ArtifactPath $tempPath
        $summary.SummaryText | Should -Match '^\[SUCCESS\] Action=deploy Mode=quick Duration=13s RunId=20260101-020202'
    }
}
```

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path .\Tests\OpenCodeLabGuiHelpers.Tests.ps1 -Output Detailed`

Expected: FAIL until summary gate helper is added/wired.

**Step 3: Write minimal implementation**

- Add a lightweight summary toggle control (checkbox button) and internal flag `$chkShowArtifactDetails`.
- Keep existing status text area and `Add-StatusLine`, but on run completion:
  - always emit one compact line from `Get-LabRunArtifactSummary` text.
  - only emit detailed event lines when the details toggle is enabled.
- If artifact parse fails, emit one error line with reason and keep existing explicit error output.

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path .\Tests\OpenCodeLabGuiHelpers.Tests.ps1 -Output Detailed`

Expected: PASS.

**Step 5: Commit**

```bash
git add OpenCodeLab-GUI.ps1 Tests/OpenCodeLabGuiHelpers.Tests.ps1
git commit -m "feat: compact gui status output with optional details"
```

### Task 4: Preserve command accuracy while reducing visual noise

**Files:**
- Modify: `OpenCodeLab-GUI.ps1`
- Test: `Tests/OpenCodeLabGuiHelpers.Tests.ps1`

**Step 1: Write the failing test**

Re-use existing preview tests and add one for hidden-option visibility to assert hidden controls do not change built arguments.

**Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path .\Tests\OpenCodeLabGuiHelpers.Tests.ps1 -Output Detailed`

Expected: Preview/argument tests fail until advanced panel logic is fully wired and non-visible controls remain part of options object only when set.

**Step 3: Write minimal implementation**

- Keep `New-LabAppArgumentList` input shape unchanged.
- Ensure `Get-SelectedOptions` always includes `Action`/`Mode`/`NonInteractive` and conditional values exactly as before.
- Verify preview text remains full command-string-equivalent for operators who want copy/paste.

**Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path .\Tests\OpenCodeLabGuiHelpers.Tests.ps1 -Output Detailed`

Expected: PASS.

**Step 5: Commit**

```bash
git add OpenCodeLab-GUI.ps1 Tests/OpenCodeLabGuiHelpers.Tests.ps1
git commit -m "test: verify gui declutter does not alter command composition"
```

### Task 5: Run full verification gates

**Files:**
- Read-only verification: `OpenCodeLab-GUI.ps1`, `Private/New-LabAppArgumentList.ps1`, `Private/Get-LabRunArtifactSummary.ps1`

**Step 1: Run focused tests**

Run: `Invoke-Pester -Path .\Tests\OpenCodeLabGuiHelpers.Tests.ps1 -Output Detailed`

Expected: PASS.

**Step 2: Run smoke validation commands from docs**

Run: `pwsh -File .\Scripts\Run-OpenCodeLab.ps1 -NoLaunch -SkipBuild`

Expected: Syntax check and helper dot-load succeed.

**Step 3: Run a quick manual GUI smoke check**

- Open `OpenCodeLab-GUI.ps1`.
- Validate:
  - default view minimal and readable,
  - advanced section reveals on destructive selection,
  - compact status line appears on run completion,
  - command preview matches launched arguments.

**Step 4: Commit**

```bash
git add OpenCodeLab-GUI.ps1 Private/Get-LabGuiLayoutState.ps1 Private/Get-LabGuiCommandPreview.ps1 Tests/OpenCodeLabGuiHelpers.Tests.ps1
git commit -m "docs: document and verify gui declutter implementation"
```

---

Execution handoff summary: this plan intentionally avoids changing `OpenCodeLab-App.ps1` argument behavior and keeps behavior parity while reducing UI and status clutter.

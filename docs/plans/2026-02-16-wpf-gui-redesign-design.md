# WPF GUI Redesign — Design Document

**Date:** 2026-02-16
**Status:** Approved
**Approach:** PowerShell + WPF with external `.xaml` files (Approach 3)

## Goal

Replace the current WinForms launcher GUI (`OpenCodeLab-GUI.ps1`) with a full WPF management dashboard featuring live VM status cards, network topology visualization, an actions launcher, real-time log viewer, settings editor, and switchable dark/light themes.

## Architecture

### File Structure

```
GUI/
├── MainWindow.xaml              # Shell: sidebar nav + content area
├── MainWindow.ps1               # Window logic, navigation, theme toggle
├── Themes/
│   ├── Dark.xaml                 # Dark color palette + styles
│   └── Light.xaml                # Light color palette + styles
├── Views/
│   ├── DashboardView.xaml        # VM cards + topology canvas
│   ├── ActionsView.xaml          # Launch operations (replaces current GUI)
│   ├── LogsView.xaml             # Real-time log viewer
│   └── SettingsView.xaml         # Config editor (paths, passwords, etc.)
├── Components/
│   ├── VMCard.xaml               # Reusable VM status card template
│   └── TopologyMap.xaml          # Network topology canvas
└── Start-OpenCodeLabGUI.ps1      # Entry point, loads XAML + sources helpers
```

### Integration with Existing Code

- `Start-OpenCodeLabGUI.ps1` sources all `Private/` and `Public/` functions (same pattern as `OpenCodeLab-App.ps1`)
- Actions page calls existing functions directly (`Initialize-LabVMs`, `Reset-Lab`, etc.) — no subprocess launching
- Dashboard polls VM state via `Get-VM`, `Test-LabVM`, `Get-VMNetworkAdapter` on a `DispatcherTimer`
- Existing CLI menu in `OpenCodeLab-App.ps1` remains untouched — GUI is an alternative entry point
- Reuses existing helpers: `Get-LabGuiDestructiveGuard`, `Get-LabGuiLayoutState`, `New-LabAppArgumentList`, `Get-LabRunArtifactSummary`, `ConvertTo-LabTargetHostList`

### Navigation Model

Sidebar with icons + labels: Dashboard, Actions, Logs, Settings. Content area swaps views. Similar to Windows Settings app.

## Dashboard View

### Layout

Two-panel split — VM cards on the left (~40% width), topology canvas on the right (~60%).

### VM Cards

Each VM (dc1, svr1, ws1, lin1) displayed as a card showing:

- VM name + role label (e.g., "dc1 — Domain Controller")
- Status indicator: colored dot (green=Running, red=Off, yellow=Paused, gray=Unknown)
- IP address (from `Get-VMNetworkAdapter`)
- Memory / CPU usage bars (from `Measure-VM`)
- Quick action buttons: Start, Stop, Connect (RDP/SSH)

Cards update every 5 seconds via `DispatcherTimer` + background runspace.

### Topology Canvas

Simple network diagram drawn on a WPF `Canvas`:

- Virtual switch in the center as a horizontal bar
- NAT gateway box at the top with external IP
- VM nodes connected to the switch with lines
- Node colors match VM status (green/red/yellow)
- Labels show VM name + IP
- Static layout — positions calculated from VM count
- Redraws when VM list changes

### Polling Strategy

- Background PowerShell runspace runs `Get-VM` every 5 seconds
- Dispatches results back to UI thread via `$window.Dispatcher.Invoke()`
- All Hyper-V cmdlets run off-thread to avoid UI freezing

## Actions View

Replaces the current WinForms GUI with styled WPF controls.

### Controls

- **Action dropdown:** deploy, teardown, status, health, setup, one-button-setup, one-button-reset, blow-away
- **Mode dropdown:** quick, full
- **Toggle switches:** NonInteractive, Force, DryRun (modern toggle style, not checkboxes)
- **Collapsible "Advanced" expander:** RemoveNetwork, CoreOnly, ProfilePath, TargetHosts, ConfirmationToken
- **Auto-reveal logic:** Reuses `Get-LabGuiDestructiveGuard` and `Get-LabGuiLayoutState` unchanged
- **Command preview:** Read-only textbox with full PowerShell command (copy-paste friendly)
- **Run button:** Large, accent-colored. Shows "Running..." with progress ring during execution

### Execution Model

- Actions run in a background runspace within the same process (not a separate `powershell.exe`)
- Output streams to Logs view in real-time via synchronized queue
- Enables live progress without file polling

### Safety Gates

Confirmation dialogs for destructive actions, styled as WPF modal dialogs.

## Logs View

- Scrollable monospace text area (Cascadia Code / Consolas)
- Color-coded lines: white=info, yellow=warning, red=error, green=success
- Auto-scroll with "pin to bottom" toggle
- Filter bar: dropdown by level (All, Info, Warning, Error)
- Clear button to reset
- Logs persist during session — switching views doesn't lose output
- Auto-switches to Logs view when an action starts running

## Settings View

Reads/writes `Lab-Config.ps1` values via `$GlobalLabConfig`.

### Sections

- **Paths:** LabRoot, ISO paths (with browse buttons via `OpenFileDialog`)
- **Network:** SwitchName, Subnet, GatewayIP
- **Credentials:** Admin password (masked field)
- **Theme:** Dark/Light toggle (mirrored from sidebar)

Save button writes changes back to config. Validates inputs before saving (IP format, paths exist).

## Theming (Dark/Light)

### Implementation

- Two resource dictionary XAML files (`Dark.xaml`, `Light.xaml`) defining colors, button styles, textbox styles, card templates
- Toggle button in sidebar (sun/moon icon)
- Swapped at runtime via `Application.Current.Resources.MergedDictionaries`
- Preference persisted to `gui-settings.json` in `.planning/`
- Default: Dark theme

### Color Palettes

**Dark:**
- Background: `#1E1E2E`, Cards: `#2A2A3C`, Accent: `#7C3AED` (purple), Text: `#E0E0E0`

**Light:**
- Background: `#F5F5F5`, Cards: `#FFFFFF`, Accent: `#6D28D9` (purple), Text: `#1A1A1A`

## Key Principles

- **Thin wrapper:** GUI does not contain business logic. All functionality available via CLI.
- **No compilation:** Pure `.ps1` + `.xaml` files, same dev workflow as today.
- **Existing code untouched:** CLI menu, all Public/Private functions remain as-is.
- **Progressive disclosure:** Advanced controls hidden until needed.
- **Safety-first:** Confirmation gates on destructive operations.

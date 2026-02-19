# Phase 5: GUI Integration - Context

**Gathered:** 2026-02-17
**Status:** Ready for planning

<domain>
## Phase Boundary

WPF GUI provides full feature parity with CLI — all actions accessible and functional from both interfaces. Dashboard view loads and polls VM status every 5 seconds without crashes. Actions view populates dropdown with all available actions and executes them correctly. Customize view loads template editor, creates/saves/applies templates without errors. Settings view persists theme, admin username, and preferences to gui-settings.json. Logs view displays color-coded log entries from in-memory log list. View switching works reliably between all views without state corruption. Script-scoped variable closures captured correctly in all event handlers.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
User explicitly deferred all implementation decisions to Claude across Phases 3, 4, and this phase follows the same pattern. The following areas are open for Claude to determine the best approach based on codebase analysis:

**View reliability:**
- How to handle WPF dispatcher thread marshaling for background operations
- Timer-based polling approach for Dashboard VM status updates
- Error recovery when a view fails to load (fallback vs error message)
- Whether to add defensive null-checks on XAML element bindings

**Action execution from GUI:**
- How to wire GUI action dropdown to CLI action handlers
- Background thread execution for long-running actions (deploy, teardown)
- Progress reporting back to UI thread
- How to handle action failures without crashing the GUI

**State management:**
- Script-scoped variable capture strategy for WPF event handler closures
- View switching state isolation (cleanup previous view before loading next)
- Settings persistence error handling (corrupt JSON, missing file)
- In-memory log list management (size limits, thread safety)

**Feature parity:**
- Mapping between CLI actions and GUI controls
- Which actions need confirmation dialogs in GUI (matching CLI confirmation gates)
- Template editor integration with existing Private/ template helpers

</decisions>

<specifics>
## Specific Ideas

- User wants every GUI view to work without crashes — reliability over features
- Dashboard should show live VM status with automatic refresh
- Actions dropdown should match CLI's 25+ actions exactly
- Customize view already has template editor — needs hardening, not new features
- Settings persistence already works — needs error handling for edge cases
- Logs view already displays entries — needs color coding and proper formatting
- View switching is the most fragile area — WPF dispatcher issues cause crashes

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 05-gui-integration*
*Context gathered: 2026-02-17*

---
phase: 10-module-diagnostics
created: 2026-02-17
---

# Phase 10: Module Diagnostics — Context

## Decisions

### 1. Out-Null Replacement Strategy: Context-Aware

**Decision:** Replace Out-Null using context-appropriate patterns, not a blanket Write-Verbose.

| Pattern | Replacement | Rationale |
|---------|-------------|-----------|
| Cmdlet output suppression (Hyper-V, Import-Module, New-Item in prod code) | `Write-Verbose "..."` or `$null = ...` | Surfaces diagnostic info via -Verbose |
| .NET return value suppression (`.Add()`, `Parser.ParseFile()`) | `[void]` cast or `$null =` | Write-Verbose doesn't suppress return values |
| External process suppression (`2>&1 \| Out-Null`) | Leave as-is | These intentionally discard all output |
| Test file Out-Null (`New-Item` in test setup) | Leave as-is | Test infrastructure, not diagnostic path |
| `Read-Host \| Out-Null` | Leave as-is | Intentional discard of user input return |

### 2. GUI Out-Null: Convert to [void] Cast

**Decision:** Convert all 50 GUI `| Out-Null` instances to `[void]` cast pattern.

- `$col.Add($x) | Out-Null` → `[void]$col.Add($x)`
- `$window.ShowDialog() | Out-Null` → `[void]$window.ShowDialog()`
- Cleaner, consistent, slightly more performant (avoids pipeline overhead)

### 3. Ghost Exports: Remove Dead Entries

**Decision:** Remove 3 dead entries from SimpleLab.psm1 Export-ModuleMember:
- `Test-LabCleanup` — no source file exists
- `Test-LabPrereqs` — no source file exists
- `Write-ValidationReport` — no source file exists

Sync SimpleLab.psd1 FunctionsToExport to match actual Public/ function count.

## Scope Revision

Original estimate: 65 Out-Null instances.
Actual count: 261 Out-Null instances across 63 files.

Breakdown by action:
- ~120 instances in Private/, Public/, LabBuilder/, Bootstrap.ps1, Deploy.ps1 → context-aware replacement
- ~50 instances in GUI/ → [void] cast
- ~70 instances in Tests/ → leave as-is
- ~21 instances in Scripts/ → context-aware replacement (production-adjacent)

## Constraints

- PowerShell 5.1 compatibility (both `[void]` and `$null =` work)
- No behavior changes — output suppression must be preserved
- Write-Verbose messages should be concise and useful (not just "command completed")

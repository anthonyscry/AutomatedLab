# SimpleLab

## What This Is

A streamlined PowerShell CLI tool for spinning up Windows domain test labs via Hyper-V. Menu-driven interface for quick lab creation and teardown. Simplified version of the existing AutomatedLab project.

## Core Value

One command builds a Windows domain lab; one command tears it down.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Menu-driven lab type selection
- [ ] Windows Domain template (1 DC, 1 Server 2019, 1 Win 11)
- [ ] Fast VM provisioning
- [ ] Remove lab VMs command (preserves templates)
- [ ] Clean slate command (removes everything)
- [ ] Hyper-V on local machine

### Out of Scope

- **Linux servers** — Original source of complexity, not needed for Windows domain testing
- **Complex configuration options** — Keep it simple: pick lab type, go
- **Multi-lab management** — One lab at a time is fine

## Context

This is a simplification of the existing AutomatedLab project in this repository. The project grew complex with Linux server support and numerous configuration options that made builds slow and the tool difficult to use.

The goal is to return to the original simple purpose: spin up a Windows domain test environment quickly for development/testing, then tear it down just as quickly.

## Constraints

- **PowerShell** — Existing codebase is PowerShell, continue with it
- **Hyper-V only** — Local Windows machine with Hyper-V enabled
- **Windows focus** — Domain Controller, Server 2019, Windows 11
- **Local only** — No remote/Azure considerations

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Remove Linux support | Was the main source of complexity and build slowness | — Pending |
| Menu-driven interface | Easier than editing config files for simple use cases | — Pending |
| Preserve templates on teardown | Faster rebuilds, don't re-download ISOs each time | — Pending |

---
*Last updated: 2025-02-09 after initialization*

# Changelog

## v1.2.0 - Compatibility Hardening

- Replaced all `<# ... #>` block comments with `#` line comments across all 15 scripts
- Stripped UTF-8 BOMs from Lab-Common, Start-LabDay, Test-OnWS1
- Removed unicode/non-ASCII characters from Deploy.ps1 and Bootstrap.ps1
- Removed redundant `#Requires -Modules AutomatedLab` from Deploy.ps1
- All scripts now extract cleanly from GitHub release zips without parser errors

## v1.1.0 - Cleanup & Bugfix Release

### Bug Fixes (17 total)
- Fixed `Get-LIN1IPForUI` infinite recursion in menu
- Fixed menu invoking scripts by wrong filenames
- Fixed `Open-LabTerminal` param() block placement
- Fixed Deploy heredoc using interpolating strings that destroyed bash `$(...)` syntax
- Fixed stale script filenames in Lab-Config
- Fixed raw bash syntax in Lab-Status ScriptBlock and missing variable passing
- Fixed broken bash variable escaping in Push-ToWS1
- Fixed broken bash variable escaping in Save-LabWork
- Fixed `$LinuxUser` not passed to remote scriptblock in New-LabProject
- Fixed duplicate step numbering in Bootstrap
- Fixed hardcoded values in health check (now dot-sources Lab-Config)
- Fixed `$args` automatic variable collision (renamed to `$scriptArgs`)
- Fixed deprecated `gateway4:` in netplan for Ubuntu 24.04 (replaced with `routes:` block)
- Deleted orphan code fragment in Deploy.ps1
- Fixed PS double-quoted string breaking bash `\"` and `||` in Lab-Status
- Fixed swapped here-string terminator in Save-LabWork
- Added VM existence guard after bootstrap

### Simplification Refactor
- Renamed all scripts from verbose `_POLISHED_FINAL` / `_REBUILDABLE` suffixes to clean names
- Deleted superseded `Lab-Menu_POLISHED_FINAL.ps1` (replaced by `OpenCodeLab-App.ps1`)
- Added `Invoke-BashOnLIN1` helper to `Lab-Common.ps1` (copy `.sh` + remote execute pattern)
- Added `Ensure-VMsReady` helper to `Lab-Common.ps1`
- Centralized deploy hardcoded values into `Lab-Config.ps1`
- Refactored daily scripts to use shared helpers
- Simplified `Resolve-ScriptPath` in orchestrator (direct join, no glob)
- Updated all internal cross-references to new filenames
- Updated README and docs

## v1.2.0 - Parameter Audit & Documentation

### AutomatedLab Parameter Audit
- Audited all 15 cmdlets against AutomatedLab source (commit 869e498b890682640a1d2b0b514756509d9844b7)
- **Result:** All cmdlet parameters in codebase are CORRECT
- Install-Lab correctly called without -Machines parameter (installs all defined machines)

### Documentation Updates
- Updated README with cmdlet parameter reference
- Added parameter validation examples to comments

## v1.0.0 - Automation Hardening Release

- Added `OpenCodeLab-App.ps1` as the single orchestrator entry point.
- Added one-button setup/reset workflows and desktop shortcut installer.
- Added strict preflight (`Test-OpenCodeLabPreflight.ps1`) and health gate (`Test-OpenCodeLabHealth.ps1`).
- Added automatic rollback attempt to `LabReady` when post-deploy health fails.
- Added noninteractive support across setup and daily workflow scripts.
- Standardized SSH key path usage to `C:\LabSources\SSHKeys\id_ed25519`.
- Hardened deploy secret handling: admin password now required via env var or parameter.
- Replaced plaintext SMB password-in-fstab with a protected credentials file on LIN1.
- Added machine-readable run artifacts (`json` + `txt`) with retention support.
- Added destructive action dry-run support.

## Breaking/Operational Notes

- `Deploy.ps1` now requires `-AdminPassword` or `OPENCODELAB_ADMIN_PASSWORD`.
- `OpenCodeLab-App.ps1 -Action menu` is interactive-only; automation should use explicit actions.

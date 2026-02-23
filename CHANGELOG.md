# Changelog

All notable changes to OpenCodeLab will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2026-02-22

### Added
- Collapsible Preflight Checks panel on Dashboard showing Hyper-V, AutomatedLab, LabSources, and network status
- Initialize Environment button to install prerequisites and configure the host in one click
- Help window with quick reference guide (getting started, VM roles, default config)
- About window with version, tech stack, and GitHub link
- Help and About buttons in sidebar navigation
- Offline-only installation mode in Setup-AutomatedLab.ps1

### Changed
- Repository reorganized: removed legacy folders, added LabSources scaffold with .gitkeep structure
- Setup script simplified to offline-only installation (removed internet detection logic)
- README rewritten for WPF desktop app workflow
- GETTING-STARTED.md rewritten for GUI-first flow
- ARCHITECTURE.md updated to describe WPF MVVM architecture
- CHANGELOG updated to reflect OpenCodeLab branding

### Fixed
- Incremental deployment now re-adds existing VMs to lab definition including RootDC role
- Preflight panel button alignment using Grid layout instead of DockPanel

### Removed
- Legacy CLI files (OpenCodeLab-App.ps1, OpenCodeLab-GUI.ps1, SimpleLab module)
- Legacy CI workflows
- Development artifacts and tests from v1

## [Unreleased]

### Fixed
- Fixed `Restore-VMCheckpoint` parameter names (`-VMName`/`-Name` instead of `-Name`/`-SnapshotName`) and added `-Confirm:$false` to suppress interactive prompts during restore
- Fixed `Remove-LabVMs` parameter name (`DeleteVHD` instead of `RemoveVHD`) and result property (`VHDDeleted` instead of `VHDRemoved`) to match `Remove-LabVM` return contract
- Fixed preflight switch/NAT warnings to use `Write-Warning` for proper severity
- Fixed `Wait-LabVMReady` variable interpolation (`${vmName}:` instead of `$vmName:`)

### Added
- Added quick/full orchestration helpers for action dispatch, mode fallback decisions, execution intent, and profile resolution used by `OpenCodeLab-App.ps1`.
- Added `OpenCodeLab-GUI.ps1` WinForms wrapper and GUI helper functions for safe argument building, command preview, and latest-run artifact summaries.
- Added coordinator metadata to run artifacts (`policy_outcome`, `policy_reason`, `host_outcomes`, `blast_radius`) for post-run auditability of host scope and policy decisions.
- Added per-VM `EnableHostInternet` policy with VM editor checkbox and deploy-time route enforcement for full and incremental redeploys.
- Disk space validation (65 GB minimum) in `New-LabVM` before VHD creation
- SCP exit code checking in `Copy-LinuxFile` — throws on non-zero exit
- SSH default timeout fallback (10s) and exit code warning in `Invoke-LinuxSSH`
- Dynamic VM list discovery from `$LabVMs` config with LIN1 auto-detection in 5 checkpoint/cleanup functions
- Parallel checkpoint save/restore operations via `Start-Job` with 120s timeout
- Parallel LIN1 git/mount health checks in `Lab-Status.ps1` via `Start-Job` with 30s timeout
- Adaptive heartbeat polling in `Ensure-VMRunning` (500ms intervals, 15s deadline) replacing fixed 2s sleep
- `Write-Verbose` and `Write-Progress` output for `Test-LabDNS` health checks
- Configurable `$LabTimeZone` in `Lab-Config.ps1` (auto-detected from host) used by `New-LabUnattendXml`

### Changed
- Updated operator docs to publish multi-host orchestration arguments (`-TargetHosts`, `-InventoryPath`, `-ConfirmationToken`) and fail-closed coordinator outcomes including `EscalationRequired`.
- Masked admin password in `Add-LIN1.ps1` console output (shows `**********` instead of plaintext)
- `Select-LabRoles` uses cursor repositioning instead of `Clear-Host` to eliminate screen flicker
- Refactored module/script loaders (`SimpleLab.psm1`, `Lab-Common.ps1`) to use deterministic sorted imports with clearer failure messages.
- Consolidated shared loader behavior into `Private/Import-LabScriptTree.ps1` and switched module/script imports to use it.
- Reorganized Linux-specific helpers into `Public/Linux/` and `Private/Linux/` while preserving exported command names.
- Updated tests and coverage discovery to recurse under `Public/` and `Private/` so nested folders are automatically included.
- Removed duplicate Git installer logic in `Deploy.ps1` by reusing a single remote installer scriptblock for both DC1 and Win11.
- Added resilient module root resolution in `SimpleLab.psm1` for environments where `$PSScriptRoot` is unavailable during import.
- Standardized user-facing topology naming in key orchestration flows from legacy `WSUS1` wording to `SVR1` where applicable.
- Expanded `.gitignore` coverage for test and coverage XML artifacts to keep generated files out of version control.
- Centralized admin password resolution for deploy/LIN1 flows through `Resolve-LabPassword` and removed insecure default-password fallback behavior.
- Updated Linux/network defaults to align helper scripts with the `10.0.10.0/24` topology.
- Updated test runner to execute only `*.Tests.ps1` suites (excluding `Run.Tests.ps1`) and fixed noninteractive output-path handling.

### Added
- Added `docs/ARCHITECTURE.md` with runtime model and workflow boundaries.
- Added `docs/REPOSITORY-STRUCTURE.md` with folder responsibilities and repo hygiene conventions.
- Rewrote `README.md` to match current entry points, topology, and usage patterns.
- Added `.planning/runs/` to gitignore to avoid committing generated run artifacts.
- Added design and implementation plan docs for fast deploy/teardown and GUI operations under `docs/plans/`.

### Removed
- Removed tracked root `testResults.xml` artifact.

## [0.2.0] - 2025-02-09

### Added
- Cross-platform support for Linux/macOS development
- VM lifecycle management: `Start-LabVMs`, `Stop-LabVMs`
- Lab status overview: `Get-LabStatus`
- Checkpoint management: `Save-LabCheckpoint`, `Restore-LabCheckpoint`, `Get-LabCheckpoint`
- Comprehensive comment-based help for all public functions
- Platform detection in `Get-HostInfo`

### Changed
- Enhanced `Test-DiskSpace` with Linux/macOS support (uses `df` command)
- Improved `Test-HyperVEnabled` with better verbose output
- Enhanced `Test-LabPrereqs` to skip platform-specific checks gracefully
- Updated `Write-RunArtifact` with cross-platform path handling
- Improved error messages for non-Windows platforms

### Fixed
- Disk space check now works on Linux (uses "/" instead of "C:\")
- Hyper-V check no longer errors on non-Windows platforms
- Path handling now uses `Join-Path` for cross-platform compatibility

## [0.1.0] - 2025-02-08

### Added
- Initial release of SimpleLab module
- VM creation: `New-LabVM`, `Initialize-LabVMs`
- VM removal: `Remove-LabVM`
- Network management: `New-LabSwitch`, `Initialize-LabNetwork`
- Validation: `Test-LabPrereqs`, `Test-HyperVEnabled`, `Test-LabNetwork`
- Network health testing: `Test-LabNetworkHealth`
- Configuration management
- Run artifact tracking
- Default lab configuration (DC, Server, Win11)

[Unreleased]: https://github.com/anthonyscry/OpenCodeLab/compare/v2.1.5...HEAD
[2.1.5]: https://github.com/anthonyscry/OpenCodeLab/releases/tag/v2.1.5
[2.1.4]: https://github.com/anthonyscry/OpenCodeLab/releases/tag/v2.1.4
[2.1.3]: https://github.com/anthonyscry/OpenCodeLab/releases/tag/v2.1.3
[2.1.2]: https://github.com/anthonyscry/OpenCodeLab/releases/tag/v2.1.2
[2.1.1]: https://github.com/anthonyscry/OpenCodeLab/releases/tag/v2.1.1
[2.1.0]: https://github.com/anthonyscry/OpenCodeLab/releases/tag/v2.1.0
[0.2.0]: https://github.com/anthonyscry/OpenCodeLab/releases/tag/v0.2.0
[0.1.0]: https://github.com/anthonyscry/OpenCodeLab/releases/tag/v0.1.0

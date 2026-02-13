# Changelog

All notable changes to SimpleLab will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
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

[Unreleased]: https://github.com/yourusername/SimpleLab/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/yourusername/SimpleLab/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/yourusername/SimpleLab/releases/tag/v0.1.0

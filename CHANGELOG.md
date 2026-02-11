# Changelog

All notable changes to SimpleLab will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

# SimpleLab

Streamlined Windows domain lab automation using PowerShell and Hyper-V.

## Overview

SimpleLab is a PowerShell module that automates the creation and management of Windows domain labs using Hyper-V. It provides a simple, declarative way to set up a complete lab environment with domain controllers, member servers, and client workstations.

## Features

- **Automated VM Creation**: Create and configure lab VMs with a single command
- **Network Management**: Automatic virtual switch and IP configuration
- **Checkpoint Support**: Save and restore lab states for testing scenarios
- **Cross-Platform**: Works on Windows, with graceful handling on Linux/macOS for development
- **Configuration-Based**: JSON configuration for easy customization
- **Run Artifacts**: Automatic tracking of all operations with detailed logging

## Requirements

- Windows 10/11 Pro, Enterprise, or Education (Hyper-V requirement)
- Windows Server 2016 or later
- Hyper-V role enabled
- PowerShell 5.1 or later
- Minimum 16GB RAM (more recommended)
- Minimum 100GB free disk space

## Installation

1. Clone the repository:
```powershell
git clone <repository-url>
cd SimpleLab
```

2. Import the module:
```powershell
Import-Module .\SimpleLab.psd1
```

3. Validate prerequisites:
```powershell
Test-LabPrereqs
```

## Quick Start

### 1. Initialize Configuration

The first time, initialize the lab configuration:

```powershell
Initialize-LabConfig
```

This creates `.planning/config.json` where you can customize ISO paths and requirements.

### 2. Create the Virtual Switch

```powershell
New-LabSwitch
```

### 3. Create Lab VMs

```powershell
Initialize-LabVMs
```

This creates three VMs:
- **SimpleDC**: Domain Controller (2GB RAM, Server 2019)
- **SimpleServer**: Member Server (2GB RAM, Server 2019)
- **SimpleWin11**: Windows 11 Client (4GB RAM, Windows 11)

### 4. Start the Lab

```powershell
Start-LabVMs
```

### 5. Check Lab Status

```powershell
Get-LabStatus
```

## Available Commands

### VM Management

| Command | Description |
|---------|-------------|
| `Initialize-LabVMs` | Create all lab VMs |
| `New-LabVM` | Create a single VM |
| `Remove-LabVM` | Remove a VM (optionally delete VHD) |
| `Start-LabVMs` | Start all lab VMs |
| `Stop-LabVMs` | Stop all lab VMs |
| `Get-LabStatus` | Get status of all VMs |

### Network Management

| Command | Description |
|---------|-------------|
| `New-LabSwitch` | Create the virtual switch |
| `Initialize-LabNetwork` | Configure static IPs for VMs |
| `Test-LabNetwork` | Check if switch exists |
| `Test-LabNetworkHealth` | Test VM-to-VM connectivity |

### Checkpoint Management

| Command | Description |
|---------|-------------|
| `Save-LabCheckpoint` | Create checkpoints for all VMs |
| `Restore-LabCheckpoint` | Restore all VMs to a checkpoint |
| `Get-LabCheckpoint` | List all checkpoints |

### Validation & Testing

| Command | Description |
|---------|-------------|
| `Test-LabPrereqs` | Validate all prerequisites |
| `Test-HyperVEnabled` | Check if Hyper-V is available |

## Configuration

Edit `.planning/config.json` to customize your lab:

```json
{
  "IsoPaths": {
    "Server2019": "C:\\Lab\\ISOs\\Server2019.iso",
    "Windows11": "C:\\Lab\\ISOs\\Windows11.iso"
  },
  "IsoSearchPaths": [
    "C:\\Lab\\ISOs",
    "D:\\ISOs"
  ],
  "Requirements": {
    "MinDiskSpaceGB": 100,
    "MinMemoryGB": 16
  },
  "VMConfiguration": {
    "SimpleDC": {
      "MemoryGB": 4,
      "ProcessorCount": 4
    }
  }
}
```

## Default Network Configuration

| VM Name | IP Address | Role |
|---------|------------|------|
| SimpleDC | 192.168.100.10 | Domain Controller |
| SimpleServer | 192.168.100.20 | Member Server |
| SimpleWin11 | 192.168.100.30 | Client Workstation |

## Examples

### Create a checkpoint before making changes

```powershell
Save-LabCheckpoint -CheckpointName "BeforeDCPromo"
```

### Restore to a previous state

```powershell
Restore-LabCheckpoint -CheckpointName "BeforeDCPromo"
```

### List all checkpoints

```powershell
Get-LabCheckpoint | Format-Table -AutoSize
```

### Gracefully shutdown the lab

```powershell
Stop-LabVMs
```

### Force shutdown (use with caution)

```powershell
Stop-LabVMs -Force
```

## Troubleshooting

### Hyper-V not available

If `Test-LabPrereqs` shows Hyper-V as not available:

1. Check if Hyper-V is enabled:
   ```powershell
   Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
   ```

2. Enable Hyper-V (requires reboot):
   ```powershell
   Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
   Restart-Computer
   ```

### ISO files not found

1. Place ISO files in one of the configured search paths
2. Update `IsoPaths` in `.planning/config.json` with correct paths
3. Run `Test-LabPrereqs` to verify

### VMs can't communicate

1. Ensure VMs are running: `Get-LabStatus`
2. Check network health: `Test-LabNetworkHealth`
3. Verify static IPs are configured: `Initialize-LabNetwork`

## Development

### Project Structure

```
SimpleLab/
├── Public/           # Exported functions
├── Private/          # Internal helper functions
├── .planning/        # Configuration and run artifacts
├── SimpleLab.psd1    # Module manifest
├── SimpleLab.psm1    # Module root
└── SimpleLab.ps1     # Main entry point
```

### Building from Source

```powershell
# Import the module in development mode
Import-Module .\SimpleLab.psd1 -Force

# Run tests
# (Pester tests coming soon)
```

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

MIT License - see LICENSE file for details

## Version History

- **0.1.0** - Initial release
  - VM creation and management
  - Network configuration
  - Checkpoint support
  - Cross-platform compatibility

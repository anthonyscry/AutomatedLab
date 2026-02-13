# SimpleLab v3.0.0

Enhanced Windows domain lab automation using PowerShell and Hyper-V.

## Overview

SimpleLab v3.0.0 combines the best of SimpleLab v2 with Deploy.ps1 features. It provides a streamlined yet powerful way to create and manage Windows domain labs using Hyper-V - with no external dependencies like AutomatedLab required.

## What's New in v3.0.0

- **NAT Network Support**: Create NAT networks for lab Internet access
- **SSH Key Generation**: Built-in SSH key pair generation for Linux VMs
- **Dynamic Memory**: Configure Min/Max memory for each VM
- **Enhanced Configuration**: Deploy.ps1-compatible configuration options
- **Linux VM Ready**: Infrastructure for Ubuntu server VMs (optional)
- **Improved Menu**: New NAT and SSH Key options in interactive menu

## Features

- **Zero Dependencies**: Uses native Hyper-V cmdlets - no AutomatedLab required
- **Automated VM Creation**: Create and configure lab VMs with a single command
- **Network Management**: Internal switch or NAT with gateway configuration
- **Checkpoint Support**: Save and restore lab states for testing scenarios
- **Domain Automation**: AD DS promotion, DNS configuration, domain joins
- **Configuration-Based**: JSON configuration for easy customization
- **Menu Interface**: Interactive menu for all operations
- **CLI Support**: Non-interactive mode for automation

## Requirements

- Windows 10/11 Pro, Enterprise, or Education (Hyper-V requirement)
- Windows Server 2016 or later
- Hyper-V role enabled
- PowerShell 5.1 or later
- Minimum 16GB RAM (more recommended)
- Minimum 100GB free disk space

## Quick Start

### Using the Interactive Menu

```powershell
# Run the main script
.\SimpleLab.ps1
```

This shows an interactive menu with all available operations.

### Using CLI Operations

```powershell
# Build complete lab
.\SimpleLab.ps1 -Operation Build

# Start all VMs
.\SimpleLab.ps1 -Operation Start

# Show status
.\SimpleLab.ps1 -Operation Status

# Setup NAT network
.\SimpleLab.ps1 -Operation NAT

# Generate SSH keys
.\SimpleLab.ps1 -Operation SSHKey
```

### Using PowerShell Module Functions

```powershell
# Import the module
Import-Module .\SimpleLab.psd1

# Check prerequisites
Test-LabPrereqs

# Create virtual switch
New-LabSwitch

# Or create NAT network
New-LabNAT

# Create VMs
Initialize-LabVMs

# Start VMs and wait
Start-LabVMs -Wait

# Configure network
Initialize-LabNetwork

# Configure domain
Initialize-LabDomain
Initialize-LabDNS
Join-LabDomain

# Create checkpoint
Save-LabReadyCheckpoint
```

## Available Commands

### VM Management

| Command | Description |
|---------|-------------|
| `Initialize-LabVMs` | Create all lab VMs |
| `New-LabVM` | Create a single VM |
| `Remove-LabVM` | Remove a VM (optionally delete VHD) |
| `Remove-LabVMs` | Remove multiple VMs |
| `Start-LabVMs` | Start all lab VMs |
| `Stop-LabVMs` | Stop all lab VMs |
| `Restart-LabVM` | Restart a single VM |
| `Restart-LabVMs` | Restart all VMs |
| `Suspend-LabVM` | Suspend a VM (save state) |
| `Resume-LabVM` | Resume a suspended VM |
| `Connect-LabVM` | Open VM console |
| `Get-LabStatus` | Get status of all VMs |
| `Show-LabStatus` | Display color-coded status |
| `Wait-LabVMReady` | Wait for VMs to finish Windows installation |

### Network Management

| Command | Description |
|---------|-------------|
| `New-LabSwitch` | Create internal vSwitch |
| `New-LabNAT` | Create NAT network with gateway |
| `Remove-LabSwitch` | Remove virtual switch |
| `Initialize-LabNetwork` | Configure static IPs for VMs |
| `Test-LabNetwork` | Check if switch exists |
| `Test-LabNetworkHealth` | Test VM-to-VM connectivity |

### Domain Management

| Command | Description |
|---------|-------------|
| `Initialize-LabDomain` | Promote DC and create domain |
| `Initialize-LabDNS` | Configure DNS forwarders |
| `Join-LabDomain` | Join member servers to domain |
| `Test-LabDomainHealth` | Comprehensive domain health check |

### Checkpoint Management

| Command | Description |
|---------|-------------|
| `Save-LabCheckpoint` | Create checkpoints for all VMs |
| `Save-LabReadyCheckpoint` | Create baseline "LabReady" checkpoint |
| `Restore-LabCheckpoint` | Restore all VMs to a checkpoint |
| `Get-LabCheckpoint` | List all checkpoints |

### Lab Operations

| Command | Description |
|---------|-------------|
| `Reset-Lab` | Complete lab teardown (VMs, checkpoints, vSwitch) |
| `Test-LabCleanup` | Verify no orphaned artifacts remain |
| `Test-LabPrereqs` | Validate all prerequisites |
| `Test-HyperVEnabled` | Check if Hyper-V is available |
| `Test-LabIso` | Validate ISO files |
| `New-LabSSHKey` | Generate SSH key pair |

## Configuration

Edit `.planning/config.json` to customize your lab:

```json
{
  "IsoPaths": {
    "Server2019": "C:\\LabSources\\ISOs\\server2019.iso",
    "Windows11": "C:\\LabSources\\ISOs\\windows11.iso",
    "Ubuntu": "C:\\LabSources\\ISOs\\ubuntu-24.04-live-server-amd64.iso"
  },
  "LabSettings": {
    "LabName": "SimpleLab",
    "DomainName": "simplelab.local",
    "EnableLinux": false,
    "EnableNAT": false
  },
  "NetworkConfiguration": {
    "Subnet": "10.0.0.0/24",
    "Gateway": "",
    "SwitchName": "SimpleLab",
    "NATName": "SimpleLabNAT",
    "HostGatewayIP": "10.0.0.1",
    "VMIPs": {
      "SimpleDC": "10.0.0.2",
      "SimpleServer": "10.0.0.3",
      "SimpleWin11": "10.0.0.4",
      "SimpleLIN": "10.0.0.5"
    }
  },
  "VMConfiguration": {
    "SimpleDC": {
      "MemoryGB": 4,
      "MinMemoryGB": 2,
      "MaxMemoryGB": 6,
      "ProcessorCount": 4,
      "DiskSizeGB": 60
    }
  }
}
```

## Default VMs

| VM Name | IP Address | Role | Memory |
|---------|------------|------|--------|
| SimpleDC | 10.0.0.2 | Domain Controller | 4GB |
| SimpleServer | 10.0.0.3 | Member Server | 4GB |
| SimpleWin11 | 10.0.0.4 | Client Workstation | 4GB |
| SimpleLIN | 10.0.0.5 | Linux Server (optional) | 4GB |

## NAT Network Setup

To give your lab VMs Internet access:

```powershell
# Via menu - option 9
.\SimpleLab.ps1

# Or via CLI
.\SimpleLab.ps1 -Operation NAT

# Or via PowerShell
New-LabNAT
```

This creates:
- Internal vSwitch "SimpleLab"
- Host gateway IP (10.0.0.1)
- NAT network "SimpleLabNAT"
- VMs can access Internet through host NAT

## SSH Key Generation

For Linux VMs (SimpleLIN):

```powershell
# Via menu - option A
.\SimpleLab.ps1

# Or via CLI
.\SimpleLab.ps1 -Operation SSHKey

# Or via PowerShell
New-LabSSHKey
```

Keys are saved to `C:\LabSources\SSHKeys` by default.

## Examples

### Complete Lab Build with NAT

```powershell
# Setup NAT first
New-LabNAT

# Build lab
.\SimpleLab.ps1 -Operation Build
```

### Create Checkpoint Before Changes

```powershell
Save-LabCheckpoint -CheckpointName "BeforeTesting"
```

### Restore to Previous State

```powershell
Restore-LabCheckpoint -CheckpointName "BeforeTesting"
```

### Check Lab Health

```powershell
# Full status
Show-LabStatus

# Domain health
Test-LabDomainHealth

# Network health
Test-LabNetworkHealth
```

## Project Structure

```
SimpleLab/
├── Public/           # Exported functions
├── Private/          # Internal helper functions
├── .planning/        # Configuration and run artifacts
├── SimpleLab.psd1    # Module manifest
├── SimpleLab.psm1    # Module root
├── SimpleLab.ps1     # Main entry point (menu/CLI)
└── README.md         # This file
```

## Troubleshooting

### Hyper-V not available

```powershell
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
Restart-Computer
```

### ISO files not found

Edit `.planning/config.json` with correct ISO paths, then run:
```powershell
Test-LabPrereqs
```

### VMs can't communicate

```powershell
Get-LabStatus
Test-LabNetworkHealth
Initialize-LabNetwork
```

## Version History

- **3.0.0** - Merge with Deploy.ps1 features
  - NAT network support
  - SSH key generation
  - Dynamic memory configuration
  - Enhanced configuration system
- **2.2.0** - Complete phase 9 (User Experience)
  - Menu-driven interface
  - CLI argument support
- **2.0.0** - All 9 phases complete
  - Full lifecycle management
  - Snapshot/rollback support
  - Domain configuration
  - VM provisioning

## License

MIT License

## Contributing

Contributions welcome! Please feel free to submit issues or pull requests.

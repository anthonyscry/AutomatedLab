# OpenCodeLab

WPF desktop app for building and managing Hyper-V lab environments using AutomatedLab.

## Features

- **Preflight checks** - Dashboard panel validates Hyper-V, AutomatedLab, LabSources, and network before deployment
- **Initialize Environment** - One-click button to install prerequisites and configure the host
- **One-click deployment** - Create Active Directory domains with DCs, member servers, and workstations
- **Incremental labs** - Add VMs to existing labs without starting over
- **EFI boot repair** - Automatic 3-method repair for Gen2 VM boot failures
- **NAT networking** - Internal switch with NAT for VM internet access (no Wi-Fi bridge conflicts)
- **Dashboard** - Live VM status, RAM, CPU, IP, and role information from Hyper-V
- **Lab management** - Create, edit, deploy, and remove labs through the GUI
- **Help & About** - Built-in quick reference guide and app information

## Requirements

- Windows 10/11 Pro or Enterprise (Hyper-V required)
- .NET 8 Runtime (or use the self-contained portable release)
- AutomatedLab PowerShell module (`Install-Module AutomatedLab`)
- 16GB+ RAM recommended for multi-VM labs

## Quick Start

1. Download the latest release from [Releases](https://github.com/anthonyscry/LabBuilder/releases)
2. Extract the zip
3. Run `OpenCodeLab-V2.exe` as Administrator
4. Review the **Preflight Checks** panel on the Dashboard
5. Click **Initialize Env** to install prerequisites (AutomatedLab, LabSources, network)
6. Place ISOs in `C:\LabSources\ISOs\` (see `LabSources/ISOs/README.md`)
7. Click **New Lab**, configure VMs, click **Deploy**

## Default Configuration

| Setting | Default |
|---------|---------|
| Domain | lab.com |
| Admin Account | dod_admin (Domain Admins + Enterprise Admins) |
| Admin Password | Server123! |
| VM RAM | 4 GB |
| VM Disk | 80 GB |
| VM Storage | C:\LabSources\VMs |
| Network | Internal + NAT (192.168.10.0/24) |

## Repository Structure

```
OpenCodeLab/
├── OpenCodeLab-v2/          # WPF .NET 8 application
│   ├── Models/              # Data models (LabConfig, VirtualMachine)
│   ├── Views/               # XAML views and dialogs
│   ├── ViewModels/          # MVVM view models
│   ├── Services/            # HyperV and deployment services
│   └── Deploy-Lab.ps1       # PowerShell deployment script
├── LabSources/              # AutomatedLab resource scaffold
│   ├── ISOs/                # Windows/Linux ISO files (not tracked)
│   ├── VMs/                 # VM disk storage (not tracked)
│   ├── LabConfig/           # Saved lab configurations (not tracked)
│   ├── CustomRoles/         # Custom AutomatedLab roles
│   ├── Tools/               # Utilities (oscdimg, git, etc.)
│   └── SampleScripts/       # Example lab scripts
└── .github/workflows/       # CI pipelines
```

## Building from Source

```powershell
cd OpenCodeLab-v2
dotnet build -c Release -r win-x64

# Self-contained portable exe
dotnet publish -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true -o publish
```

## VM Roles

| Role | OS | Description |
|------|----|-------------|
| DC | Windows Server 2019 | Domain Controller (RootDC) |
| MemberServer | Windows Server 2019 | Domain-joined server |
| FileServer | Windows Server 2019 | File server role |
| WebServer | Windows Server 2019 | IIS web server |
| Client | Windows 11 Enterprise | Domain-joined workstation |

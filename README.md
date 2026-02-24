# OpenCodeLab

WPF desktop app for building and managing Hyper-V lab environments using AutomatedLab.

## Features

- **Preflight checks** - Dashboard panel validates Hyper-V, AutomatedLab, LabSources, and network before deployment
- **Initialize Environment** - One-click button to install prerequisites and configure the host
- **One-click deployment** - Create Active Directory domains with DCs, member servers, and workstations
- **Incremental labs** - Add VMs to existing labs without starting over
- **EFI boot repair** - Automatic 3-method repair for Gen2 VM boot failures
- **NAT networking** - Internal switch with NAT for VM internet access (no Wi-Fi bridge conflicts)
- **Per-VM host internet policy** - New VM checkbox to allow/block outbound host internet access per machine
- **Dashboard** - Live VM status, RAM, CPU, IP, and role information from Hyper-V
- **Lab management** - Create, edit, deploy, and remove labs through the GUI
- **Help & About** - Built-in quick reference guide and app information

## Requirements

- Windows 10/11 Pro or Enterprise (Hyper-V required)
- .NET 8 Desktop Runtime (required for app-only release zip)
- AutomatedLab PowerShell module (`Install-Module AutomatedLab`)
- 16GB+ RAM recommended for multi-VM labs

## Quick Start

1. Download the latest release from [Releases](https://github.com/anthonyscry/OpenCodeLab/releases)
2. Choose the correct artifact:
   - `OpenCodeLab-v<version>-app-only-win-x64.zip` (smaller, requires installed .NET 8 Desktop Runtime)
   - `OpenCodeLab-v<version>-dotnet-bundle-win-x64.zip` (larger, includes runtime; just extract and run)
3. Extract the selected zip
4. Run `OpenCodeLab-V2.exe` as Administrator
5. Review the **Preflight Checks** panel on the Dashboard
6. Click **Initialize Env** to install prerequisites (AutomatedLab, LabSources, network)
7. Place ISOs in `C:\LabSources\ISOs\` (see `LabSources/ISOs/README.md`)
8. Click **New Lab**, configure VMs, click **Deploy**

IMPORTANT: If .NET 8 Desktop Runtime is not installed on the host, use the `dotnet-bundle` zip.
You do not install the bundle separately; it is already packaged with the app in that zip.

Incremental redeploy applies updated per-VM host internet policy to existing VMs without recreating them.

## Required ISOs (Where to Download)

Place ISOs in `C:\LabSources\ISOs\`.

- Windows Server 2019 Evaluation:
  `https://www.microsoft.com/en-us/evalcenter/download-windows-server-2019`
- Windows 11 Enterprise Evaluation:
  `https://www.microsoft.com/en-us/evalcenter/download-windows-11-enterprise`
- Ubuntu Server (optional):
  `https://ubuntu.com/download/server`

To validate what deployment can detect from your ISOs, run:

```powershell
Get-LabAvailableOperatingSystem -Path 'C:\LabSources\ISOs'
```

If deployment reports an OS mismatch, verify your ISO edition names against this output.

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

## Launcher

Run the repository launcher from root:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "./Scripts/Run-OpenCodeLab.ps1"
```

If no arguments are passed, the launcher opens interactive menu mode.

## Release Packaging

For release maintainers, use the split-artifact packaging script:

```powershell
pwsh -NoProfile -File Build-ReleaseArtifacts.ps1 -Version <x.y.z>
```

This produces:

- `OpenCodeLab-v<version>-app-only-win-x64.zip`
- `OpenCodeLab-v<version>-dotnet-bundle-win-x64.zip` (unless `-SkipDotNetBundle` is used)

It also prints SHA256 hashes and whether the `dotnet-bundle` artifact changed compared to the previous release.

See `RELEASE-PACKAGING.md` for release-note template text.

## VM Roles

| Role | OS | Description |
|------|----|-------------|
| DC | Windows Server 2019 | Domain Controller (RootDC) |
| MemberServer | Windows Server 2019 | Domain-joined server |
| FileServer | Windows Server 2019 | File server role |
| WebServer | Windows Server 2019 | IIS web server |
| Client | Windows 11 Enterprise | Domain-joined workstation |

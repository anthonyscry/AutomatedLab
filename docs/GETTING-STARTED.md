# Getting Started with OpenCodeLab

This guide walks you through setting up and deploying your first Hyper-V lab using the OpenCodeLab desktop app.

See [README.md](../README.md) for a full feature overview.

---

## Requirements

- Windows 10/11 Pro or Enterprise (Hyper-V required; Home edition is **not** supported)
- .NET 8 Desktop Runtime (required for app-only release zip)
- 16 GB+ RAM recommended for multi-VM labs
- 80 GB+ free disk space on an SSD

---

## First Run

### Step 1 - Download and extract

Download the latest release from [Releases](https://github.com/anthonyscry/OpenCodeLab/releases).

Choose the correct artifact:

- `OpenCodeLab-v<version>-app-only-win-x64.zip` (smaller, requires installed .NET 8 Desktop Runtime)
- `OpenCodeLab-v<version>-dotnet-bundle-win-x64.zip` (larger, includes runtime; just extract and run)

If .NET 8 Desktop Runtime is not installed, download the `dotnet-bundle` zip.
No separate runtime installer step is needed when you use the `dotnet-bundle` zip.

Tip: Release notes now include "Dotnet-bundle artifact changed" so you can tell whether an older runtime bundle can be reused.

Extract your selected zip to a folder.

### Step 2 - Run the application

Run `OpenCodeLab-V2.exe` as Administrator (required for Hyper-V access). The app will open to the Dashboard.

### Step 3 - Review preflight checks

The Dashboard shows a **Preflight Checks** panel that validates:

- Hyper-V is enabled
- AutomatedLab PowerShell module is installed
- LabSources folder exists at `C:\LabSources`
- Network switch is configured

Any failed checks will be highlighted. Click **Re-check** to refresh the status.

### Step 4 - Initialize the environment

Click **Initialize Env** to automatically install and configure missing prerequisites:

- Installs AutomatedLab module
- Creates the `C:\LabSources` folder structure
- Configures the Hyper-V network switch and NAT

Wait for initialization to complete, then click **Re-check** to verify all checks pass.

### Step 5 - Place ISO files

Copy your Windows ISO files to `C:\LabSources\ISOs\`:

- **Windows Server 2019 Evaluation** - Required for DC, MemberServer, FileServer, WebServer roles
- **Windows 11 Enterprise Evaluation** - Required for Client role

Download sources:

- Windows Server 2019 Evaluation: `https://www.microsoft.com/en-us/evalcenter/download-windows-server-2019`
- Windows 11 Enterprise Evaluation: `https://www.microsoft.com/en-us/evalcenter/download-windows-11-enterprise`
- Ubuntu Server (optional): `https://ubuntu.com/download/server`

See `LabSources/ISOs/README.md` for specific ISO requirements.

You can validate detected OS entries with:

```powershell
Get-LabAvailableOperatingSystem -Path 'C:\LabSources\ISOs'
```

### Step 6 - Create a lab

Navigate to **Actions** in the sidebar and click **New Lab**:

1. Enter a lab name and domain name
2. Configure network settings
3. Add virtual machines with roles (DC, MemberServer, FileServer, WebServer, Client)
4. Click **Create Lab**

### Step 7 - Deploy

Select your lab from the list and click **Deploy**. Enter the admin password when prompted (default: `Server123!`).

Expected duration: 20-60 minutes depending on host speed and number of VMs.

### Step 8 - Verify

Return to the **Dashboard** to see live VM status including state, RAM, CPU, IP, and role information.

---

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

---

## VM Roles

| Role | OS | Description |
|------|----|-------------|
| DC | Windows Server 2019 | Domain Controller (RootDC) |
| MemberServer | Windows Server 2019 | Domain-joined server |
| FileServer | Windows Server 2019 | File server role |
| WebServer | Windows Server 2019 | IIS web server |
| Client | Windows 11 Enterprise | Domain-joined workstation |

---

## Troubleshooting

### Preflight checks fail after Initialize Env

- Ensure you are running as Administrator
- Check that Hyper-V is enabled in Windows Features
- Reboot if Hyper-V was just enabled

### Deployment fails

- Verify ISOs are in `C:\LabSources\ISOs\` and match expected names
- Check that you have enough disk space and RAM
- Review the deployment output in the Actions panel

### VMs not showing on Dashboard

- Click **Refresh** to reload VM status from Hyper-V
- Ensure the VMs are running in Hyper-V Manager

---

## Next Steps

- **[README.md](../README.md)** - Full feature overview and build instructions
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - Application architecture and design
- **Help > Quick Reference** - Built-in help accessible from the sidebar

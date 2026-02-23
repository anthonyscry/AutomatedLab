# Offline AutomatedLab Modules

This folder is used for airgapped/offline installation of the AutomatedLab PowerShell module.

## Creating an Offline Bundle

On a machine with internet access, run:

```powershell
Save-Module AutomatedLab -Path "LabSources\Modules\" -Repository PSGallery
```

This downloads AutomatedLab and all dependencies (~50MB) into this folder.

## Installing on an Airgapped Server

1. Copy the entire release package (including this `LabSources\Modules\` folder) to the target server
2. Run `Setup-AutomatedLab.ps1` — it auto-detects no internet and installs from the bundled modules
3. Or force offline mode: `.\Setup-AutomatedLab.ps1 -Offline`

## What Gets Installed

The AutomatedLab module and its dependencies are copied to `$env:ProgramFiles\WindowsPowerShell\Modules\`.

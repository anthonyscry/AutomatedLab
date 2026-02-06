# Rollback Runbook

Use this runbook when deployment or health checks fail.

## 1) Check Current Health

```powershell
.\OpenCodeLab-App.ps1 -Action health
```

## 2) Roll Back to Baseline Snapshot

```powershell
.\OpenCodeLab-App.ps1 -Action rollback
```

If rollback fails, the `LabReady` snapshot is likely missing.

## 3) Rebuild Baseline if Needed

```powershell
$env:OPENCODELAB_ADMIN_PASSWORD = "YourStrongPasswordHere"
.\OpenCodeLab-App.ps1 -Action one-button-setup -NonInteractive
```

## 4) Destructive Reset (Last Resort)

Preview first:

```powershell
.\OpenCodeLab-App.ps1 -Action blow-away -DryRun -RemoveNetwork
```

Then execute:

```powershell
.\OpenCodeLab-App.ps1 -Action one-button-reset -NonInteractive -Force -RemoveNetwork
```

## 5) Audit Artifacts

Review latest run reports:

- `C:\LabSources\Logs\OpenCodeLab-Run-*.json`
- `C:\LabSources\Logs\OpenCodeLab-Run-*.txt`

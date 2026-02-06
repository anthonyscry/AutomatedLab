# Secrets Bootstrap

Use this before any noninteractive deployment.

## Required Secret

- `OPENCODELAB_ADMIN_PASSWORD`

`Deploy-OpenCodeLab-Slim_REBUILDABLE_v3.2.ps1` requires this value unless `-AdminPassword` is passed.

## One-Time (Current Shell)

```powershell
$env:OPENCODELAB_ADMIN_PASSWORD = "YourStrongPasswordHere"
```

## Verify

```powershell
if ([string]::IsNullOrWhiteSpace($env:OPENCODELAB_ADMIN_PASSWORD)) { "MISSING" } else { "OK" }
```

## Run

```powershell
.\OpenCodeLab-App.ps1 -Action one-button-setup -NonInteractive
```

## Notes

- Do not commit secrets to git.
- Prefer your local secret manager for persistence.

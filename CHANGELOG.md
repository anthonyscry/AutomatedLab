# Changelog

## v1.0.0 - Automation Hardening Release

- Added `OpenCodeLab-App.ps1` as the single orchestrator entry point.
- Added one-button setup/reset workflows and desktop shortcut installer.
- Added strict preflight (`Test-OpenCodeLabPreflight.ps1`) and health gate (`Test-OpenCodeLabHealth.ps1`).
- Added automatic rollback attempt to `LabReady` when post-deploy health fails.
- Added noninteractive support across setup and daily workflow scripts.
- Standardized SSH key path usage to `C:\LabSources\SSHKeys\id_ed25519`.
- Hardened deploy secret handling: admin password now required via env var or parameter.
- Replaced plaintext SMB password-in-fstab with a protected credentials file on LIN1.
- Added machine-readable run artifacts (`json` + `txt`) with retention support.
- Added destructive action dry-run support.

## Breaking/Operational Notes

- `Deploy-OpenCodeLab-Slim_REBUILDABLE_v3.2.ps1` now requires `-AdminPassword` or `OPENCODELAB_ADMIN_PASSWORD`.
- `OpenCodeLab-App.ps1 -Action menu` is interactive-only; automation should use explicit actions.

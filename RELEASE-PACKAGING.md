# Release Packaging Guide

This guide defines the release artifact split for OpenCodeLab so users can avoid downloading the full runtime bundle when they do not need it.

## Artifact Model

Each release publishes one or two zip files:

1. `OpenCodeLab-v<version>-app-only-win-x64.zip`
   - Smaller download
   - Requires installed .NET 8 Desktop Runtime

2. `OpenCodeLab-v<version>-dotnet-bundle-win-x64.zip` (optional)
   - Larger download
   - Includes runtime for hosts without .NET 8 installed
   - Extract and run directly (no separate runtime install required)

IMPORTANT: Users without .NET 8 Desktop Runtime must download the `dotnet-bundle` zip.
The `dotnet-bundle` artifact is not a runtime-only add-on; it is a complete app package with runtime included.

## Build Artifacts

From repository root:

```powershell
pwsh -NoProfile -File Build-ReleaseArtifacts.ps1 -Version <x.y.z>
```

Optional parameters:

- `-OutputRoot <path>`
- `-PreviousTag v<prev-version>`
- `-PreviousDotNetBundleSha256 <sha256>`
- `-GitHubRepo anthonyscry/OpenCodeLab`
- `-SkipDotNetBundle` (build app-only artifact only)

If `gh` is unavailable in your PowerShell environment, pass `-PreviousDotNetBundleSha256` explicitly so bundle change reporting can still be computed.

The script outputs:

- one or two release zips (depending on `-SkipDotNetBundle`),
- SHA256 hashes,
- `Dotnet-bundle artifact changed: Yes/No/Unknown/Skipped`,
- release-note snippet text.

## Release Notes Template

Include this section in every release:

```markdown
## Downloads
- OpenCodeLab-v<version>-app-only-win-x64.zip
- OpenCodeLab-v<version>-dotnet-bundle-win-x64.zip (omit if `-SkipDotNetBundle` used)

## Dotnet-Bundle Status
- Dotnet-bundle artifact changed: <Yes|No|Unknown|Skipped>
- Reuse prior runtime bundle: <Yes|No|Review required>

## SHA256
- App-only SHA256: <hash>
- Dotnet-bundle SHA256: <hash or N/A when skipped>

## Requirement Reminder
- If .NET 8 Desktop Runtime is not installed, use the `dotnet-bundle` zip.
```

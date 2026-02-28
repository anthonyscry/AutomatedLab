# MyLab Internet Fix Evidence (2026-02-27)

## Context

- Fix commit: `176b77e` (`fix: restore member internet by enabling DC DNS egress in NAT mode`)
- Deployment mode: update-existing, internal Hyper-V switch + host NAT

## Evidence Artifacts

- Redeploy log: `C:\projects\OpenCodeLab\_runlogs\redeploy-MyLab-latest.log`
- Connectivity check log: `C:\projects\OpenCodeLab\_runlogs\connectivity-MyLab-latest.log`
- Console screenshot capture log: `C:\projects\OpenCodeLab\_runlogs\capture-vm-console-screenshots.log`
- MS01 logged-in screenshot workflow log: `C:\projects\OpenCodeLab\_runlogs\capture-ms01-loggedin-proof.log`
- Screenshot (WS01): `C:\Users\Tony\Pictures\Screenshots\MyLab-WS01-20260227-162953.png`
- Screenshot (MS01): `C:\Users\Tony\Pictures\Screenshots\MyLab-MS01-20260227-162953.png`
- Screenshot (MS01 logged in): `C:\Users\Tony\Pictures\Screenshots\MyLab-MS01-loggedin-20260227-165433.png`

## Key Verification Points

1. Redeploy applied the DNS egress safeguard for AD DNS in NAT mode.
   - `redeploy-MyLab-latest.log` includes: `Auto-enabling host internet on domain controller 'DC01'`.
2. Redeploy completed successfully.
   - `redeploy-MyLab-latest.log` includes: `[100%] Deployment completed successfully!`.
3. Member VMs report working internet and DNS.
   - `connectivity-MyLab-latest.log` shows for `MS01` and `WS01`:
     - `GatewayReachable : True`
     - `InternetPing : True`
     - `HttpMsftConnect : True`
     - `IPv4Connectivity : Internet`
4. UI proof captured for both target VMs.
   - `MyLab-WS01-20260227-162953.png`, `MyLab-MS01-20260227-162953.png`, and `MyLab-MS01-loggedin-20260227-165433.png`.

## Validation Commands

1. Pester regression suite for deployment script.
   - Command: `pwsh -NoProfile -Command 'Invoke-Pester -Path "OpenCodeLab-v2/Services/DeployLabScript.Tests.ps1" -CI -PassThru | Select-Object PassedCount, FailedCount, SkippedCount, NotRunCount, Result | Format-List'`
   - Result: `PassedCount: 20`, `FailedCount: 0`, `SkippedCount: 0`, `NotRunCount: 0`, `Result: Passed`
2. PowerShell parser validation for `Deploy-Lab.ps1`.
   - Command: `pwsh -NoProfile -Command '$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile("OpenCodeLab-v2/Deploy-Lab.ps1", [ref]$tokens, [ref]$errors) > $null; if ($errors.Count -eq 0) { "Parse OK" } else { $errors | ForEach-Object { $_.Message }; exit 1 }'`
   - Result: `Parse OK`

# Evidence Summary: fix-dc-dns-egress-for-member-internet

## PR/Issue-ready Summary

Redeploy in update-existing mode now auto-enables host internet on the domain controller when internet-enabled domain members rely on internal NAT DNS. Post-deploy validation confirms member internet/DNS restored for both MS01 and WS01.

## Key Log Evidence

- `_runlogs/redeploy-MyLab-latest.log:85`
  - `WARNING: Auto-enabling host internet on domain controller 'DC01' so domain DNS can resolve external names for internet-enabled member VMs.`
- `_runlogs/redeploy-MyLab-latest.log:88`
  - `[NET] Applying host internet policy to DC01: enabled`
- `_runlogs/redeploy-MyLab-latest.log:99`
  - `[NET] Applying host internet policy to MS01: enabled`
- `_runlogs/redeploy-MyLab-latest.log:109`
  - `[NET] Applying host internet policy to WS01: enabled`
- `_runlogs/redeploy-MyLab-latest.log:167`
  - `[100%] Deployment completed successfully!`
- `_runlogs/connectivity-MyLab-latest.log:26`
  - `GatewayReachable   : True` (MS01)
- `_runlogs/connectivity-MyLab-latest.log:27`
  - `InternetPing       : True` (MS01)
- `_runlogs/connectivity-MyLab-latest.log:30`
  - `HttpMsftConnect    : True` (MS01)
- `_runlogs/connectivity-MyLab-latest.log:36`
  - `IPv4Connectivity   : Internet` (MS01)
- `_runlogs/connectivity-MyLab-latest.log:44`
  - `GatewayReachable   : True` (WS01)
- `_runlogs/connectivity-MyLab-latest.log:45`
  - `InternetPing       : True` (WS01)
- `_runlogs/connectivity-MyLab-latest.log:48`
  - `HttpMsftConnect    : True` (WS01)
- `_runlogs/connectivity-MyLab-latest.log:54`
  - `IPv4Connectivity   : Internet` (WS01)

## Screenshot Paths

- `C:\Users\Tony\Pictures\Screenshots\MyLab-WS01-20260227-162953.png`
- `C:\Users\Tony\Pictures\Screenshots\MyLab-MS01-20260227-162953.png`
- `C:\Users\Tony\Pictures\Screenshots\MyLab-MS01-loggedin-20260227-165433.png`

## Validation Checks

- `Invoke-Pester` on `OpenCodeLab-v2/Services/DeployLabScript.Tests.ps1` (CI mode): `PassedCount: 20`, `FailedCount: 0`, `SkippedCount: 0`, `NotRunCount: 0`, `Result: Passed`
- PowerShell parser check on `OpenCodeLab-v2/Deploy-Lab.ps1`: `Parse OK`

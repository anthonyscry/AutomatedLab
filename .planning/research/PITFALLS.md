# Pitfalls Research

**Domain:** PowerShell Lab Lifecycle Automation — PowerSTIG DSC, ADMX/GPO Import, Lab TTL Scheduled Tasks, WPF Dashboard Enrichment
**Researched:** 2026-02-20
**Confidence:** HIGH (architecture pitfalls from codebase analysis + MEDIUM for PowerSTIG-specific from official docs + community)

> This document covers pitfalls specific to v1.6 features being added to the existing AutomatedLab codebase. It assumes PowerShell 5.1 compatibility, the single-`$GlobalLabConfig` architecture, and the existing DispatcherTimer-based WPF GUI pattern.

---

## Critical Pitfalls

### Pitfall 1: DSC Module Scope — Installing to CurrentUser Instead of Machine Scope

**What goes wrong:**
`Install-Module PowerSTIG -Scope CurrentUser` installs to the current user's profile. DSC configurations run under the SYSTEM account context via the WMI Provider Host Process (`WmiPrvSE`). SYSTEM cannot see modules installed to `C:\Users\<user>\Documents\WindowsPowerShell\Modules`. The MOF compiles successfully on the host but `Start-DscConfiguration` fails on the guest VM with "resource module not found."

**Why it happens:**
Developers habitually use `-Scope CurrentUser` to avoid UAC prompts during interactive install. The discrepancy between who installs the module and who runs DSC is non-obvious.

**How to avoid:**
Always install PowerSTIG and its dependent DSC resource modules as Administrator without the `-Scope` parameter. This places them in `C:\Program Files\WindowsPowerShell\Modules` where SYSTEM can reach them. PowerSTIG's official docs explicitly state: "the `-Scope` switch is not used here because DSC runs as the system."

For guest VM application, the same rule applies: DSC resources must be present on the target node at machine scope before `Start-DscConfiguration` runs.

**Warning signs:**
- MOF compilation succeeds on the host but `Start-DscConfiguration` throws "The PowerShell DSC resource [X] does not exist at the PowerShell module path nor be registered as a WMI DSC resource"
- Error appears only when run under a service or scheduled context, not in interactive PS sessions

**Phase to address:**
Phase that introduces PowerSTIG baseline application (DSC Baselines phase). Add a `Test-PowerStigInstallation` guard that checks both host and target VM module scope before attempting compilation.

---

### Pitfall 2: PowerSTIG Version/STIG Version Mismatch Causing MOF Compilation Failure

**What goes wrong:**
The `StigVersion` parameter in the DSC composite resource configuration must correspond to an actual STIG version bundled in the installed PowerSTIG module. Specifying an outdated or unavailable STIG version causes the configuration block to throw a terminating error during MOF compilation, not at apply time. The failure message is cryptic: the module name is reported but not the version mismatch root cause.

**Why it happens:**
PowerSTIG ships STIG data as processed XML files under `StigData\Processed\`. Available versions change between PowerSTIG releases. Lab automation code that hard-codes `StigVersion = '2.5'` silently breaks when the developer upgrades PowerSTIG to a version that dropped or renamed that STIG version.

**How to avoid:**
- Never hard-code `StigVersion` in lab code. Resolve it at runtime by scanning the `StigData\Processed\` directory for the newest available version for the target STIG type:
  ```powershell
  $stigPath = "C:\Program Files\WindowsPowerShell\Modules\PowerSTIG\$($(Get-Module PowerSTIG -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).Version)\StigData\Processed"
  ```
- Pin the PowerSTIG module version in `$GlobalLabConfig` and validate on startup that the pinned version is installed.

**Warning signs:**
- Error during MOF compilation mentioning a STIG type string (e.g., "WindowsServer-2019-MS-1.5 was not found")
- Lab works after an `Update-Module PowerSTIG` but breaks after a later update

**Phase to address:**
DSC Baselines phase. The STIG version discovery helper must be written before any DSC configuration scaffold.

---

### Pitfall 3: WinRM MaxEnvelopeSizekb Blocking Large MOF Delivery

**What goes wrong:**
PowerSTIG MOF files are large — a full Windows Server STIG MOF commonly exceeds the default WinRM `MaxEnvelopeSizekb` of 500 KB. `Start-DscConfiguration -ComputerName $vm` fails with: "The WinRM client sent a request to the remote WS-Management service and was notified that the request size exceeded the configured MaxEnvelopeSize quota."

**Why it happens:**
WinRM defaults are conservative. Fresh Windows Server VMs deployed by the lab have never had WinRM tuned. The issue does not appear when applying a small DSC config but manifests specifically with PowerSTIG's composite resources.

**How to avoid:**
Add a `Set-LabVMWinRMForDsc` helper that runs before any DSC push:
```powershell
Invoke-Command -ComputerName $vmName -ScriptBlock {
    Set-Item -Path WSMan:\localhost\MaxEnvelopeSizekb -Value 8192
    Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
}
```
This must also run on the host to support local DSC compilation. Include it in post-domain-join provisioning so it is idempotent across re-deploys.

**Warning signs:**
- Error message contains "MaxEnvelopeSize quota"
- Error only appears with PowerSTIG configs, not smaller DSC configs
- Issue surfaces on first VM it is applied to and is consistent across all VMs

**Phase to address:**
DSC Baselines phase. Add WinRM pre-flight to `Invoke-LabApplyDscBaseline` before any `Start-DscConfiguration` call.

---

### Pitfall 4: DSC "A Configuration Is Already Pending" Blocking Re-Application

**What goes wrong:**
If a previous `Start-DscConfiguration` run was interrupted (VM rebooted mid-apply, PS session lost, operator killed it), the LCM on the guest VM enters a "pending" state. Subsequent calls to `Start-DscConfiguration` fail with "A configuration is already pending." The lab re-deploy flow calls apply again on the same VM and gets stuck.

**Why it happens:**
DSC's LCM tracks configuration state on the node. An interrupted push leaves a pending `.mof` in `C:\Windows\System32\Configuration\`. The LCM refuses a new configuration until the pending one is resolved. This happens any time the VM is rebooted between `Start-DscConfiguration` and LCM completing apply.

**How to avoid:**
Add `-Force` to all `Start-DscConfiguration` calls in the lab automation. The `-Force` flag instructs the LCM to discard any pending configuration and apply the new one immediately. Also add a pre-check step:
```powershell
$lcmState = (Get-DscLocalConfigurationManager -CimSession $vm).LCMState
if ($lcmState -eq 'PendingSendConfiguration' -or $lcmState -eq 'PendingConfigurationCheckin') {
    Remove-DscConfigurationDocument -Stage Pending -CimSession $vm -Force
}
```

**Warning signs:**
- Error contains "A configuration is already pending"
- Fails consistently after a lab that had a VM rebooted mid-deployment
- `Get-DscLocalConfigurationManager` shows `LCMState` of `PendingSendConfiguration`

**Phase to address:**
DSC Baselines phase. Pre-flight LCM state check must be in `Invoke-LabApplyDscBaseline` before the `Start-DscConfiguration` call.

---

### Pitfall 5: ADMX Import Before DC Promotion Is Complete

**What goes wrong:**
The ADMX central store creation and GPO import automation runs Invoke-Command against the DC VM. If the script proceeds before AD Web Services and SYSVOL replication are fully ready, GPO cmdlets like `Import-GPO` and `New-GPO` fail with "The server is not operational" or "The SYSVOL path is unavailable." This is not the same signal as WinRM availability — the VM answers WinRM but AD is still initializing.

**Why it happens:**
`Wait-LabVMReady` checks for WinRM responsiveness, not AD service health. AD Web Services (`ADWS`) can take 60–120 seconds after a domain controller finishes its initial promotion reboot before it accepts LDAP/GroupPolicy cmdlets reliably.

**How to avoid:**
Add an explicit AD readiness gate before any Group Policy operations:
```powershell
$maxWait = 180
$waited = 0
do {
    try {
        $null = Get-ADDomain -Server $dcName -ErrorAction Stop
        break
    } catch {
        Start-Sleep -Seconds 10
        $waited += 10
    }
} while ($waited -lt $maxWait)
if ($waited -ge $maxWait) { throw "AD not ready on $dcName after $maxWait seconds" }
```
This gate must run before `New-GPO`, `Import-GPO`, and central store ADMX copy operations.

**Warning signs:**
- GPO import fails on the first run but succeeds if the operator re-runs 2–3 minutes later
- Error contains "The server is not operational" or "RPC server is unavailable"
- Works in manual testing but fails in automated deployment (timing dependency)

**Phase to address:**
ADMX/GPO Import phase. The AD readiness gate should be a named private helper (`Wait-LabADReady`) so it can be reused across any step that requires AD.

---

### Pitfall 6: ADMX Central Store Version Conflicts Causing "Extra Registry Settings" in GPO Editor

**What goes wrong:**
Copying ADMX files from one Windows version (e.g., Windows 10 22H2) to the central store when the DC or admin workstation uses RSAT with files from a different version causes the Group Policy Management Console to display settings as "Extra Registry Settings." Operators see warnings and policy edits require manual XML work to fix.

**Why it happens:**
ADMX/ADML files use the same filenames across Windows versions but contain different content. The central store path (`\\domain\SYSVOL\domain\Policies\PolicyDefinitions`) must have a single, consistent version. Merging files from different sources breaks this.

**How to avoid:**
- Source ADMX files exclusively from one consistent Windows version — use the files from the DC itself (`C:\Windows\PolicyDefinitions`) as the authoritative source for the initial import.
- Never merge partial sets. Always replace the entire `PolicyDefinitions` folder atomically.
- Store the source Windows build in `$GlobalLabConfig` so the ADMX import is version-aware:
  ```powershell
  $sourceAdmx = "\\$dcName\C$\Windows\PolicyDefinitions"
  $centralStore = "\\$domainName\SYSVOL\$domainName\Policies\PolicyDefinitions"
  ```

**Warning signs:**
- Group Policy Management Console shows "Extra Registry Settings" warnings on any GPO
- Multiple ADMX error dialogs appear when opening the GPMC after ADMX import
- Some ADMX settings appear duplicated with subtly different names

**Phase to address:**
ADMX/GPO Import phase. Enforce single-source ADMX copy in the import helper and add a post-copy validation that compares file counts.

---

### Pitfall 7: Scheduled Task Working Directory and Path Assumptions Causing Silent Failures

**What goes wrong:**
A scheduled task registered with `Register-ScheduledTask` runs the TTL monitor script as SYSTEM. The script uses relative paths (e.g., `.\Lab-Common.ps1`) or assumes `$PSScriptRoot` resolves correctly. Under Task Scheduler, `$PSScriptRoot` may be empty or point to `C:\Windows\System32` rather than the project root. The task runs but the script silently does nothing because module imports fail.

**Why it happens:**
Interactive PowerShell sessions set `$PSScriptRoot` from the script file's location. Scheduled tasks launched via `powershell.exe -File "path\script.ps1"` set it correctly only if the full path is given — but the task's working directory (`-WorkingDirectory`) defaults to `%windir%\System32` when not explicitly set.

**How to avoid:**
- Always register the task with an explicit working directory set to the project root:
  ```powershell
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
      -Argument "-NonInteractive -NoProfile -File `"$scriptPath`"" `
      -WorkingDirectory $projectRoot
  ```
- Use absolute paths constructed from a known anchor (`$GlobalLabConfig.Paths.LabRoot`) rather than relative paths inside the monitoring script.
- Add a startup guard in the monitoring script that validates its expected paths exist before doing any work.

**Warning signs:**
- Task shows "Last Run Result: 0x0" (success) but no log entries appear
- Works when invoked manually via PowerShell but produces no output via Task Scheduler
- Script contains `Import-Module` or dot-source using relative paths

**Phase to address:**
Lab TTL / Lifecycle Monitoring phase. The task registration helper must be built with explicit path construction from the start.

---

### Pitfall 8: Scheduled Task Re-Registration Errors Breaking Idempotent Deployment

**What goes wrong:**
`Register-ScheduledTask` throws a terminating error if a task with the same name already exists. A lab re-deploy or `Initialize-LabConfig` re-run invokes the TTL task registration helper, which crashes with "Cannot create a file when that file already exists."

**Why it happens:**
`Register-ScheduledTask` is not idempotent by default. Developers add `-Force` to fix it interactively, but forget it in the automation path, or the task was created manually and has a slightly different principal.

**How to avoid:**
Wrap task registration in an explicit check-then-create pattern:
```powershell
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($null -ne $existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}
Register-ScheduledTask @registrationSplat
```
Using `-Force` on `Register-ScheduledTask` alone is insufficient because it still errors when the task principal (user/SYSTEM) differs from the registered version.

**Warning signs:**
- Deploy succeeds on first run, fails on second run with a file-exists type error
- Error message contains the scheduled task name
- Operator has previously registered the task manually to test it

**Phase to address:**
Lab TTL / Lifecycle Monitoring phase. The task registration function must be idempotent by design, not patched after the fact.

---

### Pitfall 9: GlobalLabConfig TTL Keys Absent Causing NullReferenceException in Background Monitor

**What goes wrong:**
The background monitoring script reads `$GlobalLabConfig.TTL.EnableAutoSuspend` and similar keys. If the lab is running with an older `Lab-Config.ps1` that predates the TTL section being added, the keys do not exist. Under `Set-StrictMode -Version Latest`, any access to a missing hashtable key throws an error. The scheduled task silently fails (exit code non-zero, no log entry).

**Why it happens:**
Existing `Lab-Config.ps1` files from v1.5 do not have the new TTL block. The monitoring script assumes the config is always current. `Set-StrictMode` is used project-wide per coding standards, making absent key access a hard error rather than a null return.

**How to avoid:**
Apply the same defensive pattern used in other project helpers:
```powershell
# Test for key existence before access
$ttlEnabled = if ($GlobalLabConfig.ContainsKey('TTL') -and $GlobalLabConfig.TTL.ContainsKey('EnableAutoSuspend')) {
    $GlobalLabConfig.TTL.EnableAutoSuspend
} else {
    $false  # safe default
}
```
Also add the TTL block with safe defaults to `Lab-Config.ps1` during the phase that introduces TTL, so new deployments have it automatically.

**Warning signs:**
- Task exit code is non-zero but no errors are written to the log file
- Error in DSC/Task event log mentions a null reference or property access on null
- Works when `Lab-Config.ps1` was freshly generated but fails on an existing config

**Phase to address:**
Lab TTL / Lifecycle Monitoring phase. All config key reads in the monitoring script must be guarded with `ContainsKey` checks.

---

### Pitfall 10: DispatcherTimer Tick Hanging the UI When Enriched Data Collection Is Slow

**What goes wrong:**
The existing `$script:VMPollTimer` (5-second `DispatcherTimer`) runs on the WPF UI thread. Adding slow Hyper-V data collection calls (disk usage, snapshot age, uptime) to the tick handler causes the GUI to freeze for 1–3 seconds every 5 seconds — noticeable as jank when scrolling or clicking buttons.

**Why it happens:**
`DispatcherTimer` ticks execute on the UI thread. This is by design and is why it works without `Dispatcher.Invoke`. However, adding expensive synchronous calls to the tick (e.g., `Get-VMHardDiskDrive`, `Get-VMSnapshot`) blocks the UI event loop for the duration of each call. With 6+ VMs the cumulative cost per tick is significant.

**How to avoid:**
Keep the DispatcherTimer tick lightweight — update UI from a pre-computed data snapshot only. Do expensive data collection on a separate runspace and push results to a script-scoped synchronized hashtable:
```powershell
$script:DashDataSync = [hashtable]::Synchronized(@{})
# Background runspace populates $script:DashDataSync.VMMetrics
# DispatcherTimer tick reads from $script:DashDataSync.VMMetrics (no I/O)
```
The background runspace must NOT touch WPF controls directly — only write to the synchronized hashtable. The timer tick reads from it and updates controls.

**Warning signs:**
- GUI becomes unresponsive for noticeable intervals (1+ seconds) on the Dashboard tab
- Freeze duration increases proportionally with VM count
- CPU spikes on the host during timer ticks visible in Task Manager

**Phase to address:**
Dashboard Enrichment phase. The runspace/synchronized-hashtable pattern must be designed upfront — retrofitting it after the feature is built is expensive.

---

### Pitfall 11: PowerSTIG SkipRule and OrgSettings Conflicting in Multi-STIG MOF

**What goes wrong:**
When compiling a single MOF with multiple PowerSTIG composite resources (e.g., `WindowsServer` + `WindowsDnsServer` for a DC), some rules conflict across STIGs — both attempt to enforce the same registry key to different values. The MOF compiler throws a duplicate resource ID error or silently picks one value over the other. Using `SkipRule` and `SkipRuleType` together in the same configuration block causes a known compilation exception.

**Why it happens:**
PowerSTIG's composite resources are designed to be used independently. When stacked in one configuration block targeting the same node, overlapping registry rules create DSC duplicate resource conflicts. The `SkipRuleType` and `SkipRule` parameters have a documented incompatibility when used simultaneously (GitHub issue #653).

**How to avoid:**
- Apply one STIG per `Start-DscConfiguration` call with separate MOF files, rather than compiling all STIGs into one MOF.
- For DC nodes that need both `WindowsServer` and `WindowsDnsServer`, compile and apply them sequentially with a state check between applications.
- Never combine `SkipRuleType` and `SkipRule` in the same composite resource call — use one mechanism per resource block.
- Maintain a per-role OrgSettings override file in `$GlobalLabConfig.Paths.LabRoot\DSC\OrgSettings\` so exceptions are documented and version-controlled.

**Warning signs:**
- MOF compilation error referencing duplicate resource IDs
- Configuration applies for single-STIG roles (member servers) but fails for DC roles
- Subtle settings drift where one STIG silently wins over a conflicting rule from another STIG

**Phase to address:**
DSC Baselines phase. The role-to-STIG mapping must be designed to avoid multi-STIG single-MOF compilation upfront.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hard-code `StigVersion = '2.5'` in DSC config | No version-discovery logic needed | Breaks silently after any PowerSTIG update | Never — always resolve at runtime |
| Copy ADMX from arbitrary source rather than DC's own `C:\Windows\PolicyDefinitions` | Simpler to source | "Extra Registry Settings" in GPMC, hard to debug | Never in automation |
| Run DSC apply inline in the deploy orchestrator | Simpler flow, no async complexity | Deploy hangs if DSC takes >5 min or VM reboots | Never — always async/detached with status polling |
| Register scheduled task without working directory | Works interactively | Silent failures in Task Scheduler SYSTEM context | Never — always explicit `-WorkingDirectory` |
| Add all enriched VM data collection inside the DispatcherTimer tick | Simple, works for 1-2 VMs | GUI jank at 5+ VMs as I/O grows | Only for initial prototype; must be replaced before feature merge |
| Skip `ContainsKey` checks on `$GlobalLabConfig` new keys | Less verbose code | Hard error on older config files under `Set-StrictMode` | Never — project coding standard requires defensive key access |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| PowerSTIG + Invoke-Command | Running `Start-DscConfiguration` from host against guest without checking WinRM is tuned | Add `Set-LabVMWinRMForDsc` pre-flight that sets `MaxEnvelopeSizekb = 8192` on the guest before any DSC push |
| Import-GPO + DC promotion timing | Calling `Import-GPO` immediately after `Wait-LabVMReady` returns | Gate on `Get-ADDomain` succeeding, not just WinRM; ADWS is slower than WinRM |
| Register-ScheduledTask + SYSTEM principal | Assuming `-Force` on `Register-ScheduledTask` handles all re-registration cases | Unregister-then-register pattern; check `Get-ScheduledTask` before registration |
| DSC + pending LCM state | Re-running `Start-DscConfiguration` without `-Force` on a VM that had an interrupted prior apply | Always use `-Force`; add `Get-DscLocalConfigurationManager` LCM state pre-check |
| DispatcherTimer tick + Hyper-V data collection | Adding expensive calls directly inside the timer tick | Collect data in background runspace, push to synchronized hashtable, timer tick reads only from sync table |
| PowerSTIG + $GlobalLabConfig | Adding `$GlobalLabConfig.DSC` block without backward-compat guards | All new config key reads must use `ContainsKey` defensive pattern per `Set-StrictMode` requirements |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Synchronous Hyper-V calls in DispatcherTimer tick | GUI freezes 1–3 seconds every 5 seconds | Move data collection to background runspace; tick reads from sync hashtable | At 4+ VMs with enriched metrics |
| `Get-VMSnapshot` for all VMs on every dashboard poll | Snapshot enumeration is O(n) with snapshot depth; slow on VMs with 10+ snapshots | Cache snapshot data with a longer refresh interval (60s vs. 5s) separate from VM state (5s) | At VMs with 15+ snapshots or 8+ VMs |
| Compiling a PowerSTIG MOF per VM on each deploy | MOF compilation takes 10–30 seconds per VM; blocks deploy progress | Compile once per role type and cache the MOF file; reuse across same-role VMs | At 5+ VMs in a deploy run |
| Full AD SYSVOL sync wait during ADMX import | ADMX copy returns immediately but GPMC shows stale data until SYSVOL replication completes | Add `Start-Sleep` or poll for SYSVOL replication completion before declaring import done | Always — SYSVOL replication is asynchronous |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Storing credentials in the scheduled task action as plaintext `-Argument "-Password SimplePass"` | Credentials visible in Task Scheduler MMC and event logs | Run task as SYSTEM (no credentials needed for local Hyper-V) or use Windows credential manager via `Export-Clixml`/`Import-Clixml` with DPAPI |
| Applying PowerSTIG baseline to DC without testing OrgSettings first | Security policy may lock out admin accounts or disable required services (e.g., WinRM, RDP) | Test against member server first; maintain a curated OrgSettings override file that exempts lab-required services |
| Giving the scheduled task SYSTEM privileges and importing `Lab-Common.ps1` without path validation | Privilege escalation if `Lab-Common.ps1` path can be written by a non-privileged account | Task working directory and script path must be in a location only Administrators can write to |
| ADMX import copies scripts alongside ADMX files into SYSVOL | SYSVOL contents replicate to all DCs and are readable by all domain users | Copy only `.admx` and `.adml` files to the central store; never place scripts in SYSVOL |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Dashboard shows "compliance: unknown" with no explanation during DSC apply | Operator does not know if DSC is running, failed, or just slow | Show a per-VM "Applying baseline..." spinner state while DSC is in progress, not a static unknown state |
| TTL auto-suspend fires while operator is actively using the lab | Unexpected VM suspension during active work is disruptive | Add a `LastActivityTimestamp` touch mechanism — any manual GUI action updates the lab TTL countdown |
| ADMX import status gives no feedback (fire-and-forget) | Operator cannot tell if GPO import succeeded until they open GPMC manually | Return structured result from GPO import helper with success/failure counts; surface in GUI action log |
| DSC baseline apply is synchronous and blocks the deploy progress display | Deploy progress bar freezes at "applying STIG baseline" for 5–10 minutes per VM | Apply DSC asynchronously (`Start-DscConfiguration -Wait:$false`) and poll `Get-DscConfigurationStatus` separately |

---

## "Looks Done But Isn't" Checklist

- [ ] **PowerSTIG DSC apply:** Compiled the MOF on the host but never verified `Start-DscConfiguration` completed on the guest — verify with `Test-DscConfiguration` after apply
- [ ] **ADMX central store:** Copied `.admx` files but forgot the matching `.adml` files in the `en-US` subfolder — verify GPMC opens without "Administrative Templates Resource could not be found" errors
- [ ] **GPO import:** Called `Import-GPO` but did not link the GPO to the domain or OU — verify with `Get-GPOReport` that GPO is linked and enabled
- [ ] **Scheduled task registration:** Task appears in Task Scheduler but "Last Run Result" shows 0x1 (general failure) — verify the script runs interactively under SYSTEM via `psexec -s powershell.exe` before declaring it done
- [ ] **TTL monitoring:** Task is registered and runs but TTL countdown does not reset on lab activity — verify `LastActivityTimestamp` is being updated by all lifecycle operations
- [ ] **Dashboard enrichment:** Snapshot age column shows data in the UI but the background refresh runspace has no error handling — verify runspace errors are captured and don't silently stop data updates
- [ ] **WinRM MaxEnvelopeSizekb:** Set on the host but not on guest VMs — verify setting is applied to each VM as part of the post-domain-join provisioning step
- [ ] **OrgSettings override file:** DSC baseline applies without error but a lab-critical service (WinRM, RDP) is disabled — verify `OrgSettings.xml` explicitly skips or overrides rules that affect lab connectivity

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| DSC resources in wrong scope (CurrentUser) | LOW | Re-install without `-Scope` as Administrator; restart WmiPrvSE process or reboot VM |
| LCM pending configuration stuck | LOW | Run `Remove-DscConfigurationDocument -Stage Pending -Force` on the target VM; re-run `Start-DscConfiguration -Force` |
| ADMX version conflict in central store | MEDIUM | Rename current `PolicyDefinitions` to `PolicyDefinitions-backup`; re-copy from a single consistent source; restart GPMC |
| Scheduled task working directory silent failure | LOW | Re-register task with explicit `-WorkingDirectory`; test by running `schtasks /run /tn TaskName` and checking output |
| DispatcherTimer UI freeze from slow data calls | HIGH | Refactor timer tick to read from sync hashtable; build background runspace; affects all VM card rendering logic |
| PowerSTIG multi-STIG MOF duplicate resource conflict | MEDIUM | Split into per-STIG MOF files; apply sequentially; existing MOF files must be recompiled |
| `$GlobalLabConfig` missing TTL keys crashing monitor | LOW | Add `ContainsKey` guards; add TTL defaults block to existing `Lab-Config.ps1` |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| DSC module scope (CurrentUser vs SYSTEM) | DSC Baselines phase | `Test-PowerStigInstallation` helper passes; `Start-DscConfiguration` succeeds on a clean VM |
| PowerSTIG/STIG version mismatch | DSC Baselines phase | Runtime version discovery helper returns valid version; Pester test validates version resolution logic |
| WinRM MaxEnvelopeSizekb | DSC Baselines phase | `Invoke-LabApplyDscBaseline` includes pre-flight WinRM tuning; test against VM with default WinRM |
| LCM pending configuration state | DSC Baselines phase | `Invoke-LabApplyDscBaseline` includes LCM state pre-check; `-Force` used on `Start-DscConfiguration` |
| ADMX import before DC ready | ADMX/GPO Import phase | `Wait-LabADReady` helper gating all GPO operations; Pester test mocks AD unavailability |
| ADMX central store version conflict | ADMX/GPO Import phase | Single-source ADMX copy; post-copy file count validation; manual GPMC open check in acceptance test |
| Scheduled task working directory | Lab TTL phase | Task runs correctly as SYSTEM; `$PSScriptRoot` not used — absolute paths from `$GlobalLabConfig` only |
| Task re-registration idempotency | Lab TTL phase | Second `Initialize-LabTTLMonitor` call succeeds without error; Pester test runs registration twice |
| `$GlobalLabConfig` missing new keys | Lab TTL phase | `ContainsKey` guards on all new config reads; Pester test passes with a config that lacks the TTL block |
| DispatcherTimer tick UI freeze | Dashboard Enrichment phase | GUI stays responsive (no freeze) with 8 VMs and full metric collection; background runspace pattern in place |
| PowerSTIG multi-STIG conflict | DSC Baselines phase | Per-role STIG mapping defined; DC role applies STIG types sequentially; Pester tests compile each role's MOF |
| SkipRule + SkipRuleType conflict | DSC Baselines phase | OrgSettings override file used instead of mixed SkipRule/SkipRuleType; MOF compilation verified in CI |

---

## Sources

- [PowerSTIG DscGettingStarted Wiki — microsoft/PowerStig](https://github.com/microsoft/PowerStig/wiki/DscGettingStarted) — module scope, WinRM MaxEnvelopeSizekb, STIG version requirements (HIGH confidence)
- [PowerSTIG GettingStarted Wiki — microsoft/PowerStig](https://github.com/microsoft/PowerStig/wiki/GettingStarted) — StigVersion parameter validation, processed STIG data directory (HIGH confidence)
- [Troubleshooting DSC — Microsoft Learn](https://learn.microsoft.com/en-us/powershell/dsc/troubleshooting/troubleshooting?view=dsc-1.1) — LCM pending state, WmiPrvSE cache, DSC event logs (HIGH confidence)
- [Create and Manage Central Store — Microsoft Learn](https://learn.microsoft.com/en-us/troubleshoot/windows-client/group-policy/create-and-manage-central-store) — ADMX version conflicts, "Extra Registry Settings" cause (HIGH confidence)
- [Group Policy settings show as Extra Registry Settings — Microsoft Learn](https://learn.microsoft.com/en-us/troubleshoot/windows-server/group-policy/group-policy-settings-show-as-extra-registry-settings) — ADMX/ADML version conflict details (HIGH confidence)
- [ServerManager Breaking / SkipRuleType issue #653 — microsoft/PowerStig GitHub](https://github.com/microsoft/PowerStig/issues/653) — SkipRule + SkipRuleType incompatibility (MEDIUM confidence)
- [Optimizing Performance: Data Binding — Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/optimizing-performance-data-binding) — WPF data binding performance patterns (HIGH confidence)
- [PowerShell and WPF: Writing Data to a UI From a Different Runspace](https://learn-powershell.net/2012/10/14/powershell-and-wpf-writing-data-to-a-ui-from-a-different-runspace/) — synchronized hashtable pattern for background runspace + WPF (MEDIUM confidence)
- [Troubleshooting PowerShell Based Scheduled Tasks — ramblingcookiemonster.github.io](http://ramblingcookiemonster.github.io/Task-Scheduler/) — working directory and SYSTEM context pitfalls (MEDIUM confidence)
- Existing AutomatedLab codebase — `GUI/Start-OpenCodeLabGUI.ps1` DispatcherTimer pattern, `Lab-Config.ps1` structure, `Set-StrictMode` coding standard, `ContainsKey` pattern from v1.4 profile helpers (HIGH confidence)

---
*Pitfalls research for: PowerShell lab lifecycle automation — PowerSTIG DSC, ADMX/GPO import, lab TTL scheduled tasks, WPF dashboard enrichment*
*Researched: 2026-02-20*

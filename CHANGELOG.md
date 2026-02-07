# Changelog

## v1.5.5 - Do Not Fail Deploy on DC1 OpenSSH Capability Errors

### Bug Fixes
- Hardened DC1 OpenSSH setup in `Deploy.ps1` so capability install/configuration failures no longer abort the entire deployment.
- Deployment now logs a warning and continues when OpenSSH optional feature install fails (for example, DISM `Access is denied`).
- Host key bootstrap to DC1 is now conditional and runs only when OpenSSH is confirmed ready.

## v1.5.4 - Remove Empty-Password Blocker

### Changes
- Updated `Deploy.ps1` to stop throwing when `-AdminPassword` is passed as empty.
- If password input resolves empty after overrides, deployment now falls back to `Server123!` and continues with a warning.

## v1.5.3 - Default Deploy Password for Non-Interactive Runs

### Changes
- Set `Deploy.ps1` default `-AdminPassword` value to `Server123!` so deployment can run without interactive password entry.
- Kept environment/parameter overrides (`OPENCODELAB_ADMIN_PASSWORD` and `-AdminPassword`) for customization.
- Updated README setup notes to reflect the new default password behavior.

## v1.5.2 - Restore Fully Unattended LIN1 Install Flow

### Bug Fixes
- Reworked deployment order in `Deploy.ps1` so stage 1 installs only `DC1` and `WS1`.
- DHCP is now configured on `DC1` before `LIN1` is defined/installed, so Ubuntu autoinstall is no longer started on an internal switch without DHCP.
- Added a dedicated LIN1 stage: define LIN1, run `Install-Lab` again for the pending Linux machine, then explicitly wait for SSH readiness.

## v1.5.1 - LIN1 Reachability Wait Hardened

### Bug Fixes
- Increased LIN1 readiness wait window from 30 to 75 minutes in `Deploy.ps1` to better accommodate fully unattended Ubuntu installs on slower hosts.
- LIN1 readiness now requires both ICMP reachability and SSH (TCP/22) before post-install Linux configuration begins.
- Wait-loop progress logging now distinguishes between "no DHCP/IP yet" and "IP present but services not ready" to make unattended progress clearer.

## v1.5.0 - Fix DC1 AD DS Promotion Failure & Recovery

### Bug Fixes
- **Add AD DS validation after Install-Lab**: After `Install-Lab` completes (or fails), the
  script now verifies that AD DS is actually operational on DC1 by checking the NTDS service,
  domain membership, and AD cmdlet availability. Previously, only network connectivity (ping
  and WinRM) was validated, so a silently failed DC promotion would go undetected.
- **Add AD DS recovery logic**: If validation detects that DC1 was not promoted (e.g.
  `Install-ADDSForest` failed silently), the script now attempts automatic recovery:
  1. Installs the AD-Domain-Services feature if missing
  2. Runs `Install-ADDSForest` manually with the correct domain parameters
  3. Waits for DC1 to restart and AD Web Services to initialize
  4. Re-validates that the forest is operational
- **Wrap Install-Lab in try/catch**: `Install-Lab` timeout errors are now caught gracefully
  instead of aborting the entire deployment, allowing the recovery logic to attempt a fix.
- **Create LIN1 via Hyper-V instead of Install-Lab**: AutomatedLab's Ubuntu 24.04 autoinstall
  does not work on Internal switches (drops to interactive language selection). LIN1 is now
  removed from `Install-Lab` and created directly via Hyper-V cmdlets (Gen2 VM, DVD boot from
  Ubuntu ISO, Secure Boot off). The user completes the Ubuntu install interactively in the VM
  console. A wait loop (45 min) monitors for LIN1 to get a DHCP address and become pingable
  before proceeding to automated post-install configuration (SSH, netplan, SMB, packages).

## v1.4.1 - Increase AD Readiness Timeout for Slow Hosts

### Bug Fixes
- Increased `AL_Timeout_AdwsReady` from 45 to 120 minutes in `Lab-Config.ps1`.
- This addresses deployments where AD DS promotion completes, but AutomatedLab times out waiting for AD readiness on `DC1` on slower or heavily loaded hosts.
- `Deploy.ps1` already applies this value through `Set-PSFConfig -Name Timeout_DcPromotionAdwsReady`.

## v1.4.0 - Network Validation & Error Propagation Fixes

### Bug Fixes
- **Fix `Get-VM` PowerCLI conflict**: Module-qualified `Get-VM` → `Hyper-V\Get-VM` in
  `OpenCodeLab-App.ps1` post-deploy VM check. Machines with VMware PowerCLI installed
  would silently use the wrong `Get-VM` cmdlet, always reporting VMs as missing.
- **Add Stage 1 network connectivity validation** in `Deploy.ps1`: After `Install-Lab`
  creates DC1, the script now verifies before proceeding to Stage 2:
  1. Host adapter (`vEthernet (OpenCodeLabSwitch)`) still has 192.168.11.1 assigned
  2. NAT rule still exists
  3. DC1 (192.168.11.3) responds to ping
  4. WinRM port 5985 is reachable on DC1 (with 60s retry)
  - If the host IP or NAT were removed by `Install-Lab`, they are automatically re-applied
  - If DC1 is unreachable, deployment aborts with a clear error instead of waiting 80+ min
- **Fix error propagation in `Deploy.ps1`**: The outer `catch` block now re-throws after
  logging, so `Bootstrap.ps1` (and `OpenCodeLab-App.ps1`) correctly detect deployment
  failure instead of reporting "ok"

## v1.3.0 - Fix DC Promotion Timeout on Resource-Constrained Hosts

### Bug Fix
- Fixed deployment failure: "Timeout occurred waiting for Active Directory to be ready on Domain Controller: DC1"
- AutomatedLab default ADWS timeout (20 min) was too short for smaller hosts
- Added configurable timeout overrides in `Lab-Config.ps1`:
  - `AL_Timeout_DcRestart` = 90 min (was 60)
  - `AL_Timeout_AdwsReady` = 45 min (was 20) -- **root cause**
  - `AL_Timeout_StartVM` = 90 min (was 60)
  - `AL_Timeout_WaitVM` = 90 min (was 60)
- `Deploy.ps1` now applies `Set-PSFConfig` overrides before `Install-Lab`

## v1.2.0 - Compatibility Hardening

- Replaced all `<# ... #>` block comments with `#` line comments across all 15 scripts
- Stripped UTF-8 BOMs from Lab-Common, Start-LabDay, Test-OnWS1
- Removed unicode/non-ASCII characters from Deploy.ps1 and Bootstrap.ps1
- Removed redundant `#Requires -Modules AutomatedLab` from Deploy.ps1
- All scripts now extract cleanly from GitHub release zips without parser errors

## v1.1.0 - Cleanup & Bugfix Release

### Bug Fixes (17 total)
- Fixed `Get-LIN1IPForUI` infinite recursion in menu
- Fixed menu invoking scripts by wrong filenames
- Fixed `Open-LabTerminal` param() block placement
- Fixed Deploy heredoc using interpolating strings that destroyed bash `$(...)` syntax
- Fixed stale script filenames in Lab-Config
- Fixed raw bash syntax in Lab-Status ScriptBlock and missing variable passing
- Fixed broken bash variable escaping in Push-ToWS1
- Fixed broken bash variable escaping in Save-LabWork
- Fixed `$LinuxUser` not passed to remote scriptblock in New-LabProject
- Fixed duplicate step numbering in Bootstrap
- Fixed hardcoded values in health check (now dot-sources Lab-Config)
- Fixed `$args` automatic variable collision (renamed to `$scriptArgs`)
- Fixed deprecated `gateway4:` in netplan for Ubuntu 24.04 (replaced with `routes:` block)
- Deleted orphan code fragment in Deploy.ps1
- Fixed PS double-quoted string breaking bash `\"` and `||` in Lab-Status
- Fixed swapped here-string terminator in Save-LabWork
- Added VM existence guard after bootstrap

### Simplification Refactor
- Renamed all scripts from verbose `_POLISHED_FINAL` / `_REBUILDABLE` suffixes to clean names
- Deleted superseded `Lab-Menu_POLISHED_FINAL.ps1` (replaced by `OpenCodeLab-App.ps1`)
- Added `Invoke-BashOnLIN1` helper to `Lab-Common.ps1` (copy `.sh` + remote execute pattern)
- Added `Ensure-VMsReady` helper to `Lab-Common.ps1`
- Centralized deploy hardcoded values into `Lab-Config.ps1`
- Refactored daily scripts to use shared helpers
- Simplified `Resolve-ScriptPath` in orchestrator (direct join, no glob)
- Updated all internal cross-references to new filenames
- Updated README and docs

## v1.2.0 - Parameter Audit & Documentation

### AutomatedLab Parameter Audit
- Audited all 15 cmdlets against AutomatedLab source (commit 869e498b890682640a1d2b0b514756509d9844b7)
- **Result:** All cmdlet parameters in codebase are CORRECT
- Install-Lab correctly called without -Machines parameter (installs all defined machines)

### Documentation Updates
- Updated README with cmdlet parameter reference
- Added parameter validation examples to comments

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

- `Deploy.ps1` now requires `-AdminPassword` or `OPENCODELAB_ADMIN_PASSWORD`.
- `OpenCodeLab-App.ps1 -Action menu` is interactive-only; automation should use explicit actions.

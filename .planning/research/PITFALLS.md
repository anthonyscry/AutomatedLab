# Pitfalls Research

**Domain:** PowerShell Hyper-V Lab Automation
**Researched:** 2025-02-09
**Confidence:** HIGH

> This document catalogs common mistakes in PowerShell/Hyper-V lab automation projects. Each pitfall includes warning signs (early detection), prevention strategies (how to avoid), and phase mapping (when to address it). Use this to prevent mistakes during roadmap planning for SimpleLab (a simplified alternative to AutomatedLab).

---

## Critical Pitfalls

### Pitfall 1: Silent Failures in Automation Scripts

**What goes wrong:**
Scripts that work 99% of the time but fail silently during the critical 1% cause cascading failures across the entire lab deployment. The most dangerous automation is what doesn't fail loudly when something goes wrong.

**Why it happens:**
- Overuse of `-ErrorAction SilentlyContinue` to "make scripts work"
- Missing validation checkpoints between deployment stages
- Assuming external dependencies (ISOs, network, services) always succeed
- Not checking return codes or structured outputs from remote commands

**How to avoid:**
- Use `Set-StrictMode -Version Latest` in all scripts
- Implement structured return objects with required properties (see `Invoke-LabStructuredCheck` pattern in existing code)
- Add explicit validation gates after each critical stage (ISO detection, vSwitch creation, VM startup, AD promotion)
- Never use `-ErrorAction SilentlyContinue` except for truly non-critical operations
- Log all failures with context (what, when, why) for debugging

**Warning signs:**
- Scripts complete "successfully" but VMs aren't running or accessible
- Having to manually check Hyper-V Manager to see what actually happened
- Inconsistent behavior between runs without clear error messages
- "It worked yesterday" without understanding what changed

**Phase to address:** Phase 1 (Foundation) - Build error handling and validation patterns into the core framework from day one.

---

### Pitfall 2: Stale VM State from Previous Failed Runs

**What goes wrong:**
Failed deployment runs leave behind VMs, checkpoints, or virtual network adapters in inconsistent states. Subsequent runs fail with "machine already exists" errors or malformed configuration, creating a death spiral where each run makes the problem worse.

**Why it happens:**
- Scripts assume clean environment on every run
- Missing pre-flight checks for existing artifacts
- Inadequate cleanup on failure (error handling doesn't remove partial state)
- Hyper-V operations are asynchronous and take time to complete

**How to avoid:**
- Implement aggressive pre-flight cleanup (see `Remove-HyperVVMStale` pattern)
- Use multiple retry attempts with exponential backoff for VM removal
- Kill vmwp.exe worker processes as last resort if VM won't delete
- Implement `Try { } Finally { }` blocks to ensure cleanup on failure
- Create snapshots only at known-good states (e.g., "LabReady" after full deployment succeeds)

**Warning signs:**
- Re-running scripts gives "machine already exists" errors
- Hyper-V Manager shows VMs that PowerShell says don't exist
- Having to manually delete VMs between runs
- Scripts that work once but never again without manual intervention

**Phase to address:** Phase 1 (Foundation) - Build idempotent operations that handle existing state gracefully.

---

### Pitfall 3: vSwitch/NAT Configuration Drift

**What goes wrong:**
The lab's virtual network configuration (vSwitch + NAT) becomes inconsistent between host reboots or script runs. VMs can't get IPs, can't reach each other, or can't access external networks. The "Default Switch" is particularly unreliable because Windows manages its subnet dynamically.

**Why it happens:**
- Assuming vSwitch/NAT created in previous runs still exists
- Windows updates or host reboots changing network configuration
- Using Hyper-V "Default Switch" which has unpredictable subnets
- AutomatedLab or other tools accidentally removing/recreating network objects

**How to avoid:**
- Always use a dedicated Internal vSwitch (never "Default Switch")
- Check and recreate vSwitch + NAT idempotently every run
- Verify host gateway IP is still assigned to vNIC after operations
- Use static IPs for infrastructure VMs (DC1) and DHCP for clients
- Validate network connectivity (ping, WinRM) before proceeding with deployment

**Warning signs:**
- VMs start but can't ping each other
- VMs can't reach external networks (GitHub, package feeds)
- Having to manually recreate vSwitch after host reboot
- IP addresses change between runs

**Phase to address:** Phase 1 (Foundation) - Network setup must be bulletproof and idempotent.

---

### Pitfall 4: Timeout Mismatches on Resource-Constrained Hosts

**What goes wrong:**
AutomatedLab's default timeouts (60-120 seconds) are too short for resource-constrained hosts. Scripts fail waiting for DC promotion, VM startup, or service readiness, even though the operation would succeed if given more time.

**Why it happens:**
- AutomatedLab defaults assume powerful server hardware
- Lab developers test on powerful machines, users run on laptops
- No adjustment for disk speed (SSD vs HDD), RAM, or CPU
- Passing integers to timeout configs instead of TimeSpan objects (interpreted as ticks!)

**How to avoid:**
- Override AutomatedLab timeouts using `Set-PSFConfig` with proper TimeSpan objects
- Wait for DC restart with 90-minute timeout (default is 60)
- Wait for ADWS readiness with 120-minute timeout (default is 20)
- Wait for VM startup with 90-minute timeout (default is 60)
- Document timeout requirements and adjust based on host capabilities

**Warning signs:**
- Deployment fails at same point on slower machines but succeeds on fast ones
- Errors mention timeouts during DC promotion or VM startup
- Having to manually retry operations

**Phase to address:** Phase 1 (Foundation) - Configure timeouts appropriately for target hardware.

---

### Pitfall 5: AD DS Promotion Failures Without Recovery

**What goes wrong:**
Install-Lab fails during DC promotion, leaving the lab in an inconsistent state. DC1 exists but isn't a domain controller, and there's no recovery logic. The entire deployment must be scrapped and restarted.

**Why it happens:**
- Assuming Install-Lab never fails
- Not validating AD DS promotion success after Install-Lab
- No fallback mechanism to promote DC1 manually if AutomatedLab fails
- Not detecting that NTDS service isn't running

**How to avoid:**
- Implement explicit AD DS validation after Install-Lab completes
- Check NTDS service status, AD cmdlet functionality, and domain membership
- If validation fails, manually run Install-ADDSForest with recovery logic
- Wait for DC to restart and come back online after recovery promotion
- Verify ADWS and NTDS services are running before proceeding

**Warning signs:**
- Install-Lab completes but DC1 isn't a domain controller
- Get-ADForest or other AD cmdlets fail
- NTDS service not running on DC1
- Having to manually promote DC1

**Phase to address:** Phase 2 (Core Lab) - AD DS promotion is critical; must have validation and recovery.

---

### Pitfall 6: Linux VM Support Gaps in Automation Frameworks

**What goes wrong:**
AutomatedLab doesn't support Ubuntu 24.04 (or other recent Linux distributions). Projects that need mixed Windows/Linux labs end up with hybrid automation: some VMs managed by the framework, others created manually with native Hyper-V cmdlets.

**Why it happens:**
- Frameworks lag behind OS releases (Ubuntu 24.04 was released after AutomatedLab added it)
- Linux autoinstall mechanisms (cloud-init, Subiquity) are different from Windows unattended.xml
- Frameworks focus primarily on Windows workflows

**How to avoid:**
- Create Linux VMs manually using native Hyper-V cmdlets (New-VM, Set-VMFirmware)
- Use cloud-init NoCloud datasource with CIDATA VHDX for unattended installs
- Generate CIDATA VHDX with user-data and meta-data (no ISO tools required)
- Disable Secure Boot for Gen2 Linux VMs
- Detach installer ISO and CIDATA after install completes to prevent reboot loops

**Warning signs:**
- Framework documentation doesn't mention your Linux distribution
- Having to create Linux VMs manually while Windows VMs are automated
- Ubuntu installer menu appears instead of unattended install

**Phase to address:** Phase 3 (Mixed OS) - Plan for hybrid automation if framework lacks Linux support.

---

### Pitfall 7: WinRM/SSH Connectivity Assumptions

**What goes wrong:**
Scripts assume WinRM (Windows) or SSH (Linux) are immediately available after VM creation. They fail trying to run commands before the VM's networking or services are ready, leading to flaky deployments that sometimes work and sometimes don't.

**Why it happens:**
- Not waiting for VMs to fully boot and start services
- Assuming VM startup = services ready (false, especially for DC promotion)
- Network adapters take time to get DHCP addresses
- SSH daemon starts later than boot process

**How to avoid:**
- Wait for WinRM port 5985 to be reachable before invoking commands
- Implement retry logic with exponential backoff (try 12 times, 15 seconds apart)
- Wait for SSH port 22 to be reachable before configuring Linux VMs
- Use structured checks that retry until required property is returned
- Don't assume Test-Connection (ping) success means services are ready

**Warning signs:**
- Scripts fail intermittently with "WinRM connection failed"
- Having to rerun scripts to get them to work
- Different behavior on fast vs slow hardware
- "RPC server unavailable" errors

**Phase to address:** Phase 1 (Foundation) - Build reliable connectivity waiting into all remote operations.

---

### Pitfall 8: ISO Detection Failures

**What goes wrong:**
Scripts can't detect the operating system from ISO files, or detect the wrong OS. Deployment fails with "no operating system found" or installs the wrong Windows version (Server Core instead of Desktop Experience).

**Why it happens:**
- ISO filenames don't match expected patterns
- Get-LabAvailableOperatingSystem can't read ISO metadata
- Multiple Windows editions in same ISO (wrong one selected)
- ISO files are corrupted or incomplete downloads

**How to avoid:**
- Validate ISOs exist before starting deployment (file size check)
- Verify AutomatedLab can detect OS from ISOs (Get-LabAvailableOperatingSystem)
- Use explicit OS names in Add-LabMachineDefinition (not wildcards)
- Document exact ISO versions required (e.g., "Windows Server 2019 Datacenter Evaluation (Desktop Experience)")
- Include "Desktop Experience" in OS name to avoid Server Core

**Warning signs:**
- Get-LabAvailableOperatingSystem returns nothing
- Deployment installs wrong Windows edition
- "Operating system not found" errors during Install-Lab

**Phase to address:** Phase 1 (Foundation) - ISO validation is a prerequisite check.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Using `-ErrorAction SilentlyContinue` | Script doesn't stop on errors | Silent failures, hard to debug | Never (except truly non-critical ops like removing existing objects) |
| Hardcoding VM names/IPs | Quick deployment | Can't run multiple labs, conflicts | Never (use config file) |
| Skipping pre-flight validation | Faster to "just run it" | Failures mid-deployment, wasted time | Never (pre-flight catches issues early) |
| Assuming clean environment | Simpler scripts | Won't work after first failure | Never (must be idempotent) |
| Using Default Switch | No network setup required | Unpredictable subnets, breaks after reboot | Never (use dedicated vSwitch) |
| Manual intervention between steps | Works once | Can't automate end-to-end | Only for one-time emergency fixes |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| AutomatedLab | Assuming it supports all OS versions | Check documentation for OS support, create unsupported VMs manually |
| Hyper-V Default Switch | Using it for lab VMs | Create dedicated Internal vSwitch + NAT |
| Windows Update | Not disabling WSUS redirect for feature installs | Temporarily bypass WSUS policy, install features, then restore |
| DHCP on DC | Not installing DHCP role | Install DHCP on DC1 for Linux VMs (static IPs don't work well with cloud-init) |
| SSH keys | Not generating keypair before deployment | Generate ed25519 keypair in Bootstrap, include in CIDATA for Linux VMs |
| Git installation | Assuming winget or external access works | Fallback chain: winget -> local installer -> web download (with DNS check) |
| Domain join | Assuming join happens immediately | Wait for WinRM, validate domain join before proceeding |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Serial VM operations | Deployment takes hours | Parallelize where possible, use timeouts appropriately | On hosts with <16GB RAM (parallel operations cause memory pressure) |
| No resource limits | Host becomes unusable during deployment | Set VM memory min/max appropriately, don't overcommit CPU | Always (but especially on laptops) |
| Waiting for external downloads | Deployment hangs on slow connections | Check DNS resolution before downloading, use local cached installers | On networks with filtering or slow DNS |
| Not using checkpoints | Have to redeploy from scratch after mistakes | Create "LabReady" checkpoint after successful deployment | After any long-running operation that could fail |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Default passwords everywhere | Anyone can access your lab VMs | Use environment variable override for admin password, document password rotation |
| Opening unnecessary firewall ports | Lab VMs exposed to network | Only open required ports (WinRM 5985/5986, SSH 22) |
| Reusing same SSH keys | Key compromise affects all labs | Generate unique keys per lab, document key rotation |
| No certificate validation | Man-in-the-middle attacks | Use self-signed certificates for WinRM HTTPS, validate thumbprints |
| Sharing lab on public network | Unauthorized access | Use Internal vSwitch only, never External for lab VMs |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No progress indication | Users think script hung | Write progress for each major step (1/10, 2/10, etc.) |
| Cryptic error messages | Users can't fix problems themselves | Include "what to do next" in error messages |
| No confirmation before destructive operations | Accidental data loss | Require explicit `-Force` flag for destructive operations |
| No dry-run mode | Can't predict what will happen | Implement `-DryRun` flag that shows what would happen |
| No log files | Can't debug failures | Write structured log files (JSON + text) with timestamps and error details |
| Interactive-only scripts | Can't automate or schedule | Support `-NonInteractive` flag for all operations |

---

## "Looks Done But Isn't" Checklist

- [ ] **Domain join:** Often missing DNS resolution — verify `Resolve-DnsName dc1.$domain` works from client VMs
- [ ] **Network connectivity:** Often missing actual connectivity — verify `Test-Connection` AND `Test-NetConnection` on WinRM/SSH ports
- [ ] **Services running:** Often missing service readiness — verify NTDS, DNS, SSHD services are actually Running (not just exist)
- [ ] **SMB shares:** Often missing permissions — verify share exists AND can be accessed from client VMs
- [ ] **SSH access:** Often missing key authorization — verify SSH works with key, not just password
- [ ] **Installer media detached:** Often leaves ISO attached — verify no installer DVDs attached to Linux VMs
- [ ] **Checkpoints created:** Often assumes snapshot succeeded — verify "LabReady" snapshot actually exists
- [ ] **External connectivity:** Often assumes outbound access works — verify `Resolve-DnsName` to external hosts works

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Silent failure | HIGH | Add extensive logging, re-run with validation enabled, identify what silently failed |
| Stale VM state | LOW | Run aggressive cleanup script (Remove-HyperVVMStale), delete lab metadata, re-run |
| Network drift | MEDIUM | Delete and recreate vSwitch + NAT, verify host gateway IP, re-run deployment |
| Timeout failure | LOW | Increase timeouts, re-run deployment (VMs usually in good state) |
| AD DS failure | HIGH | Manual AD DS promotion using Install-ADDSForest, wait for restart, verify services |
| Linux VM gaps | MEDIUM | Create Linux VMs manually with native cmdlets, use cloud-init for unattended install |
| Connectivity failure | MEDIUM | Wait for services to start, use retry logic, validate ports before proceeding |
| ISO detection failure | LOW | Verify ISO filenames and integrity, re-download if corrupted |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Silent failures | Phase 1 (Foundation) | Structured error handling, validation gates after each step |
| Stale VM state | Phase 1 (Foundation) | Pre-flight cleanup, idempotent operations |
| Network drift | Phase 1 (Foundation) | Idempotent vSwitch/NAT setup, connectivity checks |
| Timeout mismatches | Phase 1 (Foundation) | Configure timeouts based on host capabilities |
| AD DS failures | Phase 2 (Core Lab) | Explicit AD DS validation, recovery promotion logic |
| Linux support gaps | Phase 3 (Mixed OS) | Hybrid automation: framework for Windows, native for Linux |
| Connectivity assumptions | Phase 1 (Foundation) | Wait for WinRM/SSH ports, retry with backoff |
| ISO detection | Phase 1 (Foundation) | Pre-flight ISO validation, explicit OS names |

---

## Sources

- [Building a PowerShell Script for Safe Hyper-V VM Updates (Medium)](https://medium.com/meetcyber/ultra-detailed-guide-building-a-powershell-script-for-safe-hyper-v-vm-updates-with-automatic-7154a4f3eb46) - Silent failure patterns
- [Automating Hyper-V Network Adapter Cleanup (AwakeCoding)](https://awakecoding.com/posts/automating-hyper-v-network-adapter-cleanup-migration/) - Ghost adapter issues
- [AutomatedLab Troubleshooting Basics](https://theautomatedlab.com/article.html?content=troubleshooting-1) - Official troubleshooting guide
- [AutomatedLab GitHub Issues](https://github.com/AutomatedLab/AutomatedLab/issues) - Real-world issues and solutions
- [Four Common Hyper-V Errors (RedmondMag)](https://redmondmag.com/articles/2026/01/09/four-common-hyperv-errors-and-how-to-correct-them.aspx) - Virtual switch and network adapter issues
- [Link Between NAT VMSwitch and NetNat (ServerFault)](https://serverfault.com/questions/944129/link-between-nat-vmswitch-and-netnat-windows-powershell) - NAT configuration pitfalls
- [A (not-so) Short Guide on Hyper-V (Reddit)](https://www.reddit.com/r/HyperV/comments/1limllg/a_notso_short_guide_on_quick_and_dirty_hyperv/) - Community best practices
- [AutomatedLab Documentation](https://automatedlab.org/en/latest/Wiki/) - Official command reference and patterns
- Project code analysis: `/mnt/projects/AutomatedLab/Deploy.ps1`, `/mnt/projects/AutomatedLab/Lab-Common.ps1`, `/mnt/projects/AutomatedLab/Test-OpenCodeLabHealth.ps1` - Existing patterns and recovery strategies

---

*Pitfalls research for: PowerShell Hyper-V Lab Automation*
*Researched: 2025-02-09*

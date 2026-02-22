# Codebase Concerns

**Analysis Date:** 2025-02-21

## Security Concerns

### Plaintext Password Handling

**Severity:** High

- **Issue:** Default passwords are hardcoded in configuration files and exposed in plaintext during credential resolution
- **Files:**
  - `Lab-Config.ps1` (lines 62, 71, 15)
  - `LabBuilder/Build-LabFromSelection.ps1` (lines 60-62)
  - `Private/Resolve-LabPassword.ps1` (referenced in Deploy.ps1 line 57)
- **Details:**
  - Default password `SimpleLab123!` is set in `Lab-Config.ps1` with only a warning message
  - Default SQL SA password `SimpleLabSqlSa123!` is exposed in config
  - Password is converted from SecureString to plaintext during credential resolution
  - While environment variable fallback exists (`OPENCODELAB_ADMIN_PASSWORD`, `LAB_ADMIN_PASSWORD`), plaintext defaults remain accessible
  - 28 occurrences of hardcoded default passwords found across codebase
- **Impact:**
  - Lab VMs deployed with default password are vulnerable if config is committed or shared
  - Plaintext password strings in memory during credential resolution
  - SQL SA account uses predictable default password
  - Tests verify passwords are not in Initialize-LabVMs but config file itself is unprotected
- **Fix approach:**
  - Remove hardcoded defaults from Lab-Config.ps1 entirely
  - Enforce environment variable requirement with validation in Resolve-LabPassword
  - Add preflight check that fails loudly if env vars not set
  - Consider using Windows Credential Manager or DPAPI for stored credentials

### SSH StrictHostKeyChecking Disabled

**Severity:** Medium

- **Issue:** SSH operations may bypass host key verification; fixed in recent commits but patterns need audit
- **Files:** `Public/Linux/` directory, `Deploy.ps1` SSH sections
- **Details:**
  - Recent commit f1347a8 addressed security issues from code review
  - StrictHostKeyChecking patterns in Linux deployment scripts
  - SSH key generation and host key verification may not be robust
- **Impact:**
  - Man-in-the-middle attack vulnerability on SSH connections
  - Linux domain join and configuration scripts may be exploitable
  - First-time SSH connection to new VMs accepts any key
- **Fix approach:**
  - Pre-populate known_hosts before SSH operations where possible
  - Use SSH key pinning for Linux VM connections
  - Implement key-based auth only (disable password SSH where possible)

### PowerShell ExecutionPolicy Bypass

**Severity:** Medium

- **Issue:** LabDeploymentService.cs executes PowerShell with `-ExecutionPolicy Bypass`
- **Files:** `OpenCodeLab-v2/Services/LabDeploymentService.cs` (implied from architecture)
- **Details:**
  - C# deployment service may invoke scripts without policy verification
  - Scripts executed with elevated privileges (admin context)
  - No validation of script sources before execution
- **Impact:**
  - Execution bypass allows unsigned scripts to run
  - Could enable injection attacks if script paths are user-controlled
  - No audit trail of what scripts executed
- **Fix approach:**
  - Validate PowerShell scripts with Invoke-ScriptAnalyzer before execution
  - Use signed scripts where possible; document code signing process
  - Log all PowerShell invocations with arguments (redact passwords)
  - Consider constraining to local file sources only

## Reliability Concerns

### Error Handling Gaps

**Severity:** High

- **Issue:** Inconsistent error handling patterns across major orchestration scripts
- **Files:**
  - `OpenCodeLab-App.ps1` (1081 lines) - complex orchestration
  - `Deploy.ps1` (1418 lines) - large deployment script
  - `GUI/Start-OpenCodeLabGUI.ps1` (2284 lines) - WPF GUI with event handlers
- **Details:**
  - `$ErrorActionPreference = 'Stop'` set globally but error recovery is unclear
  - Long scripts with complex state management increase risk of partial failures
  - AutoHeal feature attempts automatic recovery but may mask underlying issues
  - Deploy.ps1 has many WARN statuses that allow continuation (DHCP, LIN1 post-install, etc.)
- **Impact:**
  - Partial lab deployments leave infrastructure in inconsistent state
  - Errors during quick-mode operations may not properly fallback to full mode
  - WARN status messages may go unnoticed in long deployment logs
  - Health checks may pass on partially-broken labs
- **Fix approach:**
  - Wrap critical operations in try-catch blocks (VM creation, network setup, DC promotion)
  - Implement transaction-like patterns with explicit rollback on failure
  - Add error boundary pattern to GUI event handlers
  - Distinguish between recoverable warnings and blocking failures
  - Log all errors to artifact files for post-mortem analysis

### Snapshot Healing Race Conditions

**Severity:** Medium

- **Issue:** Invoke-LabQuickModeHeal may timeout waiting for LabReady snapshot health checks
- **Files:**
  - `Private/Invoke-LabQuickModeHeal.ps1` (lines 57-110)
  - `Lab-Config.ps1` (AutoHeal.TimeoutSeconds = 120)
  - `Private/Invoke-LabOneButtonSetup.ps1` (auto-heal orchestration)
- **Details:**
  - State probing and auto-heal operate on snapshots of system state without locks
  - Time gap between state probe and repair execution can cause issues
  - Multiple retry loops with hardcoded sleep times
  - Healing timeout (120s) may be exceeded on slow hosts
- **Impact:**
  - Concurrent deployments could conflict
  - Auto-heal may recreate infrastructure that another process is fixing
  - Switch/NAT operations may partially succeed leaving orphaned resources
  - "heal_timeout_exceeded" failure mode not clearly communicated to user
- **Fix approach:**
  - Implement file-based or registry-based lock mechanism for serialization
  - Add retry logic with exponential backoff (1s, 2s, 4s, 8s) for infrastructure operations
  - Re-probe state after each repair to detect concurrent changes
  - Document single-operator assumption in README
  - Increase timeout or make it configurable based on hardware

### AutomatedLab Timeout Configuration

**Severity:** Medium

- **Issue:** Timeout values are configurable but not consistently enforced
- **Files:**
  - `Lab-Config.ps1` (Timeouts section, lines 182-196)
  - `Deploy.ps1` (lines 217-225 timeout override setup)
  - `Private/Wait-LabADReady.ps1` (timeout parameters)
- **Details:**
  - Separate timeout configs for AutomatedLab core and Linux operations
  - Some operations (DC restart, ADWS readiness) have dedicated timeouts
  - WinRM timeout failures trigger WARN status and continue (line 688 Deploy.ps1)
  - LIN1 SSH wait defaults to 30 minutes but can hit soft timeouts
  - HealthCheck timeout is separate from overall auto-heal timeout
- **Impact:**
  - Scripts may hang indefinitely if timeout configuration is ignored
  - Insufficient timeouts cause false failures on slower hardware
  - Excessive timeouts delay feedback on real failures
  - Mixed timeout semantics (hard vs. soft) across operations
- **Fix approach:**
  - Audit all Wait-* and Start-* functions for timeout parameter usage
  - Add timeout enforcement to all loops and retry logic
  - Document timeout tuning guidance for different hardware profiles
  - Implement hard timeout boundaries that prevent infinite waits
  - Add timeout telemetry to run artifacts

## Maintainability Concerns

### Large Orchestration Scripts

**Severity:** High

- **Issue:** Core orchestration scripts exceed 1000-2000 lines making them difficult to maintain
- **Files:**
  - `OpenCodeLab-App.ps1` (1081 lines) - main orchestrator
  - `GUI/Start-OpenCodeLabGUI.ps1` (2284 lines) - WPF GUI entry point
  - `Deploy.ps1` (1418 lines) - lab deployment script
- **Details:**
  - OpenCodeLab-App.ps1 handles 20+ actions with complex routing logic
  - GUI contains embedded PowerShell cmdlet definitions mixed with XAML binding
  - Deploy.ps1 has 11+ section results with cascading error handling
  - Inline function definitions mixed with orchestration logic
  - State management spread across multiple variable scopes
- **Impact:**
  - High cognitive load for code reviewers and contributors
  - Difficult to test individual code paths in isolation
  - Bug fixes risk introducing regressions in adjacent logic
  - Refactoring becomes increasingly risky as script grows
  - New contributors struggle with understanding control flow
- **Fix approach:**
  - Extract inline functions to Private/ helpers (target: <500 lines per script)
  - Split action handlers into separate modules per concern (deploy, teardown, health)
  - Create orchestration state object to encapsulate run context
  - Add integration tests that exercise full action flows
  - Implement helper function search/discovery pattern in Lab-Common.ps1 instead of manual registration

### Configuration Complexity

**Severity:** Medium

- **Issue:** Lab-Config.ps1 spans 600+ lines with many nested hashtables and interdependent settings
- **Files:**
  - `Lab-Config.ps1` (603 lines) - defines `$GlobalLabConfig` with 15+ top-level keys
- **Details:**
  - Complex nested hashtables (Network.Switches, IPPlan, VMSizing, LabBuilder subconfig)
  - 337 Private/ helper functions scattered throughout codebase
  - Config changes require understanding full dependency graph
  - Multiple validation layers (Test-LabConfigRequired, deployment preflight, etc.)
  - Backward compatibility with legacy variables maintained but unclear
- **Impact:**
  - New contributors confused about which config values to use
  - Risk of config drift between related settings
  - Testing complexity due to large config state space
  - Refactoring blocked by backward compatibility constraints
  - Configuration errors only caught at deploy time, not at startup
- **Fix approach:**
  - Add immediate validation of Lab-Config.ps1 at sourcing time (Test-LabConfigRequired runs but doesn't catch all issues)
  - Create config schema validation that runs early
  - Document which config changes require redeploy vs. which are hot-reloadable
  - Implement config accessor functions that abstract source
  - Deprecation plan for legacy variables with migration guide

### Helper Function Sourcing Pattern

**Severity:** Medium

- **Issue:** 337 Private/ helper functions sourced via dynamic Import-LabScriptTree pattern
- **Files:**
  - `Lab-Common.ps1` (lines 1-33) - dynamic script tree import using Import-LabScriptTree helper
  - `Private/Import-LabScriptTree.ps1` - recursive file discovery
  - Multiple modules load helpers differently (Deploy.ps1, OpenCodeLab-App.ps1, GUI)
- **Details:**
  - Import-LabScriptTree provides dynamic loading but loading order not guaranteed
  - New helpers just dropped in Private/ directory without manual registration
  - No dependency tracking between helpers
  - Function name collisions possible if multiple helpers define same function
  - Some helpers may not be sourced by all entry points
- **Impact:**
  - Helper load order matters but isn't explicit or documented
  - New helpers might work in one context but not another
  - Debugging failures due to unsourced functions
  - Difficult to understand which helpers are available to which scripts
- **Fix approach:**
  - Document helper sourcing order and dependency requirements
  - Add validation that all helpers load successfully at startup
  - Implement topological sort for helper dependencies (if complex)
  - Add helper registry for runtime function discovery
  - Create "required" vs. "optional" helper categories with clear markers

### Test Coverage & Validation Gaps

**Severity:** High

- **Issue:** 337 Private/ helpers but test coverage is sparse; many critical paths untested
- **Files:**
  - `Tests/` directory - 60+ test files but gaps in Deploy.ps1 error paths
  - `Tests/DeployErrorHandling.Tests.ps1` - limited coverage
  - `Tests/DeployModeHandoff.Tests.ps1` - mode switching only
- **Details:**
  - Failure scenarios during Install-Lab, DNS forwarder, LIN1 post-install not fully tested
  - Transient WinRM failure retry logic detected but not stress-tested
  - Multi-switch network integration defined in config but no integration test
  - LabBuilder role dependencies (DC before SQL join) not enforced by validation
  - GUI state consistency under concurrent operations not tested
- **Impact:**
  - Critical failure paths like "AD not operational after Install-Lab" may fail in production
  - Deployments fail unexpectedly on flaky networks due to untested retry logic
  - Users attempting multi-switch setup hit undocumented failures
  - Role combination conflicts discovered during user deployments, not in CI
  - GUI may have race conditions in concurrent operation scenarios
- **Fix approach:**
  - Add parametrized tests for each Deploy.ps1 exception handler; mock Install-Lab failures
  - Add stress test simulating intermittent WinRM failures; verify retry count compliance
  - Add integration test for Deploy.ps1 with multi-switch config; verify routing
  - Create role dependency matrix with integration tests for all supported combinations
  - Add stress test launching 3+ concurrent operations; verify UI responsiveness
  - Target: >80% code coverage for Deploy.ps1 and critical helpers

## Performance Bottlenecks

### Synchronous VM State Polling in GUI

**Severity:** Medium

- **Issue:** GUI may block on synchronous Hyper-V queries during state refresh
- **Files:**
  - `OpenCodeLab-v2/ViewModels/ActionsViewModel.cs`
  - `OpenCodeLab-v2/Services/HyperVService.cs` (lines 14-42)
- **Details:**
  - GetVirtualMachinesAsync() awaits Task.Run() around ManagementObjectSearcher.Get()
  - ManagementObjectSearcher.Get() blocks on WMI query; no caching layer
  - UI thread may wait for VM enumeration on every dashboard refresh
  - Memory objects created on each query; no pooling
- **Impact:**
  - GUI responsiveness degradation during large labs (10+ VMs)
  - Dashboard updates may be slow and blocking
  - No indication to user that state query is in progress
- **Fix approach:**
  - Implement background worker thread with configurable poll interval (e.g., 30s)
  - Cache VM state; notify UI only on changes
  - Add loading indicator while state query in progress
  - Consider WMI event subscriptions instead of polling for event-driven updates

### Snapshot Restoration Speed

**Severity:** Medium

- **Issue:** Quick teardown and quick mode rely on snapshot restore (30-60s per VM on typical storage)
- **Files:**
  - `Private/Invoke-LabQuickTeardown.ps1` - checkpoint restoration
  - `Deploy.ps1` auto-heal flow with LabReady snapshot restoration
  - Transient backoff loops with hardcoded 5-second delays
- **Details:**
  - Hyper-V checkpoint restore I/O bound on storage performance
  - No parallelization of multi-VM snapshot restores
  - Hardcoded sleep(5) between WinRM retry attempts (lines 688-700 Deploy.ps1)
  - No exponential backoff; fixed delay even after multiple timeouts
- **Impact:**
  - Quick-mode failover takes 60-120s for 3-5 VM labs
  - Slow network responses during retry loops cause 5-10 minute delay before falling back
  - Poor user experience during frequent redeploy cycles
- **Fix approach:**
  - Restore multiple VM snapshots in parallel using background jobs
  - Monitor and report snapshot restore progress to GUI
  - Implement exponential backoff (1s, 2s, 4s, 8s max jitter) for WinRM retries
  - Add timeout-aware retry logic that backs off faster on resource contention

### Linear VM Creation Speed

**Severity:** Low

- **Issue:** AutomatedLab Install-Lab runs sequentially; no parallel VM provisioning
- **Files:**
  - `Deploy.ps1` (lines 400-500) - Install-Lab call followed by sequential post-install
- **Details:**
  - 3-5 minute per VM on typical SSD (full 3VM deployment = 15-25 min)
  - Install-Lab from AutomatedLab module doesn't parallelize
  - Post-install steps (DHCP, DNS, shares) run after all VMs created
- **Impact:**
  - Slow feedback loop for development iteration
  - Resource underutilization on multi-CPU hosts
- **Fix approach:**
  - Profile Install-Lab performance bottleneck
  - Consider AutomatedLab module upgrade or native parallel provisioning
  - Parallelize independent post-install tasks (e.g., DNS setup vs. DHCP scope)

## Fragile Areas

### Deploy.ps1 Install-Lab Error Handling

**Files:** `Deploy.ps1` (lines 467-469, 538)

- **Why fragile:** Catch block logs WARN status for Install-Lab failures but does not stop deployment; subsequent steps assume DC1 ADDS operational
- **Safe modification:**
  - Add AD validation check after Install-Lab (already done at line 538 with service check)
  - Throw if critical services (NTDS, ADWS) not running within health gate
  - Make WARN status more prominent (bold, color, sound alert)
- **Test coverage:**
  - Gaps in error path testing for "AD not operational post-Install-Lab"
  - No test for cascading failure (AD down → subsequent steps fail → confusing error messages)

### Multi-Switch Networking Configuration

**Files:** `Lab-Config.ps1` (Network.Switches array, lines 101-114), `Deploy.ps1` subnet conflict detection

- **Why fragile:**
  - Complex nested subnet validation only runs if helper Test-LabVirtualSwitchSubnetConflict exists
  - Graceful fallback hides real conflicts behind WARN status
  - Multi-switch config defined but Deploy.ps1 doesn't validate all switches created
- **Safe modification:**
  - Refactor subnet conflict detection into mandatory pre-flight step
  - Fail loudly on conflicts instead of warning and continuing
  - Validate all configured switches exist before VM creation
- **Test coverage:**
  - Limited multi-switch integration tests; most tests use single LabCorpNet
  - No test for cross-subnet VM communication (routing)

### LabBuilder Dynamic Role Loading

**Files:** `LabBuilder/Build-LabFromSelection.ps1` (VM creation loop), role handlers in `LabBuilder/Roles/`

- **Why fragile:**
  - Each role (DC.ps1, SQL.ps1, Linux*.ps1) manages its own configuration validation
  - No validation that all required fields present before role runs
  - Role dependencies (DC before SQL join) not enforced
  - SQL role may attempt join before DC is ready
- **Safe modification:**
  - Create role schema validation helper that runs before any role
  - Fail with clear error message listing missing config fields
  - Add explicit dependency check (DC promoted before SQL join attempt)
  - Create role execution order specification
- **Test coverage:**
  - Individual role tests exist but integration test gaps
  - No test matrix for role dependency combinations
  - Missing tests for "DC not ready when SQL tries to join"

### GUI Event Log Memory Growth

**Files:** `GUI/Start-OpenCodeLabGUI.ps1` (log circular buffer with $script:LogEntriesMaxCount = 2000)

- **Why fragile:**
  - Long-running deployments (4+ hours) may exceed 2000 entry limit
  - Old entries dropped without warning when buffer full
  - No indication to user that log is truncated
  - WPF TextBox performance degrades with large collections
- **Safe modification:**
  - Implement background log archival to file when nearing max
  - Emit warning when 80% of buffer full
  - Make buffer size configurable in Lab-Config
  - Implement virtual scrolling for log display
- **Test coverage:**
  - No stress test for extended deployment logging
  - No test verifying log entries don't drop unexpectedly

## Scaling Limits

### Single Domain Limitation

- **Current capacity:** Lab supports only one domain (simplelab.local); multi-domain scenarios blocked
- **Limit:** Cannot deploy complex multi-trust scenarios (parent-child, external trust forests)
- **Scaling path:** Extend AutomatedLab integration to support domain definitions array in Lab-Config; enhance VM domain-join logic

### Snapshot Proliferation

- **Current capacity:** Up to ~10 snapshots per VM before Hyper-V performance degrades noticeably
- **Limit:** LabReady checkpoint + user-created checkpoints; >10 causes snapshot chain slowdown
- **Scaling path:** Implement snapshot cleanup policy in Lab-Config; archive old snapshots; consolidate snapshot chains on deploy completion

### VHDx File Growth

- **Current capacity:** ~20-30GB per VM typical deployment (Server + apps)
- **Limit:** Snapshot chains can double storage; 5VM lab on single SSD can exhaust space
- **Scaling path:** Implement disk space monitoring and warning; add snapshot consolidation automation; consider thin provisioning

### GUI Event Loop Responsiveness

- **Current capacity:** GUI remains responsive for deployments <4 hours; log rendering slows after 5000+ entries
- **Limit:** WPF TextBox performance degrades with large item collections
- **Scaling path:** Implement virtual scrolling for log display; background-thread log updates; separate display layer from data

## Dependencies at Risk

### AutomatedLab Module Version Pinning

- **Risk:** Deploy.ps1 and LabBuilder depend on AutomatedLab module but do not enforce minimum version
- **Files:** `Deploy.ps1` (Import-Module AutomatedLab), `LabBuilder/Build-LabFromSelection.ps1`
- **Impact:** Breaking changes in AutomatedLab can break deployment silently
- **Migration plan:**
  - Pin AutomatedLab module version in Lab-Config.ps1
  - Add version check to Bootstrap.ps1 before deployment
  - Document tested versions in README

### PowerShell 5.1 Language Constraints

- **Risk:** Project targets Windows PowerShell 5.1; ternary operator not supported (PS 7+ only)
- **Files:** Multiple helpers in `Private/` use `if-else` workaround instead of ternary
- **Impact:** Code is verbose; contributors may accidentally use PS7-only syntax
- **Migration plan:**
  - Document PowerShell 5.1 constraints in CONVENTIONS.md
  - Add pre-commit check for unsupported syntax
  - Plan PS7 migration path

### Join-Path Limitation in PowerShell 5.1

- **Risk:** PowerShell 5.1 Join-Path only accepts 2 arguments; PS6+ supports 3+
- **Files:** `Deploy.ps1` line 22 uses nested Join-Path calls (documented in memory)
- **Impact:** Nested path joining is less readable; easy to introduce bugs
- **Migration plan:**
  - Create wrapper function Path-Combine that handles multiple segments
  - Document in CONVENTIONS.md (already in memory)

### Windows-Only Execution Model

- **Risk:** Deployment scripts assume Windows-only environment; no cross-platform testing
- **Files:** All shell integration uses PowerShell.exe; SSH key generation uses Windows OpenSSH
- **Impact:** CI/CD pipelines cannot run on non-Windows runners
- **Migration plan:**
  - Refactor core logic into PowerShell Core scripts
  - Containerize test environment
  - Support Docker-based lab simulation

## Missing Critical Features

### No Lab Rollback on Partial Failure

- **Problem:** If Deploy.ps1 fails midway (e.g., after DC creation but before SVR1 join), lab left in inconsistent state
- **Blocks:** Automated recovery workflows; safe "undo" for exploratory deployments
- **Suggested approach:**
  - Implement transactional checkpoint before each major section (VM creation, DC promotion, member join)
  - On exception, restore prior checkpoint and roll forward cleanup

### No Multi-Lab Instance Support

- **Problem:** Lab-Config.ps1 and Deploy.ps1 assume single lab per host
- **Blocks:** Multi-tenant lab scenarios; parallel testing of different configurations
- **Suggested approach:**
  - Extend Lab-Config to support lab instance ID
  - Namespace all Hyper-V objects with instance ID
  - Coordinate via instance registry in .planning/

### No Lab State Persistence API

- **Problem:** Lab state not persisted to queryable store; each script re-discovers state from Hyper-V
- **Blocks:** Audit trail; state-aware failover; historical tracking
- **Suggested approach:**
  - Create JSON-based lab state manifest (saved to .planning/labs/)
  - Track VM creation times, snapshot dates, deployment duration
  - Query via Get-LabState helper

### No Integrated Lab Backup/Restore

- **Problem:** No built-in mechanism to backup/restore full lab state for archival
- **Blocks:** Lab disaster recovery; off-site backup; version control of lab disk state
- **Suggested approach:**
  - Create Export-LabSnapshot / Import-LabSnapshot helpers
  - Archive VHDx files + metadata to .planning/backups/
  - Integration with cloud storage

---

*Concerns audit: 2025-02-21*

# Codebase Concerns

**Analysis Date:** 2026-02-16

## Security Concerns

### Plaintext Password Handling

**Severity:** High

- **Issue:** Default passwords are hardcoded in configuration files and exposed in plaintext during credential resolution
- **Files:**
  - `Lab-Config.ps1` (lines 62, 71, 333, 456)
  - `LabBuilder/Build-LabFromSelection.ps1` (lines 60-62)
- **Details:**
  - Default password `SimpleLab123!` is set in `Lab-Config.ps1` with only a warning message
  - Default SQL SA password `SimpleLabSqlSa123!` is exposed in config
  - Password is converted from SecureString to plaintext (`PtrToStringAuto`) in LabBuilder for AutomatedLab credential handling
  - While environment variable fallback exists (`OPENCODELAB_ADMIN_PASSWORD`), plaintext defaults remain accessible
- **Impact:**
  - Lab VMs deployed with default password are vulnerable if config is committed or shared
  - Plaintext password strings in memory during credential resolution
  - SQL SA account uses predictable default password
- **Fix approach:**
  - Remove hardcoded defaults from Lab-Config.ps1
  - Enforce environment variable or secure credential store usage
  - Add validation that password != default value before VM deployment
  - Consider using ConvertFrom-SecureString with encryption for stored credentials

### SSH StrictHostKeyChecking Disabled

**Severity:** Medium

- **Issue:** Recent commit history shows fixes for `StrictHostKeyChecking=no`, but codebase may still have residual insecure SSH patterns
- **Files:** (identified in commit ef9003f)
- **Details:**
  - Linux SSH operations may have previously bypassed host key verification
  - Recent fix moved to `accept-new` which is more secure but still permissive on first connection
- **Impact:**
  - Man-in-the-middle attack vulnerability on SSH connections
  - Linux domain join and configuration scripts may be exploitable
- **Fix approach:**
  - Audit all SSH-related scripts in `Public/Linux/` directory
  - Use pre-populated known_hosts where possible
  - Document SSH security model for lab vs. production

### Git Package Download Integrity

**Severity:** Medium

- **Issue:** SHA256 checksum validation added recently (commit e6c019e) but similar patterns may exist elsewhere
- **Files:**
  - `Lab-Config.ps1` (lines 176-182) - Git package config with SHA256
  - Potentially other software package downloads
- **Details:**
  - Git installer download URL and SHA256 are now validated
  - Other software packages in `SoftwarePackages` config may lack integrity checks
- **Impact:**
  - Supply chain attack if installer downloads are compromised
  - Man-in-the-middle injection during package downloads
- **Fix approach:**
  - Extend SHA256 validation pattern to all external downloads
  - Add checksum validation helper function
  - Consider using signed installers where available

## Reliability Concerns

### Error Handling Gaps

**Severity:** High

- **Issue:** Inconsistent error handling patterns across major orchestration scripts
- **Files:**
  - `OpenCodeLab-App.ps1` (1971 lines) - complex orchestration with deep nesting
  - `Deploy.ps1` (1242 lines) - large script with multiple error paths
  - `GUI/Start-OpenCodeLabGUI.ps1` (1534 lines) - WPF GUI with event handlers
- **Details:**
  - No use of `trap` or consistent catch blocks detected in grep search
  - `$ErrorActionPreference = 'Stop'` is set globally but error recovery is unclear
  - Long scripts with complex state management increase risk of partial failures
  - AutoHeal feature (`Invoke-LabQuickModeHeal.ps1`) attempts automatic recovery but may mask underlying issues
- **Impact:**
  - Partial lab deployments leave infrastructure in inconsistent state
  - Errors during quick-mode operations may not properly fallback to full mode
  - WPF GUI crashes could lose user state without proper exception handling
- **Fix approach:**
  - Add try-catch blocks around critical operations (VM creation, network setup, domain promotion)
  - Implement transaction-like patterns with explicit rollback on failure
  - Add error boundary pattern to GUI event handlers
  - Log all errors to artifact files for post-mortem analysis

### State Probing Race Conditions

**Severity:** Medium

- **Issue:** State probing and auto-heal operate on snapshots of system state without locks
- **Files:**
  - `Private/Get-LabStateProbe.ps1`
  - `Private/Invoke-LabQuickModeHeal.ps1` (lines 52-100)
  - `OpenCodeLab-App.ps1` (lines 1524-1567) - auto-heal orchestration
- **Details:**
  - State probe captures infrastructure state (VMs, switches, NAT, snapshots)
  - Auto-heal runs repairs based on stale state snapshot
  - No locking mechanism to prevent concurrent operations
  - Time gap between state probe and repair execution
- **Impact:**
  - Concurrent OpenCodeLab-App invocations could conflict
  - Auto-heal may recreate infrastructure that another process is fixing
  - Switch/NAT operations may partially succeed leaving orphaned resources
- **Fix approach:**
  - Implement file-based or registry-based lock mechanism
  - Add retry logic with exponential backoff for infrastructure operations
  - Re-probe state after each repair to detect concurrent changes
  - Document single-operator assumption in README

### AutomatedLab Timeout Configuration

**Severity:** Medium

- **Issue:** Timeout values are configurable but not consistently applied across all operations
- **Files:**
  - `Lab-Config.ps1` (lines 149-164, 301-311) - timeout configuration blocks
  - Various public functions that wait for VM readiness
- **Details:**
  - Separate timeout configs for AutomatedLab core and Linux operations
  - Some operations (DC restart, ADWS readiness) have dedicated timeouts
  - Unclear if timeouts are enforced consistently in all wait operations
  - HealthCheck timeout is separate from overall auto-heal timeout
- **Impact:**
  - Scripts may hang indefinitely if timeout configuration is ignored
  - Insufficient timeouts cause false failures on slower hardware
  - Excessive timeouts delay feedback on real failures
- **Fix approach:**
  - Audit all Wait-* and Start-* functions for timeout parameter usage
  - Add timeout enforcement to all loops and retry logic
  - Document timeout tuning guidance for different hardware profiles
  - Add timeout telemetry to run artifacts

## Maintainability Concerns

### Large Orchestration Scripts

**Severity:** High

- **Issue:** Core orchestration scripts exceed 1000-2000 lines making them difficult to maintain
- **Files:**
  - `OpenCodeLab-App.ps1` (1971 lines) - main orchestrator
  - `GUI/Start-OpenCodeLabGUI.ps1` (1534 lines) - WPF GUI entry point
  - `Deploy.ps1` (1242 lines) - lab deployment script
- **Details:**
  - OpenCodeLab-App.ps1 handles 25+ actions with complex routing logic
  - Deep nesting for mode decision, auto-heal, and dispatch coordination
  - Inline function definitions mixed with orchestration logic
  - State management spread across multiple variable scopes
- **Impact:**
  - High cognitive load for code reviewers and contributors
  - Difficult to test individual code paths in isolation
  - Bug fixes risk introducing regressions in adjacent logic
  - Refactoring becomes increasingly risky
- **Fix approach:**
  - Extract inline functions to Private/ helpers
  - Split action handlers into separate modules per concern (deploy, teardown, health, etc.)
  - Create orchestration state object to encapsulate run context
  - Add integration tests that exercise full action flows

### Configuration Complexity

**Severity:** Medium

- **Issue:** Dual configuration system with both structured hashtables and legacy variables
- **Files:**
  - `Lab-Config.ps1` (516 lines) - defines both `$GlobalLabConfig` hashtable and legacy exports
- **Details:**
  - Lines 1-398 define structured `$GlobalLabConfig` hashtable
  - Lines 400-516 export legacy variables like `$LabName`, `$LabSwitch`, etc.
  - Backward compatibility layer maintained for "existing scripts"
  - Two parallel config systems for LabBuilder vs. core lab
  - Config changes require updating both hashtable and legacy variable
- **Impact:**
  - New contributors confused about which config pattern to use
  - Risk of config drift between hashtable and legacy variables
  - Testing complexity due to dual state representation
  - Refactoring blocked by backward compatibility constraints
- **Fix approach:**
  - Deprecation plan for legacy variables with migration guide
  - Add validation that hashtable and legacy variables stay in sync
  - Create config accessor functions that abstract source
  - Migrate all new code to use `$GlobalLabConfig` exclusively

### Helper Function Sourcing Pattern

**Severity:** Medium

- **Issue:** Complex helper sourcing with inconsistent patterns across entry points
- **Files:**
  - `OpenCodeLab-App.ps1` (lines 69-94) - explicit array of orchestration helper paths
  - `Lab-Common.ps1` (lines 1-33) - dynamic script tree import
  - `GUI/Start-OpenCodeLabGUI.ps1` (lines 25-31) - foreach loop over subdirectories
- **Details:**
  - OpenCodeLab-App maintains hardcoded list of 18 orchestration helper paths
  - Adding new Private/ helper requires updating `$OrchestrationHelperPaths` array
  - Lab-Common.ps1 uses Import-LabScriptTree helper for dynamic loading
  - GUI uses Get-ChildItem with recursive directory traversal
  - Three different sourcing patterns across the codebase
- **Impact:**
  - New helpers may be forgotten in manual registration
  - Helper load order matters but isn't explicit
  - Debugging failures due to missing sourced functions
  - Pattern inconsistency confuses contributors
- **Fix approach:**
  - Standardize on Import-LabScriptTree pattern everywhere
  - Add validation that all helpers load successfully
  - Document helper registration conventions in CONVENTIONS.md
  - Consider PowerShell module manifest for better dependency management

### Test-Path Variable Checks

**Severity:** Low

- **Issue:** Variables checked with Get-Variable -ErrorAction SilentlyContinue pattern instead of Test-Path variable:
- **Files:**
  - `OpenCodeLab-App.ps1` (lines 99-103, 1524, 1528)
  - `Deploy.ps1` (lines 52-62)
- **Details:**
  - Pattern: `Get-Variable -Name VarName -ErrorAction SilentlyContinue`
  - More verbose than Set-StrictMode compliant `Test-Path variable:VarName`
  - Memory knowledge document mentions this as preferred pattern
- **Impact:**
  - Verbose code reduces readability
  - Inconsistent with Set-StrictMode best practices documented in MEMORY.md
- **Fix approach:**
  - Update OpenCodeLab-App and Deploy to use `Test-Path variable:` pattern
  - Add PSScriptAnalyzer rule to enforce consistent variable checking
  - Update CONVENTIONS.md with preferred pattern

## Scalability Limitations

### Single-Host Assumption

**Severity:** Medium

- **Issue:** Architecture assumes single Hyper-V host despite multi-host coordinator infrastructure
- **Files:**
  - `Private/Get-LabHostInventory.ps1` - supports inventory with multiple hosts
  - `Private/Invoke-LabCoordinatorDispatch.ps1` - dispatch logic for remote execution
  - `Private/Resolve-LabDispatchMode.ps1` - dispatch mode resolution
  - `Private/Test-LabScopedConfirmationToken.ps1` - multi-host safety tokens
- **Details:**
  - Coordinator/dispatch framework exists for multi-host operations
  - Most core operations (Deploy, Bootstrap) assume local Hyper-V execution
  - No remote PowerShell or SSH transport for core lab operations
  - Inventory file format defined but limited usage
- **Impact:**
  - Coordinator infrastructure adds complexity without clear benefit for single-host use case
  - Multi-host dispatch not tested or documented
  - Unclear scaling path for multiple Hyper-V hosts
  - Dispatch mode (off/canary/enforced) is configurable but execution unclear
- **Fix approach:**
  - Document intended multi-host usage scenarios
  - Either complete multi-host implementation or simplify to single-host
  - Add integration tests for dispatch modes
  - Clarify whether this is dev-only feature or production capability

### Memory Sizing Hardcoded

**Severity:** Low

- **Issue:** VM memory allocations are fixed in configuration without dynamic host capacity detection
- **Files:**
  - `Lab-Config.ps1` (lines 107-139, 279-299) - VM sizing configuration
- **Details:**
  - All VMs configured with 4GB base memory, 2-6GB dynamic range
  - No detection of host available memory
  - No validation that total VM memory fits on host
  - Ubuntu VMs configured with 2GB (less than typical Windows VMs)
- **Impact:**
  - Lab deployment may fail on hosts with < 16GB RAM
  - Over-commitment can cause VM performance degradation
  - No guidance for users to tune VM sizes for their hardware
- **Fix approach:**
  - Add host capacity check to Bootstrap.ps1 preflight
  - Calculate recommended VM counts based on available memory
  - Add "-Light" preset for resource-constrained hosts
  - Document minimum/recommended host specs in README

### LabBuilder Role Explosion

**Severity:** Low

- **Issue:** Growing list of roles increases configuration matrix complexity
- **Files:**
  - `Lab-Config.ps1` (lines 378-396) - RoleMenu with 15+ role options
  - `LabBuilder/Roles/` - role-specific configuration scripts
- **Details:**
  - Core roles: DC, DSC, IIS, SQL, WSUS, DHCP, FileServer, PrintServer, Jumpbox, Client
  - Linux roles: Ubuntu, WebServerUbuntu, DatabaseUbuntu, DockerUbuntu, K8sUbuntu
  - Each role requires IP plan entry, VM name mapping, and role handler
  - Testing all role combinations is exponentially complex
- **Impact:**
  - Untested role combinations may have conflicts (IP, DNS, ports)
  - Role-specific scripts may have drift in patterns and conventions
  - Adding new roles increases maintenance burden
- **Fix approach:**
  - Define core supported role sets with integration tests
  - Document which role combinations are tested vs. experimental
  - Consider role composition patterns instead of full-matrix support
  - Add role dependency validation (e.g., require DC for all domain-joined roles)

## Missing Features

### No Partial Rollback

**Severity:** Medium

- **Issue:** Teardown operations are all-or-nothing without selective VM removal
- **Files:**
  - `OpenCodeLab-App.ps1` (teardown action)
  - `Public/Remove-LabVM.ps1` - single VM removal
  - `Public/Remove-LabVMs.ps1` - multiple VM removal
- **Details:**
  - Teardown removes entire lab or nothing
  - No "-TargetVMs" parameter to selectively tear down specific VMs
  - Quick mode teardown restores LabReady snapshot affecting all VMs
  - Cannot remove experimental VMs while keeping core lab intact
- **Impact:**
  - Testing new roles requires full lab rebuild on failure
  - Cannot incrementally scale down lab to free resources
  - Experimentation workflow is rebuild-heavy
- **Fix approach:**
  - Add TargetVMs parameter to teardown action
  - Support selective VM removal while preserving lab registration
  - Add "reset-vm" action to restore single VM from checkpoint
  - Document which operations are safe for partial teardown

### Limited Checkpoint Management

**Severity:** Low

- **Issue:** Only LabReady checkpoint is managed; no user-defined checkpoints
- **Files:**
  - `Public/Save-LabReadyCheckpoint.ps1` - creates single checkpoint
  - `Public/Restore-LabCheckpoint.ps1` - restore generic checkpoint
  - `Public/Get-LabCheckpoint.ps1` - list checkpoints
- **Details:**
  - LabReady checkpoint is special-cased in quick mode logic
  - No UI or CLI for creating named checkpoints
  - Cannot checkpoint before risky operations (e.g., testing DSC configs)
  - Restore operations are manual, not integrated into orchestrator
- **Impact:**
  - Users must manually create checkpoints via Hyper-V Manager
  - No checkpoint naming conventions or metadata
  - Quick-mode rollback limited to single LabReady state
- **Fix approach:**
  - Add "save" action with optional checkpoint name
  - Add "rollback" action with checkpoint selection
  - Store checkpoint metadata (timestamp, description) in run artifacts
  - Integrate checkpoint list into GUI dashboard

### No Cost Estimation

**Severity:** Low

- **Issue:** No disk space or resource requirement calculation before deployment
- **Files:**
  - `Private/Test-DiskSpace.ps1` - exists but usage unclear
- **Details:**
  - Test-DiskSpace helper exists but not integrated into preflight
  - No calculation of expected disk usage for VMs + VHDx
  - No warning about disk space exhaustion mid-deployment
  - ISO requirements listed but total storage need not calculated
- **Impact:**
  - Deployments fail mid-process due to disk space exhaustion
  - Users unaware of storage requirements before starting
  - No guidance on cleanup to free space
- **Fix approach:**
  - Integrate Test-DiskSpace into Bootstrap.ps1 preflight
  - Calculate expected disk usage: ISOs + VHDx (expand) + checkpoints
  - Add disk space monitoring to health checks
  - Suggest cleanup actions when space is low

## Technical Debt

### Archive Directory Size

**Severity:** Low

- **Issue:** Large deprecated code archive committed to repository
- **Files:**
  - `.archive/deprecated-builders/` - old New-AutomatedLab.ps1, SimpleLab.ps1
  - `.archive/SimpleLab-20260210/` - full directory snapshot with 60+ files
- **Details:**
  - Archive contains 60+ deprecated scripts from 2026-02-10
  - Deprecated builders are preserved in git history anyway
  - Increases repository clone size and search noise
- **Impact:**
  - Repository size bloat
  - Search results polluted with deprecated code
  - Confusion about which code is current
- **Fix approach:**
  - Remove `.archive/` from main branch (available in git history)
  - Document migration from deprecated patterns in README
  - Add note in STRUCTURE.md about git history access
  - Keep `.gitignore` exclusion comment for clarity

### PowerShell LSP Tools Committed

**Severity:** Low

- **Issue:** PowerShell Language Server Protocol tools committed to repository
- **Files:**
  - `.tools/powershell-lsp/` directory (multiple MB)
- **Details:**
  - Full PSES (PowerShell Editor Services) distribution in .tools/
  - PSReadLine and PSScriptAnalyzer modules included
  - Typically installed via editor extension, not committed
  - Ignored in .gitignore but still tracked
- **Impact:**
  - Repository size increase
  - Tools may be outdated compared to latest releases
  - Editor-specific tooling in shared repository
- **Fix approach:**
  - Move to .gitignore if not already (appears to be ignored per .gitignore line 27)
  - Remove from git history using git-filter-repo or BFG
  - Document required VS Code extensions in README
  - Consider dev container approach for consistent tooling

### Test Coverage Artifacts Committed

**Severity:** Low

- **Issue:** Coverage.xml file appears in test directory (681K)
- **Files:**
  - `Tests/coverage.xml` (361K per ls output)
- **Details:**
  - Coverage report from Pester test runs
  - Should be generated locally or in CI, not committed
  - Already in .gitignore (line 4) but still tracked
- **Impact:**
  - Repository churn on every test run with coverage
  - Merge conflicts on coverage reports
  - No value in versioning test artifacts
- **Fix approach:**
  - Remove from git: `git rm Tests/coverage.xml`
  - Verify .gitignore pattern catches it
  - Document coverage report generation in TESTING.md

---

*Concerns audit: 2026-02-16*

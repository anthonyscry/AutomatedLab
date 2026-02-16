# Requirements: AutomatedLab Hardening & Integration

**Defined:** 2026-02-16
**Core Value:** Every button, menu option, and CLI action works reliably from start to finish

## v1 Requirements

Requirements for this hardening milestone. Each maps to roadmap phases.

### CLI Orchestrator

- [ ] **CLI-01**: User can run all 25+ actions in OpenCodeLab-App.ps1 without unhandled errors
- [ ] **CLI-02**: Deploy action provisions VMs from template with correct hardware specs and network config
- [ ] **CLI-03**: Teardown action removes all lab resources cleanly (VMs, checkpoints, vSwitch, NAT)
- [ ] **CLI-04**: Bootstrap action installs prerequisites, creates directories, validates environment
- [ ] **CLI-05**: Quick mode restores from LabReady snapshot and auto-heals infrastructure gaps
- [ ] **CLI-06**: Health check action reports accurate lab status with actionable diagnostics
- [ ] **CLI-07**: All destructive actions require confirmation tokens before executing
- [ ] **CLI-08**: Error handling uses try-catch on all critical operations with context-aware messages
- [ ] **CLI-09**: Menu system displays correct options and routes to correct handlers

### GUI

- [ ] **GUI-01**: Dashboard view loads and polls VM status every 5 seconds without crashes
- [ ] **GUI-02**: Actions view populates dropdown with all available actions and executes them correctly
- [ ] **GUI-03**: Customize view loads template editor, creates/saves/applies templates without errors
- [ ] **GUI-04**: Settings view persists theme, admin username, and preferences to gui-settings.json
- [ ] **GUI-05**: Logs view displays color-coded log entries from in-memory log list
- [ ] **GUI-06**: View switching works reliably between all views without state corruption
- [ ] **GUI-07**: GUI achieves feature parity with CLI — all actions accessible from both interfaces
- [ ] **GUI-08**: Script-scoped variable closures captured correctly in all event handlers

### Lifecycle

- [ ] **LIFE-01**: Bootstrap → Deploy → Use → Teardown completes end-to-end on clean Windows host
- [ ] **LIFE-02**: Full mode creates VMs, configures network, promotes DC, joins domain, applies roles
- [ ] **LIFE-03**: Quick mode restores LabReady checkpoint and heals any infrastructure gaps
- [ ] **LIFE-04**: Teardown cleans all resources with no orphaned VMs, switches, or NAT rules
- [ ] **LIFE-05**: Re-deploy after teardown succeeds (idempotent infrastructure creation)

### Roles

- [ ] **ROLE-01**: DC role promotes domain controller with DNS and ADWS services running
- [ ] **ROLE-02**: SQL role installs SQL Server with configured SA account
- [ ] **ROLE-03**: IIS role installs and configures web server
- [ ] **ROLE-04**: WSUS role installs Windows Server Update Services
- [ ] **ROLE-05**: DHCP role configures DHCP server with lab scope
- [ ] **ROLE-06**: FileServer role creates and shares directories
- [ ] **ROLE-07**: PrintServer role installs print services
- [ ] **ROLE-08**: DSC role configures Desired State Configuration pull server
- [ ] **ROLE-09**: Jumpbox role configures RDP gateway access
- [ ] **ROLE-10**: Client role joins domain as workstation
- [ ] **ROLE-11**: All roles handle missing prerequisites gracefully with clear error messages

### Network

- [ ] **NET-01**: vSwitch creation is idempotent (create if missing, skip if exists)
- [ ] **NET-02**: NAT configuration applies correctly with no subnet conflicts
- [ ] **NET-03**: Static IP assignment configures VMs via PowerShell Direct
- [ ] **NET-04**: DNS configuration sets forwarders and validates resolution
- [ ] **NET-05**: Network health check validates VM-to-VM connectivity

### Multi-Host

- [ ] **MH-01**: Host inventory file loads and validates remote host entries
- [ ] **MH-02**: Coordinator dispatch routes operations to correct target hosts
- [ ] **MH-03**: Dispatch modes (off/canary/enforced) behave as documented
- [ ] **MH-04**: Scoped confirmation tokens validate per-host safety gates
- [ ] **MH-05**: Remote operations handle connectivity failures gracefully

### Configuration

- [ ] **CFG-01**: GlobalLabConfig hashtable is single source of truth — legacy variables removed or deprecated
- [ ] **CFG-02**: All entry points use consistent helper sourcing pattern (standardize on one approach)
- [ ] **CFG-03**: Lab-Config.ps1 validates configuration on load (required fields, type checks)
- [ ] **CFG-04**: Template system reads/writes JSON correctly with schema validation

### Security

- [ ] **SEC-01**: Default passwords removed from config — environment variable or prompt required
- [ ] **SEC-02**: SSH operations use secure host key checking (accept-new minimum, known_hosts preferred)
- [ ] **SEC-03**: All external downloads validate SHA256 checksums before execution
- [ ] **SEC-04**: Credentials never appear in plain text in log output or run artifacts

### Cleanup

- [ ] **CLN-01**: .archive/ directory removed from main branch (preserved in git history)
- [ ] **CLN-02**: Test coverage artifacts (coverage.xml) removed from tracked files
- [ ] **CLN-03**: LSP tools removed from tracked files (already in .gitignore)
- [ ] **CLN-04**: Leftover debug/test scripts (test-*.ps1, test.json) removed
- [ ] **CLN-05**: Dead or unreachable code paths identified and removed

## v2 Requirements

### Linux VM Support

- **LIN-01**: Ubuntu VM provisions with cloud-init and SSH key access
- **LIN-02**: Linux roles (WebServer, Database, Docker, K8s) configure correctly
- **LIN-03**: Linux domain join via realmd/SSSD works

### Advanced Features

- **ADV-01**: Selective VM teardown (remove individual VMs without full reset)
- **ADV-02**: Named user checkpoints with metadata
- **ADV-03**: Host capacity detection and VM sizing recommendations
- **ADV-04**: Disk space estimation before deployment

## Out of Scope

| Feature | Reason |
|---------|--------|
| New features or capabilities | This milestone is hardening existing code only |
| Linux VM active testing | Code preserved but deprioritized — Windows flows first |
| Performance optimization | Correctness before speed |
| Cloud/Azure integration | Local Hyper-V only |
| Mobile or web interface | Desktop WPF GUI only |
| CI/CD pipeline | Single developer workflow |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| (To be populated during roadmap creation) | | |

**Coverage:**
- v1 requirements: 42 total
- Mapped to phases: 0
- Unmapped: 42

---
*Requirements defined: 2026-02-16*
*Last updated: 2026-02-16 after initial definition*

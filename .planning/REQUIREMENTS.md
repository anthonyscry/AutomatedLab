# Requirements: AutomatedLab Hardening & Integration

**Defined:** 2026-02-16
**Core Value:** Every button, menu option, and CLI action works reliably from start to finish

## v1 Requirements

Requirements for this hardening milestone. Each maps to roadmap phases.

### CLI Orchestrator

- [x] **CLI-01**: User can run all 25+ actions in OpenCodeLab-App.ps1 without unhandled errors
- [x] **CLI-02**: Deploy action provisions VMs from template with correct hardware specs and network config
- [x] **CLI-03**: Teardown action removes all lab resources cleanly (VMs, checkpoints, vSwitch, NAT)
- [x] **CLI-04**: Bootstrap action installs prerequisites, creates directories, validates environment
- [x] **CLI-05**: Quick mode restores from LabReady snapshot and auto-heals infrastructure gaps
- [x] **CLI-06**: Health check action reports accurate lab status with actionable diagnostics
- [x] **CLI-07**: All destructive actions require confirmation tokens before executing
- [x] **CLI-08**: Error handling uses try-catch on all critical operations with context-aware messages
- [x] **CLI-09**: Menu system displays correct options and routes to correct handlers

### GUI

- [x] **GUI-01**: Dashboard view loads and polls VM status every 5 seconds without crashes
- [x] **GUI-02**: Actions view populates dropdown with all available actions and executes them correctly
- [x] **GUI-03**: Customize view loads template editor, creates/saves/applies templates without errors
- [x] **GUI-04**: Settings view persists theme, admin username, and preferences to gui-settings.json
- [x] **GUI-05**: Logs view displays color-coded log entries from in-memory log list
- [x] **GUI-06**: View switching works reliably between all views without state corruption
- [x] **GUI-07**: GUI achieves feature parity with CLI — all actions accessible from both interfaces
- [x] **GUI-08**: Script-scoped variable closures captured correctly in all event handlers

### Lifecycle

- [x] **LIFE-01**: Bootstrap → Deploy → Use → Teardown completes end-to-end on clean Windows host
- [x] **LIFE-02**: Full mode creates VMs, configures network, promotes DC, joins domain, applies roles
- [x] **LIFE-03**: Quick mode restores LabReady checkpoint and heals any infrastructure gaps
- [x] **LIFE-04**: Teardown cleans all resources with no orphaned VMs, switches, or NAT rules
- [x] **LIFE-05**: Re-deploy after teardown succeeds (idempotent infrastructure creation)

### Roles

- [x] **ROLE-01**: DC role promotes domain controller with DNS and ADWS services running
- [x] **ROLE-02**: SQL role installs SQL Server with configured SA account
- [x] **ROLE-03**: IIS role installs and configures web server
- [x] **ROLE-04**: WSUS role installs Windows Server Update Services
- [x] **ROLE-05**: DHCP role configures DHCP server with lab scope
- [x] **ROLE-06**: FileServer role creates and shares directories
- [x] **ROLE-07**: PrintServer role installs print services
- [x] **ROLE-08**: DSC role configures Desired State Configuration pull server
- [x] **ROLE-09**: Jumpbox role configures RDP gateway access
- [x] **ROLE-10**: Client role joins domain as workstation
- [x] **ROLE-11**: All roles handle missing prerequisites gracefully with clear error messages

### Network

- [x] **NET-01**: vSwitch creation is idempotent (create if missing, skip if exists)
- [x] **NET-02**: NAT configuration applies correctly with no subnet conflicts
- [x] **NET-03**: Static IP assignment configures VMs via PowerShell Direct
- [x] **NET-04**: DNS configuration sets forwarders and validates resolution
- [x] **NET-05**: Network health check validates VM-to-VM connectivity

### Multi-Host

- [ ] **MH-01**: Host inventory file loads and validates remote host entries
- [ ] **MH-02**: Coordinator dispatch routes operations to correct target hosts
- [ ] **MH-03**: Dispatch modes (off/canary/enforced) behave as documented
- [ ] **MH-04**: Scoped confirmation tokens validate per-host safety gates
- [ ] **MH-05**: Remote operations handle connectivity failures gracefully

### Configuration

- [x] **CFG-01**: GlobalLabConfig hashtable is single source of truth — legacy variables removed or deprecated
- [x] **CFG-02**: All entry points use consistent helper sourcing pattern (standardize on one approach)
- [x] **CFG-03**: Lab-Config.ps1 validates configuration on load (required fields, type checks)
- [x] **CFG-04**: Template system reads/writes JSON correctly with schema validation

### Security

- [x] **SEC-01**: Default passwords removed from config — environment variable or prompt required
- [x] **SEC-02**: SSH operations use secure host key checking (accept-new minimum, known_hosts preferred)
- [x] **SEC-03**: All external downloads validate SHA256 checksums before execution
- [x] **SEC-04**: Credentials never appear in plain text in log output or run artifacts

### Cleanup

- [x] **CLN-01**: .archive/ directory removed from main branch (preserved in git history)
- [x] **CLN-02**: Test coverage artifacts (coverage.xml) removed from tracked files
- [x] **CLN-03**: LSP tools removed from tracked files (already in .gitignore)
- [x] **CLN-04**: Leftover debug/test scripts (test-*.ps1, test.json) removed
- [x] **CLN-05**: Dead or unreachable code paths identified and removed

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
| CLN-01 | Phase 1 | Done |
| CLN-02 | Phase 1 | Done |
| CLN-03 | Phase 1 | Done |
| CLN-04 | Phase 1 | Done |
| CLN-05 | Phase 1 | Done |
| CFG-01 | Phase 1 | Done |
| CFG-02 | Phase 1 | Done |
| CFG-03 | Phase 1 | Done |
| CFG-04 | Phase 1 | Done |
| SEC-01 | Phase 2 | Done |
| SEC-02 | Phase 2 | Done |
| SEC-03 | Phase 2 | Done |
| SEC-04 | Phase 2 | Done |
| LIFE-01 | Phase 3 | Done |
| LIFE-02 | Phase 3 | Done |
| LIFE-03 | Phase 3 | Done |
| LIFE-04 | Phase 3 | Done |
| LIFE-05 | Phase 3 | Done |
| CLI-01 | Phase 3 | Done |
| CLI-02 | Phase 3 | Done |
| CLI-03 | Phase 3 | Done |
| CLI-04 | Phase 3 | Done |
| CLI-05 | Phase 3 | Done |
| CLI-06 | Phase 3 | Done |
| CLI-07 | Phase 3 | Done |
| CLI-08 | Phase 3 | Done |
| CLI-09 | Phase 3 | Done |
| NET-01 | Phase 3 | Done |
| NET-02 | Phase 3 | Done |
| NET-03 | Phase 3 | Done |
| NET-04 | Phase 3 | Done |
| NET-05 | Phase 3 | Done |
| ROLE-01 | Phase 4 | Done |
| ROLE-02 | Phase 4 | Done |
| ROLE-03 | Phase 4 | Done |
| ROLE-04 | Phase 4 | Done |
| ROLE-05 | Phase 4 | Done |
| ROLE-06 | Phase 4 | Done |
| ROLE-07 | Phase 4 | Done |
| ROLE-08 | Phase 4 | Done |
| ROLE-09 | Phase 4 | Done |
| ROLE-10 | Phase 4 | Done |
| ROLE-11 | Phase 4 | Done |
| GUI-01 | Phase 5 | Done |
| GUI-02 | Phase 5 | Done |
| GUI-03 | Phase 5 | Done |
| GUI-04 | Phase 5 | Done |
| GUI-05 | Phase 5 | Done |
| GUI-06 | Phase 5 | Done |
| GUI-07 | Phase 5 | Done |
| GUI-08 | Phase 5 | Done |
| MH-01 | Phase 6 | Pending |
| MH-02 | Phase 6 | Pending |
| MH-03 | Phase 6 | Pending |
| MH-04 | Phase 6 | Pending |
| MH-05 | Phase 6 | Pending |

**Coverage:**
- v1 requirements: 56 total
- Mapped to phases: 56
- Unmapped: 0

---
*Requirements defined: 2026-02-16*
*Last updated: 2026-02-16 after roadmap creation*

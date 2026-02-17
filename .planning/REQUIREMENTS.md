# Requirements: AutomatedLab v1.1 Production Robustness

**Defined:** 2026-02-17
**Core Value:** Every function handles errors explicitly, surfaces clear diagnostics, and the codebase is modular enough that each piece can be tested and maintained independently.

## v1.1 Requirements

Requirements for production robustness milestone. Each maps to roadmap phases.

### Security

- [ ] **SEC-01**: Initialize-LabVMs.ps1 uses $GlobalLabConfig.Credentials.AdminPassword instead of hardcoded default
- [ ] **SEC-02**: Open-LabTerminal.ps1 uses StrictHostKeyChecking=accept-new instead of =no
- [ ] **SEC-03**: Deploy.ps1 validates Git installer SHA256 checksum after download
- [ ] **SEC-04**: New-LabUnattendXml emits Write-Warning about plaintext password storage

### Reliability

- [ ] **REL-01**: Test-DCPromotionPrereqs always executes network check (no early return skip)
- [ ] **REL-02**: Ensure-VMsReady uses return instead of exit 0
- [ ] **REL-03**: New-LabNAT and Set-VMStaticIP validate IP addresses and CIDR prefix
- [ ] **REL-04**: Initialize-LabVMs and New-LabSSHKey use config paths instead of hardcoded paths

### Orchestrator Extraction

- [ ] **EXT-01**: All 31 inline functions extracted from OpenCodeLab-App.ps1 to Private/ helpers
- [ ] **EXT-02**: OpenCodeLab-App.ps1 sources extracted helpers via Lab-Common.ps1
- [ ] **EXT-03**: Extracted helpers have [CmdletBinding()] and explicit parameters (no script-scope dependency)
- [ ] **EXT-04**: All existing Pester tests continue passing after extraction

### Error Handling

- [ ] **ERR-01**: All 28 Private functions without try-catch get explicit error handling
- [ ] **ERR-02**: All 11 Public functions without try-catch get explicit error handling
- [ ] **ERR-03**: Error messages include function name and actionable context
- [ ] **ERR-04**: No function uses exit to terminate — all use return or throw

### Diagnostics

- [ ] **DIAG-01**: Out-Null replaced with Write-Verbose in operational paths (65 instances)
- [ ] **DIAG-02**: Module export list reconciled — SimpleLab.psd1 matches actual Public/ functions
- [ ] **DIAG-03**: SimpleLab.psm1 export matches .psd1 FunctionsToExport

## v2 Requirements

Deferred to future milestones. Tracked but not in current roadmap.

### Documentation (v1.2)

- **DOC-01**: README.md updated with correct GUI entry point and multi-host docs
- **DOC-02**: User guide covering CLI and GUI workflows
- **DOC-03**: Troubleshooting guide for common issues
- **DOC-04**: All Public functions have help comments with examples

### CI/CD (v1.2)

- **CICD-01**: GitHub Actions workflow for Pester tests on PR
- **CICD-02**: PSScriptAnalyzer integration
- **CICD-03**: Release automation with version bumping
- **CICD-04**: PowerShell Gallery publishing

### Test Coverage (v1.2)

- **TEST-01**: Unit tests for 20+ untested Public functions
- **TEST-02**: Code coverage reporting with thresholds
- **TEST-03**: E2E smoke test suite

## Out of Scope

| Feature | Reason |
|---------|--------|
| New capabilities | This milestone is about robustness, not features |
| Docker toolchain | Separate concern, deferred |
| Linux VM testing | Keep code intact but don't prioritize |
| Performance optimization | Correctness first |
| Cloud/Azure integration | Local Hyper-V only |
| Deploy.ps1 modularization | Separate from orchestrator extraction — future milestone |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SEC-01 | — | Pending |
| SEC-02 | — | Pending |
| SEC-03 | — | Pending |
| SEC-04 | — | Pending |
| REL-01 | — | Pending |
| REL-02 | — | Pending |
| REL-03 | — | Pending |
| REL-04 | — | Pending |
| EXT-01 | — | Pending |
| EXT-02 | — | Pending |
| EXT-03 | — | Pending |
| EXT-04 | — | Pending |
| ERR-01 | — | Pending |
| ERR-02 | — | Pending |
| ERR-03 | — | Pending |
| ERR-04 | — | Pending |
| DIAG-01 | — | Pending |
| DIAG-02 | — | Pending |
| DIAG-03 | — | Pending |

**Coverage:**
- v1.1 requirements: 19 total
- Mapped to phases: 0
- Unmapped: 19 ⚠️

---
*Requirements defined: 2026-02-17*
*Last updated: 2026-02-17 after initial definition*

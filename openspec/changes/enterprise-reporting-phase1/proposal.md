# Enterprise Reporting Phase 1

## Summary
Port compliance reporting infrastructure from feat/enterprise-reporting-phase1 worktree to main branch. This provides tamper-evident evidence packaging and compliance framework mapping capabilities required for enterprise audit workflows.

## Motivation
Enterprise deployments require audit trails and compliance evidence that maps to security frameworks (NIST, CIS, etc.). The existing worktree contains a working implementation that needs to be merged to main.

## Changes

### New Files
1. **Scripts/Compliance/ControlMap.psd1** - Framework control mappings (NIST 800-53)
2. **Scripts/Compliance/README.md** - Documentation for compliance schema
3. **Scripts/New-ComplianceEvidencePack.ps1** - Creates tamper-evident zip bundles with SHA256 manifests
4. **Scripts/Helpers-ComplianceReport.ps1** - Helper functions for compliance annotation

### Features
- **Evidence Bundling**: Creates timestamped zip files with SHA256 hashes for tamper detection
- **Manifest Generation**: JSON manifests with artifact hashes and bundle integrity
- **Framework Mapping**: Maps checks to NIST 800-53 controls
- **Compliance Annotation**: Pipeline-friendly functions to add framework metadata to objects

## Acceptance Criteria
- [x] All 4 enterprise files copied from worktree to main
- [x] Scripts load without errors
- [x] New-ComplianceEvidencePack creates valid zip with manifest
- [x] Helpers-ComplianceReport functions resolve mappings correctly

## Testing
```powershell
# Test compliance helpers
Import-Module ./Scripts/Helpers-ComplianceReport.ps1
$map = Get-ComplianceControlMap
$map.Checks.ContainsKey('DNS.ExternalResolution') # Should be $true

# Test evidence pack creation
. ./Scripts/New-ComplianceEvidencePack.ps1
$result = New-ComplianceEvidencePack -OutputRoot ./test-evidence -InputPaths @("./Scripts/Compliance/ControlMap.psd1")
Test-Path $result.BundlePath # Should be $true
Test-Path $result.ManifestPath # Should be $true
```

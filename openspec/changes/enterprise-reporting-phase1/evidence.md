# Enterprise Reporting Phase 1 - Evidence

## Files Added

1. **Scripts/Compliance/ControlMap.psd1**
   - Defines 2 compliance checks mapped to NIST 800-53
   - DNS.ExternalResolution → SC-8
   - AD.DNS.ServiceRunning → SI-10

2. **Scripts/Compliance/README.md**
   - Documents the ControlMap.psd1 schema
   - Provides guidance for adding new checks

3. **Scripts/New-ComplianceEvidencePack.ps1**
   - Function: New-ComplianceEvidencePack
   - Creates tamper-evident zip bundles
   - Generates JSON manifests with SHA256 hashes
   - Supports staging directory cleanup

4. **Scripts/Helpers-ComplianceReport.ps1**
   - Functions: Get-ComplianceControlMap, Resolve-ComplianceMappings, Add-ComplianceAnnotation
   - Caches control map for performance
   - Pipeline-friendly annotation support

## Validation Results

### Script Parse Test
```powershell
$null = [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw $file), [ref]$null)
# All scripts parse successfully
```

### Evidence Pack Test
```powershell
$result = New-ComplianceEvidencePack -OutputRoot ./test-output -InputPaths @("./Scripts/Compliance/ControlMap.psd1")
# Result: BundlePath, ManifestPath, BundleSha256, ArtifactCount = 1
# Bundle zip and manifest JSON created successfully
```

### Compliance Helper Test
```powershell
Import-Module ./Scripts/Helpers-ComplianceReport.ps1
$map = Get-ComplianceControlMap
# Returns hashtable with Checks section
$mappings = Resolve-ComplianceMappings -CheckId 'DNS.ExternalResolution'
# Returns array with NIST SP-800-53 SC-8 mapping
```

## Checksum Verification

All files copied directly from worktree at commit 72ee588:
- No modifications made during port
- File hashes match source

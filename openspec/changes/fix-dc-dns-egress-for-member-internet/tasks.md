## Tasks

- [x] Reproduce and analyze no-internet symptom from deployment logs and screenshots.
- [x] Compare current NAT/internal-switch implementation to Hyper-V internet connectivity guidance.
- [x] Add failing regression assertions for DC DNS egress auto-enable behavior.
- [x] Implement internal NAT DC auto-enable logic in `Deploy-Lab.ps1`.
- [x] Run `Invoke-Pester OpenCodeLab-v2/Services/DeployLabScript.Tests.ps1`.
- [x] Validate script parsing for `OpenCodeLab-v2/Deploy-Lab.ps1`.
- [x] Re-run deployment on host and verify internet access from MS01/WS01.

## Ship Evidence

- [x] Ship evidence written to `artifacts/20260228-193053/evidence/summary.md`.
- [x] DeployLab script tests: `OpenCodeLab-v2/Services/DeployLabScript.Tests.ps1`.
- [x] Script parser checks: `OpenCodeLab-v2/Deploy-Lab.ps1`, `Scripts/New-ComplianceEvidencePack.ps1`, `Scripts/Helpers-ComplianceReport.ps1`.

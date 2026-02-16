# Remaining Production Readiness Gaps Design

**Date:** 2026-02-16
**Status:** Approved

## Goal

Fix 11 remaining production readiness issues across security, reliability, and maintainability, then implement the Docker development toolchain.

## Security Fixes (S1-S4)

**S1: Initialize-LabVMs.ps1 duplicate default password**
- Replace hardcoded `$defaultPassword = "SimpleLab123!"` with `$GlobalLabConfig.Credentials.AdminPassword` lookup
- Fallback to existing default if config unavailable

**S2: Open-LabTerminal.ps1 SSH host key checking disabled**
- Replace `-o StrictHostKeyChecking=no` with `-o StrictHostKeyChecking=accept-new`
- `accept-new` trusts on first connect but warns on changes (TOFU pattern)

**S3: Deploy.ps1 no checksum on Git installer download**
- Add SHA256 checksum validation after download
- Store expected hash in Lab-Config.ps1 under a new `SoftwarePackages` section
- Skip validation if offline installer exists locally

**S4: Unattend.xml plaintext password awareness**
- Add `Write-Warning` when generating unattend.xml noting the password is stored in plaintext
- This is inherent to Windows unattended installs — no code change beyond the warning

## Reliability Fixes (R1-R4)

**R1: Test-DCPromotionPrereqs early return**
- Fix control flow so network check (Check 5) is always executed
- Set `CanPromote` flag correctly before returning

**R2: Ensure-VMsReady uses `exit` instead of `return`**
- Replace `exit 0` with `return` so calling scripts aren't terminated

**R3: Missing IP/CIDR validation**
- Add `[ValidatePattern]` for IP addresses in New-LabNAT and Set-VMStaticIP
- Add `[ValidateRange(1,32)]` for PrefixLength

**R4: Hardcoded paths should use config**
- Initialize-LabVMs.ps1: Replace `C:\Lab\VMs` with `$GlobalLabConfig.Paths.LabRoot`
- New-LabSSHKey.ps1: Replace `C:\LabSources\SSHKeys` with config path

## Maintainability Fixes (M1-M2)

**M1: Module export list audit**
- Compare SimpleLab.psd1 FunctionsToExport against actual Public/*.ps1 function names
- Fix any mismatches

**M2: Diagnostic info lost to Out-Null**
- Replace `Out-Null` with `Write-Verbose` in key operational paths:
  - Ensure-VMRunning.ps1 VM start
  - New-LabNAT.ps1 switch/NAT removal
  - Start-LabVMs.ps1 / Stop-LabVMs.ps1 job timeout states

**M3 (deferred): Monolithic OpenCodeLab-App.ps1**
- Too large for this batch — needs dedicated refactoring plan
- Extract inline functions into Private/ helpers in a future session

## Implementation Order

1. S1-S4 (security) — highest priority
2. R1-R4 (reliability) — prevent runtime failures
3. M1-M2 (maintainability) — improve diagnostics
4. Docker toolchain — from the approved design doc

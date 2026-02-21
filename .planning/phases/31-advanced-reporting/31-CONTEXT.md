# Phase 31: Advanced Reporting - Planning Summary

**Status:** PLANNED
**Date:** 2026-02-21
**Requirements:** RPT-01, RPT-02, RPT-03, RPT-04

## Overview

Phase 31 implements advanced reporting capabilities for AutomatedLab, including compliance reports, resource utilization reports, scheduled report generation, and comprehensive audit trail functionality. This phase builds upon the analytics infrastructure from Phase 30 and the STIG compliance system from Phase 27.

## Requirements Delivered

| Requirement | Plan | Description |
|-------------|------|-------------|
| RPT-01 | 31-01 | Compliance reports with STIG status, pass/fail summary |
| RPT-02 | 31-02 | Resource utilization reports with disk, memory, CPU trends |
| RPT-03 | 31-03 | Scheduled report generation (daily/weekly) |
| RPT-04 | 31-04 | Audit trail with timestamp, lab name, summary statistics |

## Plans

### Plan 31-01: Compliance Reports (RPT-01)
**Wave:** 1
**Depends on:** None

Creates compliance report generation functionality:
- Reports configuration block in Lab-Config.ps1
- Get-LabReportsConfig helper function
- Format-LabComplianceReport core formatting (Console, HTML, CSV, JSON)
- Get-LabComplianceReport public API
- Unit tests for report generation

**Key Features:**
- Pass/fail summary statistics
- Compliance rate calculation with threshold warnings
- Multiple output formats for different use cases
- Per-VM status details with exception tracking

### Plan 31-02: Resource Utilization Reports (RPT-02)
**Wave:** 2
**Depends on:** 31-01

Creates resource utilization report generation:
- Get-LabResourceTrendCore aggregation function
- Format-LabResourceReport formatting with bottleneck detection
- Get-LabResourceReport public API
- Unit tests for trend calculation

**Key Features:**
- Time-based trend aggregation (Hour, Day, Week)
- Bottleneck identification with configurable thresholds
- Average and peak resource metrics
- Historical trend analysis integration

### Plan 31-03: Scheduled Report Generation (RPT-03)
**Wave:** 3
**Depends on:** 31-01, 31-02

Creates automated scheduled report generation:
- ReportSchedule configuration block
- Schedule-LabReport public API (daily/weekly schedules)
- Get-LabReportSchedule listing API
- Remove-LabReportSchedule removal API
- Invoke-ScheduledReport core script
- Windows Scheduled Tasks integration

**Key Features:**
- Survives PowerShell session termination
- Daily and weekly frequency support
- Configurable run time and days
- Scheduled vs manual report tracking

### Plan 31-04: Audit Trail and Report Metadata (RPT-04)
**Wave:** 4
**Depends on:** 31-01, 31-02, 31-03

Creates comprehensive audit trail functionality:
- Write-LabReportMetadata tracking function
- Integration into Format-LabComplianceReport
- Integration into Format-LabResourceReport
- Integration into Invoke-ScheduledReport
- Get-LabReportHistory query API
- Unit tests for audit trail

**Key Features:**
- All reports tracked in analytics log
- Timestamp, lab name, summary statistics captured
- Queryable history with filtering
- Scheduled vs manual report distinction
- Compliance audit support

## Configuration

### Lab-Config.ps1 Additions

```powershell
Reports = @{
    ComplianceReportPath       = '.planning/reports/compliance'
    IncludeDetailedResults     = $false
    ComplianceThresholdPercent = 80
    ReportFormats              = @('Console', 'Html')
}

ReportSchedule = @{
    Enabled         = $true
    TaskPrefix      = 'AutomatedLabReport'
    OutputBasePath  = '.planning/reports/scheduled'
}
```

## Dependencies

### Internal Dependencies
- **Phase 27 (PowerSTIG DSC Baselines):** STIG compliance cache data source
- **Phase 29 (Dashboard Enrichment):** Get-LabVMMetrics for resource data
- **Phase 30 (Lab Analytics):** Analytics event infrastructure for audit trail

### External Dependencies
- Windows Scheduled Tasks (for scheduled reports)
- PowerSTIG module (for compliance data)
- Hyper-V module (for VM metrics)

## Design Patterns

1. **Config Helper Pattern:** Get-LabReportsConfig, Get-LabReportScheduleConfig with ContainsKey guards
2. **Public/Core Split:** Public APIs delegate to private core formatting functions
3. **Multi-Format Output:** Console, HTML, CSV, JSON support across all report types
4. **Scheduled Task Pattern:** Reuses Phase 26 Windows Scheduled Task patterns
5. **Analytics Integration:** Audit trail via Phase 30 analytics infrastructure

## Success Criteria

1. [ ] Compliance reports generate with STIG status and pass/fail summary
2. [ ] Resource reports show disk, memory, CPU trends over time
3. [ ] Scheduled tasks create reports on daily/weekly schedules
4. [ ] All reports include timestamp, lab name, and summary statistics
5. [ ] Report generation is tracked in analytics log
6. [ ] Operators can query report history by type, format, date range
7. [ ] Unit tests cover all report generation and tracking functionality

## File Creation Summary

### Plan 31-01
- `Private/Get-LabReportsConfig.ps1` (~45 lines)
- `Private/Format-LabComplianceReport.ps1` (~250 lines)
- `Public/Get-LabComplianceReport.ps1` (~110 lines)
- `Tests/LabComplianceReport.Tests.ps1` (~130 lines)
- Modified: `Lab-Config.ps1` (Reports block)
- Modified: `SimpleLab.psm1`, `SimpleLab.psd1` (exports)

### Plan 31-02
- `Private/Get-LabResourceTrendCore.ps1` (~130 lines)
- `Private/Format-LabResourceReport.ps1` (~270 lines)
- `Public/Get-LabResourceReport.ps1` (~120 lines)
- `Tests/LabResourceReport.Tests.ps1` (~140 lines)
- Modified: `SimpleLab.psm1`, `SimpleLab.psd1` (exports)

### Plan 31-03
- `Private/Get-LabReportScheduleConfig.ps1` (~45 lines)
- `Private/Invoke-ScheduledReport.ps1` (~90 lines)
- `Public/Schedule-LabReport.ps1` (~140 lines)
- `Public/Get-LabReportSchedule.ps1` (~75 lines)
- `Public/Remove-LabReportSchedule.ps1` (~65 lines)
- `Tests/LabReportSchedule.Tests.ps1` (~160 lines)
- Modified: `Lab-Config.ps1` (ReportSchedule block)
- Modified: `SimpleLab.psm1`, `SimpleLab.psd1` (exports)

### Plan 31-04
- `Private/Write-LabReportMetadata.ps1` (~70 lines)
- `Public/Get-LabReportHistory.ps1` (~105 lines)
- `Tests/LabReportHistory.Tests.ps1` (~130 lines)
- Modified: `Private/Format-LabComplianceReport.ps1` (metadata tracking)
- Modified: `Private/Format-LabResourceReport.ps1` (metadata tracking)
- Modified: `Private/Invoke-ScheduledReport.ps1` (scheduled tracking)
- Modified: `SimpleLab.psm1`, `SimpleLab.psd1` (exports)

## Total Estimated Additions

- **New Functions:** 12 public, 4 private
- **Test Files:** 4 (~560 test lines)
- **Lines of Code:** ~2,830 lines
- **Configuration Blocks:** 2 (Reports, ReportSchedule)

## Next Steps

1. Execute Plan 31-01 (Compliance Reports)
2. Execute Plan 31-02 (Resource Reports)
3. Execute Plan 31-03 (Scheduled Reports)
4. Execute Plan 31-04 (Audit Trail)
5. Create Phase 31 completion summary
6. Update ROADMAP.md with Phase 31 status
7. Proceed to Phase 32 (Operational Workflows)

---
*Phase planning completed: 2026-02-21*

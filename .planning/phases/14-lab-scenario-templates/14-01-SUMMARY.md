---
phase: 14-lab-scenario-templates
plan: 01
subsystem: infra
tags: [scenario-templates, json, powershell, vm-definitions, resource-estimation]

# Dependency graph
requires: []
provides:
  - "Three scenario template JSON files (SecurityLab, MultiTierApp, MinimalAD)"
  - "Get-LabScenarioTemplate resolver function for scenario-to-VM-definition lookup"
  - "Get-LabScenarioResourceEstimate for RAM/disk/CPU total estimation"
  - "48 Pester tests covering templates, resolver, and estimator"
affects: [14-02-cli-integration]

# Tech tracking
tech-stack:
  added: []
  patterns: [scenario-template-json, role-based-disk-estimation]

key-files:
  created:
    - ".planning/templates/SecurityLab.json"
    - ".planning/templates/MultiTierApp.json"
    - ".planning/templates/MinimalAD.json"
    - "Private/Get-LabScenarioTemplate.ps1"
    - "Private/Get-LabScenarioResourceEstimate.ps1"
    - "Tests/ScenarioTemplates.Tests.ps1"
  modified: []

key-decisions:
  - "Role-based disk estimation lookup: DC=80GB, SQL=100GB, IIS=60GB, Client=60GB, Ubuntu=40GB, default=60GB"
  - "VM definition PSCustomObject shape matches Get-ActiveTemplateConfig for Deploy.ps1 compatibility"

patterns-established:
  - "Scenario template JSON: name/description/vms array with name/role/ip/memoryGB/processors per VM"
  - "Scenario resolver: name-to-template lookup with available-scenarios error message on invalid input"

requirements-completed: [TMPL-01, TMPL-02, TMPL-03, TMPL-05]

# Metrics
duration: 2min
completed: 2026-02-19
---

# Phase 14 Plan 01: Scenario Templates Summary

**Three scenario template JSON files with resolver and resource estimator functions, 48 Pester tests passing**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-20T05:08:07Z
- **Completed:** 2026-02-20T05:10:26Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Created SecurityLab (DC + Client + Ubuntu, 10GB/8CPU), MultiTierApp (DC + SQL + IIS + Client, 20GB/12CPU), and MinimalAD (single DC, 2GB/2CPU) scenario templates
- Built Get-LabScenarioTemplate resolver that maps scenario names to VM definition arrays compatible with Deploy.ps1
- Built Get-LabScenarioResourceEstimate with role-based disk estimation for pre-deployment resource planning
- Comprehensive Pester test suite with 48 tests covering JSON structure, resolver logic, resource calculations, and error handling

## Task Commits

Each task was committed atomically:

1. **Task 1: Create scenario template JSON files and resolver function** - `36c3745` (feat)
2. **Task 2: Create resource estimator function and Pester test suite** - `a3a9239` (feat)

## Files Created/Modified
- `.planning/templates/SecurityLab.json` - Security testing lab: DC, Windows client, Ubuntu attack VM
- `.planning/templates/MultiTierApp.json` - Multi-tier application lab: DC, SQL, IIS, client
- `.planning/templates/MinimalAD.json` - Minimal AD lab: single DC with minimum resources
- `Private/Get-LabScenarioTemplate.ps1` - Resolves scenario name to VM definition array
- `Private/Get-LabScenarioResourceEstimate.ps1` - Estimates total RAM, disk, CPU for a scenario
- `Tests/ScenarioTemplates.Tests.ps1` - 48 Pester tests for templates, resolver, and estimator

## Decisions Made
- Role-based disk estimation lookup: DC=80GB, SQL=100GB, IIS=60GB, Client=60GB, Ubuntu=40GB, default=60GB
- VM definition PSCustomObject shape matches Get-ActiveTemplateConfig for Deploy.ps1 compatibility

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Scenario template data layer and lookup logic complete
- Ready for Plan 02: CLI integration to wire scenarios into the deploy flow
- Get-LabScenarioTemplate and Get-LabScenarioResourceEstimate need to be added to $OrchestrationHelperPaths in OpenCodeLab-App.ps1 when wired into the app

## Self-Check: PASSED

All 6 created files verified on disk. Both task commits (36c3745, a3a9239) verified in git log.

---
*Phase: 14-lab-scenario-templates*
*Completed: 2026-02-19*

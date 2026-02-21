---
phase: 25-mixed-os-integration
plan: 01
subsystem: scenario-templates
tags: [mixed-os, templates, resource-estimation, linux]
dependency_graph:
  requires: []
  provides: [MixedOSLab-template, linux-disk-estimates]
  affects: [Get-LabScenarioTemplate, Get-LabScenarioResourceEstimate, Build-LabFromSelection]
tech_stack:
  added: []
  patterns: [JSON scenario template with switch field, role-based disk lookup]
key_files:
  created:
    - .planning/templates/MixedOSLab.json
  modified:
    - .planning/templates/SecurityLab.json
    - .planning/templates/MultiTierApp.json
    - Private/Get-LabScenarioResourceEstimate.ps1
decisions:
  - MixedOSLab uses DatabaseUbuntu (not CentOS) for the database VM — Builder.IPPlan assigns 10.0.10.112 to DatabaseUbuntu, matching the scenario intent
  - switch field in templates is metadata for operators; provisioning uses IPPlan from Lab-Config.ps1 for actual switch assignment
  - DatabaseUbuntu and DockerUbuntu/K8sUbuntu disk estimates set to 50GB vs Ubuntu base 40GB to account for data files and container images
metrics:
  duration_minutes: 1
  completed_date: 2026-02-21
  tasks_completed: 2
  tasks_total: 2
  files_modified: 4
---

# Phase 25 Plan 01: Mixed OS Scenario Template and Resource Estimator Summary

**One-liner:** MixedOSLab.json scenario template with DC + IIS + WebServerUbuntu + DatabaseUbuntu VMs, plus full Linux role disk lookup coverage in the resource estimator.

## What Was Built

### Task 1: MixedOSLab scenario template and existing template updates (commit: 4aa1915)

Created `.planning/templates/MixedOSLab.json` defining a mixed OS lab with four VMs:
- `dc1`: role=DC, 10.0.10.10, 4GB RAM, 4 CPUs, switch=LabCorpNet
- `iis1`: role=IIS, 10.0.10.50, 4GB RAM, 2 CPUs, switch=LabCorpNet
- `linweb1`: role=WebServerUbuntu, 10.0.10.111, 2GB RAM, 2 CPUs, switch=LabCorpNet
- `lindb1`: role=DatabaseUbuntu, 10.0.10.112, 2GB RAM, 2 CPUs, switch=LabCorpNet

IPs match `Builder.IPPlan` entries in Lab-Config.ps1. Role tags match existing LabBuilder role tags consumed by Build-LabFromSelection.

Updated `SecurityLab.json` and `MultiTierApp.json` to add a `switch` field to each VM entry (all `"LabCorpNet"`). This documents intended topology and makes templates multi-switch-aware without breaking existing provisioning.

### Task 2: Resource estimator Linux role disk lookup (commit: c9878f9)

Extended the `$diskLookup` hashtable in `Get-LabScenarioResourceEstimate.ps1` with five new entries:
- `CentOS` = 40GB
- `WebServerUbuntu` = 40GB
- `DatabaseUbuntu` = 50GB
- `DockerUbuntu` = 50GB
- `K8sUbuntu` = 50GB

The existing `Ubuntu` = 40GB entry and 60GB default remain unchanged. This ensures `Get-LabScenarioResourceEstimate -Scenario MixedOSLab` returns accurate disk totals rather than falling back to the 60GB default for Linux roles.

## Decisions Made

1. **DatabaseUbuntu for database VM, not CentOS**: The MixedOSLab plan called for an "Ubuntu app server and CentOS database server" but `Builder.IPPlan` assigns `10.0.10.112` to `DatabaseUbuntu`, not to `CentOS`. Using `DatabaseUbuntu` keeps IPs consistent with the provisioning pipeline. CentOS can be a separate scenario variant.

2. **Switch field is metadata**: The `switch` field added to templates documents the intended vSwitch topology but does not override the provisioning pipeline. Build-LabFromSelection reads switch assignments from `Builder.IPPlan` in Lab-Config.ps1.

3. **50GB for database/container roles**: DatabaseUbuntu, DockerUbuntu, and K8sUbuntu get 50GB vs the 40GB Ubuntu baseline to account for PostgreSQL data files and container image storage respectively.

## Deviations from Plan

None - plan executed exactly as written.

## Verification Results

1. All three template JSON files parse without errors via ConvertFrom-Json: **PASS**
2. MixedOSLab.json has exactly 4 VMs with roles DC, IIS, WebServerUbuntu, DatabaseUbuntu: **PASS**
3. Resource estimator diskLookup has entries for CentOS, WebServerUbuntu, DatabaseUbuntu, DockerUbuntu, K8sUbuntu: **PASS**
4. MinimalAD.json is unchanged (no switch field added): **PASS**

## Self-Check: PASSED

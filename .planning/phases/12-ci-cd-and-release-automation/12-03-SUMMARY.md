---
phase: 12-ci-cd-and-release-automation
plan: 03
subsystem: infra
tags: [github-actions, release, powershell-gallery, versioning]

requires:
  - phase: 12-ci-cd-and-release-automation
    provides: PR test workflow and test runner CI compatibility (plan 01)
provides:
  - Tag-triggered release workflow with version validation
  - GitHub Release creation with auto-generated changelog
  - PowerShell Gallery publish with WhatIf dry-run gate
  - Module manifest Gallery metadata (ProjectUri, LicenseUri, ReleaseNotes)
affects: [13-test-coverage-expansion]

tech-stack:
  added: [softprops/action-gh-release@v2]
  patterns: [tag-based release trigger, manual workflow_dispatch for publish]

key-files:
  created: [.github/workflows/release.yml]
  modified: [SimpleLab.psd1]

key-decisions:
  - "Version source of truth is SimpleLab.psd1 ModuleVersion, must match tag"
  - "Gallery publish requires manual workflow_dispatch, not automatic on tag"
  - "WhatIf dry-run step executes before actual publish"
  - "FunctionsToExport mismatch is a warning, not a blocker"

patterns-established:
  - "Tag-based release: push v* tag triggers validation + release pipeline"
  - "Two-step publish: dry-run then actual, gated by workflow_dispatch input"

requirements-completed: [CICD-03, CICD-04]

duration: 4min
completed: 2026-02-19
---

# Plan 12-03: Release and Publish Workflow Summary

**Tag-triggered release pipeline with version validation, full test gate, GitHub Release, and controlled Gallery publish**

## Performance

- **Duration:** 4 min
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Release workflow triggers on v* tag push with full validation chain: version match, test suite, module load, export count
- GitHub Release auto-created with changelog generated from commit log
- Gallery publish gated behind manual workflow_dispatch with WhatIf dry-run safety
- Module manifest updated with ProjectUri, LicenseUri, and ReleaseNotes for Gallery readiness

## Task Commits

1. **Task 1: Create release and publish workflow** - `4a6360c` (feat)
2. **Task 2: Add Gallery metadata to module manifest** - `b63d349` (feat)

## Files Created/Modified
- `.github/workflows/release.yml` - Release pipeline: version validation, test suite, module verification, GitHub Release, conditional Gallery publish
- `SimpleLab.psd1` - Added ProjectUri, LicenseUri, ReleaseNotes to PSData

## Decisions Made
- Used actual GitHub remote URL (anthonyscry/LabBuilder) for ProjectUri and LicenseUri
- FunctionsToExport mismatch emits warning (not error) since count difference may be intentional during development

## Deviations from Plan
None - plan executed exactly as written

## Issues Encountered
None

## User Setup Required
**External services require manual configuration:**
- **PSGALLERY_API_KEY**: Create a PowerShell Gallery API key at powershellgallery.com -> API Keys, then add as a repository secret at GitHub -> Repository -> Settings -> Secrets and variables -> Actions

## Next Phase Readiness
- All CI/CD workflows ready: PR tests, PR lint, release, Gallery publish
- PSGALLERY_API_KEY secret must be configured before first Gallery publish
- Phase 13 (Test Coverage) can build on the CI infrastructure established here

---
*Phase: 12-ci-cd-and-release-automation*
*Completed: 2026-02-19*

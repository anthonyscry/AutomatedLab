# Phase 12: CI/CD and Release Automation - Context

**Gathered:** 2026-02-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Add GitHub Actions workflows so Pester tests, ScriptAnalyzer linting, release versioning, and PowerShell Gallery publishing run automatically with quality gates. No new features or runtime behavior changes.

</domain>

<decisions>
## Implementation Decisions

### CI Platform & Triggers
- GitHub Actions (project already on GitHub)
- PR workflow: triggers on pull_request to main — runs Pester + ScriptAnalyzer
- Release workflow: triggers on tag push (v*) or manual workflow_dispatch
- Windows runner (windows-latest) required — Hyper-V module stubs and PowerShell 5.1 compatibility
- Fail-fast: pipeline fails on first Pester failure with actionable log output

### ScriptAnalyzer Configuration
- Use PSScriptAnalyzer with default rules as baseline
- Project-specific .PSScriptAnalyzerSettings.psd1 for rule exclusions
- Suppress PSAvoidUsingWriteHost (used intentionally for CLI output)
- Suppress PSUseShouldProcessForStateChangingFunctions where CmdletBinding already has SupportsShouldProcess
- Treat errors as pipeline failures, warnings as annotations
- Baseline exception file for known suppressions (not inline suppression attributes)

### Release & Versioning Flow
- Tag-based releases: push v1.2.0 tag triggers release pipeline
- Version source of truth: SimpleLab.psd1 ModuleVersion field
- Release pipeline: validate version matches tag, run full test suite, build module, create GitHub Release with changelog
- No automatic version bump — developer sets version in .psd1 before tagging

### Gallery Publishing
- Separate workflow step within release pipeline (not a separate workflow)
- Requires PSGALLERY_API_KEY repository secret
- Pre-publish checks: module loads without errors, FunctionsToExport matches Public/ count, version not already published
- Publish uses Publish-Module with -WhatIf dry-run step before actual publish
- Single developer: no approval gate needed, but publish step requires manual workflow_dispatch confirmation

### Claude's Discretion
- Exact workflow YAML structure and job naming
- Pester output format (NUnit XML vs console)
- Whether to cache PowerShell modules in CI
- GitHub Release body format and changelog extraction method

</decisions>

<specifics>
## Specific Ideas

- CI should work on clean GitHub-hosted runners without manual setup
- Pester failures should show the test name and error message clearly in GitHub Actions log (not just exit code 1)
- ScriptAnalyzer results should appear as GitHub PR annotations (inline comments on changed files)
- Keep workflows simple and maintainable for a single developer — avoid over-engineering

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope

</deferred>

---

*Phase: 12-ci-cd-and-release-automation*
*Context gathered: 2026-02-20*

# Docker Development Toolchain Design

**Date:** 2026-02-16
**Status:** Approved

## Goal

Add Docker-based development and testing infrastructure: clean-room test runner, pre-deploy config validator, and GitHub Actions CI pipeline — all sharing a single Dockerfile.

## Approach

**Layered Docker Toolchain** — A single Dockerfile builds a PowerShell image with Pester pre-installed. Three tools layer on top:
1. `docker compose run test` — clean-room Pester test runner
2. `docker compose run validate` — pre-deploy config/script validator
3. GitHub Actions workflow reuses the same Dockerfile for CI on push/PR

## Section 1: Docker Image & Test Runner

**Dockerfile** — Based on `mcr.microsoft.com/powershell:lts-alpine` (~180MB). Installs Pester 5.x at build time.

**docker-compose.yml** — Two services sharing the same image:
- `test` — Mounts repo read-only, runs `Invoke-Pester` with JUnit XML output to `Tests/results/`. Exit code propagates for CI.
- `validate` — Runs pre-deploy validation script for syntax, config, and naming checks.

**Local usage:**
```bash
docker compose run test           # full test suite
docker compose run validate       # pre-deploy checks
```

## Section 2: Pre-Deploy Validator

New script `Scripts/Test-LabPreDeploy.ps1` checks:

1. **Syntax validation** — `Parser::ParseFile()` on every `.ps1` file
2. **Config loading** — Dot-sources Lab-Config.ps1, verifies `$GlobalLabConfig` structure
3. **Module manifest** — `Test-ModuleManifest` on SimpleLab.psd1
4. **Naming consistency** — Deploy.ps1 VM names match `$GlobalLabConfig.Lab.CoreVMNames`
5. **Default password warning** — Flags default `AdminPassword`

Returns structured result with pass/fail per check. Exit 0 = clear, 1 = issues.

## Section 3: GitHub Actions CI Pipeline

Workflow `.github/workflows/ci.yml` triggers on push to `main` and PRs:

1. **validate** — `docker compose run validate` (~10s)
2. **test** — `docker compose run test` (~2min), depends on validate
3. **results** — Uploads JUnit XML as artifact, publishes test summary

Uses `docker compose` directly (same image locally and CI). Docker layer caching for speed.

## Section 4: File Layout

**New files:**
- `Dockerfile`
- `docker-compose.yml`
- `Scripts/Test-LabPreDeploy.ps1`
- `.github/workflows/ci.yml`

**Updated:** `.gitignore` (add `Tests/results/`, `docker-compose.override.yml`)

No changes to existing PowerShell source — purely additive infrastructure.

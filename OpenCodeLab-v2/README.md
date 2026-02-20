# OpenCodeLab v2

OpenCodeLab v2 provides a modular PowerShell baseline for local lab lifecycle operations.

## Test and quality gates

Run quality gates from the repository root:

- Unit tests: `pwsh -NoProfile -Command "Invoke-Pester -Path 'OpenCodeLab-v2/tests/unit'"`
- Integration tests: `pwsh -NoProfile -Command "Invoke-Pester -Path 'OpenCodeLab-v2/tests/integration'"`
- Smoke tests: `pwsh -NoProfile -Command "Invoke-Pester -Path 'OpenCodeLab-v2/tests/smoke'"`
- ScriptAnalyzer: `pwsh -NoProfile -Command "$issues = @(); $issues += @(Invoke-ScriptAnalyzer -Path 'OpenCodeLab-v2/src' -Recurse -Severity Error,Warning); $issues += @(Invoke-ScriptAnalyzer -Path 'OpenCodeLab-v2/scripts' -Recurse -Severity Error,Warning); if ($issues.Count -gt 0) { $issues | Format-Table -AutoSize; exit 1 }"`

The smoke baseline currently validates the preflight action path. If Hyper-V prerequisites are not available on the host, the smoke test is skipped with a clear reason instead of failing the pipeline.

## CI workflow

`OpenCodeLab-v2/.github/workflows/ci.yml` runs unit, integration, smoke, and ScriptAnalyzer gates for OpenCodeLab v2 changes.

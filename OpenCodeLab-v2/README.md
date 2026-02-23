# OpenCodeLab v2

OpenCodeLab v2 provides a modular PowerShell baseline for local lab lifecycle operations.

## Network policy behavior

- VM definitions now support per-VM host internet policy via an `Allow host internet (NAT)` checkbox in the VM editor.
- The policy is enforced on both full deploy and incremental redeploy, including already-existing VMs.

## Test and quality gates

Run quality gates from the repository root:

- Unit tests: `pwsh -NoProfile -Command "Invoke-Pester -Path 'OpenCodeLab-v2/tests/unit'"`
- Integration tests: `pwsh -NoProfile -Command "Invoke-Pester -Path 'OpenCodeLab-v2/tests/integration'"`
- Smoke tests: `pwsh -NoProfile -Command "Invoke-Pester -Path 'OpenCodeLab-v2/tests/smoke'"`
- ScriptAnalyzer: `pwsh -NoProfile -Command '$warnings = @(); $warnings += @(Invoke-ScriptAnalyzer -Path "OpenCodeLab-v2/src" -Recurse -Severity Warning); $warnings += @(Invoke-ScriptAnalyzer -Path "OpenCodeLab-v2/scripts" -Recurse -Severity Warning); if ($warnings.Count -gt 0) { $warnings | Format-Table -AutoSize }; $errors = @(); $errors += @(Invoke-ScriptAnalyzer -Path "OpenCodeLab-v2/src" -Recurse -Severity Error); $errors += @(Invoke-ScriptAnalyzer -Path "OpenCodeLab-v2/scripts" -Recurse -Severity Error); if ($errors.Count -gt 0) { $errors | Format-Table -AutoSize; exit 1 }'`

The smoke baseline currently validates the preflight action path. If Hyper-V prerequisites are not available on the host, the smoke test is skipped with a clear reason instead of failing the pipeline.

## CI workflow

`.github/workflows/opencodelab-v2-ci.yml` runs unit, integration, smoke, and ScriptAnalyzer gates for OpenCodeLab v2 changes.

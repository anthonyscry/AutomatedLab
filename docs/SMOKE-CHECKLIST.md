# Smoke Checklist

Use this checklist for release validation after dispatch and coordinator changes.

## Dispatch rollout checks

- [ ] Run with `-DispatchMode off` and verify no host dispatches are executed.
- [ ] Run with `-DispatchMode canary` on multiple target hosts and verify exactly one host is dispatched while all others are reported as `not_dispatched`.
- [ ] Run with `-DispatchMode enforced` on multiple target hosts and verify all eligible hosts are dispatched.

## Execution outcome checks

- [ ] Verify artifacts include `DispatchMode` and `ExecutionOutcome` values for each run.
- [ ] Verify canary artifacts record one dispatched host and remaining host outcomes as `not_dispatched`.
- [ ] Verify policy-blocked scenarios continue to report `ExecutionOutcome` and fail closed.

## Dispatch gate verification commands

- [ ] Run `Invoke-Pester -Path .\Tests\DispatchMode.Tests.ps1`.
- [ ] Run `Invoke-Pester -Path .\Tests\CoordinatorDispatch.Tests.ps1`.
- [ ] Run `Invoke-Pester -Path .\Tests\OpenCodeLabDispatchContract.Tests.ps1`.
- [ ] Run `.\Tests\Run.Tests.ps1` for full-suite confirmation.

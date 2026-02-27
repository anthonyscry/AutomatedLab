## Purpose

Resolve a deployment outcome where member/client VMs are marked internet-enabled but still show "No Internet" after successful deployment.

## Scope

- Update `OpenCodeLab-v2/Deploy-Lab.ps1` internet-policy target derivation to detect domain controller VMs.
- In internal NAT mode, auto-enable host internet policy on DC VMs when any non-DC VM is internet-enabled.
- Emit an explicit warning when this auto-enable behavior is applied.
- Add regression coverage in `OpenCodeLab-v2/Services/DeployLabScript.Tests.ps1`.

## Acceptance Criteria

1. Deployment script includes DC detection metadata in internet-policy targets.
2. Internal NAT mode auto-enables DC internet policy when internet-enabled member/client VMs exist.
3. Script logs a warning containing "Auto-enabling host internet on domain controller" when override is applied.
4. Regression tests pass for the new behavior and existing internet-policy checks.

## Risks

- Security posture change: DC egress can be enabled automatically in NAT mode.
- Behavior differs from explicit user VM checkbox intent for DC isolation.
- Mitigation: warning log is explicit; external-switch mode behavior is unchanged.

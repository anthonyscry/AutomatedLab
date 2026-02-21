function Invoke-LabSTIGBaseline {
    <#
    .SYNOPSIS
        Applies DISA STIG DSC baselines to lab VMs.

    .DESCRIPTION
        Re-applies role-appropriate STIG baselines to one or more lab VMs.
        Installs PowerSTIG if needed, compiles MOF with exception overrides,
        applies via DSC push mode, and updates the compliance cache.

        This is a thin public wrapper that delegates to the private
        Invoke-LabSTIGBaselineCore implementation (auto-loaded by Lab-Common.ps1).

    .PARAMETER VMName
        Specific VM name(s) to target. If omitted, targets all lab VMs
        discovered from GlobalLabConfig.Lab.CoreVMNames.

    .EXAMPLE
        Invoke-LabSTIGBaseline -VMName 'dc1'
        Re-applies STIG baseline to the VM named 'dc1'.

    .EXAMPLE
        Invoke-LabSTIGBaseline
        Re-applies STIG baselines to all lab VMs.

    .EXAMPLE
        $result = Invoke-LabSTIGBaseline -VMName 'dc1', 'svr1'
        $result | Select-Object VMsProcessed, VMsSucceeded, VMsFailed

    .OUTPUTS
        [PSCustomObject] Audit result with VMsProcessed, VMsSucceeded, VMsFailed,
        Repairs, RemainingIssues, DurationSeconds.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]]$VMName
    )

    # Delegate to private implementation (auto-loaded by Lab-Common.ps1)
    $params = @{}
    if ($VMName -and $VMName.Count -gt 0) { $params['VMName'] = $VMName }
    Invoke-LabSTIGBaselineCore @params
}

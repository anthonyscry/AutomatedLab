function Test-LabBulkOperation {
    <#
    .SYNOPSIS
        Validates pre-flight conditions for bulk VM operations.

    .DESCRIPTION
        Test-LabBulkOperation performs validation checks before executing
        bulk operations, ensuring VMs exist, Hyper-V is available, and
        sufficient resources exist. Returns structured results with
        Pass/Warn/Fail statuses and remediation guidance for any issues.

    .PARAMETER VMName
        One or more VM names to validate.

    .PARAMETER Operation
        Operation type to validate: 'Start', 'Stop', 'Suspend', 'Restart', 'Checkpoint'.

    .PARAMETER CheckResourceAvailability
        Include resource availability checks for Start operations (adds RAM/CPU validation).

    .PARAMETER Remediation
        Display remediation guidance for failed checks.

    .EXAMPLE
        Test-LabBulkOperation -VMName @('dc1', 'svr1') -Operation Start
        Validates prerequisites for starting VMs.

    .EXAMPLE
        Test-LabBulkOperation -VMName (Get-LabVM) -Operation Start -CheckResourceAvailability
        Validates all lab VMs including resource checks.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$VMName,

        [Parameter(Mandatory)]
        [ValidateSet('Start', 'Stop', 'Suspend', 'Restart', 'Checkpoint')]
        [string]$Operation,

        [switch]$CheckResourceAvailability,

        [switch]$Remediation
    )

    begin {
        $allVMs = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($vm in $VMName) {
            $allVMs.Add($vm)
        }
    }

    end {
        if ($allVMs.Count -eq 0) {
            Write-Warning 'No VMs specified for validation'
            return
        }

        $params = @{
            VMName = @($allVMs)
            Operation = $Operation
        }

        if ($CheckResourceAvailability) {
            $params.CheckResourceAvailability = $true
        }

        $result = Test-LabBulkOperationCore @params

        if ($Remediation -and $result.FailedChecks.Count -gt 0) {
            Write-Host "`nRemediation Guidance:" -ForegroundColor Cyan
            foreach ($check in $result.FailedChecks) {
                Write-Host "  [$($check.Name)]" -ForegroundColor Yellow
                Write-Host "    Problem: $($check.Message)" -ForegroundColor Gray
                if ($check.Remediation) {
                    Write-Host "    Fix: $($check.Remediation)" -ForegroundColor Green
                }
            }
        }

        Write-Verbose "Test-LabBulkOperation: OverallStatus = $($result.OverallStatus)"

        return $result
    }
}

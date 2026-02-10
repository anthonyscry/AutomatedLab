function Test-LabVM {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VMName
    )

    # Initialize result object
    $result = [PSCustomObject]@{
        VMName = $VMName
        Exists = $false
        Status = "NotFound"
        Message = ""
        State = $null
    }

    try {
        # Check if Hyper-V module is available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            $result.Status = "Error"
            $result.Message = "Hyper-V module is not available"
            return $result
        }

        # Try to get the VM
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue

        if ($null -ne $vm) {
            $result.Exists = $true
            $result.State = $vm.State
            $result.Status = "OK"
            $result.Message = "VM '$VMName' exists (State: $($vm.State))"
        }
        else {
            $result.Exists = $false
            $result.State = $null
            $result.Status = "NotFound"
            $result.Message = "VM '$VMName' not found"
        }
    }
    catch {
        $result.Status = "Error"
        $result.Message = "Failed to check VM status: $($_.Exception.Message)"
    }

    return $result
}

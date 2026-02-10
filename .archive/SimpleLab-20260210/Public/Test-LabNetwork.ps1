function Test-LabNetwork {
    <#
    .SYNOPSIS
        Tests if the SimpleLab virtual switch exists.

    .DESCRIPTION
        Checks if the SimpleLab Hyper-V virtual switch exists and returns
        its type (Internal, External, or Private).

    .OUTPUTS
        PSCustomObject with SwitchName, Exists (bool), SwitchType, Status, and Message.

    .EXAMPLE
        $network = Test-LabNetwork
        if ($network.Exists) { "Network OK" }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # Initialize result object
    $result = [PSCustomObject]@{
        SwitchName = "SimpleLab"
        Exists = $false
        SwitchType = $null
        Status = "NotFound"
        Message = ""
    }

    try {
        # Check if Hyper-V module is available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            $result.Message = "Hyper-V module is not available"
            $result.Status = "Error"
            return $result
        }

        # Try to get the SimpleLab vSwitch
        $switch = Get-VMSwitch -Name "SimpleLab" -ErrorAction SilentlyContinue

        if ($null -ne $switch) {
            $result.Exists = $true
            $result.SwitchType = $switch.SwitchType
            $result.Status = "OK"
            $result.Message = "SimpleLab vSwitch exists (Type: $($switch.SwitchType))"
        }
        else {
            $result.Exists = $false
            $result.SwitchType = $null
            $result.Status = "NotFound"
            $result.Message = "SimpleLab vSwitch not found"
        }
    }
    catch {
        $result.Status = "Error"
        $result.Message = "Failed to check vSwitch status: $($_.Exception.Message)"
    }

    return $result
}

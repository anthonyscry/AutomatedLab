function Test-LabNetwork {
    <#
    .SYNOPSIS
        Tests if the lab virtual switch exists.

    .DESCRIPTION
        Checks if the lab Hyper-V virtual switch exists and returns
        its type (Internal, External, or Private). Uses the switch name
        from $GlobalLabConfig.Network.SwitchName if available.

    .PARAMETER SwitchName
        Name of the virtual switch to test. Defaults to the switch name
        from $GlobalLabConfig.Network.SwitchName, or "SimpleLab" if config
        is not available.

    .OUTPUTS
        PSCustomObject with SwitchName, Exists (bool), SwitchType, Status, and Message.

    .EXAMPLE
        $network = Test-LabNetwork
        if ($network.Exists) { "Network OK" }

    .EXAMPLE
        $network = Test-LabNetwork -SwitchName "MyLabSwitch"
        if ($network.Exists) { "Network OK" }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$SwitchName = $(
            if ((Test-Path variable:GlobalLabConfig) -and $GlobalLabConfig.Network.SwitchName) {
                $GlobalLabConfig.Network.SwitchName
            } else {
                "SimpleLab"
            }
        )
    )

    # Initialize result object
    $result = [PSCustomObject]@{
        SwitchName = $SwitchName
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

        # Try to get the vSwitch
        $switch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue

        if ($null -ne $switch) {
            $result.Exists = $true
            $result.SwitchType = $switch.SwitchType
            $result.Status = "OK"
            $result.Message = "$SwitchName vSwitch exists (Type: $($switch.SwitchType))"
        }
        else {
            $result.Exists = $false
            $result.SwitchType = $null
            $result.Status = "NotFound"
            $result.Message = "$SwitchName vSwitch not found"
        }
    }
    catch {
        $result.Status = "Error"
        $result.Message = "Failed to check vSwitch status: $($_.Exception.Message)"
    }

    return $result
}

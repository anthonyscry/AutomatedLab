function New-LabSwitch {
    <#
    .SYNOPSIS
        Creates a new Hyper-V virtual switch for the lab.

    .DESCRIPTION
        Creates an internal Hyper-V virtual switch with the specified name.
        If the switch already exists and -Force is not specified, returns
        successfully without making changes.

    .PARAMETER SwitchName
        Name for the virtual switch (default: "SimpleLab").

    .PARAMETER Force
        If specified and switch exists, removes and recreates the switch.

    .OUTPUTS
        PSCustomObject with SwitchName, Created (bool), Status, Message, and SwitchType.

    .EXAMPLE
        New-LabSwitch
        Creates the default "SimpleLab" internal vSwitch if it does not already exist.

    .EXAMPLE
        New-LabSwitch -SwitchName "MyLab" -Force
        Removes and recreates the "MyLab" vSwitch, ensuring a clean internal switch.

    .EXAMPLE
        (New-LabSwitch).Status
        Creates the switch and checks the resulting Status field ("OK" or "Failed").
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [string]$SwitchName = "SimpleLab",

        [Parameter()]
        [switch]$Force
    )

    # Initialize result object
    $result = [PSCustomObject]@{
        SwitchName = $SwitchName
        Created = $false
        Status = "Failed"
        Message = ""
        SwitchType = "Internal"
    }

    try {
        # Step 1: Check if Hyper-V module is available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            $result.Status = "Failed"
            $result.Message = "Hyper-V module is not available"
            return $result
        }

        # Step 2: Check if switch already exists
        $networkTest = Test-LabNetwork
        $switchExists = $networkTest.Exists

        # Step 3: Skip creation if exists and not forcing
        if ($switchExists -and -not $Force) {
            $result.Status = "OK"
            $result.Created = $false
            $result.Message = "$SwitchName vSwitch already exists"
            $result.SwitchType = $networkTest.SwitchType
            return $result
        }

        # Step 4: Remove existing switch if Force is specified
        if ($switchExists -and $Force) {
            try {
                Remove-VMSwitch -Name $SwitchName -Force -ErrorAction Stop
                $result.Message = "Removed existing $SwitchName vSwitch for recreation"
            }
            catch {
                $result.Status = "Failed"
                $result.Message = "Failed to remove existing vSwitch: $($_.Exception.Message)"
                return $result
            }
        }

        # Step 5: Create the new Internal vSwitch
        try {
            $newSwitch = New-VMSwitch -Name $SwitchName -SwitchType Internal -ErrorAction Stop
            $result.Status = "OK"
            $result.Created = $true
            $result.Message = "$SwitchName vSwitch created"
            $result.SwitchType = "Internal"
        }
        catch {
            $result.Status = "Failed"
            $result.Message = "Failed to create vSwitch: $($_.Exception.Message)"
            return $result
        }
    }
    catch {
        $result.Status = "Failed"
        $result.Message = "Unexpected error: $($_.Exception.Message)"
    }

    return $result
}

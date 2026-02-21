function New-LabSwitch {
    <#
    .SYNOPSIS
        Creates a new Hyper-V virtual switch for the lab.

    .DESCRIPTION
        Creates an internal Hyper-V virtual switch with the specified name.
        If the switch already exists and -Force is not specified, returns
        successfully without making changes.

        Supports multi-switch creation via -Switches or -All parameters.

    .PARAMETER SwitchName
        Name for the virtual switch (default: "SimpleLab"). Used for single-switch mode.

    .PARAMETER Switches
        Array of switch definitions (hashtable or PSCustomObject) with Name property.
        When provided, creates one vSwitch per entry. Ignores -SwitchName.

    .PARAMETER All
        When specified, reads the Switches array from Get-LabNetworkConfig and
        creates all configured switches.

    .PARAMETER Force
        If specified and switch exists, removes and recreates the switch.

    .OUTPUTS
        PSCustomObject (single-switch mode) or PSCustomObject[] (multi-switch mode)
        with SwitchName, Created (bool), Status, Message, and SwitchType.

    .EXAMPLE
        New-LabSwitch
        Creates the default "SimpleLab" internal vSwitch if it does not already exist.

    .EXAMPLE
        New-LabSwitch -SwitchName "MyLab" -Force
        Removes and recreates the "MyLab" vSwitch, ensuring a clean internal switch.

    .EXAMPLE
        New-LabSwitch -All
        Creates all switches defined in Get-LabNetworkConfig.

    .EXAMPLE
        $switches = @([PSCustomObject]@{ Name = 'LabCorpNet' }, [PSCustomObject]@{ Name = 'LabDMZ' })
        New-LabSwitch -Switches $switches
        Creates two named switches.

    .EXAMPLE
        (New-LabSwitch).Status
        Creates the switch and checks the resulting Status field ("OK" or "Failed").
    #>
    [CmdletBinding(DefaultParameterSetName = 'Single')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Single')]
        [string]$SwitchName = "SimpleLab",

        [Parameter(ParameterSetName = 'Multi')]
        [object[]]$Switches,

        [Parameter(ParameterSetName = 'All')]
        [switch]$All,

        [Parameter()]
        [switch]$Force
    )

    # -- Helper: create a single vSwitch by name ------------------------------
    function New-SingleLabVSwitch {
        param(
            [string]$Name,
            [switch]$Force
        )

        $result = [PSCustomObject]@{
            SwitchName = $Name
            Created    = $false
            Status     = "Failed"
            Message    = ""
            SwitchType = "Internal"
        }

        try {
            # Check if Hyper-V module is available
            $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
            if ($null -eq $hyperVModule) {
                $result.Status  = "Failed"
                $result.Message = "Hyper-V module is not available"
                return $result
            }

            # Check if switch already exists
            $existingSwitch = Get-VMSwitch -Name $Name -ErrorAction SilentlyContinue
            $switchExists   = $null -ne $existingSwitch

            # Skip creation if exists and not forcing
            if ($switchExists -and -not $Force) {
                $result.Status     = "OK"
                $result.Created    = $false
                $result.Message    = "$Name vSwitch already exists"
                $result.SwitchType = if ($existingSwitch) { [string]$existingSwitch.SwitchType } else { 'Internal' }
                return $result
            }

            # Remove existing switch if Force is specified
            if ($switchExists -and $Force) {
                try {
                    Remove-VMSwitch -Name $Name -Force -ErrorAction Stop
                    $result.Message = "Removed existing $Name vSwitch for recreation"
                }
                catch {
                    $result.Status  = "Failed"
                    $result.Message = "Failed to remove existing vSwitch: $($_.Exception.Message)"
                    return $result
                }
            }

            # Create the new Internal vSwitch
            try {
                $null = New-VMSwitch -Name $Name -SwitchType Internal -ErrorAction Stop
                $result.Status     = "OK"
                $result.Created    = $true
                $result.Message    = "$Name vSwitch created"
                $result.SwitchType = "Internal"
            }
            catch {
                $result.Status  = "Failed"
                $result.Message = "Failed to create vSwitch: $($_.Exception.Message)"
                return $result
            }
        }
        catch {
            $result.Status  = "Failed"
            $result.Message = "Unexpected error: $($_.Exception.Message)"
        }

        return $result
    }

    # -- Multi-switch mode: -All ----------------------------------------------
    if ($PSCmdlet.ParameterSetName -eq 'All') {
        $networkConfig = Get-LabNetworkConfig
        $switchDefs    = $networkConfig.Switches

        $results = @()
        foreach ($sw in $switchDefs) {
            $switchName = if ($sw -is [hashtable]) { $sw['Name'] } else { $sw.Name }
            $results   += New-SingleLabVSwitch -Name $switchName -Force:$Force
        }
        return $results
    }

    # -- Multi-switch mode: -Switches -----------------------------------------
    if ($PSCmdlet.ParameterSetName -eq 'Multi') {
        $results = @()
        foreach ($sw in $Switches) {
            $switchName = if ($sw -is [hashtable]) { $sw['Name'] } else { $sw.Name }
            $results   += New-SingleLabVSwitch -Name $switchName -Force:$Force
        }
        return $results
    }

    # -- Single-switch mode (original behavior) -------------------------------
    $result = [PSCustomObject]@{
        SwitchName = $SwitchName
        Created    = $false
        Status     = "Failed"
        Message    = ""
        SwitchType = "Internal"
    }

    try {
        # Step 1: Check if Hyper-V module is available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            $result.Status  = "Failed"
            $result.Message = "Hyper-V module is not available"
            return $result
        }

        # Step 2: Check if switch already exists
        $networkTest  = Test-LabNetwork
        $switchExists = $networkTest.Exists

        # Step 3: Skip creation if exists and not forcing
        if ($switchExists -and -not $Force) {
            $result.Status     = "OK"
            $result.Created    = $false
            $result.Message    = "$SwitchName vSwitch already exists"
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
                $result.Status  = "Failed"
                $result.Message = "Failed to remove existing vSwitch: $($_.Exception.Message)"
                return $result
            }
        }

        # Step 5: Create the new Internal vSwitch
        try {
            $null = New-VMSwitch -Name $SwitchName -SwitchType Internal -ErrorAction Stop
            $result.Status     = "OK"
            $result.Created    = $true
            $result.Message    = "$SwitchName vSwitch created"
            $result.SwitchType = "Internal"
        }
        catch {
            $result.Status  = "Failed"
            $result.Message = "Failed to create vSwitch: $($_.Exception.Message)"
            return $result
        }
    }
    catch {
        $result.Status  = "Failed"
        $result.Message = "Unexpected error: $($_.Exception.Message)"
    }

    return $result
}

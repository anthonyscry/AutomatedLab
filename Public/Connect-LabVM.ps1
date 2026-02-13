function Connect-LabVM {
    <#
    .SYNOPSIS
        Opens the console window for a SimpleLab virtual machine.

    .DESCRIPTION
        Opens the VMConnect window for direct console access to a lab VM.
        Useful for GUI access, troubleshooting, or when PowerShell Direct is unavailable.

    .PARAMETER VMName
        Name of the virtual machine to connect to.

    .OUTPUTS
        PSCustomObject with connection result including VMName, Action,
        OverallStatus, and Message.

    .EXAMPLE
        Connect-LabVM -VMName dc1

    .EXAMPLE
        Connect-LabVM svr1
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$VMName
    )

    # Start timing
    $startTime = Get-Date

    # Initialize result object
    $result = [PSCustomObject]@{
        VMName = $VMName
        Action = "None"
        OverallStatus = "Failed"
        Message = ""
        Duration = $null
    }

    try {
        # Step 1: Check if Hyper-V module is available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            $result.OverallStatus = "Failed"
            $result.Message = "Hyper-V module is not available"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Step 2: Check if VM exists
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        if ($null -eq $vm) {
            $result.OverallStatus = "NotFound"
            $result.Message = "VM '$VMName' does not exist"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        # Step 3: Get the local computer name for vmconnect
        $computerName = $env:COMPUTERNAME

        # Step 4: Launch vmconnect.exe
        Write-Verbose "Opening VMConnect window for '$VMName'..."

        try {
            # Start vmconnect.exe in background
            $processStartInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processStartInfo.FileName = "vmconnect.exe"
            $processStartInfo.Arguments = "`"$computerName`" `"$VMName`""
            $processStartInfo.UseShellExecute = $true
            $processStartInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal

            $process = [System.Diagnostics.Process]::Start($processStartInfo)

            if ($null -eq $process) {
                # vmconnect might have opened an existing window
                $result.OverallStatus = "OK"
                $result.Action = "Connected"
                $result.Message = "VMConnect window opened for '$VMName'"
            }
            else {
                $result.OverallStatus = "OK"
                $result.Action = "Connected"
                $result.Message = "VMConnect window opened for '$VMName' (PID: $($process.Id))"
            }
        }
        catch {
            $result.OverallStatus = "Failed"
            $result.Message = "Failed to open VMConnect: $($_.Exception.Message)"
            $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
            return $result
        }

        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
    catch {
        $result.OverallStatus = "Failed"
        $result.Message = "Unexpected error: $($_.Exception.Message)"
        $result.Duration = (New-TimeSpan -Start $startTime -End (Get-Date))
        return $result
    }
}

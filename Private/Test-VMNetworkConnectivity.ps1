function Test-VMNetworkConnectivity {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceVM,

        [Parameter(Mandatory = $true)]
        [string]$TargetIP,

        [Parameter(Mandatory = $false)]
        [int]$Count = 4
    )

    # Initialize result object
    $result = [PSCustomObject]@{
        SourceVM = $SourceVM
        TargetIP = $TargetIP
        Reachable = $false
        Status = "Failed"
        Message = ""
    }

    try {
        # Check if Hyper-V module is available
        $hyperVModule = Get-Module -ListAvailable -Name Hyper-V -ErrorAction SilentlyContinue
        if ($null -eq $hyperVModule) {
            $result.Status = "Error"
            $result.Message = "Hyper-V module is not available"
            return $result
        }

        # Check if source VM exists and is running
        $vm = Get-VM -Name $SourceVM -ErrorAction SilentlyContinue
        if ($null -eq $vm) {
            $result.Status = "VMNotFound"
            $result.Message = "VM '$SourceVM' not found"
            return $result
        }

        if ($vm.State -ne 'Running') {
            $result.Status = "VMNotFound"
            $result.Message = "VM '$SourceVM' is not running (State: $($vm.State))"
            return $result
        }

        # Use PowerShell Direct to execute Test-Connection inside the source VM
        $pingResult = Invoke-Command -VMName $SourceVM -ScriptBlock {
            param($ip, $count)

            # Run Test-Connection with -Quiet for boolean result
            $reachable = Test-Connection -ComputerName $ip -Count $count -Quiet -ErrorAction SilentlyContinue

            return $reachable
        } -ArgumentList $TargetIP, $Count -ErrorAction Stop

        if ($pingResult -eq $true) {
            $result.Reachable = $true
            $result.Status = "OK"
            $result.Message = "Reachable from $SourceVM to $TargetIP"
        }
        else {
            $result.Reachable = $false
            $result.Status = "Failed"
            $result.Message = "Unreachable from $SourceVM to $TargetIP"
        }
    }
    catch {
        $result.Status = "Error"
        $result.Message = "Failed to test connectivity: $($_.Exception.Message)"
    }

    return $result
}

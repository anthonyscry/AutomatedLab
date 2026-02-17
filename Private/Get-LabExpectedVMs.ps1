function Get-LabExpectedVMs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$LabConfig
    )

    return @(@($LabConfig.Lab.CoreVMNames))
}

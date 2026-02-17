function Add-LabRunEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][string]$Status,
        [string]$Message = '',
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$RunEvents
    )

    $RunEvents.Add([pscustomobject]@{
        Time    = (Get-Date).ToString('o')
        Step    = $Step
        Status  = $Status
        Message = $Message
    }) | Out-Null
}

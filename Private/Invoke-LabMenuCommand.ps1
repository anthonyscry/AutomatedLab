function Invoke-LabMenuCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Command,
        [switch]$NoPause,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$RunEvents
    )

    Add-LabRunEvent -Step "menu:$Name" -Status 'start' -Message 'interactive' -RunEvents $RunEvents
    try {
        & $Command
        Add-LabRunEvent -Step "menu:$Name" -Status 'ok' -Message 'completed' -RunEvents $RunEvents
    } catch {
        Add-LabRunEvent -Step "menu:$Name" -Status 'fail' -Message $_.Exception.Message -RunEvents $RunEvents
        Write-LabStatus -Status FAIL -Message "$($_.Exception.Message)"
    }

    if (-not $NoPause) {
        Suspend-LabMenuPrompt
    }
}

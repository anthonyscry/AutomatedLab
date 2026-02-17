function Invoke-LabRepoScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseName,
        [string[]]$Arguments,
        [Parameter(Mandatory)][string]$ScriptDir,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$RunEvents
    )

    $path = Resolve-LabScriptPath -BaseName $BaseName -ScriptDir $ScriptDir
    $argText = if ($Arguments -and $Arguments.Count -gt 0) { $Arguments -join ' ' } else { '' }
    Add-LabRunEvent -Step $BaseName -Status 'start' -Message $argText -RunEvents $RunEvents
    Write-Host "  Running: $([System.IO.Path]::GetFileName($path))" -ForegroundColor Gray
    try {
        if ($Arguments -and $Arguments.Count -gt 0) {
            $scriptSplat = Convert-LabArgumentArrayToSplat -ArgumentList $Arguments
            & $path @scriptSplat
        } else {
            & $path
        }
        Add-LabRunEvent -Step $BaseName -Status 'ok' -Message 'completed' -RunEvents $RunEvents
    } catch {
        Add-LabRunEvent -Step $BaseName -Status 'fail' -Message $_.Exception.Message -RunEvents $RunEvents
        throw
    }
}

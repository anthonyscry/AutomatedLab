function Suspend-LabMenuPrompt {
    [CmdletBinding()]
    param()

    Read-Host "`n  Press Enter to continue" | Out-Null
}

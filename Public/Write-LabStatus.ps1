# Write-LabStatus.ps1 -- Unified status output helper
function Write-LabStatus {
    <#
    .SYNOPSIS
    Unified status output with consistent prefixes and colors.
    .PARAMETER Status
    One of: OK, WARN, FAIL, INFO, SKIP, CACHE, NOTE
    .PARAMETER Message
    The message text.
    .PARAMETER Indent
    Number of 2-space indentation levels (default: 1).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('OK','WARN','FAIL','INFO','SKIP','CACHE','NOTE')]
        [string]$Status,
        [Parameter(Mandatory)]
        [string]$Message,
        [int]$Indent = 1
    )

    try {
        $pad = '  ' * $Indent
        $colorMap = @{
            OK    = 'Green'
            WARN  = 'Yellow'
            FAIL  = 'Red'
            INFO  = 'Gray'
            SKIP  = 'DarkGray'
            CACHE = 'DarkGray'
            NOTE  = 'Cyan'
        }

        $color = $colorMap[$Status]
        Write-Host "${pad}[$Status] $Message" -ForegroundColor $color
    }
    catch {
        Write-Warning "Write-LabStatus: failed to write status message - $_"
    }
}

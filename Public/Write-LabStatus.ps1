# Write-LabStatus.ps1 -- Unified status output helper
function Write-LabStatus {
    <#
    .SYNOPSIS
    Unified status output with consistent prefixes and colors.

    .DESCRIPTION
    Writes a formatted status line to the host using a standardised prefix and
    colour scheme.  All lab scripts use Write-LabStatus so operator output is
    visually consistent regardless of which command produced it.

    Supported status values and their colours:
      OK    - Green   (operation succeeded)
      WARN  - Yellow  (non-fatal issue)
      FAIL  - Red     (operation failed)
      INFO  - Gray    (informational)
      SKIP  - DarkGray (step intentionally skipped)
      CACHE - DarkGray (result served from cache)
      NOTE  - Cyan    (notable information)

    The -Indent parameter controls left-padding in 2-space increments so that
    nested sub-steps are visually offset from their parent.

    .PARAMETER Status
    One of: OK, WARN, FAIL, INFO, SKIP, CACHE, NOTE

    .PARAMETER Message
    The message text to display alongside the status prefix.

    .PARAMETER Indent
    Number of 2-space indentation levels (default: 1).

    .EXAMPLE
    Write-LabStatus -Status OK -Message "Domain controller is healthy"
    # Output: [OK] Domain controller is healthy  (green)

    .EXAMPLE
    Write-LabStatus -Status WARN -Message "NIC not connected" -Indent 2
    # Output:     [WARN] NIC not connected  (yellow, indented 4 spaces)

    .EXAMPLE
    Write-LabStatus -Status FAIL -Message "Checkpoint creation failed"
    # Output: [FAIL] Checkpoint creation failed  (red)

    .EXAMPLE
    Write-LabStatus -Status INFO -Message "Skipping optional component" -Indent 0
    # Output: [INFO] Skipping optional component  (gray, no indent)
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

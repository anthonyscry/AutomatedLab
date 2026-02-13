function Select-LabRoles {
    <#
    .SYNOPSIS
        Interactive console role toggler for LabBuilder.
    .DESCRIPTION
        Displays a checkbox-style menu letting the user toggle lab roles on/off,
        then returns the selected role tags for Build-LabFromSelection.
    .OUTPUTS
        Hashtable with keys: SelectedRoles ([string[]]), Cancelled ([bool])
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath
    )

    # Resolve config path
    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $PSScriptRoot 'Config\LabDefaults.psd1'
    }
    if (-not (Test-Path $ConfigPath)) {
        throw "Config file not found: $ConfigPath"
    }

    $Config = Import-PowerShellDataFile -Path $ConfigPath

    # Initialize selection state — one bool per RoleMenu entry
    $roleMenu = $Config.RoleMenu
    $count = $roleMenu.Count
    $selected = New-Object bool[] $count
    $displayMap = @()

    for ($i = 0; $i -lt $count; $i++) {
        if (-not $roleMenu[$i].Separator) {
            $displayMap += $i
        }
    }

    # Locked items (DC) start as selected and cannot be toggled
    for ($i = 0; $i -lt $count; $i++) {
        if ($roleMenu[$i].Locked) {
            $selected[$i] = $true
        }
    }

    # Main loop
    while ($true) {
        Clear-Host

        # Banner
        Write-Host ''
        Write-Host '  +==========================================+' -ForegroundColor Cyan
        Write-Host '  |        LabBuilder - Role Selection       |' -ForegroundColor Cyan
        Write-Host '  +==========================================+' -ForegroundColor Cyan
        Write-Host ''

        # Render each role line
        $displayNum = 0
        for ($i = 0; $i -lt $count; $i++) {
            $entry = $roleMenu[$i]

            # Handle separator lines
            if ($entry.Separator) {
                Write-Host ''
                Write-Host "    $($entry.Label)" -ForegroundColor DarkYellow
                continue
            }

            $displayNum++
            $num = $displayNum.ToString().PadLeft(2)

            if ($selected[$i]) {
                $marker = '[X]'
                $markerColor = 'Green'
            }
            else {
                $marker = '[ ]'
                $markerColor = 'DarkGray'
            }

            Write-Host "    " -NoNewline
            Write-Host $marker -ForegroundColor $markerColor -NoNewline
            Write-Host " $num. " -ForegroundColor Yellow -NoNewline
            Write-Host $entry.Label -ForegroundColor White -NoNewline

            if ($entry.Locked) {
                Write-Host '  (locked)' -ForegroundColor DarkYellow
            }
            else {
                Write-Host ''
            }
        }

        Write-Host ''
        Write-Host '  Commands: [number]=toggle  a=all  n=none  b=build  q=quit  ?=help' -ForegroundColor Gray
        Write-Host ''
        $userInput = Read-Host '  LabBuilder'

        if ([string]::IsNullOrWhiteSpace($userInput)) {
            continue
        }

        $cmd = $userInput.Trim().ToLower()

        # Check for numeric input
        $num = 0
        $isNumber = [int]::TryParse($cmd, [ref]$num)

        if ($isNumber) {
            $displayIndex = $num - 1
            if ($displayIndex -lt 0 -or $displayIndex -ge $displayMap.Count) {
                Write-Host "  Invalid number. Enter 1-$($displayMap.Count)." -ForegroundColor Red
                Start-Sleep -Milliseconds 800
                continue
            }

            $index = $displayMap[$displayIndex]
            if ($roleMenu[$index].Locked) {
                Write-Host '  DC is required and cannot be deselected.' -ForegroundColor Yellow
                Start-Sleep -Milliseconds 800
                continue
            }
            $selected[$index] = -not $selected[$index]
        }
        elseif ($cmd -eq 'a') {
            for ($i = 0; $i -lt $count; $i++) {
                if ($roleMenu[$i].Separator) { continue }
                $selected[$i] = $true
            }
        }
        elseif ($cmd -eq 'n') {
            for ($i = 0; $i -lt $count; $i++) {
                if ($roleMenu[$i].Separator) { continue }
                if (-not $roleMenu[$i].Locked) {
                    $selected[$i] = $false
                }
            }
        }
        elseif ($cmd -eq 'b') {
            break
        }
        elseif ($cmd -eq 'q') {
            return @{
                SelectedRoles = @()
                Cancelled     = $true
            }
        }
        elseif ($cmd -eq '?') {
            Clear-Host
            Write-Host ''
            Write-Host '  LabBuilder - Help' -ForegroundColor Cyan
            Write-Host '  =================' -ForegroundColor Cyan
            Write-Host ''
            Write-Host "  Enter a number (1-$($displayMap.Count)) to toggle a role on or off." -ForegroundColor White
            Write-Host '  Enter a command letter to perform an action:' -ForegroundColor White
            Write-Host ''
            Write-Host '    a   Enable ALL roles' -ForegroundColor Gray
            Write-Host '    n   Disable all roles (except locked DC)' -ForegroundColor Gray
            Write-Host '    b   Build the lab with current selections' -ForegroundColor Gray
            Write-Host '    q   Quit without building' -ForegroundColor Gray
            Write-Host '    ?   Show this help' -ForegroundColor Gray
            Write-Host ''
            Write-Host '  Roles:' -ForegroundColor White
            Write-Host '    DC         Domain Controller + DNS + Certificate Authority (always on)' -ForegroundColor Gray
            Write-Host '    DSC        DSC Pull Server — HTTP endpoints on port 8080 + 9080' -ForegroundColor Gray
            Write-Host '    IIS        IIS Web Server with sample site' -ForegroundColor Gray
            Write-Host '    SQL        SQL Server (scaffold — VM created, install manual)' -ForegroundColor Gray
            Write-Host '    WSUS       WSUS (scaffold — VM created, install manual)' -ForegroundColor Gray
            Write-Host '    FileServer File Server with SMB share (\\FILE1\LabShare)' -ForegroundColor Gray
            Write-Host '    Jumpbox    Admin workstation (Win11 + RSAT tools)' -ForegroundColor Gray
            Write-Host '    Client     Client VM (Win11 + RDP enabled)' -ForegroundColor Gray
            Write-Host '    Ubuntu     Ubuntu Server 24.04 (LIN1 + SSH post-install)' -ForegroundColor Gray
            Write-Host '    WebServerUbuntu Ubuntu web server (LINWEB1 + nginx)' -ForegroundColor Gray
            Write-Host '    DatabaseUbuntu  Ubuntu database (LINDB1 + PostgreSQL)' -ForegroundColor Gray
            Write-Host '    DockerUbuntu    Ubuntu Docker host (LINDOCK1 + Docker CE)' -ForegroundColor Gray
            Write-Host '    K8sUbuntu       Ubuntu Kubernetes (LINK8S1 + k3s)' -ForegroundColor Gray
            Write-Host ''
            Read-Host '  Press Enter to continue'
        }
        else {
            Write-Host '  Invalid input. Type ? for help.' -ForegroundColor Red
            Start-Sleep -Milliseconds 800
        }
    }

    # Build list of selected role tags
    $selectedTags = @()
    for ($i = 0; $i -lt $count; $i++) {
        if ($roleMenu[$i].Separator) { continue }
        if ($selected[$i]) {
            $selectedTags += $roleMenu[$i].Tag
        }
    }

    # Print build plan summary
    Clear-Host
    Write-Host ''
    Write-Host ('  ' + ('=' * 50)) -ForegroundColor Cyan
    Write-Host '  Build Plan Summary' -ForegroundColor Cyan
    Write-Host ('  ' + ('=' * 50)) -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  VM Name       IP Address       OS    Role' -ForegroundColor White
    Write-Host '  -------       ----------       --    ----' -ForegroundColor Gray

    for ($i = 0; $i -lt $count; $i++) {
        if ($roleMenu[$i].Separator) { continue }
        if ($selected[$i]) {
            $tag = $roleMenu[$i].Tag
            $vmName = $Config.VMNames[$tag]
            $ip = $Config.IPPlan[$tag]
            $label = $roleMenu[$i].Label
            $isLinux = ($tag -like '*Ubuntu')
            $osMarker = if ($isLinux) { '[LIN]' } else { '[WIN]' }
            $osColor = if ($isLinux) { 'DarkCyan' } else { 'Gray' }

            $vmCol = $vmName.PadRight(14)
            $ipCol = $ip.PadRight(17)
            Write-Host "  $vmCol $ipCol " -NoNewline -ForegroundColor White
            Write-Host "$osMarker " -NoNewline -ForegroundColor $osColor
            Write-Host "$label" -ForegroundColor White
        }
    }

    Write-Host ''
    Write-Host "  Total VMs: $($selectedTags.Count)" -ForegroundColor Cyan
    Write-Host "  Domain:    $($Config.DomainName)" -ForegroundColor Cyan
    Write-Host "  Subnet:    $($Config.Network.AddressSpace)" -ForegroundColor Cyan
    Write-Host ''

    return @{
        SelectedRoles = [string[]]$selectedTags
        Cancelled     = $false
    }
}

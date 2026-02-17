function Invoke-LabConfigureRoleMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptDir,
        [Parameter(Mandatory)][string[]]$CoreVMNames,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$RunEvents
    )

    $roles = @(
        [pscustomobject]@{ Key = '1'; Name = 'DC';         DefaultVM = 'DC1';     BuilderTag = 'DC';         Automation = 'Built-in domain role' },
        [pscustomobject]@{ Key = '2'; Name = 'WSUS';       DefaultVM = 'WSUS1';   BuilderTag = 'WSUS';       Automation = 'LabBuilder unattended install' },
        [pscustomobject]@{ Key = '3'; Name = 'SQL';        DefaultVM = 'SQL1';    BuilderTag = 'SQL';        Automation = 'LabBuilder unattended install' },
        [pscustomobject]@{ Key = '4'; Name = 'DHCP';       DefaultVM = 'DHCP1';    BuilderTag = 'DHCP';       Automation = 'LabBuilder automated role pipeline' },
        [pscustomobject]@{ Key = '5'; Name = 'File Server';DefaultVM = 'FILE1';    BuilderTag = 'FileServer'; Automation = 'LabBuilder scaffold available' },
        [pscustomobject]@{ Key = '6'; Name = 'Print Server';DefaultVM = 'PRN1';     BuilderTag = 'PrintServer'; Automation = 'AutomatedLab Windows feature' },
        [pscustomobject]@{ Key = '7'; Name = 'Splunk';      DefaultVM = 'SPLUNK1';  BuilderTag = '';            Automation = 'Custom install required' },
        [pscustomobject]@{ Key = '8'; Name = 'Commvault';   DefaultVM = 'CV1';      BuilderTag = '';            Automation = 'Custom install required' },
        [pscustomobject]@{ Key = '9'; Name = 'Trellix';     DefaultVM = 'TRELLIX1'; BuilderTag = '';            Automation = 'Custom install required' },
        [pscustomobject]@{ Key = '0'; Name = 'ISE';         DefaultVM = 'ISE1';     BuilderTag = '';            Automation = 'Custom install required' }
    )

    Write-Host ''
    Write-Host '  CONFIGURE ROLE' -ForegroundColor Cyan
    foreach ($role in $roles) {
        Write-Host ("   [{0}] {1}" -f $role.Key, $role.Name) -ForegroundColor White
    }
    Write-Host '   [X] Back' -ForegroundColor DarkGray

    $roleChoice = (Read-Host '  Select role').Trim().ToUpperInvariant()
    if ($roleChoice -eq 'X') { return }

    $selectedRole = $roles | Where-Object { $_.Key -eq $roleChoice } | Select-Object -First 1
    if (-not $selectedRole) {
        Write-Host '  Invalid role selection.' -ForegroundColor Red
        return
    }

    Write-Host ''
    Write-Host '  Role topology mode:' -ForegroundColor Cyan
    Write-Host '   [P] Primary (default)' -ForegroundColor Gray
    Write-Host '   [S] Secondary' -ForegroundColor Gray
    $modeChoice = (Read-Host '  Select mode').Trim().ToUpperInvariant()
    $roleMode = if ($modeChoice -eq 'S') { 'Secondary' } else { 'Primary' }

    $targetVM = Get-LabMenuVmSelection -SuggestedVM $selectedRole.DefaultVM -CoreVMNames $CoreVMNames
    if ([string]::IsNullOrWhiteSpace($targetVM)) {
        Write-Host '  Target VM is required.' -ForegroundColor Red
        return
    }

    Add-LabRunEvent -Step 'configure-role' -Status 'ok' -Message ("Role={0}; Mode={1}; Target={2}" -f $selectedRole.Name, $roleMode, $targetVM) -RunEvents $RunEvents

    Write-Host ''
    Write-LabStatus -Status OK -Message ("Role plan captured: {0} ({1}) on {2}" -f $selectedRole.Name, $roleMode, $targetVM)
    Write-Host ("  Automation: {0}" -f $selectedRole.Automation) -ForegroundColor DarkGray

    if (-not [string]::IsNullOrWhiteSpace($selectedRole.BuilderTag)) {
        $builderPath = Join-Path $ScriptDir 'LabBuilder\Invoke-LabBuilder.ps1'
        Write-Host '  AutomatedLab-backed role detected.' -ForegroundColor Green
        Write-Host ("  Build command: {0} -Operation Build -Roles DC,{1}" -f $builderPath, $selectedRole.BuilderTag) -ForegroundColor Gray

        $runNow = (Read-Host '  Run this build now? (Y/n)').Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($runNow) -or $runNow -eq 'y' -or $runNow -eq 'yes') {
            if (-not (Test-Path $builderPath)) {
                Write-Host ("  LabBuilder entry not found: {0}" -f $builderPath) -ForegroundColor Red
                return
            }

            $rolesToBuild = @('DC', $selectedRole.BuilderTag) | Select-Object -Unique
            & $builderPath -Operation Build -Roles $rolesToBuild
        }
    } else {
        Write-Host '  This role does not have an automated installer in this repo yet.' -ForegroundColor Yellow
    }
}

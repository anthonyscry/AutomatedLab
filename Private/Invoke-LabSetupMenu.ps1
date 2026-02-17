# Invoke-LabSetupMenu.ps1
# Interactive setup menu: prompts for additional VM counts, runs one-button setup,
# then provisions any requested additional VMs.

function Invoke-LabSetupMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$LabConfig,

        [Parameter(Mandatory)]
        [string]$ScriptDir,

        [Parameter(Mandatory)]
        [string]$LabName,

        [Parameter(Mandatory)]
        [ValidateSet('quick', 'full')]
        [string]$EffectiveMode,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$RunEvents,

        [switch]$NonInteractive,
        [switch]$AutoFixSubnetConflict
    )

    try {
        Write-Host ''
        Write-Host '  SETUP LAB' -ForegroundColor Cyan
        Write-Host '  Core build always includes DC1 + SVR1 + WS1.' -ForegroundColor DarkGray

        $serverCount = Read-LabMenuCount -Prompt 'Additional server VMs to provision' -DefaultValue 0
        $workstationCount = Read-LabMenuCount -Prompt 'Additional workstation VMs to provision' -DefaultValue 0

        $serverIso = ''
        $workstationIso = ''
        if ($serverCount -gt 0) {
            $serverIso = (Read-Host '  Server ISO path (optional)').Trim()
        }
        if ($workstationCount -gt 0) {
            $workstationIso = (Read-Host '  Workstation ISO path (optional)').Trim()
        }

        Add-LabRunEvent -Step 'setup-plan' -Status 'ok' -Message ("ExtraServers={0}; ExtraWorkstations={1}" -f $serverCount, $workstationCount) -RunEvents $RunEvents

        Invoke-LabOneButtonSetup -EffectiveMode $EffectiveMode -LabConfig $LabConfig -ScriptDir $ScriptDir -LabName $LabName -RunEvents $RunEvents -NonInteractive:$NonInteractive -AutoFixSubnetConflict:$AutoFixSubnetConflict

        if (($serverCount + $workstationCount) -gt 0) {
            Write-Host ''
            Write-Host '  Provisioning additional VMs...' -ForegroundColor Cyan
            Invoke-LabBulkVMProvision -ServerCount $serverCount -WorkstationCount $workstationCount -ServerIsoPath $serverIso -WorkstationIsoPath $workstationIso -LabConfig $LabConfig -RunEvents $RunEvents
        }
    }
    catch {
        Write-Warning "Invoke-LabSetupMenu: setup menu error - $_"
    }
}

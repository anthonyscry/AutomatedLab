function Import-LabModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LabName
    )

    if (Get-Module -Name AutomatedLab -ErrorAction SilentlyContinue) {
        # Module already loaded; just ensure lab is imported
        try {
            $lab = Get-Lab -ErrorAction SilentlyContinue
            if ($lab -and $lab.Name -eq $LabName) { return }
        } catch {
            Write-Verbose "Lab query failed (expected if lab not yet created): $_"
        }
    }

    try {
        Write-Verbose "Importing module: AutomatedLab"
        $null = Import-Module AutomatedLab -ErrorAction Stop
    } catch {
        throw "AutomatedLab module is not installed. Run setup first."
    }

    try {
        Write-Verbose "Importing lab: $LabName"
        $null = Import-Lab -Name $LabName -ErrorAction Stop
    } catch {
        throw "Lab '$LabName' is not registered. Run setup first."
    }
}

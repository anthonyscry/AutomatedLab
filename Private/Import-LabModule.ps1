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
        Import-Module AutomatedLab -ErrorAction Stop | Out-Null
    } catch {
        throw "AutomatedLab module is not installed. Run setup first."
    }

    try {
        Import-Lab -Name $LabName -ErrorAction Stop | Out-Null
    } catch {
        throw "Lab '$LabName' is not registered. Run setup first."
    }
}

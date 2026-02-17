# Import-OpenCodeLab.ps1 -- Import AutomatedLab and lab context
function Import-OpenCodeLab {
    param([string]$Name)

    try {
        Write-Verbose "Importing module: AutomatedLab"
        $null = Import-Module AutomatedLab -ErrorAction Stop
    } catch {
        throw "AutomatedLab module not available. Install AutomatedLab first."
    }

    try {
        Write-Verbose "Importing lab: $Name"
        $null = Import-Lab -Name $Name -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# Import-OpenCodeLab.ps1 -- Import AutomatedLab and lab context
function Import-OpenCodeLab {
    param([string]$Name)

    try {
        Import-Module AutomatedLab -ErrorAction Stop | Out-Null
    } catch {
        throw "AutomatedLab module not available. Install AutomatedLab first."
    }

    try {
        Import-Lab -Name $Name -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

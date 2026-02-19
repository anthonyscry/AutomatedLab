Set-StrictMode -Version Latest

function Get-LabCommandMap {
    return [ordered]@{
        preflight = 'Invoke-LabPreflight'
        deploy    = 'Invoke-LabDeploy'
        teardown  = 'Invoke-LabTeardown'
        status    = 'Get-LabStatus'
        health    = 'Get-LabHealth'
        dashboard = 'Start-LabDashboard'
    }
}

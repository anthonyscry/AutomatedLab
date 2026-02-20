function Get-LabScenarioTemplate {
    <#
    .SYNOPSIS
        Resolves a scenario name to its VM template definitions.
    .DESCRIPTION
        Reads a scenario template JSON file by name from the templates directory
        and returns an array of VM definition objects compatible with Deploy.ps1.
        If the scenario name is not found, throws an error listing available scenarios.
    .PARAMETER Scenario
        The scenario name to resolve (e.g., SecurityLab, MultiTierApp, MinimalAD).
    .PARAMETER TemplatesRoot
        Path to the directory containing scenario template JSON files.
        Defaults to .planning/templates relative to the repository root.
    .EXAMPLE
        Get-LabScenarioTemplate -Scenario SecurityLab
        Returns 3 VM definition objects for the SecurityLab scenario.
    .EXAMPLE
        Get-LabScenarioTemplate -Scenario MultiTierApp -TemplatesRoot 'C:\MyTemplates'
        Returns VM definitions from a custom templates directory.
    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Array of VM definition objects with Name, Role, Ip, MemoryGB, Processors properties.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Scenario,

        [Parameter()]
        [string]$TemplatesRoot = (Join-Path (Join-Path $PSScriptRoot '..') '.planning/templates')
    )

    try {
        $templatePath = Join-Path $TemplatesRoot "$Scenario.json"

        if (-not (Test-Path $templatePath)) {
            # List available scenarios (exclude default.json)
            $available = @()
            if (Test-Path $TemplatesRoot) {
                $jsonFiles = Get-ChildItem -Path $TemplatesRoot -Filter '*.json' -File
                foreach ($f in $jsonFiles) {
                    if ($f.BaseName -ne 'default') {
                        $available += $f.BaseName
                    }
                }
            }
            $availableList = $available -join ', '
            throw "Get-LabScenarioTemplate: Scenario '$Scenario' not found. Available scenarios: $availableList"
        }

        try {
            $template = Get-Content -Path $templatePath -Raw | ConvertFrom-Json
        }
        catch {
            throw "Get-LabScenarioTemplate: Failed to parse '$templatePath' - $_"
        }

        # Validate template data using shared validation helper
        if (Get-Command -Name Test-LabTemplateData -ErrorAction SilentlyContinue) {
            Test-LabTemplateData -Template $template -TemplatePath $templatePath
        }

        # Build VM definition array matching Get-ActiveTemplateConfig shape
        $vmDefs = @()
        foreach ($vm in $template.vms) {
            $vmDefs += [pscustomobject]@{
                Name       = $vm.name
                Role       = $vm.role
                Ip         = $vm.ip
                MemoryGB   = [int]$vm.memoryGB
                Processors = [int]$vm.processors
            }
        }

        return $vmDefs
    }
    catch {
        if ($_.Exception.Message -like 'Get-LabScenarioTemplate:*') {
            throw
        }
        throw "Get-LabScenarioTemplate: $($_.Exception.Message)"
    }
}

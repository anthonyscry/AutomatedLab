function Get-ActiveTemplateConfig {
    <#
    .SYNOPSIS
        Reads the active template from .planning/config.json and returns VM definitions.
    .DESCRIPTION
        Checks .planning/config.json for an ActiveTemplate key, loads the matching
        template from .planning/templates/, and returns the VM definitions array.
        Returns $null if no active template is set or the template file is missing.
    .PARAMETER RepoRoot
        Root directory of the AutomatedLab repository.
    .OUTPUTS
        Array of PSCustomObjects with Name, Role, Ip, MemoryGB, Processors properties,
        or $null if no template override is active.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $configPath = Join-Path (Join-Path $RepoRoot '.planning') 'config.json'
    if (-not (Test-Path $configPath)) { return $null }

    try {
        $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to read config.json: $_"
    }

    if (-not $config.ActiveTemplate) { return $null }

    $templateName = $config.ActiveTemplate
    $templatePath = Join-Path (Join-Path (Join-Path $RepoRoot '.planning') 'templates') "$templateName.json"

    if (-not (Test-Path $templatePath)) {
        Write-Warning "Active template '$templateName' not found at $templatePath"
        return $null
    }

    try {
        $template = Get-Content -Path $templatePath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Template file '$templatePath' contains invalid JSON: $($_.Exception.Message)"
    }

    # Validate template data using shared validation helper
    # This will throw if structure is invalid or any VM data is invalid
    Test-LabTemplateData -Template $template -TemplatePath $templatePath

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

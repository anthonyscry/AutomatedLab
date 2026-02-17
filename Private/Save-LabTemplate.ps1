function Save-LabTemplate {
    <#
    .SYNOPSIS
        Saves a VM deployment template to .planning/templates/{Name}.json.
    .PARAMETER RepoRoot
        Root directory of the AutomatedLab repository.
    .PARAMETER Name
        Template name (used as filename, must be filesystem-safe).
    .PARAMETER Description
        Human-readable description of the template.
    .PARAMETER VMs
        Array of VM definition objects with name, role, ip, memoryGB, processors.
    .OUTPUTS
        PSCustomObject with Success and Message properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$Description = '',

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$VMs
    )

    # Validate VMs array is not empty
    if ($null -eq $VMs -or @($VMs).Count -eq 0) {
        throw "Template validation failed: At least one VM is required."
    }

    # Validate template name is filesystem-safe
    if ($Name -notmatch '^[a-zA-Z0-9_-]+$') {
        throw "Template validation failed: Template name '$Name' contains invalid characters. Use only letters, numbers, hyphens, and underscores."
    }

    # Build template object from input VMs
    $template = [ordered]@{
        name        = $Name
        description = $Description
        vms         = @()
    }

    foreach ($vm in $VMs) {
        $template.vms += [ordered]@{
            name       = $vm.name
            role       = $vm.role
            ip         = $vm.ip
            memoryGB   = [int]$vm.memoryGB
            processors = [int]$vm.processors
        }
    }

    # Validate template data using shared validation helper
    # This will throw if any VM data is invalid
    Test-LabTemplateData -Template $template

    # Ensure directory exists
    $templatesDir = Join-Path (Join-Path $RepoRoot '.planning') 'templates'
    if (-not (Test-Path $templatesDir)) {
        New-Item -ItemType Directory -Path $templatesDir -Force | Out-Null
    }

    $templatePath = Join-Path $templatesDir "$Name.json"

    try {
        $template | ConvertTo-Json -Depth 10 | Set-Content -Path $templatePath -Encoding UTF8
        return [pscustomobject]@{
            Success = $true
            Message = "Template '$Name' saved successfully."
        }
    }
    catch {
        throw "Failed to save template to '$templatePath': $_"
    }
}

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
        [array]$VMs
    )

    # Validate template name is filesystem-safe
    if ($Name -notmatch '^[a-zA-Z0-9_-]+$') {
        return [pscustomobject]@{
            Success = $false
            Message = "Template name '$Name' contains invalid characters. Use only letters, numbers, hyphens, and underscores."
        }
    }

    # Validate at least one VM
    if ($VMs.Count -eq 0) {
        return [pscustomobject]@{
            Success = $false
            Message = 'At least one VM is required.'
        }
    }

    # Validate each VM
    $vmNames = @()
    foreach ($vm in $VMs) {
        # NetBIOS name validation
        if ($vm.name -notmatch '^[a-zA-Z0-9-]{1,15}$') {
            return [pscustomobject]@{
                Success = $false
                Message = "VM name '$($vm.name)' is invalid. Use 1-15 alphanumeric characters and hyphens."
            }
        }

        # Unique name check
        if ($vmNames -contains $vm.name.ToLowerInvariant()) {
            return [pscustomobject]@{
                Success = $false
                Message = "Duplicate VM name: '$($vm.name)'."
            }
        }
        $vmNames += $vm.name.ToLowerInvariant()

        # IP validation
        if ($vm.ip -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
            return [pscustomobject]@{
                Success = $false
                Message = "Invalid IP address for VM '$($vm.name)': '$($vm.ip)'."
            }
        }

        # Memory validation
        if ([int]$vm.memoryGB -lt 1) {
            return [pscustomobject]@{
                Success = $false
                Message = "Memory for VM '$($vm.name)' must be at least 1 GB."
            }
        }

        # Processor validation
        if ([int]$vm.processors -lt 1 -or [int]$vm.processors -gt 8) {
            return [pscustomobject]@{
                Success = $false
                Message = "Processors for VM '$($vm.name)' must be between 1 and 8."
            }
        }
    }

    # Build template object
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
        return [pscustomobject]@{
            Success = $false
            Message = "Failed to save template: $_"
        }
    }
}

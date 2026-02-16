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

    # Known VM roles (empty/null is also acceptable for generic VMs)
    $validRoles = @(
        'DC', 'SQL', 'IIS', 'WSUS', 'DHCP', 'FileServer', 'PrintServer',
        'DSC', 'Jumpbox', 'Client', 'Ubuntu', 'WebServerUbuntu',
        'DatabaseUbuntu', 'DockerUbuntu', 'K8sUbuntu'
    )

    # Validate template name is filesystem-safe
    if ($Name -notmatch '^[a-zA-Z0-9_-]+$') {
        throw "Template validation failed: Template name '$Name' contains invalid characters. Use only letters, numbers, hyphens, and underscores."
    }

    # Validate at least one VM
    if ($VMs.Count -eq 0) {
        throw "Template validation failed: At least one VM is required."
    }

    # Validate each VM
    $vmNames = @()
    $vmIPs = @()
    foreach ($vm in $VMs) {
        # NetBIOS name validation
        if ($vm.name -notmatch '^[a-zA-Z0-9-]{1,15}$') {
            throw "Template validation failed: VM name '$($vm.name)' is invalid. NetBIOS names must be 1-15 alphanumeric characters and hyphens."
        }

        # Check name length explicitly for better error message
        if ($vm.name.Length -gt 15) {
            throw "Template validation failed: VM name '$($vm.name)' exceeds 15 characters."
        }

        # Unique name check
        if ($vmNames -contains $vm.name.ToLowerInvariant()) {
            throw "Template validation failed: Duplicate VM name '$($vm.name)'."
        }
        $vmNames += $vm.name.ToLowerInvariant()

        # IP validation - format
        if ($vm.ip -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
            throw "Template validation failed: Invalid IP '$($vm.ip)' for VM '$($vm.name)'. Expected IPv4 format."
        }

        # IP validation - octet range check
        $octets = $vm.ip -split '\.'
        foreach ($octet in $octets) {
            if ([int]$octet -lt 0 -or [int]$octet -gt 255) {
                throw "Template validation failed: Invalid IP '$($vm.ip)' for VM '$($vm.name)'. Octets must be 0-255."
            }
        }

        # Unique IP check
        if ($vmIPs -contains $vm.ip) {
            throw "Template validation failed: Duplicate IP address '$($vm.ip)'."
        }
        $vmIPs += $vm.ip

        # Role validation (empty/null is acceptable)
        if ($vm.role -and $vm.role -ne '' -and $validRoles -notcontains $vm.role) {
            $roleList = $validRoles -join ', '
            throw "Template validation failed: Unknown role '$($vm.role)' for VM '$($vm.name)'. Valid roles: $roleList"
        }

        # Memory validation (1-64 GB range per spec)
        try {
            $memoryValue = [int]$vm.memoryGB
        }
        catch {
            throw "Template validation failed: Memory for VM '$($vm.name)' must be a numeric value."
        }

        if ($memoryValue -lt 1 -or $memoryValue -gt 64) {
            throw "Template validation failed: Memory for VM '$($vm.name)' must be between 1 and 64 GB."
        }

        # Processor validation (1-16 range per spec)
        try {
            $processorValue = [int]$vm.processors
        }
        catch {
            throw "Template validation failed: Processors for VM '$($vm.name)' must be a numeric value."
        }

        if ($processorValue -lt 1 -or $processorValue -gt 16) {
            throw "Template validation failed: Processors for VM '$($vm.name)' must be between 1 and 16."
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
        throw "Failed to save template to '$templatePath': $_"
    }
}

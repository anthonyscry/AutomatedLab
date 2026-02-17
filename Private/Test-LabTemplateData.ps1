function Test-LabTemplateData {
    <#
    .SYNOPSIS
        Validates VM template data structure and field values.
    .DESCRIPTION
        Performs comprehensive validation of a template object including structure checks,
        VM name validation (NetBIOS), IP address validation (IPv4), role validation,
        memory and processor range validation, and uniqueness checks.
        Throws on the first validation error encountered.
    .PARAMETER Template
        Template object (deserialized JSON) to validate.
    .PARAMETER TemplatePath
        Optional path to the template file (used for error messages).
    .OUTPUTS
        None. Throws on validation failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Template,

        [Parameter()]
        [string]$TemplatePath = ''
    )

    $errorPrefix = if ($TemplatePath) { "Template '$TemplatePath' validation failed" } else { "Template validation failed" }

    # Known VM roles (empty/null is also acceptable for generic VMs)
    $validRoles = @(
        'DC', 'SQL', 'IIS', 'WSUS', 'DHCP', 'FileServer', 'PrintServer',
        'DSC', 'Jumpbox', 'Client', 'Ubuntu', 'WebServerUbuntu',
        'DatabaseUbuntu', 'DockerUbuntu', 'K8sUbuntu'
    )

    # Structure validation - must have VMs array with at least one entry
    if (-not $Template.vms -or @($Template.vms).Count -eq 0) {
        throw "${errorPrefix}: At least one VM is required."
    }

    # Validate each VM
    $vmNames = @()
    $vmIPs = @()
    foreach ($vm in $Template.vms) {
        # Required fields check
        if (-not $vm.name) {
            throw "${errorPrefix}: VM entry missing 'name' field."
        }

        if (-not $vm.ip) {
            throw "${errorPrefix}: VM '$($vm.name)' missing 'ip' field."
        }

        # NetBIOS name validation
        if ($vm.name -notmatch '^[a-zA-Z0-9-]{1,15}$') {
            throw "${errorPrefix}: VM name '$($vm.name)' is invalid. NetBIOS names must be 1-15 alphanumeric characters and hyphens."
        }

        # Check name length explicitly for better error message
        if ($vm.name.Length -gt 15) {
            throw "${errorPrefix}: VM name '$($vm.name)' exceeds 15 characters."
        }

        # Unique name check
        if ($vmNames -contains $vm.name.ToLowerInvariant()) {
            throw "${errorPrefix}: Duplicate VM name '$($vm.name)'."
        }
        $vmNames += $vm.name.ToLowerInvariant()

        # IP validation - format
        if ($vm.ip -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
            throw "${errorPrefix}: Invalid IP '$($vm.ip)' for VM '$($vm.name)'. Expected IPv4 format."
        }

        # IP validation - octet range check
        $octets = $vm.ip -split '\.'
        foreach ($octet in $octets) {
            if ([int]$octet -lt 0 -or [int]$octet -gt 255) {
                throw "${errorPrefix}: Invalid IP '$($vm.ip)' for VM '$($vm.name)'. Octets must be 0-255."
            }
        }

        # Unique IP check
        if ($vmIPs -contains $vm.ip) {
            throw "${errorPrefix}: Duplicate IP address '$($vm.ip)'."
        }
        $vmIPs += $vm.ip

        # Role validation (empty/null is acceptable)
        if ($vm.role -and $vm.role -ne '' -and $validRoles -notcontains $vm.role) {
            $roleList = $validRoles -join ', '
            throw "${errorPrefix}: Unknown role '$($vm.role)' for VM '$($vm.name)'. Valid roles: $roleList"
        }

        # Memory validation (1-64 GB range)
        if ($null -ne $vm.memoryGB) {
            try {
                $memoryValue = [int]$vm.memoryGB
            }
            catch {
                throw "${errorPrefix}: Memory for VM '$($vm.name)' must be a numeric value."
            }

            if ($memoryValue -lt 1 -or $memoryValue -gt 64) {
                throw "${errorPrefix}: Memory for VM '$($vm.name)' must be between 1 and 64 GB."
            }
        }

        # Processor validation (1-16 range)
        if ($null -ne $vm.processors) {
            try {
                $processorValue = [int]$vm.processors
            }
            catch {
                throw "${errorPrefix}: Processors for VM '$($vm.name)' must be a numeric value."
            }

            if ($processorValue -lt 1 -or $processorValue -gt 16) {
                throw "${errorPrefix}: Processors for VM '$($vm.name)' must be between 1 and 16."
            }
        }
    }
}

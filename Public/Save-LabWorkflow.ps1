function Save-LabWorkflow {
    <#
    .SYNOPSIS
        Saves a custom operational workflow to a JSON file.

    .DESCRIPTION
        Save-LabWorkflow creates a workflow definition file that specifies a
        sequence of VM operations. Workflows can include bulk operations,
        individual VM operations, and delays between steps. Useful for
        automating common multi-step procedures.

    .PARAMETER Name
        Name of the workflow (filename without .json extension).

    .PARAMETER Description
        Human-readable description of what the workflow does.

    .PARAMETER Steps
        Array of workflow steps. Each step is a hashtable with Operation,
        VMName (optional), CheckpointName (for checkpoint operations), and
        DelaySeconds (optional) properties.

    .PARAMETER Force
        Overwrite existing workflow file if it exists.

    .EXAMPLE
        Save-LabWorkflow -Name 'StartLab' -Description 'Start all lab VMs in order' -Steps @(
            @{ Operation = 'Start'; VMName = @('dc1') },
            @{ Operation = 'Start'; VMName = @('svr1', 'cli1'); DelaySeconds = 30 }
        )
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Description,

        [Parameter(Mandatory)]
        [hashtable[]]$Steps,

        [switch]$Force
    )

    $workflowConfig = Get-LabWorkflowConfig

    if (-not $workflowConfig.Enabled) {
        throw 'Workflows are disabled in Lab configuration'
    }

    $storagePath = $workflowConfig.StoragePath
    $parentDir = Split-Path -Parent $storagePath

    if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path $parentDir)) {
        $null = New-Item -Path $parentDir -ItemType Directory -Force
        Write-Verbose "Created directory: $parentDir"
    }

    if (-not (Test-Path $storagePath)) {
        $null = New-Item -Path $storagePath -ItemType Directory -Force
        Write-Verbose "Created directory: $storagePath"
    }

    $fileName = if ($Name -match '\.json$') { $Name } else { "$Name.json" }
    $filePath = Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) $storagePath) $fileName

    if ((Test-Path $filePath) -and -not $Force) {
        throw "Workflow file already exists: $filePath (use -Force to overwrite)"
    }

    $workflow = [ordered]@{
        Name        = $Name
        Description = $Description
        Version     = '1.0'
        CreatedAt   = (Get-Date -Format 'o')
        Steps       = @()
    }

    foreach ($step in $Steps) {
        $stepObj = [ordered]@{
            Operation = $step.Operation
        }

        if ($step.ContainsKey('VMName')) {
            $stepObj.VMName = @($step.VMName)
        }

        if ($step.ContainsKey('CheckpointName')) {
            $stepObj.CheckpointName = $step.CheckpointName
        }

        if ($step.ContainsKey('DelaySeconds')) {
            $stepObj.DelaySeconds = [int]$step.DelaySeconds
        }

        $workflow.Steps += $stepObj
    }

    $targetPath = $filePath
    if ($PSCmdlet.ShouldProcess($targetPath, 'Save workflow')) {
        $workflow | ConvertTo-Json -Depth 4 | Set-Content -Path $filePath -Encoding UTF8
        Write-Verbose "Saved workflow: $filePath"

        return [pscustomobject]@{
            Name   = $Name
            Path   = $filePath
            Status = 'Created'
        }
    }
}

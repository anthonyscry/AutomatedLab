function Get-LabWorkflow {
    <#
    .SYNOPSIS
        Retrieves custom workflow definitions.

    .DESCRIPTION
        Get-LabWorkflow lists all available workflows or retrieves details for
        a specific workflow. Workflows are stored as JSON files in the
        .planning/workflows/ directory and define sequences of VM operations.

    .PARAMETER Name
        Name of the workflow to retrieve. If not specified, lists all workflows.

    .EXAMPLE
        Get-LabWorkflow
        Lists all available workflows.

    .EXAMPLE
        Get-LabWorkflow -Name 'StartLab'
        Retrieves details for the StartLab workflow.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string]$Name
    )

    $workflowConfig = Get-LabWorkflowConfig
    $storagePath = Join-Path (Split-Path -Parent $PSScriptRoot) $workflowConfig.StoragePath

    if (-not (Test-Path $storagePath)) {
        return @()
    }

    if ($PSBoundParameters.ContainsKey('Name')) {
        $fileName = if ($Name -match '\.json$') { $Name } else { "$Name.json" }
        $filePath = Join-Path $storagePath $fileName

        if (-not (Test-Path $filePath)) {
            Write-Warning "Workflow not found: $Name"
            return @()
        }

        try {
            $workflow = Get-Content -Raw -Path $filePath | ConvertFrom-Json
            return [pscustomobject]@{
                Name        = $workflow.Name
                Description = $workflow.Description
                Version     = $workflow.Version
                CreatedAt   = $workflow.CreatedAt
                StepCount   = $workflow.Steps.Count
                Steps       = @($workflow.Steps)
                Path        = $filePath
            }
        }
        catch {
            Write-Warning "Failed to read workflow file '$filePath': $($_.Exception.Message)"
            return @()
        }
    }
    else {
        $workflows = @()

        Get-ChildItem -Path $storagePath -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $workflow = Get-Content -Raw -Path $_.FullName | ConvertFrom-Json

                $workflows += [pscustomobject]@{
                    Name        = $workflow.Name
                    Description = $workflow.Description
                    Version     = $workflow.Version
                    CreatedAt   = $workflow.CreatedAt
                    StepCount   = $workflow.Steps.Count
                    Path        = $_.FullName
                }
            }
            catch {
                Write-Warning "Failed to read workflow file '$($_.FullName)': $($_.Exception.Message)"
            }
        }

        return @($workflows | Sort-Object -Property Name)
    }
}

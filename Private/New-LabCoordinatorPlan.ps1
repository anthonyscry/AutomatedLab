function New-LabCoordinatorPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('deploy', 'teardown')]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [ValidateSet('quick', 'full')]
        [string]$Mode
    )

    $steps = @(
        [pscustomobject]@{
            Id = 'preflight'
            DependsOn = @()
            Kind = 'preflight'
        },
        [pscustomobject]@{
            Id = 'policy'
            DependsOn = @('preflight')
            Kind = 'policy'
        },
        [pscustomobject]@{
            Id = 'execute-nondestructive'
            DependsOn = @('policy')
            Kind = 'execute'
        }
    )

    if ($Action -eq 'teardown' -and $Mode -eq 'full') {
        $steps += [pscustomobject]@{
            Id = 'destructive-barrier'
            DependsOn = @('execute-nondestructive')
            Kind = 'barrier'
        }

        $steps += [pscustomobject]@{
            Id = 'execute-destructive'
            DependsOn = @('destructive-barrier')
            Kind = 'execute'
        }
    }

    return [pscustomobject]@{
        Action = $Action
        Mode = $Mode
        Steps = $steps
    }
}

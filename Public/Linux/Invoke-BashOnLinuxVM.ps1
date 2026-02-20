# Invoke-BashOnLinuxVM.ps1 -- Run bash script on Linux VM via AutomatedLab
function Invoke-BashOnLinuxVM {
    <#
    .SYNOPSIS
    Run a bash script on a Linux VM registered with AutomatedLab.

    .DESCRIPTION
    Writes the provided bash script to a temporary file, copies it to the target
    VM via Copy-LabFileItem, then executes it with Invoke-LabCommand.  Supports
    simple variable substitution using the __KEY__ placeholder pattern before the
    script is written to disk.  The temporary file is removed from the host after
    the invocation regardless of success or failure.

    .PARAMETER VMName
    Name of the AutomatedLab-registered Linux VM (default: LIN1).

    .PARAMETER BashScript
    Full content of the bash script to execute on the VM.

    .PARAMETER ActivityName
    Label used for the AutomatedLab activity and for the temporary script filename.

    .PARAMETER Variables
    Hashtable of substitution variables.  Each key K is replaced in the script
    wherever the placeholder __K__ appears.

    .PARAMETER PassThru
    When specified, passes -PassThru to Invoke-LabCommand so the command output
    is returned to the caller.

    .EXAMPLE
    Invoke-BashOnLinuxVM -VMName 'LIN1' -ActivityName 'UpdatePackages' `
        -BashScript "apt-get update -qq && apt-get upgrade -y -qq"

    .EXAMPLE
    $script = 'echo "Hello from __HOST__"'
    Invoke-BashOnLinuxVM -VMName 'LIN1' -ActivityName 'HelloWorld' `
        -BashScript $script -Variables @{ HOST = 'LIN1' } -PassThru
    #>
    param(
        # Uses AutomatedLab Copy-LabFileItem / Invoke-LabCommand and requires the VM to be registered in AutomatedLab.
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$VMName = 'LIN1',
        [Parameter(Mandatory)][string]$BashScript,
        [Parameter(Mandatory)][string]$ActivityName,
        [hashtable]$Variables = @{},
        [switch]$PassThru
    )
    # Apply variable substitutions (placeholder pattern: __KEY__)
    $content = $BashScript
    foreach ($key in $Variables.Keys) {
        $content = $content.Replace("__${key}__", $Variables[$key])
    }

    $tempName = "$ActivityName-$(Get-Date -Format 'HHmmss').sh"
    $tempPath = Join-Path $env:TEMP $tempName
    $content | Set-Content -Path $tempPath -Encoding ASCII -Force

    try {
        Copy-LabFileItem -Path $tempPath -ComputerName $VMName -DestinationFolderPath '/tmp'

        $invokeParams = @{
            ComputerName = $VMName
            ActivityName = $ActivityName
            ScriptBlock = {
                param($ScriptFile)
                chmod +x "/tmp/$ScriptFile"
                bash "/tmp/$ScriptFile"
            }
            ArgumentList = @($tempName)
        }
        if ($PassThru) { $invokeParams.PassThru = $true }

        Invoke-LabCommand @invokeParams
    } finally {
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
    }
}

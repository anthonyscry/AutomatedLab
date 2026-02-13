# Invoke-BashOnLinuxVM.ps1 -- Run bash script on Linux VM via AutomatedLab
function Invoke-BashOnLinuxVM {
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

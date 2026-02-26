function Test-OpenCodeLabLaunchPreconditions {
    [CmdletBinding()]
    param(
        [object]$WindowsHost = $null,
        [object]$WslHost = $null,
        [object]$ElevatedSession = $null
    )

    $effectiveIsWindows = if ($null -ne $WindowsHost) { [bool]$WindowsHost } else { $env:OS -eq 'Windows_NT' }
    $effectiveIsWsl = if ($null -ne $WslHost) { [bool]$WslHost } else { -not [string]::IsNullOrWhiteSpace($env:WSL_DISTRO_NAME) }

    if ($effectiveIsWsl) {
        return [pscustomobject]@{
            CanLaunch = $false
            Message = 'WSL cannot launch the Windows WPF app directly. Run from Windows PowerShell: powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\projects\OpenCodeLab\Scripts\Run-OpenCodeLab.ps1"'
        }
    }

    if ($effectiveIsWindows) {
        if ($null -ne $ElevatedSession) {
            $effectiveElevated = [bool]$ElevatedSession
        }
        else {
            try {
                $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
                $principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
                $effectiveElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            }
            catch {
                $effectiveElevated = $false
            }
        }

        if (-not $effectiveElevated) {
            return [pscustomobject]@{
                CanLaunch = $false
                Message = 'The desktop launcher requires elevation. Start Windows PowerShell as Administrator and run Scripts/Run-OpenCodeLab.ps1 again.'
            }
        }
    }

    return [pscustomobject]@{
        CanLaunch = $true
        Message = ''
    }
}

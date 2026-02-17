function Get-LabScriptFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter(Mandatory)]
        [string[]]$RelativePaths,

        [string[]]$ExcludeFileNames = @()
    )

    try {
        $resolvedFiles = @()

        foreach ($relativePath in $RelativePaths) {
            $fullPath = Join-Path -Path $RootPath -ChildPath $relativePath
            if (-not (Test-Path -Path $fullPath -PathType Container)) {
                continue
            }

            $scriptFiles = @(
                Get-ChildItem -Path $fullPath -Filter '*.ps1' -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $ExcludeFileNames -notcontains $_.Name } |
                Sort-Object FullName
            )

            $resolvedFiles += $scriptFiles
        }

        return @($resolvedFiles)
    }
    catch {
        throw "Get-LabScriptFiles: failed to load scripts from '$RootPath' - $_"
    }
}

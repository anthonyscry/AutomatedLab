function Get-LabScriptFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter(Mandatory)]
        [string[]]$RelativePaths,

        [string[]]$ExcludeFileNames = @()
    )

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

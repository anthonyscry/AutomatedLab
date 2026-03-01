function New-ComplianceEvidencePack {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutputRoot,

        [string[]]$InputPaths = @()
    )

    $resolvedOutput = (Resolve-Path -LiteralPath $OutputRoot -ErrorAction SilentlyContinue)?.ProviderPath
    if (-not $resolvedOutput) {
        $resolvedOutput = $OutputRoot
    }

    New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
    $resolvedOutput = (Resolve-Path -LiteralPath $resolvedOutput).ProviderPath

    $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $bundleName = "ComplianceEvidence-$timestamp.zip"
    $manifestName = "ComplianceEvidence-$timestamp.manifest.json"
    $bundlePath = Join-Path $resolvedOutput $bundleName
    $manifestPath = Join-Path $resolvedOutput $manifestName

    $stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ComplianceEvidencePack-$([Guid]::NewGuid())"
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
    $artifactHashes = @()

    try {
        foreach ($candidate in $InputPaths) {
            if (-not $candidate) { continue }

            $resolved = Resolve-Path -LiteralPath $candidate -ErrorAction SilentlyContinue
            if (-not $resolved) { continue }

            $sourcePath = $resolved.ProviderPath
            $destination = Join-Path $stagingRoot (Split-Path $sourcePath -Leaf)
            $item = Get-Item -LiteralPath $sourcePath

            if ($item.PSIsContainer) {
                Copy-Item -LiteralPath $sourcePath -Destination $destination -Recurse -Force
            } else {
                New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
                Copy-Item -LiteralPath $sourcePath -Destination $destination -Force
            }
        }

        $stagedFiles = Get-ChildItem -LiteralPath $stagingRoot -Recurse -File -Force -ErrorAction SilentlyContinue
        if ($stagedFiles) {
            Compress-Archive -LiteralPath $stagedFiles.FullName -DestinationPath $bundlePath -Force
        } else {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            $zip = [System.IO.Compression.ZipFile]::Open($bundlePath, [System.IO.Compression.ZipArchiveMode]::Create)
            $zip.Dispose()
        }

        foreach ($file in @($stagedFiles)) {
            $hash = Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
            $relativePath = [System.IO.Path]::GetRelativePath($stagingRoot, $file.FullName)
            $artifactHashes += [pscustomobject]@{
                Path   = $relativePath
                Sha256 = $hash.Hash
            }
        }

        $bundleHash = Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256

        $manifest = [pscustomobject]@{
            GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            BundleName      = [System.IO.Path]::GetFileName($bundlePath)
            BundleSha256    = $bundleHash.Hash
            Artifacts       = $artifactHashes
        }

        $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8NoBOM

        [pscustomobject]@{
            BundlePath   = $bundlePath
            ManifestPath = $manifestPath
            BundleSha256 = $bundleHash.Hash
            ArtifactCount= $artifactHashes.Count
        }
    } finally {
        if (Test-Path $stagingRoot) {
            Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

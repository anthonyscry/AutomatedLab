[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $false)]
    [string]$OutputRoot,

    [Parameter(Mandatory = $false)]
    [string]$PreviousTag,

    [Parameter(Mandatory = $false)]
    [string]$PreviousDotNetBundleSha256,

    [Parameter(Mandatory = $false)]
    [switch]$SkipDotNetBundle,

    [Parameter(Mandatory = $false)]
    [ValidateSet('portable', 'legacy')]
    [string]$ArtifactMode = 'portable',

    [Parameter(Mandatory = $false)]
    [string]$GitHubRepo = 'anthonyscry/OpenCodeLab'
)

$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
    return (Resolve-Path $PSScriptRoot).Path
}

function Publish-Artifact {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectDir,
        [Parameter(Mandatory = $true)]
        [string]$OutputDir,
        [Parameter(Mandatory = $true)]
        [bool]$SelfContained
    )

    $selfContainedArg = if ($SelfContained) { 'true' } else { 'false' }
    $publishArgs = @(
        'publish',
        '-c', 'Release',
        '-r', 'win-x64',
        '--self-contained', $selfContainedArg,
        '/p:PublishSingleFile=true',
        '/p:IncludeNativeLibrariesForSelfExtract=true',
        '-o', $OutputDir
    )

    Push-Location $ProjectDir
    try {
        & dotnet @publishArgs
    }
    finally {
        Pop-Location
    }
}

function Assert-NoSatelliteResourceDirectories {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PublishDir,
        [Parameter(Mandatory = $true)]
        [string]$ArtifactLabel
    )

    if (-not (Test-Path $PublishDir)) {
        throw "Publish output not found for ${ArtifactLabel}: $PublishDir"
    }

    $satelliteDirs = Get-ChildItem -Path $PublishDir -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            @(Get-ChildItem -Path $_.FullName -Filter '*.resources.dll' -File -Recurse -ErrorAction SilentlyContinue).Count -gt 0
        } |
        Select-Object -ExpandProperty Name

    if (@($satelliteDirs).Count -gt 0) {
        $dirList = (@($satelliteDirs) | Sort-Object) -join ', '
        throw "Unexpected localized satellite resources found in $ArtifactLabel output: $dirList. Expected English-only payload; verify SatelliteResourceLanguages=en."
    }
}

function Copy-ReleasePayload {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PublishDir,
        [Parameter(Mandatory = $true)]
        [string]$StageDir,
        [Parameter(Mandatory = $true)]
        [string]$SetupScriptPath,
        [Parameter(Mandatory = $true)]
        [string]$RootReadmePath,
        [Parameter(Mandatory = $true)]
        [string]$LabSourcesPath
    )

    if (Test-Path $StageDir) {
        Remove-Item $StageDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $StageDir -Force | Out-Null

    Copy-Item (Join-Path $PublishDir '*') -Destination $StageDir -Recurse -Force
    Copy-Item $SetupScriptPath -Destination $StageDir -Force
    Copy-Item $RootReadmePath -Destination $StageDir -Force

    $stageLabSources = Join-Path $StageDir 'LabSources'
    New-Item -ItemType Directory -Path $stageLabSources -Force | Out-Null

    Get-ChildItem -Path $LabSourcesPath -Recurse -File |
        Where-Object { $_.Extension -ne '.iso' } |
        ForEach-Object {
            $relative = $_.FullName.Substring($LabSourcesPath.Length).TrimStart([char[]]@('\', '/'))
            $target = Join-Path $stageLabSources $relative
            $targetDir = Split-Path $target -Parent
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            Copy-Item $_.FullName -Destination $target -Force
        }
}

function Get-LatestReleaseTag {
    param([string]$Repo)

    try {
        $null = Get-Command gh -ErrorAction Stop
        $json = & gh release list --repo $Repo --limit 1 --json tagName
        if ([string]::IsNullOrWhiteSpace($json)) {
            return $null
        }

        $result = $json | ConvertFrom-Json
        if ($result.Count -eq 0) {
            return $null
        }

        return $result[0].tagName
    }
    catch {
        return $null
    }
}

function Get-PreviousBundleHash {
    param(
        [string]$Repo,
        [string]$Tag
    )

    if ([string]::IsNullOrWhiteSpace($Tag)) {
        return $null
    }

    try {
        $null = Get-Command gh -ErrorAction Stop
        $json = & gh release view $Tag --repo $Repo --json assets
        if ([string]::IsNullOrWhiteSpace($json)) {
            return $null
        }

        $release = $json | ConvertFrom-Json
        $asset = $release.assets |
            Where-Object { $_.name -like '*-dotnet-bundle-win-x64.zip' } |
            Select-Object -First 1

        if (-not $asset) {
            return $null
        }

        if ($asset.digest -and $asset.digest -like 'sha256:*') {
            return ($asset.digest -replace '^sha256:', '')
        }

        return $null
    }
    catch {
        return $null
    }
}

$repoRoot = Get-RepoRoot
$projectDir = Join-Path $repoRoot 'OpenCodeLab-v2'
$labSourcesPath = Join-Path $repoRoot 'LabSources'
$setupScriptPath = Join-Path $repoRoot 'Setup-AutomatedLab.ps1'
$rootReadmePath = Join-Path $repoRoot 'README.md'

if (-not (Test-Path $projectDir)) {
    throw "Project directory not found: $projectDir"
}

if (-not (Test-Path $labSourcesPath)) {
    throw "LabSources directory not found: $labSourcesPath"
}

if (-not (Test-Path $setupScriptPath)) {
    throw "Setup script not found: $setupScriptPath"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot '_release'
}

$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot, $repoRoot)

$normalizedVersion = $Version.TrimStart('v')
$releaseRoot = Join-Path $OutputRoot "v$normalizedVersion"

$publishAppOnly = Join-Path $releaseRoot 'publish-app-only'
$publishDotNetBundle = Join-Path $releaseRoot 'publish-dotnet-bundle'
$publishPortable = Join-Path $releaseRoot 'publish-portable'

$appStageDir = Join-Path $releaseRoot 'app-stage'
$bundleStageDir = Join-Path $releaseRoot 'dotnet-bundle-stage'
$portableStageDir = Join-Path $releaseRoot 'portable-stage'

$appZipPath = Join-Path $OutputRoot "OpenCodeLab-v$normalizedVersion-app-only-win-x64.zip"
$bundleZipPath = Join-Path $OutputRoot "OpenCodeLab-v$normalizedVersion-dotnet-bundle-win-x64.zip"
$portableZipPath = Join-Path $OutputRoot "OpenCodeLab-v$normalizedVersion-portable-win-x64.zip"

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
if (Test-Path $releaseRoot) {
    Remove-Item $releaseRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null

if (Test-Path $appZipPath) { Remove-Item $appZipPath -Force }
if (Test-Path $bundleZipPath) { Remove-Item $bundleZipPath -Force }
if (Test-Path $portableZipPath) { Remove-Item $portableZipPath -Force }

if ($ArtifactMode -eq 'portable') {
    if ($SkipDotNetBundle) {
        Write-Host "-ArtifactMode is 'portable', ignoring -SkipDotNetBundle." -ForegroundColor Yellow
    }

    Write-Host 'Publishing portable artifact (self-contained bundle)...' -ForegroundColor Cyan
    Publish-Artifact -ProjectDir $projectDir -OutputDir $publishPortable -SelfContained:$true
    Assert-NoSatelliteResourceDirectories -PublishDir $publishPortable -ArtifactLabel 'portable'

    Write-Host 'Staging portable payload...' -ForegroundColor Cyan
    Copy-ReleasePayload -PublishDir $publishPortable -StageDir $portableStageDir -SetupScriptPath $setupScriptPath -RootReadmePath $rootReadmePath -LabSourcesPath $labSourcesPath

    Write-Host 'Creating portable archive...' -ForegroundColor Cyan
    Compress-Archive -Path (Join-Path $portableStageDir '*') -DestinationPath $portableZipPath -Force

    $portableHash = (Get-FileHash -Path $portableZipPath -Algorithm SHA256).Hash.ToLowerInvariant()

    $metadata = [pscustomobject]@{
        Version = $normalizedVersion
        ArtifactMode = 'Portable'
        PortableZip = $portableZipPath
        PortableSha256 = $portableHash
        GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }

    $metadataPath = Join-Path $releaseRoot 'artifact-metadata.json'
    $metadata | ConvertTo-Json -Depth 4 | Set-Content -Path $metadataPath -Encoding UTF8

    Write-Host ''
    Write-Host 'Release artifacts created:' -ForegroundColor Green
    Write-Host "- $portableZipPath"
    Write-Host "Portable SHA256: $portableHash" -ForegroundColor Yellow

    Write-Host ''
    Write-Host 'Release notes snippet:' -ForegroundColor Green
    Write-Host "- Portable artifact: OpenCodeLab-v$normalizedVersion-portable-win-x64.zip"
    Write-Host "- Portable SHA256: $portableHash"
    Write-Host '- Locale payload: English-only resources (artifact size optimized)'

    return
}

Write-Host "Publishing app-only artifact (framework-dependent)..." -ForegroundColor Cyan
Publish-Artifact -ProjectDir $projectDir -OutputDir $publishAppOnly -SelfContained:$false
Assert-NoSatelliteResourceDirectories -PublishDir $publishAppOnly -ArtifactLabel 'app-only'

if (-not $SkipDotNetBundle) {
    Write-Host "Publishing .NET bundle artifact (self-contained)..." -ForegroundColor Cyan
    Publish-Artifact -ProjectDir $projectDir -OutputDir $publishDotNetBundle -SelfContained:$true
    Assert-NoSatelliteResourceDirectories -PublishDir $publishDotNetBundle -ArtifactLabel 'dotnet-bundle'
}

Write-Host "Staging app-only payload..." -ForegroundColor Cyan
Copy-ReleasePayload -PublishDir $publishAppOnly -StageDir $appStageDir -SetupScriptPath $setupScriptPath -RootReadmePath $rootReadmePath -LabSourcesPath $labSourcesPath

if (-not $SkipDotNetBundle) {
    Write-Host "Staging .NET bundle payload..." -ForegroundColor Cyan
    Copy-ReleasePayload -PublishDir $publishDotNetBundle -StageDir $bundleStageDir -SetupScriptPath $setupScriptPath -RootReadmePath $rootReadmePath -LabSourcesPath $labSourcesPath
}

Write-Host "Creating release archives..." -ForegroundColor Cyan
Compress-Archive -Path (Join-Path $appStageDir '*') -DestinationPath $appZipPath -Force
if (-not $SkipDotNetBundle) {
    Compress-Archive -Path (Join-Path $bundleStageDir '*') -DestinationPath $bundleZipPath -Force
}

$appHash = (Get-FileHash -Path $appZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$bundleHash = $null
if (-not $SkipDotNetBundle) {
    $bundleHash = (Get-FileHash -Path $bundleZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
}

if ([string]::IsNullOrWhiteSpace($PreviousTag)) {
    $PreviousTag = Get-LatestReleaseTag -Repo $GitHubRepo
    if ($PreviousTag -eq "v$normalizedVersion") {
        $PreviousTag = $null
    }
}

$previousBundleHash = if ([string]::IsNullOrWhiteSpace($PreviousDotNetBundleSha256)) {
    $null
}
else {
    $PreviousDotNetBundleSha256.Trim().ToLowerInvariant()
}
$bundleArtifactChanged = 'Skipped (dotnet bundle not produced)'
if (-not $SkipDotNetBundle) {
    if ([string]::IsNullOrWhiteSpace($previousBundleHash)) {
        $previousBundleHash = Get-PreviousBundleHash -Repo $GitHubRepo -Tag $PreviousTag
    }
    $bundleArtifactChanged = if ([string]::IsNullOrWhiteSpace($previousBundleHash)) {
        'Unknown (no prior dotnet-bundle hash found)'
    }
    elseif ($previousBundleHash -eq $bundleHash) {
        'No'
    }
    else {
        'Yes'
    }
}

$metadata = [pscustomobject]@{
    Version = $normalizedVersion
    DotNetBundleBuilt = (-not $SkipDotNetBundle)
    AppOnlyZip = $appZipPath
    DotNetBundleZip = if ($SkipDotNetBundle) { $null } else { $bundleZipPath }
    AppOnlySha256 = $appHash
    DotNetBundleSha256 = $bundleHash
    PreviousTag = $PreviousTag
    PreviousDotNetBundleSha256 = $previousBundleHash
    DotNetBundleArtifactChanged = $bundleArtifactChanged
    GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
}

$metadataPath = Join-Path $releaseRoot 'artifact-metadata.json'
$metadata | ConvertTo-Json -Depth 4 | Set-Content -Path $metadataPath -Encoding UTF8

Write-Host ''
Write-Host 'Release artifacts created:' -ForegroundColor Green
Write-Host "- $appZipPath"
if (-not $SkipDotNetBundle) {
    Write-Host "- $bundleZipPath"
}
Write-Host ''
Write-Host "App-only SHA256:      $appHash" -ForegroundColor Yellow
if (-not $SkipDotNetBundle) {
    Write-Host "Dotnet-bundle SHA256: $bundleHash" -ForegroundColor Yellow
}
Write-Host "Dotnet-bundle artifact changed: $bundleArtifactChanged" -ForegroundColor Yellow
if ($PreviousTag -and -not $SkipDotNetBundle) {
    Write-Host "Compared against: $PreviousTag" -ForegroundColor DarkGray
}

Write-Host ''
Write-Host 'Release notes snippet:' -ForegroundColor Green
Write-Host "- Dotnet-bundle artifact changed: $bundleArtifactChanged"
if ($SkipDotNetBundle) {
    Write-Host '- Reuse prior runtime bundle: Yes (bundle not rebuilt in this release)'
}
else {
    Write-Host "- Reuse prior runtime bundle: $(if ($bundleArtifactChanged -eq 'No') { 'Yes' } elseif ($bundleArtifactChanged -eq 'Yes') { 'No' } else { 'Review required' })"
}
Write-Host "- App-only SHA256: $appHash"
if (-not $SkipDotNetBundle) {
    Write-Host "- Dotnet-bundle SHA256: $bundleHash"
}
Write-Host '- Locale payload: English-only resources (artifact size optimized)'

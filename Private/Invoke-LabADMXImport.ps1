function Invoke-LabADMXImport {
    <#
    .SYNOPSIS
        Populates the ADMX Central Store and optionally imports third-party ADMX bundles.

    .DESCRIPTION
        Copies ADMX/ADML files from the DC's PolicyDefinitions directory to the
        SYSVOL Central Store. When ThirdPartyADMX entries are present in config,
        also copies ADMX bundles from operator-specified local paths. When
        CreateBaselineGPO is enabled, creates baseline GPOs from JSON templates.

    .PARAMETER DCName
        The domain controller VM name.

    .PARAMETER DomainName
        The Active Directory domain name (e.g., 'simplelab.local').

    .OUTPUTS
        PSCustomObject with FilesImported (int), Success (bool), CentralStorePath (string),
        ThirdPartyBundlesProcessed (int), DurationSeconds (int), Message (string) fields.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DCName,

        [Parameter(Mandatory)]
        [string]$DomainName
    )

    $startTime = Get-Date
    $filesImported = 0
    $thirdPartyBundles = 0
    $message = ''

    # Build Central Store path: \\domain\SYSVOL\domain\Policies\PolicyDefinitions
    $centralStorePath = "\\$DomainName\SYSVOL\$DomainName\Policies\PolicyDefinitions"

    try {
        # Ensure Central Store directory exists
        if (-not (Test-Path $centralStorePath)) {
            New-Item -ItemType Directory -Path $centralStorePath -Force | Out-Null
            Write-Verbose "[Invoke-LabADMXImport] Created Central Store: $centralStorePath"
        }

        # Copy OS ADMX/ADML from DC's PolicyDefinitions to Central Store
        Write-Verbose "[Invoke-LabADMXImport] Copying OS ADMX/ADML from $DCName..."
        $copyResult = Invoke-Command -ComputerName $DCName -ScriptBlock {
            param($centralStorePath)

            $sourcePath = 'C:\Windows\PolicyDefinitions'
            $filesCopied = 0

            # Copy all .admx files from root
            $admxFiles = Get-ChildItem -Path $sourcePath -Filter '*.admx' -ErrorAction SilentlyContinue
            foreach ($file in $admxFiles) {
                $destPath = Join-Path $centralStorePath $file.Name
                Copy-Item -Path $file.FullName -Destination $destPath -Force
                $filesCopied++
            }

            # Copy ADML subdirectories (en-US, etc.)
            $admlDirs = Get-ChildItem -Path $sourcePath -Directory -ErrorAction SilentlyContinue
            foreach ($dir in $admlDirs) {
                $destDir = Join-Path $centralStorePath $dir.Name
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                $admlFiles = Get-ChildItem -Path (Join-Path $sourcePath $dir.Name) -Filter '*.adml' -ErrorAction SilentlyContinue
                foreach ($file in $admlFiles) {
                    Copy-Item -Path $file.FullName -Destination $destDir -Force
                    $filesCopied++
                }
            }

            return $filesCopied
        } -ArgumentList $centralStorePath

        $filesImported += $copyResult
        Write-Verbose "[Invoke-LabADMXImport] Copied $copyResult OS ADMX/ADML files to Central Store"

        # Process third-party ADMX bundles if configured
        $config = Get-LabADMXConfig
        foreach ($bundle in $config.ThirdPartyADMX) {
            $bundleName = $bundle.Name
            $bundlePath = $bundle.Path

            Write-Verbose "[Invoke-LabADMXImport] Processing third-party bundle: $bundleName from $bundlePath"

            # Validate bundle path exists
            if (-not (Test-Path $bundlePath)) {
                Write-Warning "[Invoke-LabADMXImport] Third-party ADMX bundle path not found: $bundlePath. Skipping."
                continue
            }

            # Count .admx files in bundle (validate it has content)
            $admxCount = @(Get-ChildItem -Path $bundlePath -Filter '*.admx' -Recurse -ErrorAction SilentlyContinue).Count
            if ($admxCount -eq 0) {
                Write-Warning "[Invoke-LabADMXImport] Third-party ADMX bundle contains no .admx files: $bundlePath. Skipping."
                continue
            }

            # Copy all ADMX/ADML files from bundle to Central Store
            try {
                # Copy ADMX files (root level)
                $bundleAdmxFiles = Get-ChildItem -Path $bundlePath -Filter '*.admx' -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer }
                foreach ($file in $bundleAdmxFiles) {
                    $destPath = Join-Path $centralStorePath $file.Name
                    Copy-Item -Path $file.FullName -Destination $destPath -Force
                    $filesImported++
                }

                # Copy ADML subdirectories
                $bundleAdmlDirs = Get-ChildItem -Path $bundlePath -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer }
                foreach ($dir in $bundleAdmlDirs) {
                    $destDir = Join-Path $centralStorePath $dir.Name
                    if (-not (Test-Path $destDir)) {
                        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                    }
                    $admlFiles = Get-ChildItem -Path $dir.FullName -Filter '*.adml' -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer }
                    foreach ($file in $admlFiles) {
                        Copy-Item -Path $file.FullName -Destination $destDir -Force
                        $filesImported++
                    }
                }

                $thirdPartyBundles++
                Write-Verbose "[Invoke-LabADMXImport] Imported third-party bundle: $bundleName ($admxCount ADMX files)"
            }
            catch {
                Write-Warning "[Invoke-LabADMXImport] Failed to import third-party bundle $bundleName`: $($_.Exception.Message)"
            }
        }

        # Create baseline GPOs from templates if enabled
        if ($config.CreateBaselineGPO) {
            Write-Verbose "[Invoke-LabADMXImport] Creating baseline GPOs..."

            # Determine repository root (use git rev-parse if available)
            $repoRoot = if (Get-Command -Name git -ErrorAction SilentlyContinue) {
                $gitRoot = & git rev-parse --show-toplevel 2>$null
                if ($gitRoot) { $gitRoot } else { $PSScriptRoot | Split-Path -Parent }
            } else {
                $PSScriptRoot | Split-Path -Parent
            }

            $gpoTemplatePath = Join-Path $repoRoot 'Templates\GPO'

            if (-not (Test-Path $gpoTemplatePath)) {
                Write-Warning "[Invoke-LabADMXImport] GPO template path not found: $gpoTemplatePath. Skipping GPO creation."
            }
            else {
                # Convert domain FQDN to DN for link target
                $domainDN = ConvertTo-DomainDN -DomainFQDN $DomainName
                Write-Verbose "[Invoke-LabADMXImport] Domain DN for GPO links: $domainDN"

                # Get all JSON template files
                $gpoTemplates = Get-ChildItem -Path $gpoTemplatePath -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer }

                foreach ($templateFile in $gpoTemplates) {
                    Write-Verbose "[Invoke-LabADMXImport] Processing GPO template: $($templateFile.Name)"

                    try {
                        # Load JSON template
                        $templateJson = Get-Content $templateFile.FullName -Raw | ConvertFrom-Json

                        $gpoName = $templateJson.Name
                        $linkTarget = if ($templateJson.LinkTarget) {
                            $templateJson.LinkTarget
                        } else {
                            $domainDN  # Use default domain DN if LinkTarget not specified
                        }

                        Write-Verbose "[Invoke-LabADMXImport] Creating GPO: $gpoName"

                        # Create GPO on the DC
                        $gpo = New-GPO -Name $gpoName -ErrorAction Stop

                        # Apply each registry setting from template
                        foreach ($setting in $templateJson.Settings) {
                            $key = $setting.Key
                            $valueName = $setting.ValueName
                            $value = $setting.Value
                            $type = $setting.Type

                            # Remove HKLM\ or HKCU\ prefix for Set-GPRegistryValue (it infers hive from Key content)
                            $keyForGPO = $key -replace '^HK[LMCU]\\', ''

                            $params = @{
                                Name      = $gpoName
                                Key       = $keyForGPO
                                ValueName = $valueName
                                Value     = $value
                                Type      = $type
                            }

                            Set-GPRegistryValue @params -ErrorAction Stop | Out-Null
                            Write-Verbose "[Invoke-LabADMXImport] Applied registry setting: $keyForGPO\$valueName = $value"
                        }

                        # Link GPO to domain root
                        New-GPLink -Name $gpoName -Target $linkTarget -ErrorAction Stop | Out-Null
                        Write-Verbose "[Invoke-LabADMXImport] Linked GPO '$gpoName' to $linkTarget"

                        $filesImported++  # Count GPOs in FilesImported metric
                    }
                    catch {
                        Write-Warning "[Invoke-LabADMXImport] Failed to create GPO from template $($templateFile.Name): $($_.Exception.Message)"
                    }
                }
            }
        }

        $success = $true
    }
    catch {
        $success = $false
        $message = $_.Exception.Message
        Write-Warning "[Invoke-LabADMXImport] Failed to populate ADMX Central Store: $message"
    }

    $duration = [int]((Get-Date) - $startTime).TotalSeconds

    return [pscustomobject]@{
        FilesImported          = $filesImported
        Success                = $success
        CentralStorePath       = $centralStorePath
        ThirdPartyBundlesProcessed = $thirdPartyBundles
        DurationSeconds        = $duration
        Message                = $message
    }
}

# Test-LabPreDeploy.ps1 -- Pre-deploy validation checks
# Run inside Docker: docker compose run validate
# Run locally: pwsh -NoProfile -File Scripts/Test-LabPreDeploy.ps1
# Exit 0 = all clear, Exit 1 = issues found

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = Split-Path -Parent $scriptDir

$checks = @()
$failed = 0

# Check 1: PowerShell syntax validation
Write-Host "`n[CHECK 1] PowerShell syntax validation..." -ForegroundColor Cyan
$syntaxErrors = @()
Get-ChildItem -Path $repoRoot -Filter '*.ps1' -Recurse |
    Where-Object { $_.FullName -notlike '*\.archive\*' -and $_.FullName -notlike '*LabBuilder\Roles\*' -and $_.FullName -notlike '*LabBuilder/Roles/*' } |
    ForEach-Object {
        $tokens = $null
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) {
            $syntaxErrors += [pscustomobject]@{
                File = $_.FullName.Replace($repoRoot, '.')
                Errors = $errors.Count
                First = $errors[0].Message
            }
        }
    }

if ($syntaxErrors.Count -eq 0) {
    Write-Host "  PASS: All .ps1 files parse without errors" -ForegroundColor Green
    $checks += [pscustomobject]@{ Name = 'Syntax'; Status = 'Pass'; Message = 'All files clean' }
} else {
    Write-Host "  FAIL: $($syntaxErrors.Count) file(s) have syntax errors:" -ForegroundColor Red
    foreach ($err in $syntaxErrors) {
        Write-Host "    $($err.File): $($err.First)" -ForegroundColor Yellow
    }
    $checks += [pscustomobject]@{ Name = 'Syntax'; Status = 'Fail'; Message = "$($syntaxErrors.Count) files with errors" }
    $failed++
}

# Check 2: Lab-Config.ps1 loads without error
Write-Host "`n[CHECK 2] Lab-Config.ps1 loading..." -ForegroundColor Cyan
$configPath = Join-Path $repoRoot 'Lab-Config.ps1'
try {
    # Lab-Config.ps1 sets ErrorActionPreference='Stop' and uses Join-Path with Windows paths
    # that fail on Linux containers. Dot-source it, then check if GlobalLabConfig was populated.
    try { . $configPath } catch {
        # Path resolution errors (C:\ doesn't exist on Linux) are expected in containers
        if (-not (Test-Path variable:GlobalLabConfig)) { throw $_ }
    }
    $ErrorActionPreference = 'Continue'

    $requiredKeys = @('Lab', 'Network', 'Credentials', 'VMSizing')
    $missingKeys = $requiredKeys | Where-Object { -not $GlobalLabConfig.ContainsKey($_) }
    if ($missingKeys.Count -eq 0) {
        Write-Host "  PASS: GlobalLabConfig has all required sections" -ForegroundColor Green
        $checks += [pscustomobject]@{ Name = 'Config'; Status = 'Pass'; Message = 'Config valid' }
    } else {
        Write-Host "  FAIL: Missing config sections: $($missingKeys -join ', ')" -ForegroundColor Red
        $checks += [pscustomobject]@{ Name = 'Config'; Status = 'Fail'; Message = "Missing: $($missingKeys -join ', ')" }
        $failed++
    }
} catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $checks += [pscustomobject]@{ Name = 'Config'; Status = 'Fail'; Message = $_.Exception.Message }
    $failed++
}

# Check 3: Module manifest validity
Write-Host "`n[CHECK 3] Module manifest..." -ForegroundColor Cyan
$manifestPath = Join-Path $repoRoot 'SimpleLab.psd1'
try {
    $manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
    Write-Host "  PASS: SimpleLab v$($manifest.Version) manifest valid" -ForegroundColor Green
    $checks += [pscustomobject]@{ Name = 'Manifest'; Status = 'Pass'; Message = "v$($manifest.Version)" }
} catch {
    Write-Host "  FAIL: $($_.Exception.Message)" -ForegroundColor Red
    $checks += [pscustomobject]@{ Name = 'Manifest'; Status = 'Fail'; Message = $_.Exception.Message }
    $failed++
}

# Check 4: VM naming consistency
Write-Host "`n[CHECK 4] VM naming consistency..." -ForegroundColor Cyan
$deployPath = Join-Path $repoRoot 'Deploy.ps1'
$deployContent = Get-Content $deployPath -Raw
$deployVMNames = @()
[regex]::Matches($deployContent, "Add-LabMachineDefinition\s+-Name\s+'([^']+)'") | ForEach-Object {
    $deployVMNames += $_.Groups[1].Value
}
$configVMNames = @($GlobalLabConfig.Lab.CoreVMNames)
$missingInConfig = $deployVMNames | Where-Object { $_ -notin $configVMNames }
$missingInDeploy = $configVMNames | Where-Object { $_ -notin $deployVMNames }

if ($missingInConfig.Count -eq 0 -and $missingInDeploy.Count -eq 0) {
    Write-Host "  PASS: Deploy.ps1 VM names match CoreVMNames" -ForegroundColor Green
    $checks += [pscustomobject]@{ Name = 'VMNaming'; Status = 'Pass'; Message = 'Names consistent' }
} else {
    $msg = @()
    if ($missingInConfig.Count -gt 0) { $msg += "In Deploy but not config: $($missingInConfig -join ', ')" }
    if ($missingInDeploy.Count -gt 0) { $msg += "In config but not Deploy: $($missingInDeploy -join ', ')" }
    Write-Host "  WARN: $($msg -join '; ')" -ForegroundColor Yellow
    $checks += [pscustomobject]@{ Name = 'VMNaming'; Status = 'Warn'; Message = ($msg -join '; ') }
}

# Check 5: Default password detection
Write-Host "`n[CHECK 5] Default password check..." -ForegroundColor Cyan
if ($GlobalLabConfig.Credentials.AdminPassword -eq 'SimpleLab123!') {
    Write-Host "  WARN: AdminPassword is set to the default value" -ForegroundColor Yellow
    $checks += [pscustomobject]@{ Name = 'Password'; Status = 'Warn'; Message = 'Default password in use' }
} else {
    Write-Host "  PASS: AdminPassword is not the default" -ForegroundColor Green
    $checks += [pscustomobject]@{ Name = 'Password'; Status = 'Pass'; Message = 'Custom password set' }
}

# Summary
Write-Host ("`n" + ("=" * 50)) -ForegroundColor Gray
$passCount = ($checks | Where-Object Status -eq 'Pass').Count
$failCount = ($checks | Where-Object Status -eq 'Fail').Count
$warnCount = ($checks | Where-Object Status -eq 'Warn').Count
Write-Host "Results: $passCount passed, $failCount failed, $warnCount warnings" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Green' })

exit $failed

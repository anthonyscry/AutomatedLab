function Convert-LabArgumentArrayToSplat {
    [CmdletBinding()]
    param([string[]]$ArgumentList)

    $splat = @{}
    for ($i = 0; $i -lt $ArgumentList.Count; $i++) {
        $token = $ArgumentList[$i]
        if (-not $token.StartsWith('-')) {
            throw "Unsupported argument token '$token'. Use named parameters (for example -NonInteractive)."
        }

        $name = $token.TrimStart('-')
        if ([string]::IsNullOrWhiteSpace($name)) {
            throw "Invalid argument token '$token'."
        }

        $nextIsValue = ($i + 1 -lt $ArgumentList.Count) -and (-not $ArgumentList[$i + 1].StartsWith('-'))
        if ($nextIsValue) {
            $splat[$name] = $ArgumentList[$i + 1]
            $i++
        } else {
            $splat[$name] = $true
        }
    }

    return $splat
}

FROM mcr.microsoft.com/powershell:lts-alpine

# Install Pester test framework
RUN pwsh -NoProfile -Command "Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope AllUsers"

WORKDIR /app

# Pre-create writable directories needed by tests (repo is mounted read-only)
RUN mkdir -p /app/.planning/runs /app/Tests/results

# Default: run Pester test suite with JUnit XML output
CMD ["pwsh", "-NoProfile", "-Command", "$c = New-PesterConfiguration; $c.Run.Path = './Tests'; $c.TestResult.Enabled = $true; $c.TestResult.OutputPath = './Tests/results/testResults.xml'; $c.TestResult.OutputFormat = 'JUnitXml'; $c.Output.Verbosity = 'Detailed'; Invoke-Pester -Configuration $c; exit $LASTEXITCODE"]

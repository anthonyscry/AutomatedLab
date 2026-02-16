FROM mcr.microsoft.com/powershell:lts-alpine

# Install Pester test framework
RUN pwsh -NoProfile -Command "Install-Module -Name Pester -MinimumVersion 5.0.0 -Force -Scope AllUsers"

WORKDIR /app

# Default: run Pester test suite
CMD ["pwsh", "-NoProfile", "-Command", "Invoke-Pester -Path ./Tests -OutputFormat JUnitXml -OutputPath ./Tests/results/testResults.xml -Output Detailed; exit $LASTEXITCODE"]

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using OpenCodeLab.Models;

namespace OpenCodeLab.Services;

public class LabDeploymentService
{
    public event EventHandler<DeploymentProgressArgs>? Progress;

    private const string AutomatedLabModulePath = @"C:\Program Files\WindowsPowerShell\Modules\AutomatedLab";
    private const string LabSourcesRoot = @"C:\LabSources";
    private const string PasswordEnvVar = "OPENCODELAB_ADMIN_PASSWORD";

    public async Task<bool> DeployLabAsync(LabConfig config, Action<string>? log = null)
    {
        try
        {
            Report(0, "Starting deployment...", log);

            // Validate inputs to prevent command injection
            if (!ValidateConfigInputs(config, log))
            {
                log?.Invoke("Invalid configuration. Please check VM names and network settings.");
                return false;
            }

            // Determine the working directory for VMs
            string workingDir = GetWorkingDirectory(config);
            Directory.CreateDirectory(workingDir);

            // Verify AutomatedLab module is installed
            Report(5, "Checking AutomatedLab module...", log);
            if (!IsAutomatedLabInstalled(log))
            {
                log?.Invoke("AutomatedLab module not found. Please install: Install-Module AutomatedLab -Force -Scope CurrentUser");
                return false;
            }

            // Import AutomatedLab and deploy using its cmdlets
            Report(10, "Importing AutomatedLab module...", log);
            var result = await InvokeAutomatedLabDeployAsync(config, workingDir, log);

            Report(100, "Deployment complete!", log);
            return result;
        }
        catch (Exception ex)
        {
            log?.Invoke($"Deployment failed: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> RemoveLabAsync(LabConfig config, Action<string>? log)
    {
        try
        {
            Report(0, "Removing lab...", log);

            // Validate inputs to prevent command injection
            if (!ValidateConfigInputs(config, log))
            {
                log?.Invoke("Invalid configuration for removal.");
                return false;
            }

            // Use PowerShell to remove VMs via AutomatedLab
            var script = new StringBuilder();
            script.AppendLine("Import-Module AutomatedLab -ErrorAction SilentlyContinue");
            script.AppendLine("Import-Module Hyper-V -ErrorAction SilentlyContinue");

            // Remove lab definition if it exists
            script.AppendLine($"$lab = Get-Lab -Name '{EscapePowerShellString(config.LabName)}' -ErrorAction SilentlyContinue");
            script.AppendLine("if ($lab) {");
            script.AppendLine($"  Write-Host 'Removing lab definition: {config.LabName}'");
            script.AppendLine($"  Remove-Lab -Name '{EscapePowerShellString(config.LabName)}' -Confirm:$false -ErrorAction SilentlyContinue");
            script.AppendLine("}");

            // Also remove any orphaned VMs
            foreach (var vm in config.VMs)
            {
                var safeVmName = EscapePowerShellString(vm.Name);
                script.AppendLine($"$vm = Get-VM -Name '{safeVmName}' -ErrorAction SilentlyContinue");
                script.AppendLine("if ($vm) {");
                script.AppendLine($"  Write-Host \"Stopping {safeVmName}...\"");
                script.AppendLine($"  Stop-VM -Name '{safeVmName}' -TurnOff -Force -ErrorAction SilentlyContinue");
                script.AppendLine($"  Write-Host \"Removing {safeVmName}...\"");
                script.AppendLine($"  Remove-VM -Name '{safeVmName}' -Force -ErrorAction SilentlyContinue");
                script.AppendLine("}");
            }

            var result = await RunPowerShellAsync(script.ToString(), log);
            Report(100, "Lab removed!", log);
            return result.Success;
        }
        catch (Exception ex)
        {
            log?.Invoke($"Removal failed: {ex.Message}");
            return false;
        }
    }

    private string GetWorkingDirectory(LabConfig config)
    {
        if (string.IsNullOrEmpty(config.LabPath))
            return LabSourcesRoot;

        if (config.LabPath.EndsWith(".json", StringComparison.OrdinalIgnoreCase))
            return Path.GetDirectoryName(config.LabPath) ?? LabSourcesRoot;

        return config.LabPath;
    }

    private bool IsAutomatedLabInstalled(Action<string>? log)
    {
        try
        {
            if (!Directory.Exists(AutomatedLabModulePath))
            {
                var userModulePath = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                    @"Documents\WindowsPowerShell\Modules\AutomatedLab");
                if (!Directory.Exists(userModulePath))
                {
                    log?.Invoke("AutomatedLab module not found in system or user module directories.");
                    return false;
                }
            }
            return true;
        }
        catch
        {
            return false;
        }
    }

    private async Task<bool> InvokeAutomatedLabDeployAsync(LabConfig config, string workingDir, Action<string>? log)
    {
        var script = BuildAutomatedLabScript(config, workingDir);
        var result = await RunPowerShellAsync(script, log);
        return result.Success;
    }

    private string BuildAutomatedLabScript(LabConfig config, string workingDir)
    {
        var script = new StringBuilder();
        script.AppendLine("$ErrorActionPreference = 'Stop'");
        script.AppendLine();

        // Import AutomatedLab
        script.AppendLine("Write-Host 'Importing AutomatedLab module...'");
        script.AppendLine("Import-Module AutomatedLab -ErrorAction Stop");
        script.AppendLine("Import-Module Hyper-V -ErrorAction SilentlyContinue");
        script.AppendLine();

        // Set lab sources location
        script.AppendLine($"Write-Host 'Setting lab sources location: {workingDir}'");
        script.AppendLine($"Set-LabSourcesLocation -Path '{workingDir.Replace("\\", "\\\\")}' -ErrorAction SilentlyContinue");
        script.AppendLine();

        // Create lab definition
        var safeLabName = EscapePowerShellString(config.LabName);
        script.AppendLine($"Write-Host 'Creating lab definition: {safeLabName}'");
        script.AppendLine($"New-LabDefinition -Name '{safeLabName}' -DefaultVirtualizationEngine HyperV");
        script.AppendLine();

        // Set up network
        var safeSwitchName = EscapePowerShellString(config.Network.SwitchName);
        script.AppendLine($"Write-Host 'Setting up virtual switch: {safeSwitchName}'");
        script.AppendLine($"$switch = Get-VMSwitch -Name '{safeSwitchName}' -ErrorAction SilentlyContinue");
        script.AppendLine("if (-not $switch) {");
        script.AppendLine($"  Write-Host 'Creating virtual switch: {safeSwitchName}'");
        script.AppendLine($"  New-VMSwitch -Name '{safeSwitchName}' -SwitchType {config.Network.SwitchType} -ErrorAction Stop");
        script.AppendLine("} else {");
        script.AppendLine($"  Write-Host 'Switch already exists: {safeSwitchName}'");
        script.AppendLine("}");
        script.AppendLine();

        // Add virtual network definition to AutomatedLab
        var addressSpace = "192.168.10.0/24";
        script.AppendLine($"Add-LabVirtualNetworkDefinition -Name '{safeSwitchName}' -AddressSpace {addressSpace}");
        script.AppendLine();

        // Add domain definition (if we have a DC role)
        var dcVM = config.VMs.FirstOrDefault(v => v.Role.Contains("DC", StringComparison.OrdinalIgnoreCase));
        string domainName = config.DomainName ?? "contoso.com";

        // Password will be passed via environment variable
        string adminUser = "Administrator";

        if (dcVM != null)
        {
            script.AppendLine($"Write-Host 'Adding domain definition: {domainName}'");
            script.AppendLine($"if ($env:OPENCODELAB_ADMIN_PASSWORD) {{");
            script.AppendLine($"  Add-LabDomainDefinition -Name {domainName} -AdminUser {adminUser} -AdminPassword $env:OPENCODELAB_ADMIN_PASSWORD");
            script.AppendLine($"  Set-LabInstallationCredential -Username {adminUser} -Password $env:OPENCODELAB_ADMIN_PASSWORD");
            script.AppendLine("} else {");
            script.AppendLine("  Write-Error 'Admin password not set. Please set OPENCODELAB_ADMIN_PASSWORD environment variable or provide password in the GUI.'");
            script.AppendLine("  exit 1");
            script.AppendLine("}");
            script.AppendLine();
        }

        // Add machine definitions
        script.AppendLine("Write-Host 'Adding machine definitions...'");
        foreach (var vm in config.VMs)
        {
            var safeVmName = EscapePowerShellString(vm.Name);
            var vmParams = new StringBuilder();
            vmParams.Append($"-Name '{safeVmName}' ");
            vmParams.Append($"-Memory {vm.MemoryGB}GB ");
            vmParams.Append($"-ProcessorCount {vm.Processors} ");

            // Network
            var safeSwitch = EscapePowerShellString(vm.SwitchName ?? config.Network.SwitchName);
            vmParams.Append($"-Network '{safeSwitch}' ");

            // Operating System
            string osType = vm.Role.Contains("DC", StringComparison.OrdinalIgnoreCase) ||
                           vm.Role.Contains("Server", StringComparison.OrdinalIgnoreCase)
                ? "Windows Server 2022 Datacenter Evaluation (Desktop Experience)"
                : "Windows 11 Pro";
            vmParams.Append($"-OperatingSystem '{osType}' ");

            // Domain (if DC exists)
            if (dcVM != null)
            {
                vmParams.Append($"-DomainName {domainName} ");
            }

            // Roles for AutomatedLab
            var roles = GetAutomatedLabRoles(vm);
            if (roles.Count > 0)
            {
                var rolesList = string.Join("', '", roles);
                vmParams.Append($"-Roles @('{rolesList}') ");
            }
            else
            {
                // Warn about unrecognized roles
                script.AppendLine($"Write-Host '  [WARN] Unrecognized role: {vm.Role} for VM {safeVmName} - deploying without specific roles'");
            }

            script.AppendLine($"Write-Host '  Adding: {safeVmName} ({vm.Role})'");
            script.AppendLine($"Add-LabMachineDefinition {vmParams}");
        }
        script.AppendLine();

        // Install the lab
        script.AppendLine("Write-Host 'Installing lab (this will take 15-45 minutes)...'");
        script.AppendLine("Install-Lab -ErrorAction Stop");
        script.AppendLine();

        // Create checkpoint
        script.AppendLine("Write-Host 'Creating LabReady checkpoint...'");
        script.AppendLine("foreach ($vm in (Get-LabVM)) {");
        script.AppendLine("  Checkpoint-LabVM -VMName $vm.Name -SnapshotName 'LabReady' -ErrorAction SilentlyContinue");
        script.AppendLine("  Write-Host \"Checkpoint created: $($vm.Name)\"");
        script.AppendLine("}");
        script.AppendLine();

        script.AppendLine("Write-Host 'Deployment complete!'");
        return script.ToString();
    }

    private List<string> GetAutomatedLabRoles(VMDefinition vm)
    {
        var roles = new List<string>();

        // Map our role names to AutomatedLab built-in roles
        if (vm.Role.Contains("DC", StringComparison.OrdinalIgnoreCase))
        {
            roles.Add("RootDC");
            roles.Add("CaRoot");
        }
        if (vm.Role.Contains("DHCP", StringComparison.OrdinalIgnoreCase))
            roles.Add("DHCP");
        if (vm.Role.Contains("DNS", StringComparison.OrdinalIgnoreCase))
            roles.Add("DNS");
        if (vm.Role.Contains("FileServer", StringComparison.OrdinalIgnoreCase) ||
            vm.Role.Contains("FS", StringComparison.OrdinalIgnoreCase))
            roles.Add("FileServer");
        if (vm.Role.Contains("WebServer", StringComparison.OrdinalIgnoreCase) ||
            vm.Role.Contains("WEB", StringComparison.OrdinalIgnoreCase))
            roles.Add("WebServer");
        if (vm.Role.Contains("SQL", StringComparison.OrdinalIgnoreCase))
            roles.Add("SQLServer");

        return roles;
    }

    private string GetAdminPassword()
    {
        // Try to get password from environment variable
        var envPassword = Environment.GetEnvironmentVariable(PasswordEnvVar);
        if (!string.IsNullOrEmpty(envPassword))
            return envPassword;

        // Return empty - user will be prompted via GUI
        return string.Empty;
    }

    private async Task<PowerShellResult> RunPowerShellAsync(string script, Action<string>? log)
    {
        return await Task.Run(() =>
        {
            string tempScript = null;
            try
            {
                // Set password environment variable for the script
                var envPassword = GetAdminPassword();
                var startInfo = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true
                };

                // Set environment variables for the process
                if (!string.IsNullOrEmpty(envPassword))
                {
                    startInfo.Environment[PasswordEnvVar] = envPassword;
                }

                // Write script to temp file
                tempScript = Path.Combine(Path.GetTempPath(), $"lab-deploy-{Guid.NewGuid():N}.ps1");
                File.WriteAllText(tempScript, script, Encoding.UTF8);
                startInfo.Arguments = $"-ExecutionPolicy Bypass -File \"{tempScript}\"";

                using var process = Process.Start(startInfo);
                var output = new StringBuilder();

                // Read output asynchronously
                var stdoutTask = Task.Run(() => {
                    string line;
                    while ((line = process.StandardOutput.ReadLine()) != null)
                    {
                        output.AppendLine(line);
                        log?.Invoke(line);
                    }
                });

                var stderrTask = Task.Run(() => {
                    string line;
                    while ((line = process.StandardError.ReadLine()) != null)
                    {
                        output.AppendLine($"ERROR: {line}");
                        log?.Invoke($"ERROR: {line}");
                    }
                });

                process.WaitForExit();
                Task.WaitAll(stdoutTask, stderrTask);

                // Check exit code for proper error detection
                int exitCode = process.ExitCode;
                bool success = exitCode == 0;

                if (!success)
                {
                    log?.Invoke($"PowerShell exited with code: {exitCode}");
                }

                return new PowerShellResult
                {
                    Output = output.ToString(),
                    ExitCode = exitCode,
                    Success = success && !output.ToString().Contains("error", StringComparison.OrdinalIgnoreCase)
                };
            }
            catch (Exception ex)
            {
                var error = $"PowerShell execution failed: {ex.Message}";
                log?.Invoke(error);
                return new PowerShellResult { Output = error, Success = false, ExitCode = -1 };
            }
            finally
            {
                // Clean up temp file
                try { if (tempScript != null) File.Delete(tempScript); } catch { }
            }
        });
    }

    private bool ValidateConfigInputs(LabConfig config, Action<string>? log)
    {
        // Validate lab name (allow alphanumeric, hyphen, underscore, spaces)
        var validLabName = Regex.IsMatch(config.LabName, @"^[a-zA-Z0-9\-_\s]+$");
        if (!validLabName)
        {
            log?.Invoke($"Invalid lab name: {config.LabName}");
            return false;
        }

        // Validate switch name
        var validSwitch = Regex.IsMatch(config.Network.SwitchName, @"^[a-zA-Z0-9\-_]+$");
        if (!validSwitch)
        {
            log?.Invoke($"Invalid switch name: {config.Network.SwitchName}");
            return false;
        }

        // Validate VM names
        foreach (var vm in config.VMs)
        {
            var validVmName = Regex.IsMatch(vm.Name, @"^[a-zA-Z0-9\-_]+$");
            if (!validVmName)
            {
                log?.Invoke($"Invalid VM name: {vm.Name}");
                return false;
            }

            // Validate switch name in VM if present
            if (!string.IsNullOrEmpty(vm.SwitchName))
            {
                var validVmSwitch = Regex.IsMatch(vm.SwitchName, @"^[a-zA-Z0-9\-_]+$");
                if (!validVmSwitch)
                {
                    log?.Invoke($"Invalid VM switch name: {vm.SwitchName}");
                    return false;
                }
            }
        }

        return true;
    }

    private string EscapePowerShellString(string input)
    {
        if (string.IsNullOrEmpty(input))
            return string.Empty;

        // Escape single quotes by doubling them (PowerShell escape mechanism)
        return input.Replace("'", "''");
    }

    private void Report(int pct, string msg, Action<string>? log)
    {
        Progress?.Invoke(this, new DeploymentProgressArgs(pct, msg));
        log?.Invoke(msg);
    }
}

public class DeploymentProgressArgs : EventArgs
{
    public int Percent { get; }
    public string Message { get; }
    public DeploymentProgressArgs(int pct, string msg)
    {
        Percent = pct;
        Message = msg;
    }
}

internal class PowerShellResult
{
    public string Output { get; set; } = string.Empty;
    public int ExitCode { get; set; }
    public bool Success { get; set; }
}

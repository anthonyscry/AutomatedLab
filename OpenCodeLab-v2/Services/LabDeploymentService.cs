using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using OpenCodeLab.Models;

namespace OpenCodeLab.Services;

public class LabDeploymentService
{
    public event EventHandler<DeploymentProgressArgs>? Progress;

    private const string AutomatedLabModulePath = @"C:\Program Files\WindowsPowerShell\Modules\AutomatedLab";
    private const string LabSourcesRoot = @"C:\LabSources";

    public async Task<bool> DeployLabAsync(LabConfig config, Action<string>? log = null)
    {
        try
        {
            Report(0, "Starting deployment...", log);

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

            // Use PowerShell to remove VMs
            var script = new StringBuilder();
            script.AppendLine("Import-Module Hyper-V -ErrorAction SilentlyContinue");

            foreach (var vm in config.VMs)
            {
                script.AppendLine($"$vm = Get-VM -Name '{vm.Name}' -ErrorAction SilentlyContinue");
                script.AppendLine("if ($vm) {");
                script.AppendLine($"  Write-Host \"Stopping {vm.Name}...\"");
                script.AppendLine($"  Stop-VM -Name '{vm.Name}' -TurnOff -Force -ErrorAction SilentlyContinue");
                script.AppendLine($"  Write-Host \"Removing {vm.Name}...\"");
                script.AppendLine($"  Remove-VM -Name '{vm.Name}' -Force -ErrorAction SilentlyContinue");
                script.AppendLine("}");
            }

            await RunPowerShellAsync(script.ToString(), log);
            Report(100, "Lab removed!", log);
            return true;
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
            // Check if module directory exists
            if (!Directory.Exists(AutomatedLabModulePath))
            {
                // Also check user module path
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
        var output = await RunPowerShellAsync(script, log);

        // Check for common failure indicators in output
        if (output.Contains("error", StringComparison.OrdinalIgnoreCase) &&
            output.Contains("failed", StringComparison.OrdinalIgnoreCase))
        {
            log?.Invoke("Deployment may have failed. Check logs above.");
            return false;
        }

        return true;
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

        // Create lab definition
        script.AppendLine($"Write-Host 'Creating lab definition: {config.LabName}'");
        script.AppendLine($"New-LabDefinition -Name '{config.LabName}' -DefaultVirtualizationEngine HyperV -VmPath '{workingDir}'");
        script.AppendLine();

        // Set up network
        script.AppendLine($"Write-Host 'Setting up virtual switch: {config.Network.SwitchName}'");
        script.AppendLine($"$switch = Get-VMSwitch -Name '{config.Network.SwitchName}' -ErrorAction SilentlyContinue");
        script.AppendLine("if (-not $switch) {");
        script.AppendLine($"  Write-Host 'Creating virtual switch: {config.Network.SwitchName}'");
        script.AppendLine($"  New-VMSwitch -Name '{config.Network.SwitchName}' -SwitchType {config.Network.SwitchType} -ErrorAction Stop");
        script.AppendLine("} else {");
        script.AppendLine($"  Write-Host 'Switch already exists: {config.Network.SwitchName}'");
        script.AppendLine("}");
        script.AppendLine();

        // Add virtual network definition to AutomatedLab
        var addressSpace = "192.168.10.0/24"; // Default, could be configurable
        script.AppendLine($"Add-LabVirtualNetworkDefinition -Name '{config.Network.SwitchName}' -AddressSpace {addressSpace}");
        script.AppendLine();

        // Add domain definition (if we have a DC role)
        var dcVM = config.VMs.FirstOrDefault(v => v.Role.Contains("DC", StringComparison.OrdinalIgnoreCase));
        string domainName = "contoso.com"; // Default, could be made configurable
        if (dcVM != null)
        {
            string adminUser = "Administrator";
            script.AppendLine($"Write-Host 'Adding domain definition: {domainName}'");
            script.AppendLine($"Add-LabDomainDefinition -Name {domainName} -AdminUser {adminUser} -AdminPassword 'P@ssw0rd'");
            script.AppendLine($"Set-LabInstallationCredential -Username {adminUser} -Password 'P@ssw0rd'");
            script.AppendLine();
        }

        // Add machine definitions
        script.AppendLine("Write-Host 'Adding machine definitions...'");
        foreach (var vm in config.VMs)
        {
            var vmParams = new StringBuilder();
            vmParams.Append($"-Name '{vm.Name}' ");
            vmParams.Append($"-Memory {vm.MemoryGB}GB ");
            vmParams.Append($"-ProcessorCount {vm.Processors} ");

            // Network
            vmParams.Append($"-Network '{vm.SwitchName ?? config.Network.SwitchName}' ");

            // Operating System - use Server OS for DC roles, Client OS otherwise
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

            script.AppendLine($"Write-Host '  Adding: {vm.Name} ({vm.Role})'");
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

    private async Task<string> RunPowerShellAsync(string script, Action<string>? log)
    {
        return await Task.Run(() =>
        {
            try
            {
                // Write script to temp file for complex scripts
                var tempScript = Path.Combine(Path.GetTempPath(), $"lab-deploy-{Guid.NewGuid():N}.ps1");
                File.WriteAllText(tempScript, script, Encoding.UTF8);

                var psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = $"-ExecutionPolicy Bypass -File \"{tempScript}\"",
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true
                };

                using var process = Process.Start(psi);
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

                // Clean up temp file
                try { File.Delete(tempScript); } catch { }

                return output.ToString();
            }
            catch (Exception ex)
            {
                var error = $"PowerShell execution failed: {ex.Message}";
                log?.Invoke(error);
                return error;
            }
        });
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

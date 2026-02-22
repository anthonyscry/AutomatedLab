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
                log?.Invoke("AutomatedLab module not found!");
                log?.Invoke("Please install AutomatedLab from the included MSI:");
                log?.Invoke($"  {Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "AutomatedLab.msi")}");
                log?.Invoke("Or run: Install-Module AutomatedLab -Force -Scope CurrentUser");
                return false;
            }

            // Clean up any previous deployment lock
            try
            {
                var lockFile = @"C:\ProgramData\AutomatedLab\LabDiskDeploymentInProgress.txt";
                if (File.Exists(lockFile))
                {
                    log?.Invoke("Removing previous deployment lock file...");
                    File.Delete(lockFile);
                }
            }
            catch (Exception ex)
            {
                log?.Invoke($"Warning: Could not remove lock file: {ex.Message}");
            }

            // Clean up orphaned disk files
            try
            {
                log?.Invoke("Checking for orphaned VM disks...");
                foreach (var vm in config.VMs)
                {
                    var diskPath = Path.Combine(workingDir, vm.Name, $"{vm.Name}.vhdx");
                    if (File.Exists(diskPath))
                    {
                        log?.Invoke($"  Removing orphaned disk: {diskPath}");
                        File.Delete(diskPath);
                    }
                }
            }
            catch (Exception ex)
            {
                log?.Invoke($"Warning: Could not clean up disks: {ex.Message}");
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

        // Import Hyper-V module directly - no need for AutomatedLab's complex OS detection
        script.AppendLine("Write-Host 'Importing Hyper-V module...'");
        script.AppendLine("Import-Module Hyper-V -ErrorAction Stop");
        script.AppendLine();

        // Set up network - create virtual switch if needed
        var safeSwitchName = EscapePowerShellString(config.Network.SwitchName);
        script.AppendLine($"Write-Host 'Setting up virtual switch: {safeSwitchName}'");
        script.AppendLine($"$switch = Get-VMSwitch -Name '{safeSwitchName}' -ErrorAction SilentlyContinue");
        script.AppendLine("if (-not $switch) {");
        script.AppendLine($"  Write-Host 'Creating virtual switch: {safeSwitchName}'");
        script.AppendLine($"  New-VMSwitch -Name '{safeSwitchName}' -SwitchType {config.Network.SwitchType} -ErrorAction Stop | Out-Null");
        script.AppendLine("  Write-Host '  Switch created successfully'");
        script.AppendLine("} else {");
        script.AppendLine($"  Write-Host '  Switch already exists: {safeSwitchName}'");
        script.AppendLine("}");
        script.AppendLine();

        // Find ISOs
        script.AppendLine("Write-Host 'Locating ISO files...'");
        script.AppendLine($"$isosPath = '{LabSourcesRoot}\\ISOs'");
        script.AppendLine("if (-not (Test-Path $isosPath)) {");
        script.AppendLine($"    Write-Error 'ISO folder not found: {LabSourcesRoot}\\ISOs'");
        script.AppendLine("    exit 1");
        script.AppendLine("}");
        script.AppendLine();
        script.AppendLine("# Find Server and Client ISOs");
        script.AppendLine("$serverIso = Get-ChildItem $isosPath -Filter '*Server*.iso' -ErrorAction SilentlyContinue | ");
        script.AppendLine("    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName");
        script.AppendLine("$clientIso = Get-ChildItem $isosPath -Filter '*Windows*.iso' -ErrorAction SilentlyContinue | ");
        script.AppendLine("    Where-Object { $_.Name -notlike '*Server*' } | ");
        script.AppendLine("    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName");
        script.AppendLine();
        script.AppendLine("if (-not $serverIso) { Write-Error 'No Server ISO found in C:\\LabSources\\ISOs'; exit 1 }");
        script.AppendLine("if (-not $clientIso) { Write-Error 'No Client Windows ISO found in C:\\LabSources\\ISOs'; exit 1 }");
        script.AppendLine();
        script.AppendLine("Write-Host \"  Server ISO: $(Split-Path $serverIso -Leaf)\"");
        script.AppendLine("Write-Host \"  Client ISO: $(Split-Path $clientIso -Leaf)\"");
        script.AppendLine();

        // Create VMs directly with Hyper-V cmdlets - simplest approach
        script.AppendLine("Write-Host 'Creating virtual machines...'");
        script.AppendLine();

        foreach (var vm in config.VMs)
        {
            var safeVmName = EscapePowerShellString(vm.Name);
            var safeSwitch = EscapePowerShellString(vm.SwitchName ?? config.Network.SwitchName);

            // Determine which ISO to use
            bool isServerRole = vm.Role.Contains("DC", StringComparison.OrdinalIgnoreCase) ||
                vm.Role.Contains("Server", StringComparison.OrdinalIgnoreCase) ||
                vm.Role.Contains("FileServer", StringComparison.OrdinalIgnoreCase) ||
                vm.Role.Contains("WebServer", StringComparison.OrdinalIgnoreCase) ||
                vm.Role.Contains("SQL", StringComparison.OrdinalIgnoreCase) ||
                vm.Role.Contains("DHCP", StringComparison.OrdinalIgnoreCase) ||
                vm.Role.Contains("DNS", StringComparison.OrdinalIgnoreCase) ||
                vm.Role.Contains("MemberServer", StringComparison.OrdinalIgnoreCase);

            var isoVar = isServerRole ? "$serverIso" : "$clientIso";
            var osType = isServerRole ? "Server" : "Client";

            script.AppendLine($"# VM: {vm.Name} ({osType})");
            script.AppendLine($"Write-Host '  Creating {vm.Name}...'");

            // Remove existing VM if present
            script.AppendLine($"$existingVM = Get-VM -Name '{safeVmName}' -ErrorAction SilentlyContinue");
            script.AppendLine("if ($existingVM) {");
            script.AppendLine($"  Write-Host '    Removing existing VM...'");
            script.AppendLine($"  Stop-VM -Name '{safeVmName}' -TurnOff -Force -ErrorAction SilentlyContinue");
            script.AppendLine($"  Remove-VM -Name '{safeVmName}' -Force -ErrorAction SilentlyContinue");
            script.AppendLine("}");

            // Create VM path
            var vmPath = workingDir.Replace("\\", "\\\\");
            script.AppendLine($"$vmPath = '{vmPath}'");

            // Create new VM with no disk initially
            script.AppendLine($"$newVM = New-VM -Name '{safeVmName}' -MemoryStartupBytes {vm.MemoryGB}GB -SwitchName '{safeSwitchName}' -NoVHD -Path $vmPath -ErrorAction Stop");
            script.AppendLine($"$newVM | Set-VMProcessor -Count {vm.Processors} -ErrorAction Stop | Out-Null");

            // Disable dynamic memory for stability
            script.AppendLine($"$newVM | Set-VMMemory -DynamicMemoryEnabled $false -ErrorAction Stop | Out-Null");

            // Create and attach new VHDX
            script.AppendLine($"$vhdPath = Join-Path $vmPath '{safeVmName}\\{safeVmName}.vhdx'");
            script.AppendLine("$vhdFolder = Split-Path $vhdPath");
            script.AppendLine("if (-not (Test-Path $vhdFolder)) { New-Item -Path $vhdFolder -ItemType Directory -Force | Out-Null }");
            script.AppendLine($"$vhd = New-VHD -Path $vhdPath -SizeBytes 127GB -Dynamic -ErrorAction Stop");
            script.AppendLine($"$newVM | Add-VMHardDiskDrive -DiskPath $vhdPath -ErrorAction Stop | Out-Null");

            // Attach DVD drive with ISO
            script.AppendLine($"$dvd = Add-VMDvdDrive -VMName '{safeVmName}' -Path {isoVar} -ErrorAction Stop");

            // Set boot order: DVD first, then hard disk
            script.AppendLine($"$bootOrder = @((Get-VMDvdDrive -VMName '{safeVmName}'), (Get-VMHardDiskDrive -VMName '{safeVmName}'))");
            script.AppendLine($"Set-VMFirmware -VMName '{safeVmName}' -BootOrder $bootOrder -ErrorAction Stop | Out-Null");

            script.AppendLine($"Write-Host '    {vm.Name} created successfully'");
            script.AppendLine();
        }

        // Create checkpoint for all VMs
        script.AppendLine("Write-Host 'Creating LabReady checkpoints...'");
        foreach (var vm in config.VMs)
        {
            var safeVmName = EscapePowerShellString(vm.Name);
            script.AppendLine($"Checkpoint-VM -Name '{safeVmName}' -SnapshotName 'LabReady' -ErrorAction SilentlyContinue");
            script.AppendLine($"Write-Host '  Checkpoint created: {vm.Name}'");
        }
        script.AppendLine();

        script.AppendLine("Write-Host ''");
        script.AppendLine("Write-Host '========================================'");
        script.AppendLine("Write-Host 'Deployment complete!'");
        script.AppendLine("Write-Host '========================================'");
        script.AppendLine("Write-Host ''");
        script.AppendLine("Write-Host 'Next steps:'");
        script.AppendLine("Write-Host '  1. Start the VMs from the Dashboard'");
        script.AppendLine("Write-Host '  2. Connect to each VM to complete OS installation'");
        script.AppendLine("Write-Host '  3. For the DC, install AD DS and promote to domain controller'");
        script.AppendLine("Write-Host ''");

        return script.ToString();
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

                // Find PowerShell 7 - check multiple locations
                var pwshPaths = new List<string>
                {
                    @"C:\Projects\AutomatedLab\pwsh\pwsh.exe",  // User-saved location
                    Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "pwsh", "pwsh.exe"),  // Bundled with app
                    Path.Combine(Path.GetDirectoryName(AppContext.BaseDirectory) ?? "", "pwsh", "pwsh.exe")  // Next to exe
                };

                // Add the parent directory of the exe (for single-file extraction temp folder)
                var exeDir = Path.GetDirectoryName(Environment.ProcessPath);
                if (!string.IsNullOrEmpty(exeDir))
                {
                    pwshPaths.Insert(0, Path.Combine(exeDir, "pwsh", "pwsh.exe"));
                }

                var powershellExe = pwshPaths.FirstOrDefault(File.Exists) ?? "powershell.exe";
                log?.Invoke($"Using PowerShell: {powershellExe}");

                var startInfo = new ProcessStartInfo
                {
                    FileName = powershellExe,
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

                // Check for actual PowerShell errors (not just the word "error" in output)
                var outputStr = output.ToString();
                bool hasRealErrors = outputStr.Contains("Exception:", StringComparison.OrdinalIgnoreCase) ||
                                    outputStr.Contains("FullyQualifiedErrorId", StringComparison.OrdinalIgnoreCase);

                return new PowerShellResult
                {
                    Output = outputStr,
                    ExitCode = exitCode,
                    Success = success && !hasRealErrors
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

    private static readonly HashSet<string> ReservedWindowsNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
    };

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

            // Check for reserved Windows names that would cause issues
            if (ReservedWindowsNames.Contains(vm.Name))
            {
                log?.Invoke($"VM name cannot be a reserved Windows name: {vm.Name}");
                return false;
            }

            // Check VM name length (Hyper-V has limits)
            if (vm.Name.Length > 15)
            {
                log?.Invoke($"VM name too long (max 15 characters): {vm.Name}");
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

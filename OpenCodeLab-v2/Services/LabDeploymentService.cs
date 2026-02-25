using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using OpenCodeLab.Models;

namespace OpenCodeLab.Services;

public class LabDeploymentService
{
    public event EventHandler<DeploymentProgressArgs>? Progress;

    private const string LabSourcesRoot = @"C:\LabSources";
    private const string DeployScriptName = "Deploy-Lab.ps1";

    public async Task<bool> DeployLabAsync(LabConfig config, Action<string>? log = null,
        string? adminPassword = null, bool incremental = false, CancellationToken ct = default)
    {
        try
        {
            Report(0, "Starting deployment...", log);

            if (!ValidateConfigInputs(config, log))
            {
                log?.Invoke("Invalid configuration. Please check VM names and network settings.");
                return false;
            }

            string workingDir = GetWorkingDirectory(config);
            Directory.CreateDirectory(workingDir);

            // Clean up orphaned disks (skip in incremental mode - existing VMs need their disks)
            if (!incremental)
            {
                Report(2, "Checking for orphaned VM disks...", log);
                foreach (var vm in config.VMs)
                {
                    var diskPath = Path.Combine(workingDir, vm.Name, $"{vm.Name}.vhdx");
                    if (File.Exists(diskPath))
                    {
                        log?.Invoke($"  Removing: {diskPath}");
                        File.Delete(diskPath);
                    }
                }
            }

            Report(4, "Loading deployment script...", log);
            var scriptPath = FindDeployScript();
            if (scriptPath == null || !File.Exists(scriptPath))
            {
                log?.Invoke($"ERROR: Deployment script not found: {DeployScriptName}");
                return false;
            }

            // Build VMs JSON and write to temp file
            var vmsJson = JsonSerializer.Serialize(config.VMs, new JsonSerializerOptions { WriteIndented = true });
            var vmsJsonFile = Path.Combine(Path.GetTempPath(), $"lab-vms-{Guid.NewGuid():N}.json");
            File.WriteAllText(vmsJsonFile, vmsJson, Encoding.UTF8);

            var pw = adminPassword ?? Environment.GetEnvironmentVariable("OPENCODELAB_ADMIN_PASSWORD");
            if (string.IsNullOrWhiteSpace(pw))
            {
                log?.Invoke("Deployment requires an admin password for Active Directory deployments.");
                return false;
            }

            bool result;
            try
            {
                var vmPath = @"C:\LabSources\VMs"; // Default VM storage path
                try
                {
                    var settingsPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OpenCodeLab", "settings.json");
                    if (File.Exists(settingsPath))
                    {
                        var settingsJson = File.ReadAllText(settingsPath);
                        var doc = System.Text.Json.JsonDocument.Parse(settingsJson);
                        if (doc.RootElement.TryGetProperty("VMPath", out var vp))
                            vmPath = vp.GetString() ?? vmPath;
                    }
                }
                catch { }

                var args = new Dictionary<string, string>
                {
                    ["LabName"] = config.LabName,
                    ["LabPath"] = workingDir,
                    ["SwitchName"] = config.Network.SwitchName,
                    ["SwitchType"] = config.Network.SwitchType,
                    ["DomainName"] = config.DomainName ?? "lab.com",
                    ["VMsJsonFile"] = vmsJsonFile,
                    ["AdminPassword"] = pw,
                    ["VMPath"] = vmPath
                };

                var switches = new List<string>();
                if (incremental) switches.Add("Incremental");

                result = await RunPowerShellScriptAsync(scriptPath, args, log, ct, switches);
            }
            finally
            {
                try { File.Delete(vmsJsonFile); } catch { }
            }

            // Post-deployment VHDX validation
            if (result)
            {
                Report(95, "Validating VM disk images...", log);
                result = await ValidateVhdxPostDeploymentAsync(config, log);
            }

            Report(100, result ? "Deployment complete!" : "Deployment finished with warnings.", log);
            return result;
        }
        catch (OperationCanceledException)
        {
            log?.Invoke("Deployment was cancelled.");
            return false;
        }
        catch (Exception ex)
        {
            log?.Invoke($"Deployment failed: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> RemoveLabAsync(LabConfig config, Action<string>? log,
        CancellationToken ct = default)
    {
        try
        {
            Report(0, "Removing lab...", log);

            if (!ValidateConfigInputs(config, log))
            {
                log?.Invoke("Invalid configuration for removal.");
                return false;
            }

            var safeName = EscapeSingleQuote(config.LabName);
            var script = new StringBuilder();

            script.AppendLine("$ErrorActionPreference = 'SilentlyContinue'");

            // Try AutomatedLab removal (may not be installed)
            script.AppendLine("try {");
            script.AppendLine("  Import-Module AutomatedLab -ErrorAction Stop");
            script.AppendLine($"  $existingLab = Get-Lab -List | Where-Object {{ $_ -eq '{safeName}' }}");
            script.AppendLine("  if ($existingLab) {");
            script.AppendLine($"    Write-Host 'Removing AutomatedLab definition: {config.LabName}'");
            script.AppendLine($"    Remove-Lab -Name '{safeName}' -Confirm:$false");
            script.AppendLine("  }");
            script.AppendLine("} catch {");
            script.AppendLine("  Write-Host 'AutomatedLab module not available, skipping lab definition removal.'");
            script.AppendLine("}");

            // Hyper-V removal
            script.AppendLine("try { Import-Module Hyper-V -ErrorAction Stop } catch { Write-Host 'Hyper-V module not available.' }");

            foreach (var vm in config.VMs)
            {
                var safeVmName = EscapeSingleQuote(vm.Name);
                script.AppendLine($"$vm = Get-VM -Name '{safeVmName}' -ErrorAction SilentlyContinue");
                script.AppendLine("if ($vm) {");
                script.AppendLine($"  Write-Host 'Removing VM: {vm.Name}'");
                script.AppendLine($"  Stop-VM -Name '{safeVmName}' -TurnOff -Force -ErrorAction SilentlyContinue");
                script.AppendLine($"  Remove-VM -Name '{safeVmName}' -Force -ErrorAction SilentlyContinue");
                script.AppendLine("}");
                script.AppendLine($"$vhdDir = 'C:\\LabSources\\VMs\\{safeVmName}'");
                script.AppendLine("if (Test-Path $vhdDir) {");
                script.AppendLine($"  Write-Host 'Removing disks: {vm.Name}'");
                script.AppendLine("  Remove-Item $vhdDir -Recurse -Force -ErrorAction SilentlyContinue");
                script.AppendLine("}");
            }

            script.AppendLine($"$sw = Get-VMSwitch -Name '{EscapeSingleQuote(config.Network.SwitchName)}' -ErrorAction SilentlyContinue");
            script.AppendLine("if ($sw) { Remove-VMSwitch -Name $sw.Name -Force -ErrorAction SilentlyContinue }");
            script.AppendLine("Write-Host 'Removal script completed.'");

            await RunPowerShellInlineAsync(script.ToString(), log, ct);

            if (!string.IsNullOrEmpty(config.LabPath) && File.Exists(config.LabPath))
            {
                try
                {
                    File.Delete(config.LabPath);
                    log?.Invoke($"Deleted config file: {config.LabPath}");
                }
                catch (Exception ex)
                {
                    log?.Invoke($"Warning: Could not delete config file: {ex.Message}");
                }
            }

            Report(100, "Lab removed!", log);
            return true;
        }
        catch (Exception ex)
        {
            log?.Invoke($"Removal failed: {ex.Message}");
            return false;
        }
    }

    /// <summary>
    /// Run a .ps1 script file with named parameters via system-installed pwsh.exe.
    /// Streams stdout/stderr in real-time and parses progress markers.
    /// </summary>
    private async Task<bool> RunPowerShellScriptAsync(string scriptPath, Dictionary<string, string> parameters,
        Action<string>? log, CancellationToken ct, List<string>? switches = null)
    {
        var pwsh = FindPowerShell();
        log?.Invoke($"Using PowerShell: {pwsh}");

        // Build the argument string: & 'script.ps1' -Param1 'val1' -Param2 'val2' -Switch
        var sb = new StringBuilder();
        sb.Append($"& '{EscapeSingleQuote(scriptPath)}'");
        foreach (var kvp in parameters)
            sb.Append($" -{kvp.Key} '{EscapeSingleQuote(kvp.Value)}'");
        if (switches != null)
            foreach (var sw in switches)
                sb.Append($" -{sw}");

        return await RunProcessAsync(pwsh,
            $"-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command \"{sb}\"",
            log, ct);
    }

    /// <summary>
    /// Run an inline PowerShell script string via system-installed pwsh.exe.
    /// </summary>
    public async Task RunPowerShellInlineAsync(string script, Action<string>? log,
        CancellationToken ct)
    {
        var pwsh = FindPowerShell();
        log?.Invoke($"Using PowerShell: {pwsh}");

        // Write script to temp file to avoid command-line escaping issues
        var tempScript = Path.Combine(Path.GetTempPath(), $"ocl-{Guid.NewGuid():N}.ps1");
        File.WriteAllText(tempScript, script, Encoding.UTF8);

        try
        {
            await RunProcessAsync(pwsh,
                $"-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"{tempScript}\"",
                log, ct);
        }
        finally
        {
            try { File.Delete(tempScript); } catch { }
        }
    }

    /// <summary>
    /// Launch a process, stream stdout/stderr to log in real-time,
    /// parse [PROGRESS:nn] markers for progress bar updates.
    /// </summary>
    private async Task<bool> RunProcessAsync(string exe, string arguments,
        Action<string>? log, CancellationToken ct)
    {
        var psi = new ProcessStartInfo
        {
            FileName = exe,
            Arguments = arguments,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };

        using var process = new Process { StartInfo = psi };
        var hasErrors = false;

        // Progress marker regex: [PROGRESS:42] or Write-Progress parsing
        var progressRegex = new Regex(@"\[PROGRESS:(\d{1,3})\]", RegexOptions.Compiled);
        // Also parse structured output like [nn%] message
        var percentRegex = new Regex(@"^\[(\d{1,3})%\]\s*(.*)", RegexOptions.Compiled);

        process.OutputDataReceived += (s, e) =>
        {
            if (e.Data == null) return;

            // Check for progress markers
            var progressMatch = progressRegex.Match(e.Data);
            if (progressMatch.Success && int.TryParse(progressMatch.Groups[1].Value, out var pct))
            {
                if (pct >= 0 && pct <= 100)
                    Progress?.Invoke(this, new DeploymentProgressArgs(pct, e.Data));
            }

            var percentMatch = percentRegex.Match(e.Data);
            if (percentMatch.Success && int.TryParse(percentMatch.Groups[1].Value, out var pct2))
            {
                if (pct2 >= 0 && pct2 <= 100)
                    Progress?.Invoke(this, new DeploymentProgressArgs(pct2, percentMatch.Groups[2].Value));
            }

            log?.Invoke(e.Data);
        };

        process.ErrorDataReceived += (s, e) =>
        {
            if (e.Data == null) return;
            hasErrors = true;
            log?.Invoke($"ERROR: {e.Data}");
        };

        process.Start();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        // Wait with cancellation support
        try
        {
            while (!process.HasExited)
            {
                if (ct.IsCancellationRequested)
                {
                    try { process.Kill(entireProcessTree: true); } catch { }
                    ct.ThrowIfCancellationRequested();
                }
                await Task.Delay(250, ct);
            }

            await process.WaitForExitAsync(ct);
        }
        catch (OperationCanceledException)
        {
            try { process.Kill(entireProcessTree: true); } catch { }
            throw;
        }

        return process.ExitCode == 0 && !hasErrors;
    }

    /// <summary>
    /// Find PowerShell 7: bundled copy first, then system-installed, then Windows PowerShell fallback.
    /// </summary>
    private static string FindPowerShell()
    {
        // 1. Check for bundled pwsh.exe alongside the app (for airgapped deployment)
        var appDir = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        var bundledPwsh = Path.Combine(appDir, "pwsh", "pwsh.exe");
        if (File.Exists(bundledPwsh))
            return bundledPwsh;

        // 2. Check common system install locations
        var candidates = new[]
        {
            @"C:\Program Files\PowerShell\7\pwsh.exe",
            @"C:\Program Files\PowerShell\7-preview\pwsh.exe",
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "PowerShell", "7", "pwsh.exe")
        };

        foreach (var path in candidates)
        {
            if (File.Exists(path))
                return path;
        }

        // 3. Try PATH
        var pathDirs = Environment.GetEnvironmentVariable("PATH")?.Split(Path.PathSeparator) ?? Array.Empty<string>();
        foreach (var dir in pathDirs)
        {
            var pwshPath = Path.Combine(dir, "pwsh.exe");
            if (File.Exists(pwshPath))
                return pwshPath;
        }

        // 4. Fall back to Windows PowerShell
        var winPs = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
            "WindowsPowerShell", "v1.0", "powershell.exe");
        if (File.Exists(winPs))
            return winPs;

        return "pwsh.exe";
    }

    /// <summary>
    /// Validate VHDX disk sizes after deployment to detect failed OS installations.
    /// </summary>
    private async Task<bool> ValidateVhdxPostDeploymentAsync(LabConfig config, Action<string>? log)
    {
        return await Task.Run(() =>
        {
            try
            {
                var allGood = true;
                var vhdxRoot = @"C:\LabSources\VMs";

                foreach (var vm in config.VMs)
                {
                    var vmDir = Path.Combine(vhdxRoot, vm.Name);
                    if (!Directory.Exists(vmDir))
                    {
                        log?.Invoke($"WARNING: VM disk directory not found: {vmDir}");
                        allGood = false;
                        continue;
                    }

                    var vhdxFiles = Directory.GetFiles(vmDir, "*.vhdx");
                    if (vhdxFiles.Length == 0)
                    {
                        log?.Invoke($"WARNING: No VHDX files found for VM '{vm.Name}' in {vmDir}");
                        allGood = false;
                        continue;
                    }

                    foreach (var vhdx in vhdxFiles)
                    {
                        var fi = new FileInfo(vhdx);
                        var sizeMB = fi.Length / (1024 * 1024);

                        if (sizeMB < 500)
                        {
                            log?.Invoke($"WARNING: '{vm.Name}' disk is only {sizeMB}MB ({fi.Name}) - OS installation may have failed!");
                            log?.Invoke($"  Expected: >500MB for a Windows install.");
                            log?.Invoke($"  Try: Re-run deployment, or check Get-LabAvailableOperatingSystem for ISO/OS name mismatches.");
                            allGood = false;
                        }
                        else
                        {
                            var sizeGB = sizeMB / 1024.0;
                            log?.Invoke($"  '{vm.Name}' disk OK: {sizeGB:F1}GB ({fi.Name})");
                        }
                    }
                }

                return allGood;
            }
            catch (Exception ex)
            {
                log?.Invoke($"VHDX validation error: {ex.Message}");
                return false;
            }
        });
    }

    private string? FindDeployScript()
    {
        var searchPaths = new[]
        {
            AppDomain.CurrentDomain.BaseDirectory,
            Path.GetDirectoryName(Environment.ProcessPath),
            Path.GetDirectoryName(AppContext.BaseDirectory)
        };

        foreach (var basePath in searchPaths)
        {
            if (string.IsNullOrEmpty(basePath)) continue;
            var scriptPath = Path.Combine(basePath, DeployScriptName);
            if (File.Exists(scriptPath))
                return scriptPath;
        }

        return null;
    }

    private string GetWorkingDirectory(LabConfig config)
    {
        if (string.IsNullOrEmpty(config.LabPath))
            return LabSourcesRoot;

        if (config.LabPath.EndsWith(".json", StringComparison.OrdinalIgnoreCase))
            return Path.GetDirectoryName(config.LabPath) ?? LabSourcesRoot;

        return config.LabPath;
    }

    private static readonly HashSet<string> ReservedWindowsNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
    };

    private bool ValidateConfigInputs(LabConfig config, Action<string>? log)
    {
        if (!Regex.IsMatch(config.LabName, @"^[a-zA-Z0-9\-_\s]+$"))
        {
            log?.Invoke($"Invalid lab name: {config.LabName}");
            return false;
        }

        if (!Regex.IsMatch(config.Network.SwitchName, @"^[a-zA-Z0-9\-_]+$"))
        {
            log?.Invoke($"Invalid switch name: {config.Network.SwitchName}");
            return false;
        }

        foreach (var vm in config.VMs)
        {
            if (!Regex.IsMatch(vm.Name, @"^[a-zA-Z0-9\-_]+$"))
            {
                log?.Invoke($"Invalid VM name: {vm.Name}");
                return false;
            }

            if (ReservedWindowsNames.Contains(vm.Name))
            {
                log?.Invoke($"VM name cannot be a reserved Windows name: {vm.Name}");
                return false;
            }

            if (vm.Name.Length > 15)
            {
                log?.Invoke($"VM name too long (max 15 characters): {vm.Name}");
                return false;
            }
        }

        return true;
    }

    private static string EscapeSingleQuote(string input)
    {
        if (string.IsNullOrEmpty(input))
            return string.Empty;
        return input.Replace("'", "''");
    }

    private void Report(int pct, string msg, Action<string>? log)
    {
        Progress?.Invoke(this, new DeploymentProgressArgs(pct, msg));
        log?.Invoke($"[{pct}%] {msg}");
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

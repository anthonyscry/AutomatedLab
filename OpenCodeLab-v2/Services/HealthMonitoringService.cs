using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using OpenCodeLab.Models;

namespace OpenCodeLab.Services;

/// <summary>
/// Service for monitoring health of labs, VMs, and host resources
/// </summary>
public class HealthMonitoringService
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private const string HealthDir = "Health";

    /// <summary>
    /// Run comprehensive health check for a lab
    /// </summary>
    public async Task<LabHealthReport> RunHealthCheckAsync(string labName, Action<string>? log = null, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(labName))
            throw new ArgumentException("Lab name is required.", nameof(labName));

        log?.Invoke($"Running health check for lab '{labName}'...");

        var report = new LabHealthReport
        {
            LabName = labName,
            GeneratedAt = DateTime.UtcNow
        };

        try
        {
            // Run lab-level checks
            var labChecks = await RunLabChecksAsync(labName, log, ct);
            report.Checks.AddRange(labChecks);

            // Run VM-level checks
            var vmHealth = await RunVmHealthChecksAsync(labName, log, ct);
            report.VmHealthStatuses.AddRange(vmHealth);

            // Run host-level checks
            report.HostStatus = await RunHostChecksAsync(log, ct);

            // Determine overall status
            report.OverallStatus = DetermineOverallStatus(report);

            // Save report
            await SaveReportAsync(report, ct);
            log?.Invoke($"Health check complete. Status: {report.OverallStatus}");
        }
        catch (Exception ex)
        {
            log?.Invoke($"Health check error: {ex.Message}");
            report.Checks.Add(new HealthCheckResult
            {
                CheckName = "Health Check",
                Status = HealthStatus.Critical,
                Message = $"Health check failed: {ex.Message}",
                Category = "System",
                TargetName = labName
            });
            report.OverallStatus = HealthStatus.Critical;
        }

        return report;
    }

    /// <summary>
    /// Get latest health report for a lab
    /// </summary>
    public async Task<LabHealthReport?> GetLatestReportAsync(string labName, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(labName))
            return null;

        var dir = GetHealthDir(labName);
        var latestFile = Directory.GetFiles(dir, "latest.json")
            .OrderByDescending(File.GetLastWriteTimeUtc)
            .FirstOrDefault();

        if (latestFile == null || !File.Exists(latestFile))
            return null;

        var json = await File.ReadAllTextAsync(latestFile, ct);
        return JsonSerializer.Deserialize<LabHealthReport>(json);
    }

    /// <summary>
    /// Get health history for a lab
    /// </summary>
    public async Task<List<LabHealthReport>> GetHistoryAsync(string labName, int days = 7, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(labName))
            return new List<LabHealthReport>();

        var dir = GetHealthDir(labName);
        var historyFile = Path.Combine(dir, "history.jsonl");
        
        if (!File.Exists(historyFile))
            return new List<LabHealthReport>();

        var reports = new List<LabHealthReport>();
        var cutoff = DateTime.UtcNow.AddDays(-days);

        foreach (var line in await File.ReadAllLinesAsync(historyFile, ct))
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            try
            {
                var report = JsonSerializer.Deserialize<LabHealthReport>(line);
                if (report != null && report.GeneratedAt >= cutoff)
                    reports.Add(report);
            }
            catch { }
        }

        return reports.OrderByDescending(r => r.GeneratedAt).ToList();
    }

    private async Task<List<HealthCheckResult>> RunLabChecksAsync(string labName, Action<string>? log, CancellationToken ct)
    {
        var checks = new List<HealthCheckResult>();

        // Check 1: Lab definition exists
        var labDefCheck = new HealthCheckResult
        {
            CheckName = "Lab Definition",
            Category = "Lab",
            TargetName = labName
        };

        try
        {
            var labXmlPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                "AutomatedLab", "Labs", labName, "Lab.xml");
            
            if (File.Exists(labXmlPath))
            {
                labDefCheck.Status = HealthStatus.Healthy;
                labDefCheck.Message = "Lab definition found";
            }
            else
            {
                labDefCheck.Status = HealthStatus.Warning;
                labDefCheck.Message = "Lab definition not found (may not be deployed yet)";
            }
        }
        catch (Exception ex)
        {
            labDefCheck.Status = HealthStatus.Unknown;
            labDefCheck.Message = $"Could not check lab definition: {ex.Message}";
        }
        checks.Add(labDefCheck);

        // Check 2: VMs exist on host
        var vmCheck = new HealthCheckResult
        {
            CheckName = "VMs on Host",
            Category = "Lab",
            TargetName = labName
        };

        try
        {
            var vmCount = await CountLabVmsAsync(labName, ct);
            if (vmCount > 0)
            {
                vmCheck.Status = HealthStatus.Healthy;
                vmCheck.Message = $"{vmCount} VM(s) found on host";
            }
            else
            {
                vmCheck.Status = HealthStatus.Warning;
                vmCheck.Message = "No VMs found on host";
            }
        }
        catch (Exception ex)
        {
            vmCheck.Status = HealthStatus.Unknown;
            vmCheck.Message = $"Could not check VMs: {ex.Message}";
        }
        checks.Add(vmCheck);

        // Check 3: Network configuration
        var netCheck = new HealthCheckResult
        {
            CheckName = "Network Switch",
            Category = "Lab",
            TargetName = labName
        };

        try
        {
            var switchExists = await CheckSwitchExistsAsync(labName, ct);
            if (switchExists)
            {
                netCheck.Status = HealthStatus.Healthy;
                netCheck.Message = "Network switch configured";
            }
            else
            {
                netCheck.Status = HealthStatus.Warning;
                netCheck.Message = "Network switch not found";
            }
        }
        catch (Exception ex)
        {
            netCheck.Status = HealthStatus.Unknown;
            netCheck.Message = $"Could not check network: {ex.Message}";
        }
        checks.Add(netCheck);

        return checks;
    }

    private async Task<List<VmHealthStatus>> RunVmHealthChecksAsync(string labName, Action<string>? log, CancellationToken ct)
    {
        var results = new List<VmHealthStatus>();

        var pwsh = FindPowerShell();
        var script = BuildVmHealthScript(labName);
        var json = await RunPowerShellAndGetJsonAsync(pwsh, script, ct);

        if (string.IsNullOrWhiteSpace(json))
            return results;

        try
        {
            using var doc = JsonDocument.Parse(json);
            if (!doc.RootElement.TryGetProperty("VMs", out var vmsElement))
                return results;

            foreach (var vmEl in vmsElement.EnumerateArray())
            {
                var status = new VmHealthStatus
                {
                    VmName = ReadString(vmEl, "Name") ?? string.Empty,
                    State = ReadString(vmEl, "State") ?? "Unknown",
                    Heartbeat = ReadString(vmEl, "Heartbeat"),
                    IntegrationServicesRunning = ReadBool(vmEl, "IntegrationServices"),
                    LastChecked = DateTime.UtcNow
                };

                // Determine health based on state
                if (status.State == "Running")
                {
                    if (status.Heartbeat == "Ok" || status.IntegrationServicesRunning)
                        status.Health = HealthStatus.Healthy;
                    else
                    {
                        status.Health = HealthStatus.Warning;
                        status.Issues.Add("Integration services not responding");
                    }
                }
                else if (status.State == "Off")
                {
                    status.Health = HealthStatus.Warning;
                    status.Issues.Add("VM is not running");
                }
                else
                {
                    status.Health = HealthStatus.Unknown;
                }

                // Parse resource utilization if present
                if (vmEl.TryGetProperty("Resources", out var resEl))
                {
                    status.CurrentResources = new ResourceUtilizationSnapshot
                    {
                        CpuPercentUsed = ReadDouble(resEl, "CpuPercent"),
                        MemoryAllocated = ReadLong(resEl, "MemoryAssigned"),
                        MemoryUsed = ReadLong(resEl, "MemoryDemand"),
                        MemoryPercentUsed = ReadDouble(resEl, "MemoryPercent")
                    };
                }

                results.Add(status);
            }
        }
        catch (Exception ex)
        {
            log?.Invoke($"Error parsing VM health: {ex.Message}");
        }

        return results;
    }

    private async Task<HostHealthStatus> RunHostChecksAsync(Action<string>? log, CancellationToken ct)
    {
        var status = new HostHealthStatus();

        var pwsh = FindPowerShell();
        var script = @"
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average
$disks = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }

@{
    CpuPercentUsed = [math]::Round($cpu.Average, 1)
    MemoryAvailableBytes = $os.FreePhysicalMemory * 1KB
    MemoryTotalBytes = $os.TotalVisibleMemorySize * 1KB
    MemoryPercentUsed = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1)
    Disks = @($disks | ForEach-Object {
        @{
            Drive = $_.DeviceID
            Label = $_.VolumeName
            TotalBytes = $_.Size
            AvailableBytes = $_.FreeSpace
            PercentUsed = [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1)
        }
    })
} | ConvertTo-Json -Depth 3
";
        var json = await RunPowerShellAndGetJsonAsync(pwsh, script, ct);

        if (!string.IsNullOrWhiteSpace(json))
        {
            try
            {
                using var doc = JsonDocument.Parse(json);
                var root = doc.RootElement;

                status.CpuPercentUsed = ReadDouble(root, "CpuPercentUsed");
                status.MemoryAvailableBytes = ReadLong(root, "MemoryAvailableBytes");
                status.MemoryTotalBytes = ReadLong(root, "MemoryTotalBytes");
                status.MemoryPercentUsed = ReadDouble(root, "MemoryPercentUsed");

                if (root.TryGetProperty("Disks", out var disksEl))
                {
                    foreach (var diskEl in disksEl.EnumerateArray())
                    {
                        var disk = new DiskHealthStatus
                        {
                            Drive = ReadString(diskEl, "Drive") ?? string.Empty,
                            Label = ReadString(diskEl, "Label"),
                            TotalBytes = ReadLong(diskEl, "TotalBytes"),
                            AvailableBytes = ReadLong(diskEl, "AvailableBytes"),
                            PercentUsed = ReadDouble(diskEl, "PercentUsed")
                        };

                        // Determine disk status
                        if (disk.PercentUsed > 90)
                            disk.Status = HealthStatus.Critical;
                        else if (disk.PercentUsed > 80)
                            disk.Status = HealthStatus.Warning;
                        else
                            disk.Status = HealthStatus.Healthy;

                        status.Disks.Add(disk);
                    }
                }
            }
            catch { }
        }

        // Determine overall host status
        if (status.CpuPercentUsed > 90 || status.MemoryPercentUsed > 90)
            status.OverallStatus = HealthStatus.Critical;
        else if (status.CpuPercentUsed > 80 || status.MemoryPercentUsed > 80 || status.Disks.Any(d => d.Status >= HealthStatus.Warning))
            status.OverallStatus = HealthStatus.Warning;
        else
            status.OverallStatus = HealthStatus.Healthy;

        status.CheckedAt = DateTime.UtcNow;
        return status;
    }

    private static HealthStatus DetermineOverallStatus(LabHealthReport report)
    {
        var allChecks = report.Checks.Select(c => c.Status)
            .Concat(report.VmHealthStatuses.Select(v => v.Health))
            .ToList();

        if (report.HostStatus != null)
            allChecks.Add(report.HostStatus.OverallStatus);

        if (allChecks.Any(s => s == HealthStatus.Critical))
            return HealthStatus.Critical;
        if (allChecks.Any(s => s == HealthStatus.Warning))
            return HealthStatus.Warning;
        if (allChecks.All(s => s == HealthStatus.Healthy))
            return HealthStatus.Healthy;
        return HealthStatus.Unknown;
    }

    private async Task<int> CountLabVmsAsync(string labName, CancellationToken ct)
    {
        var pwsh = FindPowerShell();
        var safeLabName = labName.Replace("'", "''");
        var script = $@"(Get-VM | Where-Object {{ $_.Name -like '{safeLabName}*' }}).Count";
        
        var output = await RunPowerShellAndGetOutputAsync(pwsh, script, ct);
        return int.TryParse(output?.Trim(), out var count) ? count : 0;
    }

    private async Task<bool> CheckSwitchExistsAsync(string labName, CancellationToken ct)
    {
        var pwsh = FindPowerShell();
        var safeLabName = labName.Replace("'", "''");
        var script = $@"
$switchName = '{safeLabName}'
$switch = Get-VMSwitch -Name $switchName -ErrorAction SilentlyContinue
if ($switch) {{ 'true' }} else {{ 'false' }}
";
        var output = await RunPowerShellAndGetOutputAsync(pwsh, script, ct);
        return output?.Trim().Equals("true", StringComparison.OrdinalIgnoreCase) == true;
    }

    private async Task SaveReportAsync(LabHealthReport report, CancellationToken ct)
    {
        var dir = GetHealthDir(report.LabName);
        Directory.CreateDirectory(dir);

        // Save as latest
        var latestPath = Path.Combine(dir, "latest.json");
        await File.WriteAllTextAsync(latestPath, JsonSerializer.Serialize(report, JsonOptions), ct);

        // Append to history
        var historyPath = Path.Combine(dir, "history.jsonl");
        var line = JsonSerializer.Serialize(report);
        await File.AppendAllTextAsync(historyPath, line + "\n", ct);
    }

    private string GetHealthDir(string labName)
    {
        var dir = Path.Combine(@"C:\LabSources\LabConfig", labName, HealthDir);
        Directory.CreateDirectory(dir);
        return dir;
    }

    private static string BuildVmHealthScript(string labName)
    {
        var safeLabName = labName.Replace("'", "''");
        return $@"
$vms = Get-VM | Where-Object {{ $_.Name -like '{safeLabName}*' }}
$results = @()

foreach ($vm in $vms) {{
    $heartbeat = try {{ (Get-VMIntegrationService -VMName $vm.Name -Name 'Heartbeat' -ErrorAction SilentlyContinue).PrimaryStatusDescription }} catch {{ 'Unknown' }}
    $intServices = try {{ (Get-VMIntegrationService -VMName $vm.Name | Where-Object Enabled).Count -gt 0 }} catch {{ $false }}
    
    $memAssigned = try {{ $vm.MemoryAssigned }} catch {{ 0 }}
    $memDemand = try {{ $vm.MemoryDemand }} catch {{ 0 }}
    $cpuUsage = try {{ 
        $proc = Get-WmiObject -Query \"ASSOCIATORS OF {{`$vm.Path}} WHERE ResultClass=Msvm_Processor\" -Namespace root\virtualization\v2 -ErrorAction SilentlyContinue
        if ($proc) {{ [math]::Round(($proc | Measure-Object -Property LoadPercentage -Average).Average, 1) }} else {{ 0 }}
    }} catch {{ 0 }}
    
    $results += @{{
        Name = $vm.Name
        State = $vm.State.ToString()
        Heartbeat = $heartbeat
        IntegrationServices = $intServices
        Resources = @{{
            CpuPercent = $cpuUsage
            MemoryAssigned = $memAssigned
            MemoryDemand = $memDemand
            MemoryPercent = if ($memAssigned -gt 0) {{ [math]::Round(($memDemand / $memAssigned) * 100, 1) }} else {{ 0 }}
        }}
    }}
}}

@{{ VMs = $results }} | ConvertTo-Json -Depth 3
";
    }

    private async Task<string?> RunPowerShellAndGetJsonAsync(string pwsh, string script, CancellationToken ct)
    {
        var outputPath = Path.Combine(Path.GetTempPath(), $"health-{Guid.NewGuid():N}.json");
        var escapedScript = script.Replace("\"", "\"\"");
        
        var psi = new ProcessStartInfo
        {
            FileName = pwsh,
            Arguments = $"-NoProfile -NonInteractive -Command \"{escapedScript} | Out-File -FilePath '{outputPath}' -Encoding utf8\"",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        using var process = new Process { StartInfo = psi };
        process.Start();
        await process.WaitForExitAsync(ct);

        if (!File.Exists(outputPath))
            return null;

        var json = await File.ReadAllTextAsync(outputPath, ct);
        try { File.Delete(outputPath); } catch { }
        return json;
    }

    private async Task<string?> RunPowerShellAndGetOutputAsync(string pwsh, string script, CancellationToken ct)
    {
        var escapedScript = script.Replace("\"", "\"\"");
        
        var psi = new ProcessStartInfo
        {
            FileName = pwsh,
            Arguments = $"-NoProfile -NonInteractive -Command \"{escapedScript}\"",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        using var process = new Process { StartInfo = psi };
        process.Start();
        var output = await process.StandardOutput.ReadToEndAsync(ct);
        await process.WaitForExitAsync(ct);
        return output;
    }

    private static string FindPowerShell()
    {
        var candidates = new[]
        {
            @"C:\Program Files\PowerShell\7\pwsh.exe",
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe")
        };

        foreach (var path in candidates)
        {
            if (File.Exists(path))
                return path;
        }

        return "powershell.exe";
    }

    private static string? ReadString(JsonElement parent, string propertyName)
    {
        if (!parent.TryGetProperty(propertyName, out var prop))
            return null;
        return prop.ValueKind == JsonValueKind.String ? prop.GetString() : prop.ToString();
    }

    private static double ReadDouble(JsonElement parent, string propertyName)
    {
        if (!parent.TryGetProperty(propertyName, out var prop))
            return 0;
        if (prop.ValueKind == JsonValueKind.Number)
            return prop.GetDouble();
        if (double.TryParse(prop.GetString(), out var val))
            return val;
        return 0;
    }

    private static long ReadLong(JsonElement parent, string propertyName)
    {
        if (!parent.TryGetProperty(propertyName, out var prop))
            return 0;
        if (prop.ValueKind == JsonValueKind.Number)
            return prop.GetInt64();
        if (long.TryParse(prop.GetString(), out var val))
            return val;
        return 0;
    }

    private static bool ReadBool(JsonElement parent, string propertyName)
    {
        if (!parent.TryGetProperty(propertyName, out var prop))
            return false;
        if (prop.ValueKind == JsonValueKind.True)
            return true;
        if (prop.ValueKind == JsonValueKind.False)
            return false;
        if (bool.TryParse(prop.GetString(), out var val))
            return val;
        return false;
    }
}

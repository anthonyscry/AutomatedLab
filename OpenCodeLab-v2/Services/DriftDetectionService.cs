using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using OpenCodeLab.Models;

namespace OpenCodeLab.Services;

public class DriftDetectionService
{
    private const string BaselinesDir = "baselines";
    private const string ReportsDir = "drift-reports";
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public async Task<DriftBaseline> CaptureBaselineAsync(string labName, Action<string>? log = null, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(labName))
            throw new ArgumentException("Lab name is required.", nameof(labName));

        log?.Invoke($"Capturing baseline for lab '{labName}'...");
        var json = await CaptureVMStateJsonAsync(labName, log, ct);
        if (string.IsNullOrWhiteSpace(json))
            throw new InvalidOperationException("VM state capture returned no data.");

        var states = ParseCapturedStates(json, log);
        var baseline = new DriftBaseline
        {
            Id = Guid.NewGuid().ToString("N"),
            LabName = labName,
            CreatedAt = DateTime.UtcNow,
            VMStates = states
        };

        var baselinePath = Path.Combine(GetDir(labName, BaselinesDir), $"{baseline.Id}.json");
        await File.WriteAllTextAsync(baselinePath, JsonSerializer.Serialize(baseline, JsonOptions), ct);
        log?.Invoke($"Baseline saved: {baselinePath}");
        return baseline;
    }

    public async Task<DriftBaseline?> GetBaselineAsync(string labName, string? baselineId = null, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(labName))
            return null;

        var dir = GetDir(labName, BaselinesDir);
        string? targetPath = null;

        if (!string.IsNullOrWhiteSpace(baselineId))
        {
            var candidate = Path.Combine(dir, $"{baselineId}.json");
            if (File.Exists(candidate))
                targetPath = candidate;
        }
        else
        {
            targetPath = Directory.GetFiles(dir, "*.json")
                .OrderByDescending(File.GetLastWriteTimeUtc)
                .FirstOrDefault();
        }

        if (string.IsNullOrWhiteSpace(targetPath) || !File.Exists(targetPath))
            return null;

        var json = await File.ReadAllTextAsync(targetPath, ct);
        return JsonSerializer.Deserialize<DriftBaseline>(json);
    }

    public async Task<DriftReport> DetectDriftAsync(string labName, string? baselineId = null, Action<string>? log = null, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(labName))
            throw new ArgumentException("Lab name is required.", nameof(labName));

        var baseline = await GetBaselineAsync(labName, baselineId, ct);
        if (baseline == null)
            throw new FileNotFoundException($"No baseline found for lab '{labName}'.");

        log?.Invoke($"Running drift detection for lab '{labName}' using baseline '{baseline.Id}'...");
        var json = await CaptureVMStateJsonAsync(labName, log, ct);
        if (string.IsNullOrWhiteSpace(json))
            throw new InvalidOperationException("VM state capture returned no data.");

        var currentStates = ParseCapturedStates(json, log);
        var currentLookup = currentStates
            .Where(s => !string.IsNullOrWhiteSpace(s.VMName))
            .ToDictionary(s => s.VMName, StringComparer.OrdinalIgnoreCase);

        var results = new List<VMDriftResult>();

        foreach (var baselineVm in baseline.VMStates)
        {
            if (string.IsNullOrWhiteSpace(baselineVm.VMName))
                continue;

            if (!currentLookup.TryGetValue(baselineVm.VMName, out var currentVm))
            {
                results.Add(new VMDriftResult
                {
                    VMName = baselineVm.VMName,
                    Reachable = false,
                    Items = new List<DriftItem>
                    {
                        new()
                        {
                            Category = "Connectivity",
                            Property = "VM Reachability",
                            Expected = "Reachable",
                            Actual = "Not reachable",
                            Severity = DriftSeverity.Critical
                        }
                    }
                });
                continue;
            }

            results.Add(new VMDriftResult
            {
                VMName = baselineVm.VMName,
                Reachable = true,
                Items = CompareVMState(baselineVm, currentVm)
            });
        }

        foreach (var currentVm in currentStates)
        {
            if (string.IsNullOrWhiteSpace(currentVm.VMName))
                continue;

            var alreadyInBaseline = baseline.VMStates.Any(b =>
                !string.IsNullOrWhiteSpace(b.VMName) &&
                string.Equals(b.VMName, currentVm.VMName, StringComparison.OrdinalIgnoreCase));

            if (!alreadyInBaseline)
            {
                results.Add(new VMDriftResult
                {
                    VMName = currentVm.VMName,
                    Reachable = true,
                    Items = new List<DriftItem>
                    {
                        new()
                        {
                            Category = "Inventory",
                            Property = "VM Presence",
                            Expected = "Not present",
                            Actual = "Present",
                            Severity = DriftSeverity.Warning
                        }
                    }
                });
            }
        }

        var report = new DriftReport
        {
            Id = Guid.NewGuid().ToString("N"),
            LabName = labName,
            BaselineId = baseline.Id,
            GeneratedAt = DateTime.UtcNow,
            Results = results,
            OverallStatus = DetermineOverallStatus(results)
        };

        var reportPath = Path.Combine(GetDir(labName, ReportsDir), $"{report.Id}.json");
        await File.WriteAllTextAsync(reportPath, JsonSerializer.Serialize(report, JsonOptions), ct);
        log?.Invoke($"Drift report saved: {reportPath}");
        return report;
    }

    public async Task<List<DriftReport>> GetReportsAsync(string labName, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(labName))
            return new List<DriftReport>();

        var dir = GetDir(labName, ReportsDir);
        var reports = new List<DriftReport>();

        foreach (var file in Directory.GetFiles(dir, "*.json").OrderByDescending(File.GetLastWriteTimeUtc))
        {
            ct.ThrowIfCancellationRequested();
            var json = await File.ReadAllTextAsync(file, ct);
            var report = JsonSerializer.Deserialize<DriftReport>(json);
            if (report != null)
                reports.Add(report);
        }

        return reports;
    }

    public async Task<bool> DeleteBaselineAsync(string labName, string baselineId, CancellationToken ct = default)
    {
        await Task.Yield();
        ct.ThrowIfCancellationRequested();

        if (string.IsNullOrWhiteSpace(labName) || string.IsNullOrWhiteSpace(baselineId))
            return false;

        var path = Path.Combine(GetDir(labName, BaselinesDir), $"{baselineId}.json");
        if (!File.Exists(path))
            return false;

        File.Delete(path);
        return true;
    }

    private List<DriftItem> CompareVMState(VMBaselineState baseline, VMBaselineState current)
    {
        var items = new List<DriftItem>();

        var baselineServices = baseline.RunningServices ?? new List<string>();
        var currentServices = current.RunningServices ?? new List<string>();
        var addedServices = currentServices.Except(baselineServices, StringComparer.OrdinalIgnoreCase).ToList();
        var removedServices = baselineServices.Except(currentServices, StringComparer.OrdinalIgnoreCase).ToList();
        foreach (var svc in addedServices)
            items.Add(new DriftItem { Category = "Services", Property = svc, Expected = "Not running", Actual = "Running", Severity = DriftSeverity.Warning });
        foreach (var svc in removedServices)
            items.Add(new DriftItem { Category = "Services", Property = svc, Expected = "Running", Actual = "Not running", Severity = DriftSeverity.Warning });

        var baselineSw = (baseline.InstalledSoftware ?? new List<InstalledSoftware>())
            .Where(s => !string.IsNullOrWhiteSpace(s.Name))
            .Select(s => s.Name)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var currentSw = (current.InstalledSoftware ?? new List<InstalledSoftware>())
            .Where(s => !string.IsNullOrWhiteSpace(s.Name))
            .Select(s => s.Name)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var sw in currentSw.Except(baselineSw, StringComparer.OrdinalIgnoreCase))
            items.Add(new DriftItem { Category = "Software", Property = sw, Expected = "Not installed", Actual = "Installed", Severity = DriftSeverity.Warning });
        foreach (var sw in baselineSw.Except(currentSw, StringComparer.OrdinalIgnoreCase))
            items.Add(new DriftItem { Category = "Software", Property = sw, Expected = "Installed", Actual = "Not installed", Severity = DriftSeverity.Warning });

        var baselinePorts = baseline.OpenPorts ?? new List<string>();
        var currentPorts = current.OpenPorts ?? new List<string>();
        var addedPorts = currentPorts.Except(baselinePorts, StringComparer.OrdinalIgnoreCase).ToList();
        var removedPorts = baselinePorts.Except(currentPorts, StringComparer.OrdinalIgnoreCase).ToList();
        foreach (var port in addedPorts)
            items.Add(new DriftItem { Category = "Ports", Property = port, Expected = "Closed", Actual = "Listening", Severity = DriftSeverity.Info });
        foreach (var port in removedPorts)
            items.Add(new DriftItem { Category = "Ports", Property = port, Expected = "Listening", Actual = "Closed", Severity = DriftSeverity.Info });

        var baselineUsers = baseline.LocalUsers ?? new List<string>();
        var currentUsers = current.LocalUsers ?? new List<string>();
        var addedUsers = currentUsers.Except(baselineUsers, StringComparer.OrdinalIgnoreCase).ToList();
        var removedUsers = baselineUsers.Except(currentUsers, StringComparer.OrdinalIgnoreCase).ToList();
        foreach (var user in addedUsers)
            items.Add(new DriftItem { Category = "Users", Property = user, Expected = "Not present", Actual = "Present", Severity = DriftSeverity.Critical });
        foreach (var user in removedUsers)
            items.Add(new DriftItem { Category = "Users", Property = user, Expected = "Present", Actual = "Not present", Severity = DriftSeverity.Critical });

        var baselineFirewall = baseline.FirewallProfile ?? string.Empty;
        var currentFirewall = current.FirewallProfile ?? string.Empty;
        if (!string.Equals(baselineFirewall, currentFirewall, StringComparison.OrdinalIgnoreCase))
            items.Add(new DriftItem { Category = "Firewall", Property = "Profile", Expected = baselineFirewall, Actual = currentFirewall, Severity = DriftSeverity.Critical });

        var baselineTasks = baseline.ScheduledTasks ?? new List<string>();
        var currentTasks = current.ScheduledTasks ?? new List<string>();
        var addedTasks = currentTasks.Except(baselineTasks, StringComparer.OrdinalIgnoreCase).ToList();
        var removedTasks = baselineTasks.Except(currentTasks, StringComparer.OrdinalIgnoreCase).ToList();
        foreach (var task in addedTasks)
            items.Add(new DriftItem { Category = "ScheduledTasks", Property = task, Expected = "Not present", Actual = "Present", Severity = DriftSeverity.Info });
        foreach (var task in removedTasks)
            items.Add(new DriftItem { Category = "ScheduledTasks", Property = task, Expected = "Present", Actual = "Not present", Severity = DriftSeverity.Info });

        var baselineRegistry = baseline.RegistryKeys ?? new Dictionary<string, string>();
        var currentRegistry = current.RegistryKeys ?? new Dictionary<string, string>();
        foreach (var kvp in baselineRegistry)
        {
            if (!currentRegistry.TryGetValue(kvp.Key, out var currentVal) || !string.Equals(currentVal, kvp.Value, StringComparison.Ordinal))
                items.Add(new DriftItem { Category = "Registry", Property = kvp.Key, Expected = kvp.Value, Actual = currentVal ?? "Missing", Severity = DriftSeverity.Warning });
        }

        return items;
    }

    private static DriftStatus DetermineOverallStatus(IEnumerable<VMDriftResult> results)
    {
        var allItems = results.SelectMany(r => r.Items);
        if (allItems.Any(i => i.Severity == DriftSeverity.Critical))
            return DriftStatus.Critical;
        if (allItems.Any(i => i.Severity == DriftSeverity.Warning))
            return DriftStatus.Warning;
        return DriftStatus.Clean;
    }

    private async Task<string?> CaptureVMStateJsonAsync(string labName, Action<string>? log = null, CancellationToken ct = default)
    {
        var outputPath = Path.Combine(Path.GetTempPath(), $"vm-state-{Guid.NewGuid():N}.json");
        var pwsh = FindPowerShell();
        var script = BuildStateCaptureScript(labName, outputPath);
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

        var stderrTask = process.StandardError.ReadToEndAsync(ct);
        var stdoutTask = process.StandardOutput.ReadToEndAsync(ct);
        await process.WaitForExitAsync(ct);

        var stderr = await stderrTask;
        _ = await stdoutTask;

        if (!File.Exists(outputPath))
        {
            log?.Invoke($"State capture failed: {stderr}");
            return null;
        }

        var json = await File.ReadAllTextAsync(outputPath, ct);
        try { File.Delete(outputPath); } catch { }
        return json;
    }

    private static string BuildStateCaptureScript(string labName, string outputPath)
    {
        var safeLabName = labName.Replace("'", "''");
        var escapedOutput = outputPath.Replace("'", "''");
        return $@"
Import-Lab -Name '{safeLabName}' -NoValidation -ErrorAction SilentlyContinue
$vms = @(Get-LabVM -ErrorAction SilentlyContinue)
if ($vms.Count -eq 0) {{ $vms = @(Get-VM | Where-Object {{ $_.Name -like '{safeLabName}*' }}) }}
$states = [System.Collections.Generic.List[object]]::new()
foreach ($vm in $vms) {{
    $vmName = if ($vm.PSObject.Properties['Name']) {{ $vm.Name }} else {{ $vm.ComputerName }}
    try {{
        $state = Invoke-LabCommand -ComputerName $vmName -ActivityName 'CaptureState' -PassThru -ScriptBlock {{
            $s = @{{
                VMName = $env:COMPUTERNAME
                CapturedAt = (Get-Date).ToUniversalTime().ToString('o')
                RunningServices = @(Get-Service | Where-Object Status -eq Running | Select-Object -ExpandProperty Name | Sort-Object)
                InstalledSoftware = @(Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object {{ $_.DisplayName }} | ForEach-Object {{ @{{ Name=$_.DisplayName; Version=$_.DisplayVersion; Publisher=$_.Publisher; InstallDate=$_.InstallDate }} }} | Sort-Object {{ $_.Name }})
                OpenPorts = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LocalPort -Unique | Sort-Object)
                LocalUsers = @(Get-LocalUser -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Sort-Object)
                ScheduledTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {{ $_.State -eq 'Ready' -and $_.TaskPath -notlike '\Microsoft\*' }} | Select-Object -ExpandProperty TaskName | Sort-Object)
                RegistryKeys = @{{}}
                FirewallProfile = (Get-NetFirewallProfile -ErrorAction SilentlyContinue | Where-Object Enabled -eq $true | Select-Object -First 1 -ExpandProperty Name)
            }}
            $regPaths = @(
                @{{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName'; Name = 'ComputerName' }}
                @{{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'; Name = 'ProductName' }}
                @{{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'; Name = 'CurrentBuild' }}
            )
            foreach ($reg in $regPaths) {{
                $val = Get-ItemProperty -Path $reg.Path -Name $reg.Name -ErrorAction SilentlyContinue
                if ($val) {{
                    $s.RegistryKeys[""$($reg.Path)\$($reg.Name)""] = [string]$val.$($reg.Name)
                }}
            }}
            $s
        }}
        $states.Add(@{{ VMName=$vmName; Reachable=$true; CapturedAt=(Get-Date).ToUniversalTime().ToString('o'); State=$state }})
    }} catch {{
        $states.Add(@{{ VMName=$vmName; Reachable=$false; CapturedAt=(Get-Date).ToUniversalTime().ToString('o'); ErrorMessage=$_.Exception.Message }})
    }}
}}
@{{ LabName='{safeLabName}'; CapturedAt=(Get-Date).ToUniversalTime().ToString('o'); VMStates=@($states) }} | ConvertTo-Json -Depth 10 | Set-Content -Path '{escapedOutput}' -Encoding utf8
";
    }

    private static string FindPowerShell()
    {
        try
        {
            using var p = Process.Start(new ProcessStartInfo
            {
                FileName = "pwsh",
                Arguments = "-Version",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                CreateNoWindow = true
            });
            p?.WaitForExit(3000);
            if (p?.ExitCode == 0) return "pwsh";
        }
        catch { }
        return "powershell.exe";
    }

    private string GetDir(string labName, string subDir)
    {
        var dir = Path.Combine(@"C:\LabSources\LabConfig", labName, subDir);
        Directory.CreateDirectory(dir);
        return dir;
    }

    private static List<VMBaselineState> ParseCapturedStates(string json, Action<string>? log)
    {
        var states = new List<VMBaselineState>();

        using var document = JsonDocument.Parse(json);
        if (!document.RootElement.TryGetProperty("VMStates", out var vmStatesElement) || vmStatesElement.ValueKind != JsonValueKind.Array)
            return states;

        foreach (var vmElement in vmStatesElement.EnumerateArray())
        {
            var reachable = vmElement.TryGetProperty("Reachable", out var reachableElement) &&
                            reachableElement.ValueKind == JsonValueKind.True;
            if (!reachable)
            {
                var unreachableName = ReadString(vmElement, "VMName");
                if (!string.IsNullOrWhiteSpace(unreachableName))
                    log?.Invoke($"Skipping unreachable VM '{unreachableName}' in state capture.");
                continue;
            }

            var source = vmElement;
            if (vmElement.TryGetProperty("State", out var stateElement) && stateElement.ValueKind == JsonValueKind.Object)
                source = stateElement;

            var vmName = ReadString(source, "VMName");
            if (string.IsNullOrWhiteSpace(vmName))
                vmName = ReadString(vmElement, "VMName") ?? string.Empty;

            var baselineState = new VMBaselineState
            {
                VMName = vmName ?? string.Empty,
                RunningServices = ReadStringArray(source, "RunningServices"),
                InstalledSoftware = ReadInstalledSoftwareArray(source, "InstalledSoftware"),
                OpenPorts = ReadStringArray(source, "OpenPorts"),
                LocalUsers = ReadStringArray(source, "LocalUsers"),
                ScheduledTasks = ReadStringArray(source, "ScheduledTasks"),
                RegistryKeys = ReadStringDictionary(source, "RegistryKeys"),
                FirewallProfile = ReadString(source, "FirewallProfile"),
                CapturedAt = ReadDateTime(source, "CapturedAt") ?? DateTime.UtcNow,
                Role = string.Empty
            };

            if (!string.IsNullOrWhiteSpace(baselineState.VMName))
                states.Add(baselineState);
        }

        return states;
    }

    private static string? ReadString(JsonElement parent, string propertyName)
    {
        if (!parent.TryGetProperty(propertyName, out var property))
            return null;

        if (property.ValueKind == JsonValueKind.String)
            return property.GetString();

        return property.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined
            ? null
            : property.ToString();
    }

    private static List<string> ReadStringArray(JsonElement parent, string propertyName)
    {
        if (!parent.TryGetProperty(propertyName, out var property) || property.ValueKind != JsonValueKind.Array)
            return new List<string>();

        return property.EnumerateArray()
            .Select(item => item.ValueKind == JsonValueKind.String ? item.GetString() : item.ToString())
            .Where(item => !string.IsNullOrWhiteSpace(item))
            .Select(item => item ?? string.Empty)
            .ToList();
    }

    private static Dictionary<string, string> ReadStringDictionary(JsonElement parent, string propertyName)
    {
        if (!parent.TryGetProperty(propertyName, out var property) || property.ValueKind != JsonValueKind.Object)
            return new Dictionary<string, string>();

        var dict = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in property.EnumerateObject())
        {
            var value = item.Value.ValueKind == JsonValueKind.String
                ? item.Value.GetString() ?? string.Empty
                : item.Value.ToString();
            dict[item.Name] = value;
        }

        return dict;
    }

    private static List<InstalledSoftware> ReadInstalledSoftwareArray(JsonElement parent, string propertyName)
    {
        if (!parent.TryGetProperty(propertyName, out var property) || property.ValueKind != JsonValueKind.Array)
            return new List<InstalledSoftware>();

        var list = new List<InstalledSoftware>();
        foreach (var item in property.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.Object)
                continue;

            list.Add(new InstalledSoftware
            {
                Name = ReadString(item, "Name") ?? string.Empty,
                Version = ReadString(item, "Version") ?? string.Empty,
                Publisher = ReadString(item, "Publisher") ?? string.Empty,
                InstallDate = ReadDateTime(item, "InstallDate")
            });
        }

        return list;
    }

    private static DateTime? ReadDateTime(JsonElement parent, string propertyName)
    {
        var raw = ReadString(parent, propertyName);
        if (string.IsNullOrWhiteSpace(raw))
            return null;

        return DateTime.TryParse(raw, out var parsed) ? parsed : null;
    }
}

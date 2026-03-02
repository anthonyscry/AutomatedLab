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
/// Service for capturing and comparing host-level baselines
/// </summary>
public class HostBaselineCaptureService
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private const string BaselinesDir = "baselines";

    /// <summary>
    /// Capture host-level configuration for all VMs in a lab
    /// </summary>
    public async Task<List<HostVmConfiguration>> CaptureVmConfigurationsAsync(string labName, Action<string>? log = null, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(labName))
            throw new ArgumentException("Lab name is required.", nameof(labName));

        log?.Invoke($"Capturing VM configurations for lab '{labName}'...");

        var pwsh = FindPowerShell();
        var script = BuildCaptureScript(labName);
        var json = await RunPowerShellAndGetJsonAsync(pwsh, script, ct);

        if (string.IsNullOrWhiteSpace(json))
        {
            log?.Invoke("No VM configuration data returned.");
            return new List<HostVmConfiguration>();
        }

        var configs = ParseVmConfigurations(json, log);
        log?.Invoke($"Captured {configs.Count} VM configuration(s).");
        return configs;
    }

    /// <summary>
    /// Capture network configuration for a lab
    /// </summary>
    public async Task<HostNetworkConfiguration> CaptureNetworkConfigurationAsync(string labName, Action<string>? log = null, CancellationToken ct = default)
    {
        log?.Invoke($"Capturing network configuration for lab '{labName}'...");

        var pwsh = FindPowerShell();
        var script = BuildNetworkCaptureScript(labName);
        var json = await RunPowerShellAndGetJsonAsync(pwsh, script, ct);

        var config = new HostNetworkConfiguration { CapturedAt = DateTime.UtcNow };

        if (string.IsNullOrWhiteSpace(json))
        {
            log?.Invoke("No network configuration data returned.");
            return config;
        }

        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            // Parse switches
            if (root.TryGetProperty("Switches", out var switchesEl))
            {
                foreach (var swEl in switchesEl.EnumerateArray())
                {
                    config.Switches.Add(new VirtualSwitchConfiguration
                    {
                        Name = ReadString(swEl, "Name") ?? string.Empty,
                        SwitchType = ReadString(swEl, "SwitchType") ?? string.Empty,
                        NetAdapterInterfaceDescription = ReadString(swEl, "NetAdapterInterfaceDescription"),
                        AllowManagementOs = ReadBool(swEl, "AllowManagementOs")
                    });
                }
            }

            // Parse NAT configurations
            if (root.TryGetProperty("NAT", out var natEl))
            {
                foreach (var nEl in natEl.EnumerateArray())
                {
                    config.NatConfigurations.Add(new NatConfiguration
                    {
                        Name = ReadString(nEl, "Name") ?? string.Empty,
                        Subnet = ReadString(nEl, "Subnet") ?? string.Empty,
                        InternalIpInterfaceAddress = ReadString(nEl, "InternalIP") ?? string.Empty
                    });
                }
            }

            // Parse host adapters
            if (root.TryGetProperty("Adapters", out var adaptersEl))
            {
                foreach (var aEl in adaptersEl.EnumerateArray())
                {
                    config.HostAdapters.Add(new NetworkAdapterConfiguration
                    {
                        Name = ReadString(aEl, "Name") ?? string.Empty,
                        InterfaceDescription = ReadString(aEl, "InterfaceDescription") ?? string.Empty,
                        Status = ReadString(aEl, "Status") ?? string.Empty,
                        MacAddress = ReadString(aEl, "MacAddress")
                    });
                }
            }

            log?.Invoke($"Captured {config.Switches.Count} switch(es), {config.NatConfigurations.Count} NAT config(s).");
        }
        catch (Exception ex)
        {
            log?.Invoke($"Error parsing network configuration: {ex.Message}");
        }

        return config;
    }

    /// <summary>
    /// Save an extended baseline to disk
    /// </summary>
    public async Task<ExtendedDriftBaseline> SaveExtendedBaselineAsync(ExtendedDriftBaseline baseline, CancellationToken ct = default)
    {
        var dir = GetBaselineDir(baseline.LabName);
        Directory.CreateDirectory(dir);

        var path = Path.Combine(dir, $"{baseline.Id}.json");
        await File.WriteAllTextAsync(path, JsonSerializer.Serialize(baseline, JsonOptions), ct);
        return baseline;
    }

    /// <summary>
    /// Load an extended baseline from disk
    /// </summary>
    public async Task<ExtendedDriftBaseline?> GetExtendedBaselineAsync(string labName, string? baselineId = null, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(labName))
            return null;

        var dir = GetBaselineDir(labName);
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
        return JsonSerializer.Deserialize<ExtendedDriftBaseline>(json);
    }

    /// <summary>
    /// List all extended baselines for a lab
    /// </summary>
    public async Task<List<ExtendedDriftBaseline>> ListExtendedBaselinesAsync(string labName, CancellationToken ct = default)
    {
        await Task.Yield();
        
        if (string.IsNullOrWhiteSpace(labName))
            return new List<ExtendedDriftBaseline>();

        var dir = GetBaselineDir(labName);
        if (!Directory.Exists(dir))
            return new List<ExtendedDriftBaseline>();

        var baselines = new List<ExtendedDriftBaseline>();

        foreach (var file in Directory.GetFiles(dir, "*.json").OrderByDescending(File.GetLastWriteTimeUtc))
        {
            ct.ThrowIfCancellationRequested();
            try
            {
                var json = File.ReadAllText(file);
                var baseline = JsonSerializer.Deserialize<ExtendedDriftBaseline>(json);
                if (baseline != null)
                    baselines.Add(baseline);
            }
            catch { }
        }

        return baselines;
    }

    private List<HostVmConfiguration> ParseVmConfigurations(string json, Action<string>? log)
    {
        var configs = new List<HostVmConfiguration>();

        try
        {
            using var doc = JsonDocument.Parse(json);
            if (!doc.RootElement.TryGetProperty("VMs", out var vmsEl))
                return configs;

            foreach (var vmEl in vmsEl.EnumerateArray())
            {
                var config = new HostVmConfiguration
                {
                    VmName = ReadString(vmEl, "Name") ?? string.Empty,
                    ProcessorCount = ReadInt(vmEl, "ProcessorCount"),
                    MemoryStartupBytes = ReadLong(vmEl, "MemoryStartupBytes"),
                    MemoryMinimumBytes = ReadLong(vmEl, "MemoryMinimumBytes"),
                    MemoryMaximumBytes = ReadLong(vmEl, "MemoryMaximumBytes"),
                    DynamicMemoryEnabled = ReadBool(vmEl, "DynamicMemoryEnabled"),
                    Generation = ReadString(vmEl, "Generation") ?? "2",
                    AutomaticCheckpointsEnabled = ReadBool(vmEl, "AutomaticCheckpointsEnabled"),
                    CheckpointFileLocation = ReadString(vmEl, "CheckpointFileLocation"),
                    SmartPagingFilePath = ReadString(vmEl, "SmartPagingFilePath"),
                    CapturedAt = DateTime.UtcNow
                };

                // Parse disks
                if (vmEl.TryGetProperty("Disks", out var disksEl))
                {
                    foreach (var dEl in disksEl.EnumerateArray())
                    {
                        config.Disks.Add(new HostDiskConfiguration
                        {
                            Path = ReadString(dEl, "Path") ?? string.Empty,
                            Type = ReadString(dEl, "Type") ?? string.Empty,
                            SizeBytes = ReadLong(dEl, "SizeBytes"),
                            FileSizeBytes = ReadLongOrNull(dEl, "FileSizeBytes"),
                            ControllerNumber = ReadInt(dEl, "ControllerNumber"),
                            ControllerLocation = ReadInt(dEl, "ControllerLocation")
                        });
                    }
                }

                // Parse network adapters
                if (vmEl.TryGetProperty("NetworkAdapters", out var netEl))
                {
                    foreach (var nEl in netEl.EnumerateArray())
                    {
                        var adapter = new HostNetworkAdapterConfiguration
                        {
                            Name = ReadString(nEl, "Name") ?? string.Empty,
                            SwitchName = ReadString(nEl, "SwitchName"),
                            IsConnected = ReadBool(nEl, "IsConnected"),
                            VlanId = ReadString(nEl, "VlanId")
                        };

                        if (nEl.TryGetProperty("IpAddresses", out var ipsEl))
                        {
                            foreach (var ipEl in ipsEl.EnumerateArray())
                                adapter.IpAddresses.Add(ipEl.GetString() ?? string.Empty);
                        }

                        if (nEl.TryGetProperty("MacAddresses", out var macsEl))
                        {
                            foreach (var macEl in macsEl.EnumerateArray())
                                adapter.MacAddresses.Add(macEl.GetString() ?? string.Empty);
                        }

                        config.NetworkAdapters.Add(adapter);
                    }
                }

                configs.Add(config);
            }
        }
        catch (Exception ex)
        {
            log?.Invoke($"Error parsing VM configurations: {ex.Message}");
        }

        return configs;
    }

    private string GetBaselineDir(string labName)
    {
        var dir = Path.Combine(@"C:\LabSources\LabConfig", labName, BaselinesDir);
        Directory.CreateDirectory(dir);
        return dir;
    }

    private static string BuildCaptureScript(string labName)
    {
        var safeLabName = labName.Replace("'", "''");
        return $@"
$vms = Get-VM | Where-Object {{ $_.Name -like '{safeLabName}*' }}
$results = @()

foreach ($vm in $vms) {{
    $disks = @()
    $hardDrives = $vm.HardDrives | ForEach-Object {{
        $vhd = Get-VHD -Path $_.Path -ErrorAction SilentlyContinue
        @{{
            Path = $_.Path
            Type = if ($vhd) {{ $vhd.VhdType.ToString() }} else {{ 'Unknown' }}
            SizeBytes = $_.Size
            FileSizeBytes = if ($vhd) {{ $vhd.FileSize }} else {{ $null }}
            ControllerNumber = $_.ControllerNumber
            ControllerLocation = $_.ControllerLocation
        }}
    }}
    
    $dvddrives = $vm.DVDDrives | ForEach-Object {{
        @{{
            Path = $_.Path
            Type = 'DVD'
            SizeBytes = 0
            ControllerNumber = $_.ControllerNumber
            ControllerLocation = $_.ControllerLocation
        }}
    }}
    
    $disks = @($hardDrives) + @($dvddrives)
    
    $adapters = @($vm.NetworkAdapters | ForEach-Object {{
        $ips = @($_.IpAddresses | Where-Object {{ $_ -notlike '*%*' }})
        @{{
            Name = $_.Name
            SwitchName = $_.SwitchName
            IsConnected = $_.Connected
            IpAddresses = $ips
            MacAddresses = @($_.MacAddress)
            VlanId = if ($_.VlanSetting) {{ $_.VlanSetting.AccessVlanId.ToString() }} else {{ $null }}
        }}
    }})
    
    $results += @{{
        Name = $vm.Name
        ProcessorCount = $vm.ProcessorCount
        MemoryStartupBytes = $vm.MemoryStartup
        MemoryMinimumBytes = $vm.MemoryMinimum
        MemoryMaximumBytes = $vm.MemoryMaximum
        DynamicMemoryEnabled = $vm.DynamicMemoryEnabled
        Generation = $vm.Generation.ToString()
        AutomaticCheckpointsEnabled = $vm.AutomaticCheckpointsEnabled
        CheckpointFileLocation = $vm.CheckpointFileLocation
        SmartPagingFilePath = $vm.SmartPagingFilePath
        Disks = $disks
        NetworkAdapters = $adapters
    }}
}}

@{{ VMs = $results }} | ConvertTo-Json -Depth 5
";
    }

    private static string BuildNetworkCaptureScript(string labName)
    {
        var safeLabName = labName.Replace("'", "''");
        return $@"
$switches = @(Get-VMSwitch | Where-Object {{ $_.Name -like '*{safeLabName}*' -or $_.Name -eq '{safeLabName}' }} | ForEach-Object {{
    @{{
        Name = $_.Name
        SwitchType = $_.SwitchType.ToString()
        NetAdapterInterfaceDescription = $_.NetAdapterInterfaceDescription
        AllowManagementOs = $_.AllowManagementOS
    }}
}})

$nat = @(Get-NetNat -ErrorAction SilentlyContinue | ForEach-Object {{
    @{{
        Name = $_.Name
        Subnet = $_.ExternalIPInterfaceAddress
        InternalIP = if ($_.InternalIPInterfaceAddress) {{ $_.InternalIPInterfaceAddress }} else {{ '' }}
    }}
}})

$adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | ForEach-Object {{
    @{{
        Name = $_.Name
        InterfaceDescription = $_.InterfaceDescription
        Status = $_.Status.ToString()
        MacAddress = $_.MacAddress
    }}
}})

@{{
    Switches = $switches
    NAT = $nat
    Adapters = $adapters
}} | ConvertTo-Json -Depth 3
";
    }

    private async Task<string?> RunPowerShellAndGetJsonAsync(string pwsh, string script, CancellationToken ct)
    {
        var outputPath = Path.Combine(Path.GetTempPath(), $"host-cfg-{Guid.NewGuid():N}.json");
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

    private static int ReadInt(JsonElement parent, string propertyName)
    {
        if (!parent.TryGetProperty(propertyName, out var prop))
            return 0;
        return prop.ValueKind == JsonValueKind.Number ? prop.GetInt32() : 0;
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

    private static long? ReadLongOrNull(JsonElement parent, string propertyName)
    {
        if (!parent.TryGetProperty(propertyName, out var prop))
            return null;
        if (prop.ValueKind == JsonValueKind.Number)
            return prop.GetInt64();
        if (prop.ValueKind == JsonValueKind.Null)
            return null;
        if (long.TryParse(prop.GetString(), out var val))
            return val;
        return null;
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

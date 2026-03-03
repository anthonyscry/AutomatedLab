using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Management;
using System.Net.Sockets;
using System.Text.Json;
using System.Threading.Tasks;
using OpenCodeLab.Models;

namespace OpenCodeLab.Services;

public class HyperVService
{
    private const string HyperVNamespace = @"root\virtualization\v2";
    private static readonly ConcurrentDictionary<string, (string? DetectedRole, DateTime ExpiresUtc)> DetectionCache = new();
    private static readonly TimeSpan DetectionCacheTtl = TimeSpan.FromSeconds(30);
    private static Dictionary<string, VMDefinition>? _labConfigCache;
    private static DateTime _labConfigCacheExpiry = DateTime.MinValue;
    private static readonly TimeSpan LabConfigCacheTtl = TimeSpan.FromSeconds(60);
    private static List<VirtualMachine>? _vmListCache;
    private static DateTime _vmListCacheExpiry = DateTime.MinValue;
    private static readonly TimeSpan VmListCacheTtl = TimeSpan.FromSeconds(10);

    public async Task<List<VirtualMachine>> GetVirtualMachinesAsync()
    {
        if (_vmListCache != null && DateTime.UtcNow < _vmListCacheExpiry)
            return new List<VirtualMachine>(_vmListCache);

        var vms = await GetVirtualMachinesUncachedAsync();
        _vmListCache = vms;
        _vmListCacheExpiry = DateTime.UtcNow.Add(VmListCacheTtl);
        return new List<VirtualMachine>(vms);
    }

    private async Task<List<VirtualMachine>> GetVirtualMachinesUncachedAsync()
    {
        var vms = new List<VirtualMachine>();
        try
        {
            // Load lab config to get Role and IP info
            var labLookup = LoadLabConfigLookup();

            await Task.Run(() =>
            {
                // Get all VM details via PowerShell (memory, CPU, IP) in one call
                var vmDetails = GetAllVMDetails();
                var vmUptimes = GetAllVMUptimes();

                using var searcher = new ManagementObjectSearcher(HyperVNamespace,
                    "SELECT * FROM Msvm_ComputerSystem WHERE Caption = 'Virtual Machine'");

                foreach (ManagementObject vm in searcher.Get())
                {
                    var name = vm["ElementName"]?.ToString() ?? "Unknown";
                    var state = vm["EnabledState"] != null
                        ? GetStateText((ushort)vm["EnabledState"]) : "Unknown";

                    long memGB = 0;
                    int cpus = 0;
                    string? ip = null;

                    // Use PowerShell data if available (more reliable than WMI)
                    if (vmDetails.TryGetValue(name, out var details))
                    {
                        memGB = details.MemoryMB / 1024; // MB to GB
                        cpus = details.Processors;
                        ip = details.IP;
                    }

                    var vmObj = new VirtualMachine
                    {
                        Name = name, State = state,
                        MemoryGB = memGB,
                        Processors = cpus,
                        Uptime = state == "Running" && vmUptimes.TryGetValue(name, out var uptime) ? uptime : TimeSpan.Zero,
                        IPAddress = ip
                    };

                    // Enrich with lab config data (role, configured IP if not running)
                    if (labLookup.TryGetValue(name, out var labVm))
                    {
                        vmObj.Role = NormalizeRole(labVm.Role);
                        if (string.IsNullOrEmpty(vmObj.IPAddress) && !string.IsNullOrEmpty(labVm.IPAddress))
                            vmObj.IPAddress = labVm.IPAddress;
                    }

                    vmObj.DetectedRole = DetectRoleFromLiveSignals(vmObj);

                    vms.Add(vmObj);
                }
            });
        }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"Error: {ex.Message}"); }
        return vms;
    }

    /// <summary>
    /// Load the most recent lab config to get Role/IP mappings for VMs.
    /// </summary>
    private static Dictionary<string, VMDefinition> LoadLabConfigLookup()
    {
        if (_labConfigCache != null && DateTime.UtcNow < _labConfigCacheExpiry)
            return _labConfigCache;

        var lookup = new Dictionary<string, VMDefinition>(StringComparer.OrdinalIgnoreCase);
        try
        {
            var configDir = LabPaths.LabConfig;
            if (Directory.Exists(configDir))
            {
                // Find most recently modified lab config
                var latestConfig = Directory.GetFiles(configDir, "*.json")
                    .OrderByDescending(File.GetLastWriteTime)
                    .FirstOrDefault();
                if (latestConfig != null)
                {
                    var json = File.ReadAllText(latestConfig);
                    var config = JsonSerializer.Deserialize<LabConfig>(json);
                    if (config?.VMs != null)
                    {
                        foreach (var vm in config.VMs)
                        {
                            if (!string.IsNullOrEmpty(vm.Name))
                                lookup[vm.Name] = vm;
                        }
                    }
                }
            }
        }
         catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"Failed to load lab config: {ex.Message}"); }

         _labConfigCache = lookup;
         _labConfigCacheExpiry = DateTime.UtcNow.Add(LabConfigCacheTtl);
         return lookup;
    }

    private static string NormalizeRole(string? role)
    {
        if (string.IsNullOrWhiteSpace(role))
            return "Unknown";

        return role.Trim().ToLowerInvariant() switch
        {
            "ms" => "MemberServer",
            "member" => "MemberServer",
            "server" => "MemberServer",
            _ => role.Trim()
        };
    }

    private static string? DetectRoleFromLiveSignals(VirtualMachine vm)
    {
        if (vm.State != "Running" || string.IsNullOrWhiteSpace(vm.IPAddress))
            return null;

        if (!string.Equals(vm.Role, "MemberServer", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(vm.Role, "Unknown", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var cacheKey = $"{vm.Name}|{vm.IPAddress}";
        if (DetectionCache.TryGetValue(cacheKey, out var cached) && cached.ExpiresUtc > DateTime.UtcNow)
            return cached.DetectedRole;

        string? detectedRole = null;
        if (IsTcpPortOpen(vm.IPAddress, 8530, 150) || IsTcpPortOpen(vm.IPAddress, 8531, 150))
            detectedRole = "WSUS";

        DetectionCache[cacheKey] = (detectedRole, DateTime.UtcNow.Add(DetectionCacheTtl));

        return detectedRole;
    }

     private static bool IsTcpPortOpen(string host, int port, int timeoutMs)
     {
         try
         {
             using var client = new TcpClient();
             var connectTask = client.ConnectAsync(host, port);
             // PERF: Blocking wait used because callers are synchronous. Consider async when callers support it.
             var completed = connectTask.Wait(timeoutMs);
             return completed && client.Connected;
         }
         catch
         {
             return false;
         }
     }

    /// <summary>
    /// Get all VM details (memory, CPU, IP) via a single PowerShell call for efficiency.
    /// </summary>
    private static Dictionary<string, (long MemoryMB, int Processors, string? IP)> GetAllVMDetails()
    {
        var result = new Dictionary<string, (long, int, string?)>(StringComparer.OrdinalIgnoreCase);
        try
        {
            const string script = "Get-VM | ForEach-Object { $ip = ($_ | Get-VMNetworkAdapter | Select-Object -ExpandProperty IPAddresses | Where-Object { $_ -match '^\\d+\\.\\d+\\.\\d+\\.\\d+$' -and $_ -ne '127.0.0.1' } | Select-Object -First 1); Write-Output \"$($_.Name)|$($_.MemoryAssigned / 1MB)|$($_.ProcessorCount)|$ip\" }";
            var (output, errors, success) = PowerShellRunner.RunScriptAsync(script).GetAwaiter().GetResult();
            if (!success && !string.IsNullOrWhiteSpace(errors))
                System.Diagnostics.Debug.WriteLine($"Failed to get VM details: {errors}");

            foreach (var line in output.Split('\n', StringSplitOptions.RemoveEmptyEntries))
            {
                var parts = line.Trim().Split('|');
                if (parts.Length >= 4)
                {
                    var name = parts[0];
                    long.TryParse(parts[1], out var memMB);
                    int.TryParse(parts[2], out var cpus);
                    var ip = string.IsNullOrWhiteSpace(parts[3]) ? null : parts[3].Trim();
                    result[name] = (memMB, cpus, ip);
                }
            }
        }
         catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"Failed to get VM details: {ex.Message}"); }
         return result;
     }

     public async Task<bool> StartVMAsync(string vmName) => await ExecuteVMStateChangeAsync(vmName, 2);
    public async Task<bool> StopVMAsync(string vmName) => await ExecuteVMStateChangeAsync(vmName, 3);
    public async Task<bool> PauseVMAsync(string vmName) => await ExecuteVMStateChangeAsync(vmName, 9);
    public async Task<bool> RestartVMAsync(string vmName)
    {
        await StopVMAsync(vmName);
        await Task.Delay(2000);
        return await StartVMAsync(vmName);
    }

      public async Task<bool> RemoveVMAsync(string vmName, bool deleteDisk = true)
      {
          try
          {
             // First, ensure VM is stopped
             await ExecuteVMStateChangeAsync(vmName, 3);
             await Task.Delay(2000);

              var safeVmName = vmName.Replace("'", "''");
              var script = new System.Text.StringBuilder();
              script.AppendLine("Import-Module Hyper-V -ErrorAction SilentlyContinue");
              script.AppendLine($"$vm = Get-VM -Name '{safeVmName}' -ErrorAction SilentlyContinue");
              script.AppendLine("if ($vm) {");
              script.AppendLine("  $diskPaths = $vm.HardDrives.Path");
              script.AppendLine($"  Write-Host 'Removing VM: {safeVmName}'");
              script.AppendLine($"  Remove-VM -Name '{safeVmName}' -Force -ErrorAction Stop");

              if (deleteDisk)
              {
                  script.AppendLine("  foreach ($disk in $diskPaths) {");
                  script.AppendLine("    if (Test-Path $disk) {");
                  script.AppendLine("      Write-Host \"Deleting disk: $disk\"");
                  script.AppendLine("      Remove-Item -Path $disk -Force -ErrorAction SilentlyContinue");
                  script.AppendLine("    }");
                  script.AppendLine("  }");
              }
              script.AppendLine("}");

              var (_, errors, removed) = await PowerShellRunner.RunScriptAsync(script.ToString());
              if (!removed && !string.IsNullOrWhiteSpace(errors))
                  System.Diagnostics.Debug.WriteLine($"Error removing VM: {errors}");

              if (removed)
                  InvalidateVmCache();

              return removed;
          }
          catch (Exception ex)
          {
              System.Diagnostics.Debug.WriteLine($"Error removing VM: {ex.Message}");
              return false;
         }
     }

     private static string GetStateText(ushort state) => state switch
     {
         2 => "Running", 3 => "Off", 6 => "Saved", 9 => "Paused", _ => "Unknown"
     };

     private static Dictionary<string, TimeSpan> GetAllVMUptimes()
     {
         var uptimes = new Dictionary<string, TimeSpan>(StringComparer.OrdinalIgnoreCase);
         try
         {
             using var searcher = new ManagementObjectSearcher(HyperVNamespace,
                 "SELECT ElementName, TimeOfLastStateChange FROM Msvm_ComputerSystem WHERE Caption = 'Virtual Machine'");
             foreach (ManagementObject vm in searcher.Get())
             {
                 var name = vm["ElementName"]?.ToString();
                 var val = vm["TimeOfLastStateChange"]?.ToString();
                 if (!string.IsNullOrEmpty(name) && !string.IsNullOrEmpty(val))
                 {
                     var dt = ManagementDateTimeConverter.ToDateTime(val);
                     uptimes[name] = DateTime.Now - dt;
                 }
             }
         }
         catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"Failed to batch query VM uptimes: {ex.Message}"); }
         return uptimes;
     }

     private static void InvalidateVmCache()
     {
         _vmListCache = null;
         _vmListCacheExpiry = DateTime.MinValue;
     }

    private async Task<bool> ExecuteVMStateChangeAsync(string vmName, ushort requestedState)
    {
        return await Task.Run(() =>
        {
            try
            {
                using var s = new ManagementObjectSearcher(HyperVNamespace,
                    $"SELECT * FROM Msvm_ComputerSystem WHERE ElementName = '{vmName}'");
                foreach (ManagementObject vm in s.Get())
                {
                    using var p = vm.GetMethodParameters("RequestStateChange");
                    p["RequestedState"] = requestedState;
                    using var r = vm.InvokeMethod("RequestStateChange", p, null);
                    var success = (uint)r["ReturnValue"] == 0;
                    if (success)
                        InvalidateVmCache();
                    return success;
                }
                return false;
            }
             catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"VM state change failed for {vmName}: {ex.Message}"); return false; }
        });
    }
}

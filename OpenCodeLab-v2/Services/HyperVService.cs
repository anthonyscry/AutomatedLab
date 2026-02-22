using System;
using System.Collections.Generic;
using System.Linq;
using System.Management;
using System.Threading.Tasks;
using OpenCodeLab.Models;

namespace OpenCodeLab.Services;

public class HyperVService
{
    private const string HyperVNamespace = @"root\virtualization\v2";

    public async Task<List<VirtualMachine>> GetVirtualMachinesAsync()
    {
        var vms = new List<VirtualMachine>();
        try
        {
            await Task.Run(() =>
            {
                using var searcher = new ManagementObjectSearcher(HyperVNamespace,
                    "SELECT * FROM Msvm_ComputerSystem WHERE Caption = 'Virtual Machine'");

                foreach (ManagementObject vm in searcher.Get())
                {
                    var name = vm["ElementName"]?.ToString() ?? "Unknown";
                    var state = vm["EnabledState"] != null
                        ? GetStateText((ushort)vm["EnabledState"]) : "Unknown";

                    vms.Add(new VirtualMachine
                    {
                        Name = name, State = state,
                        MemoryGB = GetVMMemoryGB(name),
                        Processors = GetVMProcessors(name),
                        Uptime = state == "Running" ? GetVMUptime(name) : TimeSpan.Zero
                    });
                }
            });
        }
        catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"Error: {ex.Message}"); }
        return vms;
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
        return await Task.Run(() =>
        {
            try
            {
                // First, ensure VM is stopped
                ExecuteVMStateChangeAsync(vmName, 3).Wait();
                System.Threading.Thread.Sleep(2000);

                // Use PowerShell for reliable VM removal
                var script = new System.Text.StringBuilder();
                script.AppendLine("Import-Module Hyper-V -ErrorAction SilentlyContinue");

                // Get VM and disk paths before removal
                script.AppendLine($"$vm = Get-VM -Name '{vmName}' -ErrorAction SilentlyContinue");
                script.AppendLine("if ($vm) {");
                script.AppendLine("  $diskPaths = $vm.HardDrives.Path");
                script.AppendLine($"  Write-Host 'Removing VM: {vmName}'");
                script.AppendLine($"  Remove-VM -Name '{vmName}' -Force -ErrorAction Stop");

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

                var startInfo = new System.Diagnostics.ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = $"-ExecutionPolicy Bypass -Command \"{script}\"",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };

                using var process = System.Diagnostics.Process.Start(startInfo);
                if (process == null) return false;
                process.WaitForExit();

                return process.ExitCode == 0;
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"Error removing VM: {ex.Message}");
                return false;
            }
        });
    }

    private static string GetStateText(ushort state) => state switch
    {
        2 => "Running", 3 => "Off", 6 => "Saved", 9 => "Paused", _ => "Unknown"
    };

    private static long GetVMMemoryGB(string name)
    {
        try
        {
            using var s = new ManagementObjectSearcher(HyperVNamespace,
                $"SELECT * FROM Msvm_MemorySettingData WHERE InstanceID LIKE '%|%{name}|%'");
            foreach (ManagementObject m in s.Get()) return Convert.ToInt64(m["VirtualQuantity"]) / 1024;
        }
        catch { }
        return 0;
    }

    private static int GetVMProcessors(string name)
    {
        try
        {
            using var s = new ManagementObjectSearcher(HyperVNamespace,
                $"SELECT * FROM Msvm_ProcessorSettingData WHERE InstanceID LIKE '%|%{name}|%'");
            foreach (ManagementObject m in s.Get()) return Convert.ToInt32(m["VirtualQuantity"]);
        }
        catch { }
        return 0;
    }

    private static TimeSpan GetVMUptime(string name)
    {
        try
        {
            using var s = new ManagementObjectSearcher(HyperVNamespace,
                $"SELECT * FROM Msvm_ComputerSystem WHERE ElementName = '{name}'");
            foreach (ManagementObject vm in s.Get())
            {
                var val = vm["TimeOfLastStateChange"]?.ToString();
                if (!string.IsNullOrEmpty(val))
                {
                    var dt = ManagementDateTimeConverter.ToDateTime(val);
                    return DateTime.Now - dt;
                }
            }
        }
        catch { }
        return TimeSpan.Zero;
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
                    return (uint)r["ReturnValue"] == 0;
                }
                return false;
            }
            catch { return false; }
        });
    }
}

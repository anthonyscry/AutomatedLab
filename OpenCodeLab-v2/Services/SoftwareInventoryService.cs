using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using OpenCodeLab.Models;

namespace OpenCodeLab.Services;

public class SoftwareInventoryService
{
    private static readonly string DefaultInventoryDir = Path.Combine("C:\\", "LabSources", "Inventory");
    private static readonly string InventoryFileName = "inventory.json";

    public async Task<ScanResult> ScanVMAsync(string vmName, string labName, CancellationToken ct)
    {
        try
        {
            var scriptPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Get-VMSoftwareInventory.ps1");
            if (!File.Exists(scriptPath))
            {
                scriptPath = Path.Combine(
                    Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location)!,
                    "Get-VMSoftwareInventory.ps1");
            }

            var parameters = new Dictionary<string, object?>
            {
                ["VMName"] = vmName
            };
            if (!string.IsNullOrWhiteSpace(labName))
                parameters["LabName"] = labName;

            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeoutCts.CancelAfter(TimeSpan.FromSeconds(60));

            string output;
            string errorOutput;
            bool success;

            try
            {
                (output, errorOutput, success) = await PowerShellRunner.RunFileAsync(scriptPath, parameters, timeoutCts.Token);
            }
            catch (OperationCanceledException)
            {
                return new ScanResult
                {
                    VMName = vmName,
                    ScannedAt = DateTime.UtcNow,
                    Success = false,
                    ErrorMessage = ct.IsCancellationRequested
                        ? "Scan cancelled by user"
                        : "Scan timed out after 60 seconds"
                };
            }

            if (!success && string.IsNullOrWhiteSpace(output))
            {
                return new ScanResult
                {
                    VMName = vmName,
                    ScannedAt = DateTime.UtcNow,
                    Success = false,
                    ErrorMessage = string.IsNullOrWhiteSpace(errorOutput)
                        ? "PowerShell execution failed"
                        : errorOutput.Trim()
                };
            }

            if (string.IsNullOrWhiteSpace(output))
            {
                return new ScanResult
                {
                    VMName = vmName,
                    ScannedAt = DateTime.UtcNow,
                    Success = false,
                    ErrorMessage = "No output from scan script"
                };
            }

            var result = JsonSerializer.Deserialize<ScanResult>(output.Trim());
            return result ?? new ScanResult
            {
                VMName = vmName,
                ScannedAt = DateTime.UtcNow,
                Success = false,
                ErrorMessage = "Failed to parse scan output"
            };
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"ScanVMAsync error for {vmName}: {ex.Message}");
            return new ScanResult
            {
                VMName = vmName,
                ScannedAt = DateTime.UtcNow,
                Success = false,
                ErrorMessage = ex.Message
            };
        }
    }

    public async Task<List<ScanResult>> ScanAllRunningVMsAsync(
        IEnumerable<VirtualMachine> vms,
        string labName,
        IProgress<string>? progress,
        CancellationToken ct)
    {
        var results = new List<ScanResult>();
        var runningVMs = vms.Where(v => v.State == "Running").ToList();
        var skippedVMs = vms.Where(v => v.State != "Running").ToList();

        foreach (var vm in skippedVMs)
        {
            results.Add(new ScanResult
            {
                VMName = vm.Name,
                VMState = vm.State,
                ScannedAt = DateTime.UtcNow,
                Success = false,
                ErrorMessage = $"VM is not running (state: {vm.State})"
            });
        }

        for (int i = 0; i < runningVMs.Count; i++)
        {
            ct.ThrowIfCancellationRequested();
            var vm = runningVMs[i];
            progress?.Report($"Scanning {vm.Name} ({i + 1}/{runningVMs.Count})...");

            var result = await ScanVMAsync(vm.Name, labName, ct);
            results.Add(result);
        }

        progress?.Report($"Scan complete: {results.Count(r => r.Success)} of {results.Count} VMs scanned successfully");
        return results;
    }

    public async Task SaveResultsAsync(List<ScanResult> results, string? inventoryDir = null)
    {
        try
        {
            var dir = inventoryDir ?? DefaultInventoryDir;
            Directory.CreateDirectory(dir);
            var filePath = Path.Combine(dir, InventoryFileName);
            var json = JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true });
            await File.WriteAllTextAsync(filePath, json);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"SaveResultsAsync error: {ex.Message}");
        }
    }

    public async Task<List<ScanResult>> LoadResultsAsync(string? inventoryDir = null)
    {
        try
        {
            var dir = inventoryDir ?? DefaultInventoryDir;
            var filePath = Path.Combine(dir, InventoryFileName);
            if (!File.Exists(filePath))
                return new List<ScanResult>();

            var json = await File.ReadAllTextAsync(filePath);
            var results = JsonSerializer.Deserialize<List<ScanResult>>(json);
            return results ?? new List<ScanResult>();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"LoadResultsAsync error: {ex.Message}");
            return new List<ScanResult>();
        }
    }

    public void DeletePersistedResults(string? inventoryDir = null)
    {
        try
        {
            var dir = inventoryDir ?? DefaultInventoryDir;
            var filePath = Path.Combine(dir, InventoryFileName);
            if (File.Exists(filePath))
                File.Delete(filePath);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"DeletePersistedResults error: {ex.Message}");
        }
    }
}

using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using OpenCodeLab.Models;

namespace OpenCodeLab.Services;

/// <summary>
/// Service for extended drift detection that includes host-level configuration
/// </summary>
public class ExtendedDriftDetectionService
{
    private readonly DriftDetectionService _guestDriftService = new();
    private readonly HostBaselineCaptureService _hostCaptureService = new();

    /// <summary>
    /// Capture a complete extended baseline (in-guest + host-level)
    /// </summary>
    public async Task<ExtendedDriftBaseline> CaptureExtendedBaselineAsync(
        string labName,
        string? description = null,
        Action<string>? log = null,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(labName))
            throw new ArgumentException("Lab name is required.", nameof(labName));

        log?.Invoke($"Capturing extended baseline for lab '{labName}'...");

        var baseline = new ExtendedDriftBaseline
        {
            Id = Guid.NewGuid().ToString("N"),
            LabName = labName,
            CreatedAt = DateTime.UtcNow,
            CreatedBy = Environment.UserName,
            Description = description
        };

        try
        {
            // Capture in-guest baseline using existing service
            log?.Invoke("Capturing in-guest VM states...");
            var guestBaseline = await _guestDriftService.CaptureBaselineAsync(labName, log, ct);
            baseline.VmBaselines = guestBaseline.VMStates;
        }
        catch (Exception ex)
        {
            log?.Invoke($"Warning: Could not capture in-guest baseline: {ex.Message}");
            // Continue with host-level only
        }

        // Capture host-level VM configurations
        log?.Invoke("Capturing host-level VM configurations...");
        baseline.HostVmConfigs = await _hostCaptureService.CaptureVmConfigurationsAsync(labName, log, ct);

        // Capture network configuration
        log?.Invoke("Capturing network configuration...");
        baseline.NetworkConfig = await _hostCaptureService.CaptureNetworkConfigurationAsync(labName, log, ct);

        // Capture lab configuration snapshot
        baseline.LabConfig = CaptureLabConfigSnapshot(labName);

        // Save the baseline
        await _hostCaptureService.SaveExtendedBaselineAsync(baseline, ct);

        log?.Invoke($"Extended baseline captured: {baseline.Id}");
        return baseline;
    }

    /// <summary>
    /// Detect drift against an extended baseline
    /// </summary>
    public async Task<ExtendedDriftReport> DetectExtendedDriftAsync(
        string labName,
        string? baselineId = null,
        Action<string>? log = null,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(labName))
            throw new ArgumentException("Lab name is required.", nameof(labName));

        log?.Invoke($"Running extended drift detection for lab '{labName}'...");

        // Load the baseline
        var baseline = await _hostCaptureService.GetExtendedBaselineAsync(labName, baselineId, ct);
        if (baseline == null)
            throw new InvalidOperationException($"No baseline found for lab '{labName}'.");

        var report = new ExtendedDriftReport
        {
            Id = Guid.NewGuid().ToString("N"),
            LabName = labName,
            BaselineId = baseline.Id,
            BaselineDescription = baseline.Description,
            GeneratedAt = DateTime.UtcNow
        };

        // 1. Run in-guest drift detection
        try
        {
            log?.Invoke("Checking in-guest drift...");
            var guestReport = await _guestDriftService.DetectDriftAsync(labName, baseline.Id, log, ct);
            report.VmGuestDrift = guestReport.Results;
        }
        catch (Exception ex)
        {
            log?.Invoke($"Warning: In-guest drift detection failed: {ex.Message}");
        }

        // 2. Capture current host-level configuration
        log?.Invoke("Capturing current host configuration...");
        var currentHostConfigs = await _hostCaptureService.CaptureVmConfigurationsAsync(labName, log, ct);

        // 3. Compare host-level configurations
        log?.Invoke("Comparing host-level configurations...");
        report.HostVmDrift = CompareHostVmConfigs(baseline.HostVmConfigs, currentHostConfigs, log);

        // 4. Compare network configurations
        if (baseline.NetworkConfig != null)
        {
            log?.Invoke("Comparing network configurations...");
            var currentNetwork = await _hostCaptureService.CaptureNetworkConfigurationAsync(labName, log, ct);
            report.NetworkDrift = CompareNetworkConfigs(baseline.NetworkConfig, currentNetwork, log);
        }

        // 5. Determine overall status
        report.OverallStatus = DetermineOverallStatus(report);

        log?.Invoke($"Extended drift detection complete. Status: {report.OverallStatus}, Items: {report.TotalDriftCount}");
        return report;
    }

    /// <summary>
    /// Get list of extended baselines for a lab
    /// </summary>
    public async Task<List<ExtendedDriftBaseline>> ListBaselinesAsync(string labName, CancellationToken ct = default)
    {
        return await _hostCaptureService.ListExtendedBaselinesAsync(labName, ct);
    }

    /// <summary>
    /// Get a specific extended baseline
    /// </summary>
    public async Task<ExtendedDriftBaseline?> GetBaselineAsync(string labName, string? baselineId = null, CancellationToken ct = default)
    {
        return await _hostCaptureService.GetExtendedBaselineAsync(labName, baselineId, ct);
    }

    /// <summary>
    /// Delete a baseline
    /// </summary>
    public async Task<bool> DeleteBaselineAsync(string labName, string baselineId, CancellationToken ct = default)
    {
        return await _guestDriftService.DeleteBaselineAsync(labName, baselineId, ct);
    }

    private List<HostVmDriftResult> CompareHostVmConfigs(
        List<HostVmConfiguration> baseline,
        List<HostVmConfiguration> current,
        Action<string>? log)
    {
        var results = new List<HostVmDriftResult>();
        var currentLookup = current.ToDictionary(c => c.VmName, StringComparer.OrdinalIgnoreCase);

        foreach (var baselineVm in baseline)
        {
            var result = new HostVmDriftResult { VmName = baselineVm.VmName };

            if (!currentLookup.TryGetValue(baselineVm.VmName, out var currentVm))
            {
                result.VmExists = false;
                result.Items.Add(new HostDriftItem
                {
                    Category = "Existence",
                    Property = "VM Presence",
                    Expected = "Present",
                    Actual = "Not found",
                    Severity = DriftSeverity.Critical
                });
                results.Add(result);
                continue;
            }

            result.VmExists = true;

            // Compare processor count
            if (baselineVm.ProcessorCount != currentVm.ProcessorCount)
            {
                result.Items.Add(new HostDriftItem
                {
                    Category = "Hardware",
                    Property = "Processor Count",
                    Expected = baselineVm.ProcessorCount.ToString(),
                    Actual = currentVm.ProcessorCount.ToString(),
                    Severity = DriftSeverity.Warning
                });
            }

            // Compare memory
            if (baselineVm.MemoryStartupBytes != currentVm.MemoryStartupBytes)
            {
                result.Items.Add(new HostDriftItem
                {
                    Category = "Hardware",
                    Property = "Startup Memory",
                    Expected = baselineVm.MemoryStartupGB,
                    Actual = currentVm.MemoryStartupGB,
                    Severity = DriftSeverity.Warning
                });
            }

            if (baselineVm.MemoryMaximumBytes != currentVm.MemoryMaximumBytes)
            {
                result.Items.Add(new HostDriftItem
                {
                    Category = "Hardware",
                    Property = "Maximum Memory",
                    Expected = baselineVm.MemoryMaximumGB,
                    Actual = currentVm.MemoryMaximumGB,
                    Severity = DriftSeverity.Info
                });
            }

            // Compare disk count
            if (baselineVm.Disks.Count != currentVm.Disks.Count)
            {
                result.Items.Add(new HostDriftItem
                {
                    Category = "Disk",
                    Property = "Disk Count",
                    Expected = baselineVm.Disks.Count.ToString(),
                    Actual = currentVm.Disks.Count.ToString(),
                    Severity = DriftSeverity.Warning
                });
            }

            // Compare disk sizes
            foreach (var baseDisk in baselineVm.Disks)
            {
                var matchingDisk = currentVm.Disks.FirstOrDefault(d =>
                    d.ControllerNumber == baseDisk.ControllerNumber &&
                    d.ControllerLocation == baseDisk.ControllerLocation);

                if (matchingDisk == null)
                {
                    result.Items.Add(new HostDriftItem
                    {
                        Category = "Disk",
                        Property = $"Disk at {baseDisk.ControllerNumber}:{baseDisk.ControllerLocation}",
                        Expected = baseDisk.Path,
                        Actual = "Not found",
                        Severity = DriftSeverity.Warning
                    });
                }
                else if (baseDisk.SizeBytes != matchingDisk.SizeBytes)
                {
                    result.Items.Add(new HostDriftItem
                    {
                        Category = "Disk",
                        Property = $"Disk Size ({baseDisk.Path})",
                        Expected = baseDisk.SizeGB,
                        Actual = matchingDisk.SizeGB,
                        Severity = DriftSeverity.Info
                    });
                }
            }

            // Compare network adapters
            if (baselineVm.NetworkAdapters.Count != currentVm.NetworkAdapters.Count)
            {
                result.Items.Add(new HostDriftItem
                {
                    Category = "Network",
                    Property = "Network Adapter Count",
                    Expected = baselineVm.NetworkAdapters.Count.ToString(),
                    Actual = currentVm.NetworkAdapters.Count.ToString(),
                    Severity = DriftSeverity.Warning
                });
            }

            foreach (var baseAdapter in baselineVm.NetworkAdapters)
            {
                var matchingAdapter = currentVm.NetworkAdapters.FirstOrDefault(a =>
                    string.Equals(a.Name, baseAdapter.Name, StringComparison.OrdinalIgnoreCase));

                if (matchingAdapter == null)
                {
                    result.Items.Add(new HostDriftItem
                    {
                        Category = "Network",
                        Property = $"Adapter {baseAdapter.Name}",
                        Expected = "Present",
                        Actual = "Not found",
                        Severity = DriftSeverity.Warning
                    });
                }
                else if (baseAdapter.SwitchName != matchingAdapter.SwitchName)
                {
                    result.Items.Add(new HostDriftItem
                    {
                        Category = "Network",
                        Property = $"Switch for {baseAdapter.Name}",
                        Expected = baseAdapter.SwitchName ?? "None",
                        Actual = matchingAdapter.SwitchName ?? "None",
                        Severity = DriftSeverity.Warning
                    });
                }
            }

            results.Add(result);
        }

        // Check for new VMs not in baseline
        var baselineNames = baseline.Select(b => b.VmName).ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var currentVm in current)
        {
            if (!baselineNames.Contains(currentVm.VmName))
            {
                results.Add(new HostVmDriftResult
                {
                    VmName = currentVm.VmName,
                    VmExists = true,
                    Items = new List<HostDriftItem>
                    {
                        new()
                        {
                            Category = "Inventory",
                            Property = "VM Presence",
                            Expected = "Not in baseline",
                            Actual = "New VM",
                            Severity = DriftSeverity.Info
                        }
                    }
                });
            }
        }

        return results;
    }

    private List<NetworkDriftItem> CompareNetworkConfigs(
        HostNetworkConfiguration baseline,
        HostNetworkConfiguration current,
        Action<string>? log)
    {
        var items = new List<NetworkDriftItem>();

        // Compare switches
        var baseSwitches = baseline.Switches.ToDictionary(s => s.Name, StringComparer.OrdinalIgnoreCase);
        foreach (var currentSwitch in current.Switches)
        {
            if (!baseSwitches.TryGetValue(currentSwitch.Name, out var baseSwitch))
            {
                items.Add(new NetworkDriftItem
                {
                    Category = "Switch",
                    ComponentName = currentSwitch.Name,
                    Property = "Presence",
                    Expected = "Not in baseline",
                    Actual = "New switch",
                    Severity = DriftSeverity.Info
                });
                continue;
            }

            if (baseSwitch.SwitchType != currentSwitch.SwitchType)
            {
                items.Add(new NetworkDriftItem
                {
                    Category = "Switch",
                    ComponentName = currentSwitch.Name,
                    Property = "Type",
                    Expected = baseSwitch.SwitchType,
                    Actual = currentSwitch.SwitchType,
                    Severity = DriftSeverity.Warning
                });
            }
        }

        // Check for removed switches
        var currentSwitchNames = current.Switches.Select(s => s.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var baseSwitch in baseline.Switches)
        {
            if (!currentSwitchNames.Contains(baseSwitch.Name))
            {
                items.Add(new NetworkDriftItem
                {
                    Category = "Switch",
                    ComponentName = baseSwitch.Name,
                    Property = "Presence",
                    Expected = "Present",
                    Actual = "Not found",
                    Severity = DriftSeverity.Critical
                });
            }
        }

        // Compare NAT configurations
        var baseNats = baseline.NatConfigurations.ToDictionary(n => n.Name, StringComparer.OrdinalIgnoreCase);
        foreach (var currentNat in current.NatConfigurations)
        {
            if (!baseNats.TryGetValue(currentNat.Name, out var baseNat))
            {
                items.Add(new NetworkDriftItem
                {
                    Category = "NAT",
                    ComponentName = currentNat.Name,
                    Property = "Presence",
                    Expected = "Not in baseline",
                    Actual = "New NAT",
                    Severity = DriftSeverity.Info
                });
                continue;
            }

            if (baseNat.Subnet != currentNat.Subnet)
            {
                items.Add(new NetworkDriftItem
                {
                    Category = "NAT",
                    ComponentName = currentNat.Name,
                    Property = "Subnet",
                    Expected = baseNat.Subnet,
                    Actual = currentNat.Subnet,
                    Severity = DriftSeverity.Warning
                });
            }
        }

        return items;
    }

    private static DriftStatus DetermineOverallStatus(ExtendedDriftReport report)
    {
        var allSeverities = report.VmGuestDrift.SelectMany(v => v.Items).Select(i => i.Severity)
            .Concat(report.HostVmDrift.SelectMany(v => v.Items).Select(i => i.Severity))
            .Concat(report.NetworkDrift.Select(i => i.Severity))
            .ToList();

        if (allSeverities.Any(s => s == DriftSeverity.Critical))
            return DriftStatus.Critical;
        if (allSeverities.Any(s => s == DriftSeverity.Warning))
            return DriftStatus.Warning;
        if (allSeverities.Any())
            return DriftStatus.Clean;
        return DriftStatus.Clean;
    }

    private static LabConfigurationSnapshot CaptureLabConfigSnapshot(string labName)
    {
        return new LabConfigurationSnapshot
        {
            LabName = labName,
            CapturedAt = DateTime.UtcNow,
            AppVersion = AppVersion.Display
        };
    }
}

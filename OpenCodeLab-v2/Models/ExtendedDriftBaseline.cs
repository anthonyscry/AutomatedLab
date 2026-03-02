using System;
using System.Collections.Generic;

namespace OpenCodeLab.Models;

/// <summary>
/// Extended baseline that includes both in-guest and host-level state
/// </summary>
public class ExtendedDriftBaseline
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string LabName { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public string CreatedBy { get; set; } = Environment.UserName;
    public string? Description { get; set; }
    public bool IsGoldenBaseline { get; set; }
    
    // Existing in-guest baseline (VM software, services, etc.)
    public List<VMBaselineState> VmBaselines { get; set; } = new();
    
    // New host-level baseline
    public List<HostVmConfiguration> HostVmConfigs { get; set; } = new();
    public HostNetworkConfiguration? NetworkConfig { get; set; }
    public LabConfigurationSnapshot LabConfig { get; set; } = new();

    [System.Text.Json.Serialization.JsonIgnore]
    public int VmCount => VmBaselines.Count;
}

/// <summary>
/// Snapshot of lab configuration at baseline time
/// </summary>
public class LabConfigurationSnapshot
{
    public string LabName { get; set; } = string.Empty;
    public string Domain { get; set; } = string.Empty;
    public string AdminAccount { get; set; } = string.Empty;
    public string NetworkSwitch { get; set; } = string.Empty;
    public string NetworkAddress { get; set; } = string.Empty;
    public int VmCount { get; set; }
    public string AppVersion { get; set; } = string.Empty;
    public DateTime CapturedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// Extended drift report comparing extended baselines
/// </summary>
public class ExtendedDriftReport
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string LabName { get; set; } = string.Empty;
    public string BaselineId { get; set; } = string.Empty;
    public string? BaselineDescription { get; set; }
    public DateTime GeneratedAt { get; set; } = DateTime.UtcNow;
    public DriftStatus OverallStatus { get; set; } = DriftStatus.Clean;
    
    // In-guest drift (existing)
    public List<VMDriftResult> VmGuestDrift { get; set; } = new();
    
    // Host-level drift
    public List<HostVmDriftResult> HostVmDrift { get; set; } = new();
    public List<NetworkDriftItem> NetworkDrift { get; set; } = new();
    
    [System.Text.Json.Serialization.JsonIgnore]
    public int TotalDriftCount => VmGuestDrift.Sum(v => v.Items.Count) 
        + HostVmDrift.Sum(v => v.Items.Count) 
        + NetworkDrift.Count;

    [System.Text.Json.Serialization.JsonIgnore]
    public string StatusEmoji => OverallStatus switch
    {
        DriftStatus.Clean => "✅",
        DriftStatus.Warning => "⚠️",
        DriftStatus.Critical => "🔴",
        _ => "❓"
    };
}

/// <summary>
/// Host-level VM drift result
/// </summary>
public class HostVmDriftResult
{
    public string VmName { get; set; } = string.Empty;
    public bool VmExists { get; set; } = true;
    public List<HostDriftItem> Items { get; set; } = new();
}

/// <summary>
/// Individual host-level drift item
/// </summary>
public class HostDriftItem
{
    public string Category { get; set; } = string.Empty; // Hardware, Disk, Network, etc.
    public string Property { get; set; } = string.Empty;
    public string? Expected { get; set; }
    public string? Actual { get; set; }
    public DriftSeverity Severity { get; set; } = DriftSeverity.Info;

    [System.Text.Json.Serialization.JsonIgnore]
    public string SeverityEmoji => Severity switch
    {
        DriftSeverity.Info => "ℹ️",
        DriftSeverity.Warning => "⚠️",
        DriftSeverity.Critical => "🔴",
        _ => "❓"
    };
}

/// <summary>
/// Network configuration drift item
/// </summary>
public class NetworkDriftItem
{
    public string Category { get; set; } = string.Empty; // Switch, NAT, Adapter
    public string ComponentName { get; set; } = string.Empty;
    public string Property { get; set; } = string.Empty;
    public string? Expected { get; set; }
    public string? Actual { get; set; }
    public DriftSeverity Severity { get; set; } = DriftSeverity.Info;

    [System.Text.Json.Serialization.JsonIgnore]
    public string SeverityEmoji => Severity switch
    {
        DriftSeverity.Info => "ℹ️",
        DriftSeverity.Warning => "⚠️",
        DriftSeverity.Critical => "🔴",
        _ => "❓"
    };
}

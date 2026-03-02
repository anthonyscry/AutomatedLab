using System;
using System.Collections.Generic;

namespace OpenCodeLab.Models;

public class DriftBaseline
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string LabName { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public List<VMBaselineState> VMStates { get; set; } = new();
}

public class VMBaselineState
{
    public string VMName { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty;
    public List<string> RunningServices { get; set; } = new();
    public List<InstalledSoftware> InstalledSoftware { get; set; } = new();
    public List<string> OpenPorts { get; set; } = new();
    public List<string> ScheduledTasks { get; set; } = new();
    public List<string> LocalUsers { get; set; } = new();
    public Dictionary<string, string> RegistryKeys { get; set; } = new();
    public string? FirewallProfile { get; set; }
    public DateTime CapturedAt { get; set; } = DateTime.UtcNow;
}

public class DriftReport
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string LabName { get; set; } = string.Empty;
    public string BaselineId { get; set; } = string.Empty;
    public DateTime GeneratedAt { get; set; } = DateTime.UtcNow;
    public DriftStatus OverallStatus { get; set; } = DriftStatus.Clean;
    public List<VMDriftResult> Results { get; set; } = new();

    [System.Text.Json.Serialization.JsonIgnore]
    public int DriftCount => Results.FindAll(r => r.Items.Count > 0).Count;

    [System.Text.Json.Serialization.JsonIgnore]
    public string StatusEmoji => OverallStatus switch
    {
        DriftStatus.Clean => "✅",
        DriftStatus.Warning => "⚠️",
        DriftStatus.Critical => "🔴",
        _ => "❓"
    };
}

public class VMDriftResult
{
    public string VMName { get; set; } = string.Empty;
    public bool Reachable { get; set; } = true;
    public List<DriftItem> Items { get; set; } = new();
}

public class DriftItem
{
    public string Category { get; set; } = string.Empty;
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

public enum DriftSeverity
{
    Info,
    Warning,
    Critical
}

public enum DriftStatus
{
    Clean,
    Warning,
    Critical
}

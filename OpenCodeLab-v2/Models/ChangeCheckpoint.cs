using System;
using System.Collections.Generic;

namespace OpenCodeLab.Models;

public class ChangeCheckpoint
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string LabName { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public CheckpointStatus Status { get; set; } = CheckpointStatus.Active;
    public List<VMSnapshot> Snapshots { get; set; } = new();
    public Dictionary<string, string> Metadata { get; set; } = new();

    [System.Text.Json.Serialization.JsonIgnore]
    public string DisplayStatus => Status switch
    {
        CheckpointStatus.Active => "✅ Active",
        CheckpointStatus.RolledBack => "↩️ Rolled Back",
        CheckpointStatus.Superseded => "⏭️ Superseded",
        CheckpointStatus.Failed => "❌ Failed",
        _ => "❓ Unknown"
    };

    [System.Text.Json.Serialization.JsonIgnore]
    public string TimeSinceCreation
    {
        get
        {
            var span = DateTime.UtcNow - CreatedAt;
            if (span.TotalMinutes < 60) return $"{(int)span.TotalMinutes}m ago";
            if (span.TotalHours < 24) return $"{(int)span.TotalHours}h ago";
            return $"{(int)span.TotalDays}d ago";
        }
    }
}

public class VMSnapshot
{
    public string VMName { get; set; } = string.Empty;
    public string SnapshotName { get; set; } = string.Empty;
    public string? SnapshotId { get; set; }
    public bool Success { get; set; }
    public string? ErrorMessage { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public string? StateJson { get; set; }
}

public enum CheckpointStatus
{
    Active,
    RolledBack,
    Superseded,
    Failed
}

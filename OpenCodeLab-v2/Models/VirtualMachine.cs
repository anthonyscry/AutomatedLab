using System;

namespace OpenCodeLab.Models;

public class VirtualMachine
{
    public string Name { get; set; } = string.Empty;
    public string State { get; set; } = string.Empty;
    public string Role { get; set; } = "Unknown";
    public long MemoryGB { get; set; }
    public int Processors { get; set; }
    public long DiskSizeGB { get; set; }
    public string? IPAddress { get; set; }
    public TimeSpan Uptime { get; set; }
    public string? SnapshotName { get; set; }
    public DateTime? CreatedAt { get; set; }
    public bool IsSelected { get; set; }

    public string StateEmoji => State switch
    {
        "Running" => "🟢", "Off" => "⚫", "Saved" => "💾", "Paused" => "⏸️",
        _ => "❓"
    };

    public string FormattedUptime => Uptime > TimeSpan.Zero
        ? $"{(int)Uptime.TotalHours}h {Uptime.Minutes}m" : "Off";

    public bool CanStart => State is "Off" or "Saved";
    public bool CanStop => State == "Running";
    public bool CanRestart => State == "Running";
    public bool CanPause => State == "Running";
    public bool CanSnapshot => State is "Running" or "Saved";
}

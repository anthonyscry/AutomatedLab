using System;
using System.Collections.Generic;

namespace OpenCodeLab.Models;

/// <summary>
/// Health status severity levels
/// </summary>
public enum HealthStatus
{
    Healthy = 0,
    Warning = 1,
    Critical = 2,
    Unknown = 3
}

/// <summary>
/// Result of a single health check
/// </summary>
public class HealthCheckResult
{
    public string CheckName { get; set; } = string.Empty;
    public HealthStatus Status { get; set; } = HealthStatus.Unknown;
    public string Message { get; set; } = string.Empty;
    public string? Details { get; set; }
    public DateTime CheckedAt { get; set; } = DateTime.UtcNow;
    public string Category { get; set; } = string.Empty; // "Lab", "VM", "Host"
    public string TargetName { get; set; } = string.Empty; // VM name or "Host"

    [System.Text.Json.Serialization.JsonIgnore]
    public string StatusEmoji => Status switch
    {
        HealthStatus.Healthy => "✅",
        HealthStatus.Warning => "⚠️",
        HealthStatus.Critical => "🔴",
        _ => "❓"
    };

    [System.Text.Json.Serialization.JsonIgnore]
    public string StatusText => Status switch
    {
        HealthStatus.Healthy => "Healthy",
        HealthStatus.Warning => "Warning",
        HealthStatus.Critical => "Critical",
        _ => "Unknown"
    };
}

/// <summary>
/// Aggregated health report for a lab
/// </summary>
public class LabHealthReport
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string LabName { get; set; } = string.Empty;
    public DateTime GeneratedAt { get; set; } = DateTime.UtcNow;
    public HealthStatus OverallStatus { get; set; } = HealthStatus.Unknown;
    public List<HealthCheckResult> Checks { get; set; } = new();
    public List<VmHealthStatus> VmHealthStatuses { get; set; } = new();
    public HostHealthStatus? HostStatus { get; set; }
    
    [System.Text.Json.Serialization.JsonIgnore]
    public int HealthyCount => Checks.Count(c => c.Status == HealthStatus.Healthy);
    
    [System.Text.Json.Serialization.JsonIgnore]
    public int WarningCount => Checks.Count(c => c.Status == HealthStatus.Warning);
    
    [System.Text.Json.Serialization.JsonIgnore]
    public int CriticalCount => Checks.Count(c => c.Status == HealthStatus.Critical);

    [System.Text.Json.Serialization.JsonIgnore]
    public string OverallStatusEmoji => OverallStatus switch
    {
        HealthStatus.Healthy => "✅",
        HealthStatus.Warning => "⚠️",
        HealthStatus.Critical => "🔴",
        _ => "❓"
    };
}

/// <summary>
/// Health status of a single VM
/// </summary>
public class VmHealthStatus
{
    public string VmName { get; set; } = string.Empty;
    public string State { get; set; } = string.Empty; // Running, Off, Saved, etc.
    public HealthStatus Health { get; set; } = HealthStatus.Unknown;
    public List<string> Issues { get; set; } = new();
    public ResourceUtilizationSnapshot? CurrentResources { get; set; }
    public bool IntegrationServicesRunning { get; set; }
    public string? Heartbeat { get; set; }
    public DateTime LastChecked { get; set; } = DateTime.UtcNow;

    [System.Text.Json.Serialization.JsonIgnore]
    public string HealthEmoji => Health switch
    {
        HealthStatus.Healthy => "✅",
        HealthStatus.Warning => "⚠️",
        HealthStatus.Critical => "🔴",
        _ => "❓"
    };
}

/// <summary>
/// Health status of the host machine
/// </summary>
public class HostHealthStatus
{
    public double CpuPercentUsed { get; set; }
    public double MemoryPercentUsed { get; set; }
    public long MemoryAvailableBytes { get; set; }
    public long MemoryTotalBytes { get; set; }
    public List<DiskHealthStatus> Disks { get; set; } = new();
    public HealthStatus OverallStatus { get; set; } = HealthStatus.Unknown;
    public DateTime CheckedAt { get; set; } = DateTime.UtcNow;

    [System.Text.Json.Serialization.JsonIgnore]
    public string MemoryAvailableGB => $"{MemoryAvailableBytes / (1024.0 * 1024 * 1024):F1} GB";

    [System.Text.Json.Serialization.JsonIgnore]
    public string MemoryTotalGB => $"{MemoryTotalBytes / (1024.0 * 1024 * 1024):F1} GB";
}

/// <summary>
/// Health status of a disk
/// </summary>
public class DiskHealthStatus
{
    public string Drive { get; set; } = string.Empty;
    public string? Label { get; set; }
    public long TotalBytes { get; set; }
    public long AvailableBytes { get; set; }
    public double PercentUsed { get; set; }
    public HealthStatus Status { get; set; } = HealthStatus.Healthy;

    [System.Text.Json.Serialization.JsonIgnore]
    public string TotalGB => $"{TotalBytes / (1024.0 * 1024 * 1024):F1} GB";

    [System.Text.Json.Serialization.JsonIgnore]
    public string AvailableGB => $"{AvailableBytes / (1024.0 * 1024 * 1024):F1} GB";
}

/// <summary>
/// Snapshot of resource utilization at a point in time
/// </summary>
public class ResourceUtilizationSnapshot
{
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    
    // CPU
    public double CpuPercentUsed { get; set; }
    
    // Memory (bytes)
    public long MemoryAllocated { get; set; }
    public long MemoryUsed { get; set; }
    public double MemoryPercentUsed { get; set; }
    
    // Disk
    public List<DiskUsage> DiskUsages { get; set; } = new();
    
    // Network (optional)
    public long NetworkBytesReceived { get; set; }
    public long NetworkBytesSent { get; set; }

    [System.Text.Json.Serialization.JsonIgnore]
    public string MemoryAllocatedGB => $"{MemoryAllocated / (1024.0 * 1024 * 1024):F1} GB";

    [System.Text.Json.Serialization.JsonIgnore]
    public string MemoryUsedGB => $"{MemoryUsed / (1024.0 * 1024 * 1024):F1} GB";
}

/// <summary>
/// Disk usage information
/// </summary>
public class DiskUsage
{
    public string Path { get; set; } = string.Empty;
    public long TotalBytes { get; set; }
    public long UsedBytes { get; set; }
    public long AvailableBytes { get; set; }
    public double PercentUsed { get; set; }

    [System.Text.Json.Serialization.JsonIgnore]
    public string TotalGB => $"{TotalBytes / (1024.0 * 1024 * 1024):F1} GB";

    [System.Text.Json.Serialization.JsonIgnore]
    public string AvailableGB => $"{AvailableBytes / (1024.0 * 1024 * 1024):F1} GB";
}

/// <summary>
/// Historical resource utilization entry
/// </summary>
public class ResourceHistoryEntry
{
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    public string LabName { get; set; } = string.Empty;
    public string? VmName { get; set; } // null for host-level
    
    // CPU
    public double CpuPercentUsed { get; set; }
    
    // Memory (bytes)
    public long MemoryAllocated { get; set; }
    public long MemoryUsed { get; set; }
    public double MemoryPercentUsed { get; set; }
    
    // Disk
    public List<DiskUsage> DiskUsages { get; set; } = new();
    
    // Network
    public long NetworkBytesReceived { get; set; }
    public long NetworkBytesSent { get; set; }
}

/// <summary>
/// Health alert for notifications
/// </summary>
public class HealthAlert
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Title { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public HealthStatus Severity { get; set; } = HealthStatus.Warning;
    public string Category { get; set; } = string.Empty;
    public string TargetName { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public bool IsAcknowledged { get; set; }
    public DateTime? AcknowledgedAt { get; set; }
    public string? AcknowledgedBy { get; set; }

    [System.Text.Json.Serialization.JsonIgnore]
    public string SeverityEmoji => Severity switch
    {
        HealthStatus.Healthy => "✅",
        HealthStatus.Warning => "⚠️",
        HealthStatus.Critical => "🔴",
        _ => "❓"
    };

    [System.Text.Json.Serialization.JsonIgnore]
    public TimeSpan Age => DateTime.UtcNow - CreatedAt;

    [System.Text.Json.Serialization.JsonIgnore]
    public string AgeText => Age.TotalMinutes < 1 ? "Just now"
        : Age.TotalMinutes < 60 ? $"{(int)Age.TotalMinutes}m ago"
        : Age.TotalHours < 24 ? $"{(int)Age.TotalHours}h ago"
        : $"{(int)Age.TotalDays}d ago";
}

/// <summary>
/// Alert types for categorization
/// </summary>
public enum AlertType
{
    VmStoppedUnexpectedly,
    LowDiskSpace,
    HighMemoryUsage,
    HighCpuUsage,
    IntegrationServicesNotRunning,
    NetworkConnectivityLost,
    ConfigurationDriftDetected,
    VmHealthCritical,
    HostResourceWarning
}

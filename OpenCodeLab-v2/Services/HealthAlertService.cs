using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using OpenCodeLab.Models;

namespace OpenCodeLab.Services;

/// <summary>
/// Service for managing health alerts
/// </summary>
public class HealthAlertService
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private const string AlertsFile = "alerts.json";
    private readonly object _lock = new();
    private List<HealthAlert> _alerts = new();

    /// <summary>
    /// Get all active alerts
    /// </summary>
    public List<HealthAlert> GetActiveAlerts()
    {
        lock (_lock)
        {
            return _alerts.Where(a => !a.IsAcknowledged)
                .OrderByDescending(a => a.Severity)
                .ThenByDescending(a => a.CreatedAt)
                .ToList();
        }
    }

    /// <summary>
    /// Get all alerts (including acknowledged)
    /// </summary>
    public List<HealthAlert> GetAllAlerts()
    {
        lock (_lock)
        {
            return _alerts.OrderByDescending(a => a.CreatedAt).ToList();
        }
    }

    /// <summary>
    /// Add a new alert
    /// </summary>
    public HealthAlert AddAlert(string title, string message, HealthStatus severity, string category, string targetName)
    {
        var alert = new HealthAlert
        {
            Id = Guid.NewGuid(),
            Title = title,
            Message = message,
            Severity = severity,
            Category = category,
            TargetName = targetName,
            CreatedAt = DateTime.UtcNow,
            IsAcknowledged = false
        };

        lock (_lock)
        {
            // Check for duplicate recent alerts (within 5 minutes)
            var recentDuplicate = _alerts.FirstOrDefault(a =>
                !a.IsAcknowledged &&
                a.Title == title &&
                a.TargetName == targetName &&
                (DateTime.UtcNow - a.CreatedAt).TotalMinutes < 5);

            if (recentDuplicate != null)
                return recentDuplicate;

            _alerts.Add(alert);
        }

        // Persist alerts
        _ = SaveAlertsAsync();

        return alert;
    }

    /// <summary>
    /// Create alert from health check result
    /// </summary>
    public HealthAlert? CreateAlertFromCheck(HealthCheckResult check, string labName)
    {
        if (check.Status == HealthStatus.Healthy || check.Status == HealthStatus.Unknown)
            return null;

        var severity = check.Status == HealthStatus.Critical ? HealthStatus.Critical : HealthStatus.Warning;
        var title = $"{check.CheckName} - {check.TargetName}";
        var message = check.Message;

        if (!string.IsNullOrWhiteSpace(check.Details))
            message += $"\n{check.Details}";

        return AddAlert(title, message, severity, check.Category, $"{labName}/{check.TargetName}");
    }

    /// <summary>
    /// Create VM stopped unexpectedly alert
    /// </summary>
    public HealthAlert CreateVmStoppedAlert(string vmName, string labName)
    {
        return AddAlert(
            "VM Stopped Unexpectedly",
            $"VM '{vmName}' in lab '{labName}' is not running.",
            HealthStatus.Warning,
            "VM",
            $"{labName}/{vmName}");
    }

    /// <summary>
    /// Create low disk space alert
    /// </summary>
    public HealthAlert CreateLowDiskAlert(string drive, double percentUsed)
    {
        return AddAlert(
            "Low Disk Space",
            $"Drive {drive} is {percentUsed:F1}% full. Consider freeing up space.",
            percentUsed > 95 ? HealthStatus.Critical : HealthStatus.Warning,
            "Host",
            drive);
    }

    /// <summary>
    /// Create high resource usage alert
    /// </summary>
    public HealthAlert CreateHighResourceAlert(string resource, double percentUsed, string targetName)
    {
        return AddAlert(
            $"High {resource} Usage",
            $"{resource} usage on {targetName} is {percentUsed:F1}%.",
            percentUsed > 95 ? HealthStatus.Critical : HealthStatus.Warning,
            "Host",
            targetName);
    }

    /// <summary>
    /// Create drift detected alert
    /// </summary>
    public HealthAlert CreateDriftAlert(string labName, int driftCount, DriftStatus status)
    {
        return AddAlert(
            "Configuration Drift Detected",
            $"{driftCount} drift item(s) detected in lab '{labName}'.",
            status == DriftStatus.Critical ? HealthStatus.Critical : HealthStatus.Warning,
            "Drift",
            labName);
    }

    /// <summary>
    /// Acknowledge an alert
    /// </summary>
    public bool AcknowledgeAlert(Guid alertId, string? acknowledgedBy = null)
    {
        lock (_lock)
        {
            var alert = _alerts.FirstOrDefault(a => a.Id == alertId);
            if (alert == null)
                return false;

            alert.IsAcknowledged = true;
            alert.AcknowledgedAt = DateTime.UtcNow;
            alert.AcknowledgedBy = acknowledgedBy ?? Environment.UserName;
        }

        _ = SaveAlertsAsync();
        return true;
    }

    /// <summary>
    /// Acknowledge all alerts
    /// </summary>
    public void AcknowledgeAll(string? acknowledgedBy = null)
    {
        lock (_lock)
        {
            var now = DateTime.UtcNow;
            var user = acknowledgedBy ?? Environment.UserName;

            foreach (var alert in _alerts.Where(a => !a.IsAcknowledged))
            {
                alert.IsAcknowledged = true;
                alert.AcknowledgedAt = now;
                alert.AcknowledgedBy = user;
            }
        }

        _ = SaveAlertsAsync();
    }

    /// <summary>
    /// Clear old acknowledged alerts
    /// </summary>
    public int ClearOldAlerts(int daysOld = 7)
    {
        int removed;
        lock (_lock)
        {
            var cutoff = DateTime.UtcNow.AddDays(-daysOld);
            var toRemove = _alerts.Where(a => a.IsAcknowledged && a.AcknowledgedAt < cutoff).ToList();
            removed = toRemove.Count;

            foreach (var alert in toRemove)
                _alerts.Remove(alert);
        }

        if (removed > 0)
            _ = SaveAlertsAsync();

        return removed;
    }

    /// <summary>
    /// Get alert counts by severity
    /// </summary>
    public Dictionary<HealthStatus, int> GetAlertCounts()
    {
        lock (_lock)
        {
            return _alerts.Where(a => !a.IsAcknowledged)
                .GroupBy(a => a.Severity)
                .ToDictionary(g => g.Key, g => g.Count());
        }
    }

    /// <summary>
    /// Load alerts from disk
    /// </summary>
    public async Task LoadAsync(CancellationToken ct = default)
    {
        var path = GetAlertsPath();
        if (!File.Exists(path))
            return;

        try
        {
            var json = await File.ReadAllTextAsync(path, ct);
            var alerts = JsonSerializer.Deserialize<List<HealthAlert>>(json);
            if (alerts != null)
            {
                lock (_lock)
                {
                    _alerts = alerts;
                }
            }
        }
        catch
        {
            // Ignore load errors
        }
    }

    private async Task SaveAlertsAsync()
    {
        var path = GetAlertsPath();
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);

        List<HealthAlert> alertsToSave;
        lock (_lock)
        {
            alertsToSave = _alerts.ToList();
        }

        var json = JsonSerializer.Serialize(alertsToSave, JsonOptions);
        await File.WriteAllTextAsync(path, json);
    }

    private static string GetAlertsPath()
    {
        return Path.Combine(@"C:\LabSources\LabConfig", "_system", AlertsFile);
    }
}

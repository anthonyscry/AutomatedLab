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
/// Service for tracking resource utilization history over time
/// </summary>
public class ResourceHistoryService
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private const string HistoryFile = "resource-history.jsonl";
    private const int MaxHistoryDays = 30;

    /// <summary>
    /// Record a resource utilization snapshot
    /// </summary>
    public async Task RecordSnapshotAsync(ResourceHistoryEntry entry, CancellationToken ct = default)
    {
        var path = GetHistoryPath(entry.LabName);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);

        var line = JsonSerializer.Serialize(entry);
        await File.AppendAllTextAsync(path, line + "\n", ct);
    }

    /// <summary>
    /// Record host-level resource snapshot
    /// </summary>
    public async Task RecordHostSnapshotAsync(ResourceHistoryEntry entry, CancellationToken ct = default)
    {
        var path = GetHostHistoryPath();
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);

        var line = JsonSerializer.Serialize(entry);
        await File.AppendAllTextAsync(path, line + "\n", ct);
    }

    /// <summary>
    /// Get resource history for a lab
    /// </summary>
    public async Task<List<ResourceHistoryEntry>> GetHistoryAsync(string labName, int hours = 24, CancellationToken ct = default)
    {
        var path = GetHistoryPath(labName);
        if (!File.Exists(path))
            return new List<ResourceHistoryEntry>();

        var entries = new List<ResourceHistoryEntry>();
        var cutoff = DateTime.UtcNow.AddHours(-hours);

        foreach (var line in await File.ReadAllLinesAsync(path, ct))
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            try
            {
                var entry = JsonSerializer.Deserialize<ResourceHistoryEntry>(line);
                if (entry != null && entry.Timestamp >= cutoff)
                    entries.Add(entry);
            }
            catch { }
        }

        return entries.OrderBy(e => e.Timestamp).ToList();
    }

    /// <summary>
    /// Get resource history for a specific VM
    /// </summary>
    public async Task<List<ResourceHistoryEntry>> GetVmHistoryAsync(string labName, string vmName, int hours = 24, CancellationToken ct = default)
    {
        var allEntries = await GetHistoryAsync(labName, hours, ct);
        return allEntries.Where(e => e.VmName?.Equals(vmName, StringComparison.OrdinalIgnoreCase) == true).ToList();
    }

    /// <summary>
    /// Get host resource history
    /// </summary>
    public async Task<List<ResourceHistoryEntry>> GetHostHistoryAsync(int hours = 24, CancellationToken ct = default)
    {
        var path = GetHostHistoryPath();
        if (!File.Exists(path))
            return new List<ResourceHistoryEntry>();

        var entries = new List<ResourceHistoryEntry>();
        var cutoff = DateTime.UtcNow.AddHours(-hours);

        foreach (var line in await File.ReadAllLinesAsync(path, ct))
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            try
            {
                var entry = JsonSerializer.Deserialize<ResourceHistoryEntry>(line);
                if (entry != null && entry.Timestamp >= cutoff)
                    entries.Add(entry);
            }
            catch { }
        }

        return entries.OrderBy(e => e.Timestamp).ToList();
    }

    /// <summary>
    /// Calculate average resource utilization over a period
    /// </summary>
    public async Task<ResourceTrendAnalysis> AnalyzeTrendsAsync(string labName, int hours = 24, CancellationToken ct = default)
    {
        var entries = await GetHistoryAsync(labName, hours, ct);

        var analysis = new ResourceTrendAnalysis
        {
            LabName = labName,
            PeriodHours = hours,
            SampleCount = entries.Count
        };

        if (entries.Count == 0)
            return analysis;

        // Group by VM and calculate averages
        var byVm = entries.Where(e => !string.IsNullOrEmpty(e.VmName))
            .GroupBy(e => e.VmName!)
            .ToDictionary(g => g.Key, g => g.ToList());

        foreach (var kvp in byVm)
        {
            var vmEntries = kvp.Value;
            analysis.VmTrends.Add(new VmResourceTrend
            {
                VmName = kvp.Key,
                AvgCpuPercent = vmEntries.Average(e => e.CpuPercentUsed),
                MaxCpuPercent = vmEntries.Max(e => e.CpuPercentUsed),
                AvgMemoryPercent = vmEntries.Average(e => e.MemoryPercentUsed),
                MaxMemoryPercent = vmEntries.Max(e => e.MemoryPercentUsed),
                SampleCount = vmEntries.Count
            });
        }

        // Calculate overall lab trends
        analysis.AvgCpuPercent = entries.Average(e => e.CpuPercentUsed);
        analysis.MaxCpuPercent = entries.Max(e => e.CpuPercentUsed);
        analysis.AvgMemoryPercent = entries.Average(e => e.MemoryPercentUsed);
        analysis.MaxMemoryPercent = entries.Max(e => e.MemoryPercentUsed);

        // Determine trend direction (compare first half vs second half)
        if (entries.Count >= 10)
        {
            var midpoint = entries.Count / 2;
            var firstHalf = entries.Take(midpoint).ToList();
            var secondHalf = entries.Skip(midpoint).ToList();

            var firstAvgCpu = firstHalf.Average(e => e.CpuPercentUsed);
            var secondAvgCpu = secondHalf.Average(e => e.CpuPercentUsed);

            analysis.CpuTrend = secondAvgCpu > firstAvgCpu + 5 ? TrendDirection.Increasing
                : secondAvgCpu < firstAvgCpu - 5 ? TrendDirection.Decreasing
                : TrendDirection.Stable;

            var firstAvgMem = firstHalf.Average(e => e.MemoryPercentUsed);
            var secondAvgMem = secondHalf.Average(e => e.MemoryPercentUsed);

            analysis.MemoryTrend = secondAvgMem > firstAvgMem + 5 ? TrendDirection.Increasing
                : secondAvgMem < firstAvgMem - 5 ? TrendDirection.Decreasing
                : TrendDirection.Stable;
        }

        return analysis;
    }

    /// <summary>
    /// Clean up old history entries
    /// </summary>
    public async Task CleanupOldHistoryAsync(CancellationToken ct = default)
    {
        var rootDir = @"C:\LabSources\LabConfig";
        var cutoff = DateTime.UtcNow.AddDays(-MaxHistoryDays);

        foreach (var labDir in Directory.GetDirectories(rootDir))
        {
            var historyPath = Path.Combine(labDir, "resource-history.jsonl");
            if (!File.Exists(historyPath))
                continue;

            var lines = await File.ReadAllLinesAsync(historyPath, ct);
            var validLines = new List<string>();

            foreach (var line in lines)
            {
                if (string.IsNullOrWhiteSpace(line)) continue;
                try
                {
                    var entry = JsonSerializer.Deserialize<ResourceHistoryEntry>(line);
                    if (entry != null && entry.Timestamp >= cutoff)
                        validLines.Add(line);
                }
                catch { }
            }

            if (validLines.Count < lines.Length)
            {
                await File.WriteAllLinesAsync(historyPath, validLines, ct);
            }
        }

        // Also clean up host history
        var hostHistoryPath = GetHostHistoryPath();
        if (File.Exists(hostHistoryPath))
        {
            var lines = await File.ReadAllLinesAsync(hostHistoryPath, ct);
            var validLines = new List<string>();

            foreach (var line in lines)
            {
                if (string.IsNullOrWhiteSpace(line)) continue;
                try
                {
                    var entry = JsonSerializer.Deserialize<ResourceHistoryEntry>(line);
                    if (entry != null && entry.Timestamp >= cutoff)
                        validLines.Add(line);
                }
                catch { }
            }

            if (validLines.Count < lines.Length)
            {
                await File.WriteAllLinesAsync(hostHistoryPath, validLines, ct);
            }
        }
    }

    private static string GetHistoryPath(string labName)
    {
        return Path.Combine(@"C:\LabSources\LabConfig", labName, HistoryFile);
    }

    private static string GetHostHistoryPath()
    {
        return Path.Combine(@"C:\LabSources\LabConfig", "_system", HistoryFile);
    }
}

/// <summary>
/// Resource trend analysis result
/// </summary>
public class ResourceTrendAnalysis
{
    public string LabName { get; set; } = string.Empty;
    public int PeriodHours { get; set; }
    public int SampleCount { get; set; }
    
    public double AvgCpuPercent { get; set; }
    public double MaxCpuPercent { get; set; }
    public TrendDirection CpuTrend { get; set; } = TrendDirection.Stable;
    
    public double AvgMemoryPercent { get; set; }
    public double MaxMemoryPercent { get; set; }
    public TrendDirection MemoryTrend { get; set; } = TrendDirection.Stable;
    
    public List<VmResourceTrend> VmTrends { get; set; } = new();
}

/// <summary>
/// Resource trend for a specific VM
/// </summary>
public class VmResourceTrend
{
    public string VmName { get; set; } = string.Empty;
    public int SampleCount { get; set; }
    public double AvgCpuPercent { get; set; }
    public double MaxCpuPercent { get; set; }
    public double AvgMemoryPercent { get; set; }
    public double MaxMemoryPercent { get; set; }
}

/// <summary>
/// Trend direction
/// </summary>
public enum TrendDirection
{
    Increasing,
    Stable,
    Decreasing
}

using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using OpenCodeLab.Models;

namespace OpenCodeLab.Services;

/// <summary>
/// Service for generating chart data from resource history
/// Works with ScottPlot.WPF for real-time resource visualization
/// </summary>
public class ResourceChartService
{
    private readonly ResourceHistoryService _historyService = new();

    /// <summary>
    /// Data point for chart rendering
    /// </summary>
    public class ChartDataPoint
    {
        public DateTime Timestamp { get; set; }
        public double Value { get; set; }
        public string Label { get; set; } = string.Empty;
    }

    /// <summary>
    /// Chart series with data points
    /// </summary>
    public class ChartSeries
    {
        public string Name { get; set; } = string.Empty;
        public string DataType { get; set; } = string.Empty; // CPU, Memory, Disk
        public string Color { get; set; } = "#2196F3";
        public List<ChartDataPoint> DataPoints { get; set; } = new();
    }

    /// <summary>
    /// Get CPU chart data for a lab
    /// </summary>
    public async Task<ChartSeries> GetCpuChartDataAsync(string labName, int hours = 24, CancellationToken ct = default)
    {
        var history = await _historyService.GetHistoryAsync(labName, hours, ct);
        
        var series = new ChartSeries
        {
            Name = $"{labName} - CPU Usage",
            DataType = "CPU",
            Color = "#2196F3" // Blue
        };

        foreach (var entry in history)
        {
            series.DataPoints.Add(new ChartDataPoint
            {
                Timestamp = entry.Timestamp,
                Value = entry.CpuPercentUsed,
                Label = $"{entry.CpuPercentUsed:F1}%"
            });
        }

        return series;
    }

    /// <summary>
    /// Get Memory chart data for a lab
    /// </summary>
    public async Task<ChartSeries> GetMemoryChartDataAsync(string labName, int hours = 24, CancellationToken ct = default)
    {
        var history = await _historyService.GetHistoryAsync(labName, hours, ct);
        
        var series = new ChartSeries
        {
            Name = $"{labName} - Memory Usage",
            DataType = "Memory",
            Color = "#4CAF50" // Green
        };

        foreach (var entry in history)
        {
            series.DataPoints.Add(new ChartDataPoint
            {
                Timestamp = entry.Timestamp,
                Value = entry.MemoryPercentUsed,
                Label = $"{entry.MemoryPercentUsed:F1}%"
            });
        }

        return series;
    }

    /// <summary>
    /// Get Disk chart data for a lab
    /// </summary>
    public async Task<ChartSeries> GetDiskChartDataAsync(string labName, int hours = 24, CancellationToken ct = default)
    {
        var history = await _historyService.GetHistoryAsync(labName, hours, ct);
        
        var series = new ChartSeries
        {
            Name = $"{labName} - Disk Usage",
            DataType = "Disk",
            Color = "#FF9800" // Orange
        };

        foreach (var entry in history)
        {
            series.DataPoints.Add(new ChartDataPoint
            {
                Timestamp = entry.Timestamp,
                Value = entry.DiskPercentUsed,
                Label = $"{entry.DiskPercentUsed:F1}%"
            });
        }

        return series;
    }

    /// <summary>
    /// Get VM-specific chart data
    /// </summary>
    public async Task<List<ChartSeries>> GetVmChartDataAsync(string labName, string vmName, int hours = 24, CancellationToken ct = default)
    {
        var history = await _historyService.GetVmHistoryAsync(labName, vmName, hours, ct);
        var result = new List<ChartSeries>();

        // CPU series
        var cpuSeries = new ChartSeries
        {
            Name = $"{vmName} - CPU",
            DataType = "CPU",
            Color = "#2196F3"
        };

        // Memory series  
        var memorySeries = new ChartSeries
        {
            Name = $"{vmName} - Memory",
            DataType = "Memory",
            Color = "#4CAF50"
        };

        foreach (var entry in history)
        {
            cpuSeries.DataPoints.Add(new ChartDataPoint
            {
                Timestamp = entry.Timestamp,
                Value = entry.CpuPercentUsed,
                Label = $"{entry.CpuPercentUsed:F1}%"
            });

            memorySeries.DataPoints.Add(new ChartDataPoint
            {
                Timestamp = entry.Timestamp,
                Value = entry.MemoryPercentUsed,
                Label = $"{entry.MemoryPercentUsed:F1}%"
            });
        }

        result.Add(cpuSeries);
        result.Add(memorySeries);
        return result;
    }

    /// <summary>
    /// Get host resource chart data
    /// </summary>
    public async Task<List<ChartSeries>> GetHostChartDataAsync(int hours = 24, CancellationToken ct = default)
    {
        var history = await _historyService.GetHostHistoryAsync(hours, ct);
        var result = new List<ChartSeries>();

        var cpuSeries = new ChartSeries
        {
            Name = "Host CPU",
            DataType = "CPU",
            Color = "#2196F3"
        };

        var memorySeries = new ChartSeries
        {
            Name = "Host Memory",
            DataType = "Memory",
            Color = "#4CAF50"
        };

        var diskSeries = new ChartSeries
        {
            Name = "Host Disk",
            DataType = "Disk",
            Color = "#FF9800"
        };

        foreach (var entry in history)
        {
            cpuSeries.DataPoints.Add(new ChartDataPoint
            {
                Timestamp = entry.Timestamp,
                Value = entry.CpuPercentUsed,
                Label = $"{entry.CpuPercentUsed:F1}%"
            });

            memorySeries.DataPoints.Add(new ChartDataPoint
            {
                Timestamp = entry.Timestamp,
                Value = entry.MemoryPercentUsed,
                Label = $"{entry.MemoryPercentUsed:F1}%"
            });

            diskSeries.DataPoints.Add(new ChartDataPoint
            {
                Timestamp = entry.Timestamp,
                Value = entry.DiskPercentUsed,
                Label = $"{entry.DiskPercentUsed:F1}%"
            });
        }

        result.Add(cpuSeries);
        result.Add(memorySeries);
        result.Add(diskSeries);
        return result;
    }

    /// <summary>
    /// Get aggregated chart data comparing multiple labs
    /// </summary>
    public async Task<Dictionary<string, List<ChartSeries>>> GetMultiLabChartDataAsync(IEnumerable<string> labNames, int hours = 24, CancellationToken ct = default)
    {
        var result = new Dictionary<string, List<ChartSeries>>();

        foreach (var labName in labNames)
        {
            var labSeries = new List<ChartSeries>
            {
                await GetCpuChartDataAsync(labName, hours, ct),
                await GetMemoryChartDataAsync(labName, hours, ct),
                await GetDiskChartDataAsync(labName, hours, ct)
            };
            result[labName] = labSeries;
        }

        return result;
    }

    /// <summary>
    /// Get arrays suitable for ScottPlot rendering
    /// </summary>
    public (double[] xs, double[] ys) GetPlotArrays(ChartSeries series)
    {
        var xs = series.DataPoints
            .Select(p => p.Timestamp.ToOADate())
            .ToArray();
        
        var ys = series.DataPoints
            .Select(p => p.Value)
            .ToArray();

        return (xs, ys);
    }

    /// <summary>
    /// Get trend summary for display
    /// </summary>
    public async Task<ChartTrendSummary> GetTrendSummaryAsync(string labName, int hours = 24, CancellationToken ct = default)
    {
        var analysis = await _historyService.AnalyzeTrendsAsync(labName, hours, ct);
        
        return new ChartTrendSummary
        {
            LabName = labName,
            PeriodHours = hours,
            SampleCount = analysis.SampleCount,
            AvgCpu = analysis.AvgCpuPercent,
            MaxCpu = analysis.MaxCpuPercent,
            CpuTrend = analysis.CpuTrend.ToString(),
            AvgMemory = analysis.AvgMemoryPercent,
            MaxMemory = analysis.MaxMemoryPercent,
            MemoryTrend = analysis.MemoryTrend.ToString()
        };
    }
}

/// <summary>
/// Summary of resource trends for UI display
/// </summary>
public class ChartTrendSummary
{
    public string LabName { get; set; } = string.Empty;
    public int PeriodHours { get; set; }
    public int SampleCount { get; set; }
    public double AvgCpu { get; set; }
    public double MaxCpu { get; set; }
    public string CpuTrend { get; set; } = "Stable";
    public double AvgMemory { get; set; }
    public double MaxMemory { get; set; }
    public string MemoryTrend { get; set; } = "Stable";
}

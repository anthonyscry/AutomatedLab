using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using OpenCodeLab.Models;
using OpenCodeLab.Services;

namespace OpenCodeLab.ViewModels;

/// <summary>
/// ViewModel for the Resource Charts view - real-time resource utilization visualization
/// </summary>
public class ResourceChartViewModel : ObservableObject
{
    private readonly ResourceChartService _chartService = new();
    private readonly ResourceHistoryService _historyService = new();

    private string _selectedLabName = string.Empty;
    private bool _isLoading;
    private string _statusMessage = "Select a lab to view resource charts";
    private int _selectedTimeRange = 24; // hours
    private ChartTrendSummary? _trendSummary;
    private bool _showCpu = true;
    private bool _showMemory = true;
    private bool _showDisk = true;
    private bool _autoRefresh;
    private CancellationTokenSource? _refreshCts;

    // Chart data arrays for ScottPlot
    private double[] _cpuXs = Array.Empty<double>();
    private double[] _cpuYs = Array.Empty<double>();
    private double[] _memoryXs = Array.Empty<double>();
    private double[] _memoryYs = Array.Empty<double>();
    private double[] _diskXs = Array.Empty<double>();
    private double[] _diskYs = Array.Empty<double>();

    public ObservableCollection<string> AvailableLabs { get; } = new();
    public ObservableCollection<ResourceChartService.ChartSeries> ChartSeriesCollection { get; } = new();

    public AsyncCommand LoadCommand { get; }
    public AsyncCommand RefreshChartsCommand { get; }
    public AsyncCommand ExportDataCommand { get; }

    public string SelectedLabName
    {
        get => _selectedLabName;
        set
        {
            _selectedLabName = value;
            OnPropertyChanged();
            RefreshCommands();
            if (!string.IsNullOrEmpty(value))
                _ = LoadChartsAsync();
        }
    }

    public bool IsLoading
    {
        get => _isLoading;
        set { _isLoading = value; OnPropertyChanged(); RefreshCommands(); }
    }

    public string StatusMessage
    {
        get => _statusMessage;
        set { _statusMessage = value; OnPropertyChanged(); }
    }

    public int SelectedTimeRange
    {
        get => _selectedTimeRange;
        set
        {
            _selectedTimeRange = value;
            OnPropertyChanged();
            if (!string.IsNullOrEmpty(SelectedLabName))
                _ = LoadChartsAsync();
        }
    }

    public ChartTrendSummary? TrendSummary
    {
        get => _trendSummary;
        set
        {
            _trendSummary = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(HasTrendData));
        }
    }

    public bool HasTrendData => TrendSummary != null && TrendSummary.SampleCount > 0;

    public bool ShowCpu
    {
        get => _showCpu;
        set { _showCpu = value; OnPropertyChanged(); OnPropertyChanged(nameof(NeedsChartRefresh)); }
    }

    public bool ShowMemory
    {
        get => _showMemory;
        set { _showMemory = value; OnPropertyChanged(); OnPropertyChanged(nameof(NeedsChartRefresh)); }
    }

    public bool ShowDisk
    {
        get => _showDisk;
        set { _showDisk = value; OnPropertyChanged(); OnPropertyChanged(nameof(NeedsChartRefresh)); }
    }

    public bool NeedsChartRefresh => true; // Trigger for UI to know visibility changed

    public bool AutoRefresh
    {
        get => _autoRefresh;
        set
        {
            _autoRefresh = value;
            OnPropertyChanged();
            if (value)
                StartAutoRefresh();
            else
                StopAutoRefresh();
        }
    }

    // Chart data properties for binding
    public double[] CpuXs
    {
        get => _cpuXs;
        set { _cpuXs = value; OnPropertyChanged(); }
    }

    public double[] CpuYs
    {
        get => _cpuYs;
        set { _cpuYs = value; OnPropertyChanged(); }
    }

    public double[] MemoryXs
    {
        get => _memoryXs;
        set { _memoryXs = value; OnPropertyChanged(); }
    }

    public double[] MemoryYs
    {
        get => _memoryYs;
        set { _memoryYs = value; OnPropertyChanged(); }
    }

    public double[] DiskXs
    {
        get => _diskXs;
        set { _diskXs = value; OnPropertyChanged(); }
    }

    public double[] DiskYs
    {
        get => _diskYs;
        set { _diskYs = value; OnPropertyChanged(); }
    }

    public int[] TimeRangeOptions { get; } = { 1, 6, 12, 24, 48, 72, 168 }; // Hours

    public ResourceChartViewModel()
    {
        LoadCommand = new AsyncCommand(LoadAsync, () => !IsLoading);
        RefreshChartsCommand = new AsyncCommand(LoadChartsAsync, () => !IsLoading && !string.IsNullOrEmpty(SelectedLabName));
        ExportDataCommand = new AsyncCommand(ExportDataAsync, () => !IsLoading && ChartSeriesCollection.Count > 0);
    }

    public async Task LoadAsync()
    {
        IsLoading = true;
        StatusMessage = "Loading available labs...";

        try
        {
            AvailableLabs.Clear();

            // Scan for labs with resource history
            var labConfigRoot = LabPaths.LabConfig;
            if (Directory.Exists(labConfigRoot))
            {
                foreach (var dir in Directory.GetDirectories(labConfigRoot))
                {
                    var labName = Path.GetFileName(dir);
                    if (labName.StartsWith("_")) continue; // Skip system directories

                    var historyFile = Path.Combine(dir, "resource-history.jsonl");
                    if (File.Exists(historyFile))
                    {
                        AvailableLabs.Add(labName);
                    }
                }
            }

            // Also add "Host" option for host-level metrics
            var hostHistoryFile = Path.Combine(labConfigRoot, "_system", "resource-history.jsonl");
            if (File.Exists(hostHistoryFile))
            {
                AvailableLabs.Insert(0, "(Host System)");
            }

            StatusMessage = AvailableLabs.Count > 0
                ? $"Found {AvailableLabs.Count} lab(s) with resource data"
                : "No resource history found. Run health checks to collect data.";
        }
        catch (Exception ex)
        {
            StatusMessage = $"Error loading labs: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task LoadChartsAsync()
    {
        if (string.IsNullOrEmpty(SelectedLabName))
            return;

        IsLoading = true;
        StatusMessage = $"Loading chart data for {SelectedLabName}...";

        try
        {
            ChartSeriesCollection.Clear();

            if (SelectedLabName == "(Host System)")
            {
                // Load host metrics
                var hostSeries = await _chartService.GetHostChartDataAsync(SelectedTimeRange);
                foreach (var series in hostSeries)
                {
                    ChartSeriesCollection.Add(series);
                    UpdateChartArrays(series);
                }

                TrendSummary = null; // Host doesn't have trend analysis yet
            }
            else
            {
                // Load lab metrics
                var cpuSeries = await _chartService.GetCpuChartDataAsync(SelectedLabName, SelectedTimeRange);
                var memorySeries = await _chartService.GetMemoryChartDataAsync(SelectedLabName, SelectedTimeRange);
                var diskSeries = await _chartService.GetDiskChartDataAsync(SelectedLabName, SelectedTimeRange);

                ChartSeriesCollection.Add(cpuSeries);
                ChartSeriesCollection.Add(memorySeries);
                ChartSeriesCollection.Add(diskSeries);

                UpdateChartArrays(cpuSeries);
                UpdateChartArrays(memorySeries);
                UpdateChartArrays(diskSeries);

                // Load trend summary
                TrendSummary = await _chartService.GetTrendSummaryAsync(SelectedLabName, SelectedTimeRange);
            }

            var totalPoints = ChartSeriesCollection.Sum(s => s.DataPoints.Count);
            StatusMessage = totalPoints > 0
                ? $"Loaded {totalPoints} data points from {SelectedLabName}"
                : $"No data available for {SelectedLabName} in the last {SelectedTimeRange} hours";

            // Notify chart refresh needed
            OnPropertyChanged(nameof(NeedsChartRefresh));
        }
        catch (Exception ex)
        {
            StatusMessage = $"Error loading charts: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    private void UpdateChartArrays(ResourceChartService.ChartSeries series)
    {
        var (xs, ys) = _chartService.GetPlotArrays(series);

        switch (series.DataType)
        {
            case "CPU":
                CpuXs = xs;
                CpuYs = ys;
                break;
            case "Memory":
                MemoryXs = xs;
                MemoryYs = ys;
                break;
            case "Disk":
                DiskXs = xs;
                DiskYs = ys;
                break;
        }
    }

    private async Task ExportDataAsync()
    {
        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            FileName = $"resource-data-{SelectedLabName}-{DateTime.UtcNow:yyyyMMdd-HHmmss}",
            Filter = "CSV files (*.csv)|*.csv|JSON files (*.json)|*.json",
            DefaultExt = ".csv"
        };

        if (dialog.ShowDialog() != true)
            return;

        try
        {
            var extension = Path.GetExtension(dialog.FileName).ToLowerInvariant();

            if (extension == ".json")
            {
                var json = System.Text.Json.JsonSerializer.Serialize(ChartSeriesCollection.ToList(),
                    new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
                await File.WriteAllTextAsync(dialog.FileName, json);
            }
            else
            {
                // Export as CSV
                var sb = new System.Text.StringBuilder();
                sb.AppendLine("Timestamp,DataType,Value");

                foreach (var series in ChartSeriesCollection)
                {
                    foreach (var point in series.DataPoints)
                    {
                        sb.AppendLine($"{point.Timestamp:O},{series.DataType},{point.Value:F2}");
                    }
                }

                await File.WriteAllTextAsync(dialog.FileName, sb.ToString());
            }

            StatusMessage = $"Data exported to {dialog.FileName}";
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Export failed:\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void StartAutoRefresh()
    {
        _refreshCts?.Cancel();
        _refreshCts = new CancellationTokenSource();

        _ = AutoRefreshLoopAsync(_refreshCts.Token);
    }

    private void StopAutoRefresh()
    {
        _refreshCts?.Cancel();
        _refreshCts = null;
    }

    private async Task AutoRefreshLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested && AutoRefresh)
        {
            await Task.Delay(TimeSpan.FromMinutes(1), ct);

            if (!ct.IsCancellationRequested && !IsLoading && !string.IsNullOrEmpty(SelectedLabName))
            {
                await LoadChartsAsync();
            }
        }
    }

    private void RefreshCommands()
    {
        LoadCommand.RaiseCanExecuteChanged();
        RefreshChartsCommand.RaiseCanExecuteChanged();
        ExportDataCommand.RaiseCanExecuteChanged();
    }
}

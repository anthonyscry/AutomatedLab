using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using OpenCodeLab.Models;
using OpenCodeLab.Services;

namespace OpenCodeLab.ViewModels;

/// <summary>
/// ViewModel for the Health Dashboard view
/// </summary>
public class HealthDashboardViewModel : ObservableObject
{
    private readonly HealthMonitoringService _healthService = new();
    private readonly HealthAlertService _alertService = new();
    private readonly ResourceHistoryService _resourceHistoryService = new();

    private string _labName = string.Empty;
    private bool _isLoading;
    private string _statusMessage = "Ready";
    private LabHealthReport? _currentReport;
    private HealthAlert? _selectedAlert;
    private bool _autoRefresh;
    private int _autoRefreshInterval = 60; // seconds

    public ObservableCollection<LabHealthReport> RecentReports { get; } = new();
    public ObservableCollection<HealthAlert> ActiveAlerts { get; } = new();
    public ObservableCollection<VmHealthStatus> VmHealthStatuses { get; } = new();

    public AsyncCommand RunHealthCheckCommand { get; }
    public AsyncCommand LoadCommand { get; }
    public AsyncCommand AcknowledgeAlertCommand { get; }
    public AsyncCommand AcknowledgeAllAlertsCommand { get; }
    public AsyncCommand ExportReportCommand { get; }
    public AsyncCommand ViewHistoryCommand { get; }

    public string LabName
    {
        get => _labName;
        set { _labName = value; OnPropertyChanged(); RefreshCommands(); }
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

    public LabHealthReport? CurrentReport
    {
        get => _currentReport;
        set
        {
            _currentReport = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(OverallStatus));
            OnPropertyChanged(nameof(OverallStatusColor));
            OnPropertyChanged(nameof(OverallStatusEmoji));
            OnPropertyChanged(nameof(HealthyCount));
            OnPropertyChanged(nameof(WarningCount));
            OnPropertyChanged(nameof(CriticalCount));
            OnPropertyChanged(nameof(LastChecked));
            UpdateVmHealthStatuses();
        }
    }

    public HealthAlert? SelectedAlert
    {
        get => _selectedAlert;
        set { _selectedAlert = value; OnPropertyChanged(); AcknowledgeAlertCommand.RaiseCanExecuteChanged(); }
    }

    public bool AutoRefresh
    {
        get => _autoRefresh;
        set
        {
            _autoRefresh = value;
            OnPropertyChanged();
            if (value) StartAutoRefresh();
        }
    }

    public int AutoRefreshInterval
    {
        get => _autoRefreshInterval;
        set { _autoRefreshInterval = value; OnPropertyChanged(); }
    }

    public HealthStatus OverallStatus => CurrentReport?.OverallStatus ?? HealthStatus.Unknown;
    
    public Brush OverallStatusColor => OverallStatus switch
    {
        HealthStatus.Healthy => Brushes.Green,
        HealthStatus.Warning => Brushes.Orange,
        HealthStatus.Critical => Brushes.Red,
        _ => Brushes.Gray
    };

    public string OverallStatusEmoji => OverallStatus switch
    {
        HealthStatus.Healthy => "✅",
        HealthStatus.Warning => "⚠️",
        HealthStatus.Critical => "🔴",
        _ => "❓"
    };

    public int HealthyCount => CurrentReport?.HealthyCount ?? 0;
    public int WarningCount => CurrentReport?.WarningCount ?? 0;
    public int CriticalCount => CurrentReport?.CriticalCount ?? 0;
    
    public string LastChecked => CurrentReport?.GeneratedAt.ToString("yyyy-MM-dd HH:mm:ss") ?? "Never";
    
    public int AlertCount => ActiveAlerts.Count;

    public HealthDashboardViewModel()
    {
        LoadCommand = new AsyncCommand(LoadAsync, () => !IsLoading && !string.IsNullOrWhiteSpace(LabName));
        RunHealthCheckCommand = new AsyncCommand(RunHealthCheckAsync, () => !IsLoading && !string.IsNullOrWhiteSpace(LabName));
        AcknowledgeAlertCommand = new AsyncCommand(AcknowledgeAlertAsync, () => SelectedAlert != null);
        AcknowledgeAllAlertsCommand = new AsyncCommand(AcknowledgeAllAlertsAsync, () => ActiveAlerts.Count > 0);
        ExportReportCommand = new AsyncCommand(ExportReportAsync, () => CurrentReport != null);
        ViewHistoryCommand = new AsyncCommand(ViewHistoryAsync, () => !string.IsNullOrWhiteSpace(LabName));

        // Load alerts
        _ = _alertService.LoadAsync();
    }

    public async Task LoadAsync()
    {
        if (string.IsNullOrWhiteSpace(LabName))
            return;

        IsLoading = true;
        StatusMessage = "Loading health data...";

        try
        {
            // Load latest report
            var latest = await _healthService.GetLatestReportAsync(LabName);
            if (latest != null)
            {
                CurrentReport = latest;
            }

            // Load active alerts
            await _alertService.LoadAsync();
            var alerts = _alertService.GetActiveAlerts();
            ActiveAlerts.Clear();
            foreach (var alert in alerts)
                ActiveAlerts.Add(alert);
            OnPropertyChanged(nameof(AlertCount));

            // Load recent reports
            var history = await _healthService.GetHistoryAsync(LabName, 7);
            RecentReports.Clear();
            foreach (var report in history.Take(10))
                RecentReports.Add(report);

            StatusMessage = $"Last checked: {LastChecked}";
        }
        catch (Exception ex)
        {
            StatusMessage = $"Error: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task RunHealthCheckAsync()
    {
        if (string.IsNullOrWhiteSpace(LabName))
            return;

        IsLoading = true;
        StatusMessage = "Running health check...";

        try
        {
            var report = await _healthService.RunHealthCheckAsync(
                LabName,
                msg => StatusMessage = msg,
                CancellationToken.None);

            CurrentReport = report;

            // Create alerts for issues
            foreach (var check in report.Checks.Where(c => c.Status >= HealthStatus.Warning))
            {
                _alertService.CreateAlertFromCheck(check, LabName);
            }

            // Refresh alerts
            var alerts = _alertService.GetActiveAlerts();
            ActiveAlerts.Clear();
            foreach (var alert in alerts)
                ActiveAlerts.Add(alert);
            OnPropertyChanged(nameof(AlertCount));

            StatusMessage = $"Health check complete. Status: {OverallStatus}";
        }
        catch (Exception ex)
        {
            StatusMessage = $"Health check failed: {ex.Message}";
            MessageBox.Show($"Health check failed:\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task AcknowledgeAlertAsync()
    {
        if (SelectedAlert == null)
            return;

        _alertService.AcknowledgeAlert(SelectedAlert.Id);
        ActiveAlerts.Remove(SelectedAlert);
        OnPropertyChanged(nameof(AlertCount));
        SelectedAlert = null;
        await Task.CompletedTask;
    }

    private async Task AcknowledgeAllAlertsAsync()
    {
        _alertService.AcknowledgeAll();
        ActiveAlerts.Clear();
        OnPropertyChanged(nameof(AlertCount));
        await Task.CompletedTask;
    }

    private async Task ExportReportAsync()
    {
        if (CurrentReport == null)
            return;

        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            FileName = $"health-report-{LabName}-{DateTime.UtcNow:yyyyMMdd-HHmmss}",
            Filter = "Markdown files (*.md)|*.md|JSON files (*.json)|*.json",
            DefaultExt = ".md"
        };

        if (dialog.ShowDialog() == true)
        {
            try
            {
                var content = System.IO.Path.GetExtension(dialog.FileName).ToLowerInvariant() == ".json"
                    ? System.Text.Json.JsonSerializer.Serialize(CurrentReport, new System.Text.Json.JsonSerializerOptions { WriteIndented = true })
                    : GenerateMarkdownReport(CurrentReport);

                await System.IO.File.WriteAllTextAsync(dialog.FileName, content);
                StatusMessage = $"Report saved to {dialog.FileName}";
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to save report:\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }

    private async Task ViewHistoryAsync()
    {
        // This would open a history dialog - for now just load more history
        var history = await _healthService.GetHistoryAsync(LabName, 30);
        RecentReports.Clear();
        foreach (var report in history.Take(20))
            RecentReports.Add(report);
        StatusMessage = $"Loaded {RecentReports.Count} historical reports";
    }

    private void UpdateVmHealthStatuses()
    {
        VmHealthStatuses.Clear();
        if (CurrentReport == null) return;

        foreach (var vm in CurrentReport.VmHealthStatuses)
            VmHealthStatuses.Add(vm);
    }

    private void RefreshCommands()
    {
        LoadCommand.RaiseCanExecuteChanged();
        RunHealthCheckCommand.RaiseCanExecuteChanged();
        ViewHistoryCommand.RaiseCanExecuteChanged();
    }

    private async void StartAutoRefresh()
    {
        while (AutoRefresh)
        {
            await Task.Delay(AutoRefreshInterval * 1000);
            if (AutoRefresh && !IsLoading && !string.IsNullOrWhiteSpace(LabName))
            {
                await RunHealthCheckAsync();
            }
        }
    }

    private static string GenerateMarkdownReport(LabHealthReport report)
    {
        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"# Health Report: {report.LabName}");
        sb.AppendLine();
        sb.AppendLine($"**Generated:** {report.GeneratedAt:yyyy-MM-dd HH:mm:ss} UTC");
        sb.AppendLine($"**Overall Status:** {report.OverallStatus}");
        sb.AppendLine();

        sb.AppendLine("## Lab Checks");
        sb.AppendLine();
        sb.AppendLine("| Check | Status | Message |");
        sb.AppendLine("|-------|--------|---------|");
        foreach (var check in report.Checks)
        {
            sb.AppendLine($"| {check.CheckName} | {check.StatusEmoji} {check.StatusText} | {check.Message} |");
        }
        sb.AppendLine();

        if (report.VmHealthStatuses.Count > 0)
        {
            sb.AppendLine("## VM Health");
            sb.AppendLine();
            sb.AppendLine("| VM | State | Health | Issues |");
            sb.AppendLine("|----|-------|--------|--------|");
            foreach (var vm in report.VmHealthStatuses)
            {
                sb.AppendLine($"| {vm.VmName} | {vm.State} | {vm.HealthEmoji} | {vm.Issues.Count} |");
            }
            sb.AppendLine();
        }

        if (report.HostStatus != null)
        {
            sb.AppendLine("## Host Resources");
            sb.AppendLine();
            sb.AppendLine($"- **CPU:** {report.HostStatus.CpuPercentUsed:F1}%");
            sb.AppendLine($"- **Memory:** {report.HostStatus.MemoryPercentUsed:F1}% ({report.HostStatus.MemoryAvailableGB} available)");
            sb.AppendLine();
        }

        return sb.ToString();
    }
}

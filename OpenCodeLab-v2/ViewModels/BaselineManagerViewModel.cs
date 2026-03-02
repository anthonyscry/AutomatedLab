using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using OpenCodeLab.Models;
using OpenCodeLab.Services;

namespace OpenCodeLab.ViewModels;

/// <summary>
/// ViewModel for managing baselines
/// </summary>
public class BaselineManagerViewModel : ObservableObject
{
    private readonly ExtendedDriftDetectionService _driftService = new();
    private readonly DriftReportExportService _exportService = new();

    private string _labName = string.Empty;
    private bool _isLoading;
    private string _statusMessage = "Ready";
    private ExtendedDriftBaseline? _selectedBaseline;
    private string _newBaselineDescription = string.Empty;
    private ExtendedDriftReport? _currentDriftReport;

    public ObservableCollection<ExtendedDriftBaseline> Baselines { get; } = new();
    public ObservableCollection<ExtendedDriftReport> RecentReports { get; } = new();

    public AsyncCommand LoadCommand { get; }
    public AsyncCommand CaptureBaselineCommand { get; }
    public AsyncCommand CheckDriftCommand { get; }
    public AsyncCommand DeleteBaselineCommand { get; }
    public AsyncCommand ExportBaselineCommand { get; }
    public AsyncCommand SetGoldenCommand { get; }
    public AsyncCommand ViewDriftDetailsCommand { get; }

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

    public ExtendedDriftBaseline? SelectedBaseline
    {
        get => _selectedBaseline;
        set
        {
            _selectedBaseline = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(SelectedBaselineInfo));
            OnPropertyChanged(nameof(HasSelectedBaseline));
            RefreshCommands();
        }
    }

    public string NewBaselineDescription
    {
        get => _newBaselineDescription;
        set { _newBaselineDescription = value; OnPropertyChanged(); }
    }

    public ExtendedDriftReport? CurrentDriftReport
    {
        get => _currentDriftReport;
        set
        {
            _currentDriftReport = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(DriftStatusText));
            OnPropertyChanged(nameof(DriftStatusColor));
            OnPropertyChanged(nameof(DriftCount));
        }
    }

    public string SelectedBaselineInfo => SelectedBaseline == null
        ? "No baseline selected"
        : $"Created: {SelectedBaseline.CreatedAt:yyyy-MM-dd HH:mm}\nBy: {SelectedBaseline.CreatedBy}\nVMs: {SelectedBaseline.VmCount}\n{(SelectedBaseline.IsGoldenBaseline ? "⭐ Golden Baseline" : "")}";

    public bool HasSelectedBaseline => SelectedBaseline != null;

    public string DriftStatusText => CurrentDriftReport?.StatusEmoji + " " + CurrentDriftReport?.OverallStatus.ToString() ?? "No drift report";

    public System.Windows.Media.Brush DriftStatusColor => CurrentDriftReport?.OverallStatus switch
    {
        DriftStatus.Clean => System.Windows.Media.Brushes.Green,
        DriftStatus.Warning => System.Windows.Media.Brushes.Orange,
        DriftStatus.Critical => System.Windows.Media.Brushes.Red,
        _ => System.Windows.Media.Brushes.Gray
    };

    public int DriftCount => CurrentDriftReport?.TotalDriftCount ?? 0;

    public BaselineManagerViewModel()
    {
        LoadCommand = new AsyncCommand(LoadAsync, () => !IsLoading && !string.IsNullOrWhiteSpace(LabName));
        CaptureBaselineCommand = new AsyncCommand(CaptureBaselineAsync, () => !IsLoading && !string.IsNullOrWhiteSpace(LabName));
        CheckDriftCommand = new AsyncCommand(CheckDriftAsync, () => !IsLoading && SelectedBaseline != null);
        DeleteBaselineCommand = new AsyncCommand(DeleteBaselineAsync, () => !IsLoading && SelectedBaseline != null);
        ExportBaselineCommand = new AsyncCommand(ExportBaselineAsync, () => !IsLoading && SelectedBaseline != null);
        SetGoldenCommand = new AsyncCommand(SetGoldenAsync, () => !IsLoading && SelectedBaseline != null);
        ViewDriftDetailsCommand = new AsyncCommand(ViewDriftDetailsAsync, () => CurrentDriftReport != null && CurrentDriftReport.TotalDriftCount > 0);
    }

    public async Task LoadAsync()
    {
        if (string.IsNullOrWhiteSpace(LabName))
            return;

        IsLoading = true;
        StatusMessage = "Loading baselines...";

        try
        {
            var baselines = await _driftService.ListBaselinesAsync(LabName);
            Baselines.Clear();
            foreach (var baseline in baselines)
                Baselines.Add(baseline);

            // Select the latest baseline by default
            SelectedBaseline = Baselines.FirstOrDefault();

            StatusMessage = $"Loaded {Baselines.Count} baseline(s)";
        }
        catch (Exception ex)
        {
            StatusMessage = $"Error loading baselines: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task CaptureBaselineAsync()
    {
        if (string.IsNullOrWhiteSpace(LabName))
            return;

        IsLoading = true;
        StatusMessage = "Capturing baseline...";

        try
        {
            var baseline = await _driftService.CaptureExtendedBaselineAsync(
                LabName,
                NewBaselineDescription,
                msg => StatusMessage = msg,
                CancellationToken.None);

            Baselines.Insert(0, baseline);
            SelectedBaseline = baseline;
            NewBaselineDescription = string.Empty;

            StatusMessage = $"Baseline captured: {baseline.Id}";
            MessageBox.Show($"Extended baseline captured with {baseline.VmCount} VM(s).", "Baseline Captured", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            StatusMessage = $"Failed to capture baseline: {ex.Message}";
            MessageBox.Show($"Failed to capture baseline:\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task CheckDriftAsync()
    {
        if (SelectedBaseline == null)
            return;

        IsLoading = true;
        StatusMessage = "Checking for drift...";

        try
        {
            var report = await _driftService.DetectExtendedDriftAsync(
                LabName,
                SelectedBaseline.Id,
                msg => StatusMessage = msg,
                CancellationToken.None);

            CurrentDriftReport = report;
            RecentReports.Insert(0, report);

            StatusMessage = $"Drift check complete: {report.TotalDriftCount} item(s) found";

            if (report.TotalDriftCount > 0)
            {
                // Show drift details dialog
                var dialog = new Views.DriftDetailsDialog(ConvertToBasicReport(report));
                dialog.Owner = Application.Current.MainWindow;
                dialog.ShowDialog();
            }
            else
            {
                MessageBox.Show("No drift detected. Configuration matches baseline.", "Drift Check", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }
        catch (Exception ex)
        {
            StatusMessage = $"Drift check failed: {ex.Message}";
            MessageBox.Show($"Drift check failed:\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task DeleteBaselineAsync()
    {
        if (SelectedBaseline == null)
            return;

        var result = MessageBox.Show(
            $"Delete baseline '{SelectedBaseline.Id}'?\n\nThis action cannot be undone.",
            "Confirm Delete",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);

        if (result != MessageBoxResult.Yes)
            return;

        IsLoading = true;
        try
        {
            await _driftService.DeleteBaselineAsync(LabName, SelectedBaseline.Id);
            Baselines.Remove(SelectedBaseline);
            SelectedBaseline = Baselines.FirstOrDefault();
            StatusMessage = "Baseline deleted";
        }
        catch (Exception ex)
        {
            StatusMessage = $"Failed to delete baseline: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    private async Task ExportBaselineAsync()
    {
        if (SelectedBaseline == null)
            return;

        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            FileName = $"baseline-{LabName}-{SelectedBaseline.CreatedAt:yyyyMMdd-HHmmss}",
            Filter = "JSON files (*.json)|*.json",
            DefaultExt = ".json"
        };

        if (dialog.ShowDialog() == true)
        {
            try
            {
                var json = System.Text.Json.JsonSerializer.Serialize(SelectedBaseline, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
                await System.IO.File.WriteAllTextAsync(dialog.FileName, json);
                StatusMessage = $"Baseline exported to {dialog.FileName}";
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to export baseline:\n{ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }

    private async Task SetGoldenAsync()
    {
        if (SelectedBaseline == null)
            return;

        // Clear golden flag from all other baselines
        foreach (var baseline in Baselines)
            baseline.IsGoldenBaseline = false;

        SelectedBaseline.IsGoldenBaseline = true;
        
        // Save the change
        try
        {
            var service = new HostBaselineCaptureService();
            await service.SaveExtendedBaselineAsync(SelectedBaseline);
            StatusMessage = "Golden baseline set";
            OnPropertyChanged(nameof(SelectedBaselineInfo));
        }
        catch (Exception ex)
        {
            StatusMessage = $"Failed to set golden baseline: {ex.Message}";
        }
    }

    private async Task ViewDriftDetailsAsync()
    {
        if (CurrentDriftReport == null)
            return;

        var dialog = new Views.DriftDetailsDialog(ConvertToBasicReport(CurrentDriftReport));
        dialog.Owner = Application.Current.MainWindow;
        dialog.ShowDialog();
        await Task.CompletedTask;
    }

    private void RefreshCommands()
    {
        LoadCommand.RaiseCanExecuteChanged();
        CaptureBaselineCommand.RaiseCanExecuteChanged();
        CheckDriftCommand.RaiseCanExecuteChanged();
        DeleteBaselineCommand.RaiseCanExecuteChanged();
        ExportBaselineCommand.RaiseCanExecuteChanged();
        SetGoldenCommand.RaiseCanExecuteChanged();
    }

    private static DriftReport ConvertToBasicReport(ExtendedDriftReport extended)
    {
        var report = new DriftReport
        {
            Id = extended.Id,
            LabName = extended.LabName,
            BaselineId = extended.BaselineId,
            GeneratedAt = extended.GeneratedAt,
            OverallStatus = extended.OverallStatus,
            Results = extended.VmGuestDrift
        };
        return report;
    }
}

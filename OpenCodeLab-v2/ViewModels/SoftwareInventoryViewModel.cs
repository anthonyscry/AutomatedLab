using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using Microsoft.Win32;
using OpenCodeLab.Models;
using OpenCodeLab.Services;

namespace OpenCodeLab.ViewModels;

public class FlatSoftwareEntry
{
    public string VMName { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Version { get; set; } = string.Empty;
    public string Publisher { get; set; } = string.Empty;
    public DateTime? InstallDate { get; set; }
}

public class SoftwareInventoryViewModel : ObservableObject
{
    private readonly SoftwareInventoryService _inventoryService = new();
    private readonly HyperVService _hvService = new();
    private CancellationTokenSource? _cts;

    private VirtualMachine? _selectedVM;
    private string _searchText = string.Empty;
    private bool _isGroupedView = true;
    private bool _isScanning;
    private string _statusMessage = "No scan results. Click 'Scan All' to inventory running VMs.";
    private bool _hasResults;

    public ObservableCollection<ScanResult> ScanResults { get; } = new();
    public ObservableCollection<ScanResult> FilteredResults { get; } = new();
    public ObservableCollection<FlatSoftwareEntry> FilteredFlatList { get; } = new();
    public ObservableCollection<VirtualMachine> AvailableVMs { get; } = new();

    public AsyncCommand ScanAllCommand { get; }
    public AsyncCommand ScanSelectedCommand { get; }
    public AsyncCommand CancelScanCommand { get; }
    public AsyncCommand ExportCsvCommand { get; }
    public AsyncCommand ExportJsonCommand { get; }
    public AsyncCommand ClearCommand { get; }

    public VirtualMachine? SelectedVM
    {
        get => _selectedVM;
        set
        {
            _selectedVM = value;
            OnPropertyChanged();
            ScanSelectedCommand.RaiseCanExecuteChanged();
            ApplyFilters();
        }
    }

    public string SearchText
    {
        get => _searchText;
        set
        {
            _searchText = value;
            OnPropertyChanged();
            ApplyFilters();
        }
    }

    public bool IsGroupedView
    {
        get => _isGroupedView;
        set
        {
            _isGroupedView = value;
            OnPropertyChanged();
        }
    }

    public bool IsScanning
    {
        get => _isScanning;
        set
        {
            _isScanning = value;
            OnPropertyChanged();
            ScanAllCommand.RaiseCanExecuteChanged();
            ScanSelectedCommand.RaiseCanExecuteChanged();
            CancelScanCommand.RaiseCanExecuteChanged();
        }
    }

    public string StatusMessage
    {
        get => _statusMessage;
        set { _statusMessage = value; OnPropertyChanged(); }
    }

    public bool HasResults
    {
        get => _hasResults;
        set
        {
            _hasResults = value;
            OnPropertyChanged();
            ExportCsvCommand.RaiseCanExecuteChanged();
            ExportJsonCommand.RaiseCanExecuteChanged();
            ClearCommand.RaiseCanExecuteChanged();
        }
    }

    public SoftwareInventoryViewModel()
    {
        ScanAllCommand = new AsyncCommand(ScanAllAsync, () => !IsScanning);
        ScanSelectedCommand = new AsyncCommand(ScanSelectedAsync, () => SelectedVM != null && !IsScanning);
        CancelScanCommand = new AsyncCommand(CancelScanAsync, () => IsScanning);
        ExportCsvCommand = new AsyncCommand(ExportCsvAsync, () => HasResults);
        ExportJsonCommand = new AsyncCommand(ExportJsonAsync, () => HasResults);
        ClearCommand = new AsyncCommand(ClearAsync, () => HasResults);
    }

    public async Task LoadAsync()
    {
        try
        {
            var vms = await _hvService.GetVirtualMachinesAsync();
            Application.Current.Dispatcher.Invoke(() =>
            {
                AvailableVMs.Clear();
                foreach (var vm in vms)
                    AvailableVMs.Add(vm);
            });

            var persisted = await _inventoryService.LoadResultsAsync();
            if (persisted.Count > 0)
            {
                Application.Current.Dispatcher.Invoke(() =>
                {
                    ScanResults.Clear();
                    foreach (var r in persisted)
                        ScanResults.Add(r);
                    HasResults = ScanResults.Count > 0;
                    ApplyFilters();
                    StatusMessage = $"Loaded {ScanResults.Count} cached scan result(s). Click 'Scan All' to refresh.";
                });
            }
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"LoadAsync error: {ex.Message}");
        }
    }

    private async Task ScanAllAsync()
    {
        IsScanning = true;
        _cts = new CancellationTokenSource();
        try
        {
            var vms = await _hvService.GetVirtualMachinesAsync();
            Application.Current.Dispatcher.Invoke(() =>
            {
                AvailableVMs.Clear();
                foreach (var vm in vms)
                    AvailableVMs.Add(vm);
            });

            var labName = ResolveLabName();
            var progress = new Progress<string>(msg =>
            {
                Application.Current.Dispatcher.Invoke(() => StatusMessage = msg);
            });

            var results = await _inventoryService.ScanAllRunningVMsAsync(vms, labName, progress, _cts.Token);

            Application.Current.Dispatcher.Invoke(() =>
            {
                ScanResults.Clear();
                foreach (var r in results)
                    ScanResults.Add(r);
                HasResults = ScanResults.Count > 0;
                ApplyFilters();
            });

            await _inventoryService.SaveResultsAsync(results.ToList());
        }
        catch (OperationCanceledException)
        {
            Application.Current.Dispatcher.Invoke(() => StatusMessage = "Scan cancelled.");
        }
        catch (Exception ex)
        {
            Application.Current.Dispatcher.Invoke(() =>
            {
                MessageBox.Show($"Scan failed: {ex.Message}", "Error",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            });
        }
        finally
        {
            IsScanning = false;
            _cts?.Dispose();
            _cts = null;
        }
    }

    private async Task ScanSelectedAsync()
    {
        if (SelectedVM == null) return;
        IsScanning = true;
        _cts = new CancellationTokenSource();
        try
        {
            var labName = ResolveLabName();
            StatusMessage = $"Scanning {SelectedVM.Name}...";

            var result = await _inventoryService.ScanVMAsync(SelectedVM.Name, labName, _cts.Token);

            Application.Current.Dispatcher.Invoke(() =>
            {
                var existing = ScanResults.FirstOrDefault(r => r.VMName == result.VMName);
                if (existing != null)
                    ScanResults.Remove(existing);
                ScanResults.Add(result);
                HasResults = ScanResults.Count > 0;
                ApplyFilters();
                StatusMessage = result.Success
                    ? $"Scanned {result.VMName}: {result.Software.Count} packages found."
                    : $"Scan of {result.VMName} failed: {result.ErrorMessage}";
            });

            await _inventoryService.SaveResultsAsync(ScanResults.ToList());
        }
        catch (OperationCanceledException)
        {
            Application.Current.Dispatcher.Invoke(() => StatusMessage = "Scan cancelled.");
        }
        catch (Exception ex)
        {
            Application.Current.Dispatcher.Invoke(() =>
            {
                MessageBox.Show($"Scan failed: {ex.Message}", "Error",
                    MessageBoxButton.OK, MessageBoxImage.Error);
            });
        }
        finally
        {
            IsScanning = false;
            _cts?.Dispose();
            _cts = null;
        }
    }

    private async Task CancelScanAsync()
    {
        _cts?.Cancel();
        await Task.CompletedTask;
    }

    private async Task ExportCsvAsync()
    {
        try
        {
            var dialog = new SaveFileDialog
            {
                Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*",
                DefaultExt = ".csv",
                FileName = $"software-inventory-{DateTime.Now:yyyyMMdd-HHmmss}.csv"
            };

            if (dialog.ShowDialog() == true)
            {
                await ExportService.ExportToCsvAsync(ScanResults, dialog.FileName);
                MessageBox.Show($"Exported to {dialog.FileName}", "Export Successful",
                    MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Export failed: {ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async Task ExportJsonAsync()
    {
        try
        {
            var dialog = new SaveFileDialog
            {
                Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*",
                DefaultExt = ".json",
                FileName = $"software-inventory-{DateTime.Now:yyyyMMdd-HHmmss}.json"
            };

            if (dialog.ShowDialog() == true)
            {
                await ExportService.ExportToJsonAsync(ScanResults, dialog.FileName);
                MessageBox.Show($"Exported to {dialog.FileName}", "Export Successful",
                    MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Export failed: {ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async Task ClearAsync()
    {
        try
        {
            var result = MessageBox.Show("Clear all scan results?", "Confirm",
                MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (result == MessageBoxResult.Yes)
            {
                ScanResults.Clear();
                FilteredResults.Clear();
                FilteredFlatList.Clear();
                HasResults = false;
                StatusMessage = "No scan results. Click 'Scan All' to inventory running VMs.";
                _inventoryService.DeletePersistedResults();
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Clear failed: {ex.Message}", "Error",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
        await Task.CompletedTask;
    }

    private void ApplyFilters()
    {
        var filtered = ScanResults.AsEnumerable();

        if (SelectedVM != null)
            filtered = filtered.Where(r => r.VMName == SelectedVM.Name);

        if (!string.IsNullOrWhiteSpace(SearchText))
        {
            var searchLower = SearchText.ToLower();
            filtered = filtered.Where(r =>
                r.Software.Any(s =>
                    s.Name.ToLower().Contains(searchLower) ||
                    s.Version.ToLower().Contains(searchLower) ||
                    s.Publisher.ToLower().Contains(searchLower)));
        }

        Application.Current.Dispatcher.Invoke(() =>
        {
            FilteredResults.Clear();
            foreach (var r in filtered)
                FilteredResults.Add(r);

            FilteredFlatList.Clear();
            foreach (var result in FilteredResults)
            {
                foreach (var sw in result.Software)
                {
                    FilteredFlatList.Add(new FlatSoftwareEntry
                    {
                        VMName = result.VMName,
                        Name = sw.Name,
                        Version = sw.Version,
                        Publisher = sw.Publisher,
                        InstallDate = sw.InstallDate
                    });
                }
            }
        });
    }

    private string ResolveLabName()
    {
        try
        {
            var labConfigDir = @"C:\LabSources\LabConfig";
            if (!Directory.Exists(labConfigDir))
                return string.Empty;

            var jsonFiles = Directory.GetFiles(labConfigDir, "*.json")
                .OrderByDescending(f => File.GetLastWriteTime(f))
                .FirstOrDefault();

            if (string.IsNullOrEmpty(jsonFiles))
                return string.Empty;

            var json = File.ReadAllText(jsonFiles);
            using var doc = System.Text.Json.JsonDocument.Parse(json);
            if (doc.RootElement.TryGetProperty("labName", out var labNameElement))
                return labNameElement.GetString() ?? string.Empty;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"ResolveLabName error: {ex.Message}");
        }

        return string.Empty;
    }
}

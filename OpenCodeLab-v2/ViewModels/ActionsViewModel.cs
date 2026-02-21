using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using Microsoft.Win32;
using OpenCodeLab.Models;
using OpenCodeLab.Services;
using OpenCodeLab.Views;

namespace OpenCodeLab.ViewModels;

public class ActionsViewModel : ObservableObject
{
    private readonly LabDeploymentService _deploymentService = new();
    private string _logOutput = string.Empty;
    private int _deploymentProgress;
    private bool _isDeploying;

    // Default paths
    private const string DefaultLabSources = @"C:\LabSources";
    private const string DefaultLabConfigPath = @"C:\LabSources\LabConfig";
    private const string DefaultISOPath = @"C:\LabSources\ISOs";
    private const string LogDirectory = @"C:\LabSources\Logs";

    public ObservableCollection<LabConfig> RecentLabs { get; } = new();
    public AsyncCommand NewLabCommand { get; }
    public AsyncCommand LoadLabCommand { get; }
    public AsyncCommand DeployLabCommand { get; }
    public AsyncCommand RemoveLabCommand { get; }
    public AsyncCommand ClearLogsCommand { get; }
    public AsyncCommand SaveLabCommand { get; }

    public string LogOutput { get => _logOutput; set { _logOutput = value; OnPropertyChanged(); } }
    public int DeploymentProgress { get => _deploymentProgress; set { _deploymentProgress = value; OnPropertyChanged(); } }
    public bool IsDeploying { get => _isDeploying; set { _isDeploying = value; OnPropertyChanged(); UpdateCommands(); } }

    public ActionsViewModel()
    {
        NewLabCommand = new AsyncCommand(ShowNewLabDialogAsync);
        LoadLabCommand = new AsyncCommand(LoadLabAsync);
        DeployLabCommand = new AsyncCommand(DeployLabAsync, () => SelectedLab != null && !IsDeploying);
        RemoveLabCommand = new AsyncCommand(RemoveLabAsync, () => SelectedLab != null && !IsDeploying);
        ClearLogsCommand = new AsyncCommand(() => Task.Run(() => LogOutput = string.Empty));
        SaveLabCommand = new AsyncCommand(SaveLabAsync, () => SelectedLab != null);

        _deploymentService.Progress += (s, e) =>
        {
            DeploymentProgress = e.Percent;
            var msg = $"[{e.Percent}%] {e.Message}{Environment.NewLine}";
            LogOutput += msg;
            WriteToLog(msg);
        };

        // Ensure directories exist
        EnsureDirectoriesExist();

        LoadRecentLabs();
    }

    private LabConfig? _selectedLab;
    public LabConfig? SelectedLab
    {
        get => _selectedLab;
        set
        {
            _selectedLab = value;
            OnPropertyChanged();
            UpdateCommands();
        }
    }

    private void UpdateCommands()
    {
        try
        {
            ((AsyncCommand)DeployLabCommand).RaiseCanExecuteChanged();
            ((AsyncCommand)RemoveLabCommand).RaiseCanExecuteChanged();
            ((AsyncCommand)SaveLabCommand).RaiseCanExecuteChanged();
        }
        catch { }
    }

    private void EnsureDirectoriesExist()
    {
        try
        {
            Directory.CreateDirectory(DefaultLabSources);
            Directory.CreateDirectory(DefaultLabConfigPath);
            Directory.CreateDirectory(DefaultISOPath);
            Directory.CreateDirectory(LogDirectory);
        }
        catch { }
    }

    private string _currentLogFile = string.Empty;
    private void WriteToLog(string message)
    {
        try
        {
            if (string.IsNullOrEmpty(_currentLogFile))
            {
                _currentLogFile = Path.Combine(LogDirectory, $"deployment-{DateTime.Now:yyyyMMdd-HHmmss}.log");
            }
            File.AppendAllText(_currentLogFile, $"[{DateTime.Now:HH:mm:ss}] {message}");
        }
        catch { }
    }

    private void LogError(string message, Exception? ex = null)
    {
        var fullMsg = message;
        if (ex != null)
        {
            fullMsg += $" {ex.Message}";
            if (ex.InnerException != null)
                fullMsg += $"\n  Inner: {ex.InnerException.Message}";
        }
        LogOutput += $"ERROR: {fullMsg}{Environment.NewLine}";
        WriteToLog($"ERROR: {fullMsg}{Environment.NewLine}");
    }

    private void LoadRecentLabs()
    {
        try
        {
            RecentLabs.Clear();
            if (Directory.Exists(DefaultLabConfigPath))
            {
                foreach (var file in Directory.GetFiles(DefaultLabConfigPath, "*.json"))
                {
                    try
                    {
                        var json = File.ReadAllText(file);
                        var lab = System.Text.Json.JsonSerializer.Deserialize<LabConfig>(json);
                        if (lab != null)
                        {
                            lab.LabPath = file;
                            RecentLabs.Add(lab);
                        }
                    }
                    catch { }
                }
            }

            // Also load from old location for backwards compatibility
            var oldDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "AutomatedLab");
            if (Directory.Exists(oldDir))
            {
                foreach (var file in Directory.GetFiles(oldDir, "*.json"))
                {
                    try
                    {
                        var json = File.ReadAllText(file);
                        var lab = System.Text.Json.JsonSerializer.Deserialize<LabConfig>(json);
                        if (lab != null && !RecentLabs.Any(l => l.LabName == lab.LabName))
                        {
                            lab.LabPath = file;
                            RecentLabs.Add(lab);
                        }
                    }
                    catch { }
                }
            }
        }
        catch (Exception ex)
        {
            LogError("Error loading recent labs", ex);
        }
    }

    private async Task ShowNewLabDialogAsync()
    {
        await Task.Run(() => Application.Current.Dispatcher.Invoke(() =>
        {
            try
            {
                var dialog = new NewLabDialog();
                if (dialog.ShowDialog() == true)
                {
                    var lab = dialog.GetLabConfig();
                    RecentLabs.Add(lab);
                    SelectedLab = lab;
                    LogOutput += $"Created new lab: {lab.LabName} with {lab.VMs.Count} VM(s){Environment.NewLine}";
                    LogOutput += $"Note: Lab is not saved yet. Click 'Save Lab' to save it.{Environment.NewLine}";
                }
            }
            catch (Exception ex)
            {
                LogError("Error creating new lab", ex);
            }
        }));
    }

    private async Task LoadLabAsync()
    {
        await Task.Run(() => Application.Current.Dispatcher.Invoke(() =>
        {
            try
            {
                var dialog = new OpenFileDialog
                {
                    Filter = "Lab Files|*.json|All Files|*.*",
                    Title = "Select Lab Configuration",
                    InitialDirectory = DefaultLabConfigPath
                };
                if (dialog.ShowDialog() == true)
                {
                    var json = File.ReadAllText(dialog.FileName);
                    var lab = System.Text.Json.JsonSerializer.Deserialize<LabConfig>(json);
                    if (lab != null)
                    {
                        var existing = RecentLabs.FirstOrDefault(l => l.LabName == lab.LabName);
                        if (existing != null) RecentLabs.Remove(existing);
                        lab.LabPath = dialog.FileName;
                        RecentLabs.Add(lab);
                        SelectedLab = lab;
                        LogOutput += $"Loaded lab: {lab.LabName}{Environment.NewLine}";
                    }
                }
            }
            catch (Exception ex)
            {
                LogError("Error loading lab", ex);
            }
        }));
    }

    private async Task SaveLabAsync()
    {
        if (SelectedLab == null) return;

        await Task.Run(() =>
        {
            try
            {
                if (string.IsNullOrEmpty(SelectedLab.LabPath) || !SelectedLab.LabPath.EndsWith(".json"))
                {
                    SelectedLab.LabPath = Path.Combine(DefaultLabConfigPath, $"{SelectedLab.LabName}.json");
                }

                Directory.CreateDirectory(DefaultLabConfigPath);
                var json = System.Text.Json.JsonSerializer.Serialize(SelectedLab, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
                File.WriteAllText(SelectedLab.LabPath, json);

                Application.Current.Dispatcher.Invoke(() =>
                {
                    LogOutput += $"Saved lab: {SelectedLab.LabName} to {SelectedLab.LabPath}{Environment.NewLine}";
                });
            }
            catch (Exception ex)
            {
                Application.Current.Dispatcher.Invoke(() =>
                {
                    LogError("Error saving lab", ex);
                });
            }
        });
    }

    private async Task DeployLabAsync()
    {
        if (SelectedLab == null) return;

        try
        {
            // Check if lab has a DC - requires admin password
            var hasDC = SelectedLab.VMs.Any(v => v.Role.Contains("DC", StringComparison.OrdinalIgnoreCase));
            string? adminPassword = null;

            if (hasDC)
            {
                // Check environment variable first
                adminPassword = Environment.GetEnvironmentVariable("OPENCODELAB_ADMIN_PASSWORD");

                // Prompt for password if not set
                if (string.IsNullOrEmpty(adminPassword))
                {
                    await Task.Run(() => Application.Current.Dispatcher.Invoke(() =>
                    {
                        adminPassword = Views.PasswordDialog.PromptForPassword(
                            Application.Current.MainWindow!, SelectedLab.LabName);
                    }));

                    if (string.IsNullOrEmpty(adminPassword))
                    {
                        LogOutput += "Deployment cancelled: No password provided.{Environment.NewLine}";
                        return;
                    }
                }

                // Set environment variable for this process
                Environment.SetEnvironmentVariable("OPENCODELAB_ADMIN_PASSWORD", adminPassword);
            }

            // Auto-save before deploying
            if (string.IsNullOrEmpty(SelectedLab.LabPath) || !SelectedLab.LabPath.EndsWith(".json"))
            {
                SelectedLab.LabPath = Path.Combine(DefaultLabConfigPath, $"{SelectedLab.LabName}.json");
                try
                {
                    Directory.CreateDirectory(DefaultLabConfigPath);
                    var json = System.Text.Json.JsonSerializer.Serialize(SelectedLab, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
                    File.WriteAllText(SelectedLab.LabPath, json);
                    LogOutput += $"Lab saved to: {SelectedLab.LabPath}{Environment.NewLine}";
                }
                catch { }
            }

            IsDeploying = true;
            LogOutput = string.Empty;
            _currentLogFile = Path.Combine(LogDirectory, $"deployment-{DateTime.Now:yyyyMMdd-HHmmss}.log");
            WriteToLog($"Starting deployment of lab: {SelectedLab.LabName}{Environment.NewLine}");

            var success = await _deploymentService.DeployLabAsync(SelectedLab, msg =>
            {
                LogOutput += msg + Environment.NewLine;
                WriteToLog(msg + Environment.NewLine);
            });

            // Clear password from environment after deployment
            if (hasDC)
            {
                Environment.SetEnvironmentVariable("OPENCODELAB_ADMIN_PASSWORD", null);
            }

            IsDeploying = false;

            if (success)
            {
                LogOutput += $"{Environment.NewLine}*** Deployment completed successfully! ***{Environment.NewLine}";
                WriteToLog($"{Environment.NewLine}*** Deployment completed successfully! ***{Environment.NewLine}");
            }
            else
            {
                LogOutput += $"{Environment.NewLine}*** Deployment failed. Check log for details. ***{Environment.NewLine}";
                WriteToLog($"{Environment.NewLine}*** Deployment failed. ***{Environment.NewLine}");
            }
        }
        catch (Exception ex)
        {
            IsDeploying = false;
            LogError("Deployment failed with exception", ex);
            LogOutput += $"{Environment.NewLine}*** Deployment crashed. See log file: {_currentLogFile} ***{Environment.NewLine}";
        }
    }

    private async Task RemoveLabAsync()
    {
        if (SelectedLab == null) return;

        try
        {
            IsDeploying = true;
            LogOutput = string.Empty;
            _currentLogFile = Path.Combine(LogDirectory, $"removal-{DateTime.Now:yyyyMMdd-HHmmss}.log");
            WriteToLog($"Starting removal of lab: {SelectedLab.LabName}{Environment.NewLine}");

            var success = await _deploymentService.RemoveLabAsync(SelectedLab, msg =>
            {
                LogOutput += msg + Environment.NewLine;
                WriteToLog(msg + Environment.NewLine);
            });

            IsDeploying = false;

            if (success)
            {
                LogOutput += "Lab removed successfully!{Environment.NewLine}";
                RecentLabs.Remove(SelectedLab);
            }
            else
            {
                LogOutput += "Removal failed. Check log for details.{Environment.NewLine}";
            }
        }
        catch (Exception ex)
        {
            IsDeploying = false;
            LogError("Removal failed with exception", ex);
        }
    }
}

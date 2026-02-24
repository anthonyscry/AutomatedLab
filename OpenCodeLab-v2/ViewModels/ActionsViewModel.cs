using System;
using System.Collections.Generic;
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
    private System.Threading.CancellationTokenSource? _deployCts;

    // Default paths
    private const string DefaultLabSources = @"C:\LabSources";
    private const string DefaultLabConfigPath = @"C:\LabSources\LabConfig";
    private const string DefaultISOPath = @"C:\LabSources\ISOs";
    private const string LogDirectory = @"C:\LabSources\Logs";

    public ObservableCollection<LabConfig> RecentLabs { get; } = new();
    public AsyncCommand NewLabCommand { get; }
    public AsyncCommand EditLabCommand { get; }
    public AsyncCommand DeployLabCommand { get; }
    public AsyncCommand CancelDeployCommand { get; }
    public AsyncCommand RemoveLabCommand { get; }
    public AsyncCommand ClearLogsCommand { get; }
    public AsyncCommand CopyLogsCommand { get; }

    public string LogOutput { get => _logOutput; set { _logOutput = value; OnPropertyChanged(); } }
    public int DeploymentProgress { get => _deploymentProgress; set { _deploymentProgress = value; OnPropertyChanged(); } }
    public bool IsDeploying { get => _isDeploying; set { _isDeploying = value; OnPropertyChanged(); UpdateCommands(); } }

    public ActionsViewModel()
    {
        NewLabCommand = new AsyncCommand(ShowNewLabDialogAsync);
        EditLabCommand = new AsyncCommand(EditLabAsync, () => SelectedLab != null && !IsDeploying);
        DeployLabCommand = new AsyncCommand(DeployLabAsync, () => SelectedLab != null && !IsDeploying);
        CancelDeployCommand = new AsyncCommand(CancelDeploymentAsync, () => IsDeploying);
        RemoveLabCommand = new AsyncCommand(RemoveLabAsync, () => SelectedLab != null && !IsDeploying);
        ClearLogsCommand = new AsyncCommand(() => Task.Run(() => LogOutput = string.Empty));
        CopyLogsCommand = new AsyncCommand(() =>
        {
            Application.Current.Dispatcher.Invoke(() =>
            {
                var text = string.IsNullOrEmpty(LogOutput) ? " " : LogOutput;
                for (int i = 0; i < 5; i++)
                {
                    try { Clipboard.SetDataObject(text, true); return; }
                    catch { System.Threading.Thread.Sleep(50); }
                }
            });
            return Task.CompletedTask;
        });

        _deploymentService.Progress += (s, e) =>
        {
            DeploymentProgress = e.Percent;
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
            ((AsyncCommand)CancelDeployCommand).RaiseCanExecuteChanged();
            ((AsyncCommand)RemoveLabCommand).RaiseCanExecuteChanged();
            ((AsyncCommand)EditLabCommand).RaiseCanExecuteChanged();
        }
        catch { }
    }

    private Task CancelDeploymentAsync()
    {
        try
        {
            _deployCts?.Cancel();
            LogOutput += $"Deployment cancellation requested...{Environment.NewLine}";
            LogOutput += $"Note: The deployment process will continue in the background. Close and reopen the app to deploy again.{Environment.NewLine}";
        }
        catch { }
        finally
        {
            IsDeploying = false;
        }
        return Task.CompletedTask;
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

                    // Auto-save to default config folder
                    try
                    {
                        Directory.CreateDirectory(DefaultLabConfigPath);
                        lab.LabPath = Path.Combine(DefaultLabConfigPath, $"{lab.LabName}.json");
                        var json = System.Text.Json.JsonSerializer.Serialize(lab, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
                        File.WriteAllText(lab.LabPath, json);
                    }
                    catch { }

                    // Replace existing entry with same name, or add new
                    var existing = RecentLabs.FirstOrDefault(l => l.LabName == lab.LabName);
                    if (existing != null) RecentLabs.Remove(existing);
                    RecentLabs.Add(lab);
                    SelectedLab = lab;
                    LogOutput += $"Created lab: {lab.LabName} with {lab.VMs.Count} VM(s) - saved to {lab.LabPath}{Environment.NewLine}";
                }
            }
            catch (Exception ex)
            {
                LogError("Error creating new lab", ex);
            }
        }));
    }

    private async Task EditLabAsync()
    {
        if (SelectedLab == null) return;

        await Task.Run(() => Application.Current.Dispatcher.Invoke(() =>
        {
            try
            {
                var dialog = new NewLabDialog(SelectedLab);
                if (dialog.ShowDialog() == true)
                {
                    var lab = dialog.GetLabConfig();
                    lab.LabPath = SelectedLab.LabPath;

                    // Auto-save changes
                    try
                    {
                        if (string.IsNullOrEmpty(lab.LabPath))
                            lab.LabPath = Path.Combine(DefaultLabConfigPath, $"{lab.LabName}.json");
                        Directory.CreateDirectory(DefaultLabConfigPath);
                        var json = System.Text.Json.JsonSerializer.Serialize(lab, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
                        File.WriteAllText(lab.LabPath, json);
                    }
                    catch { }

                    var index = RecentLabs.IndexOf(SelectedLab);
                    if (index >= 0) RecentLabs[index] = lab;
                    else RecentLabs.Add(lab);
                    SelectedLab = lab;
                    LogOutput += $"Updated lab: {lab.LabName} with {lab.VMs.Count} VM(s){Environment.NewLine}";
                }
            }
            catch (Exception ex)
            {
                LogError("Error editing lab", ex);
            }
        }));
    }

    // Keep SaveLabAsync as internal helper (no longer exposed as button)
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
                        LogOutput += $"Deployment cancelled: No password provided.{Environment.NewLine}";
                        IsDeploying = false;
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

            // Check if any VMs already exist - offer deployment mode selection
            string deploymentMode = "full";
            bool userCancelledDeploymentMode = false;
            var existingVMs = new List<string>();
            foreach (var vm in SelectedLab.VMs)
            {
                try
                {
                    // Use PowerShell to check Hyper-V
                    var psi = new System.Diagnostics.ProcessStartInfo("powershell.exe",
                        $"-NoProfile -Command \"if (Get-VM -Name '{vm.Name}' -ErrorAction SilentlyContinue) {{ 'EXISTS' }}\"")
                    { RedirectStandardOutput = true, UseShellExecute = false, CreateNoWindow = true };
                    using var p = System.Diagnostics.Process.Start(psi);
                    var output = p?.StandardOutput.ReadToEnd()?.Trim() ?? "";
                    p?.WaitForExit();
                    if (output == "EXISTS") existingVMs.Add(vm.Name);
                }
                catch { }
            }

            if (existingVMs.Count > 0 && existingVMs.Count < SelectedLab.VMs.Count)
            {
                // Some VMs exist, some are new - ask user how to proceed
                var newVMs = SelectedLab.VMs.Where(v => !existingVMs.Contains(v.Name)).Select(v => v.Name);
                await Task.Run(() => Application.Current.Dispatcher.Invoke(() =>
                {
                    var result = MessageBox.Show(
                        $"Existing VMs found: {string.Join(", ", existingVMs)}\n" +
                        $"New VMs to create: {string.Join(", ", newVMs)}\n\n" +
                        "Click YES to update existing VMs in place and add any missing VMs.\n" +
                        "Click NO to add only missing VMs (incremental).\n" +
                        "Click CANCEL to stop deployment.",
                        "Choose Deployment Mode",
                        MessageBoxButton.YesNoCancel,
                        MessageBoxImage.Question);
                    if (result == MessageBoxResult.Yes) deploymentMode = "update-existing";
                    else if (result == MessageBoxResult.No) deploymentMode = "incremental";
                    else userCancelledDeploymentMode = true;
                }));
                if (userCancelledDeploymentMode) { IsDeploying = false; return; }
            }
            else if (existingVMs.Count > 0 && existingVMs.Count == SelectedLab.VMs.Count)
            {
                // All VMs already exist
                await Task.Run(() => Application.Current.Dispatcher.Invoke(() =>
                {
                    var result = MessageBox.Show(
                        $"All VMs already exist: {string.Join(", ", existingVMs)}\n\n" +
                        "Click YES to update existing VMs in place.\n" +
                        "Click NO to redeploy everything from scratch.\n" +
                        "Click CANCEL to stop deployment.",
                        "Lab Already Deployed",
                        MessageBoxButton.YesNoCancel,
                        MessageBoxImage.Question);
                    if (result == MessageBoxResult.Yes) deploymentMode = "update-existing";
                    else if (result == MessageBoxResult.No) deploymentMode = "full";
                    else userCancelledDeploymentMode = true;
                }));
                if (userCancelledDeploymentMode) { IsDeploying = false; return; }
            }

            var deployStopwatch = System.Diagnostics.Stopwatch.StartNew();
            var deployStartTime = DateTime.Now;
            LogOutput += $"Deployment started at {deployStartTime:HH:mm:ss}{Environment.NewLine}";
            WriteToLog($"Deployment started at {deployStartTime:HH:mm:ss}{Environment.NewLine}");

            _deployCts = new System.Threading.CancellationTokenSource();
            var success = await _deploymentService.DeployLabAsync(SelectedLab, msg =>
            {
                Application.Current.Dispatcher.BeginInvoke(() =>
                {
                    LogOutput += msg + Environment.NewLine;
                });
                WriteToLog(msg + Environment.NewLine);
            }, adminPassword, deploymentMode, _deployCts.Token);

            deployStopwatch.Stop();
            var elapsed = deployStopwatch.Elapsed;
            var timeStr = elapsed.TotalHours >= 1
                ? $"{(int)elapsed.TotalHours}h {elapsed.Minutes:D2}m {elapsed.Seconds:D2}s"
                : $"{(int)elapsed.TotalMinutes}m {elapsed.Seconds:D2}s";

            // Clear password from environment after deployment
            if (hasDC)
            {
                Environment.SetEnvironmentVariable("OPENCODELAB_ADMIN_PASSWORD", null);
            }

            if (success)
            {
                LogOutput += $"{Environment.NewLine}*** Deployment completed successfully in {timeStr}! ***{Environment.NewLine}";
                WriteToLog($"{Environment.NewLine}*** Deployment completed successfully in {timeStr}! ***{Environment.NewLine}");
            }
            else
            {
                LogOutput += $"{Environment.NewLine}*** Deployment failed after {timeStr}. Check log for details. ***{Environment.NewLine}";
                WriteToLog($"{Environment.NewLine}*** Deployment failed after {timeStr}. ***{Environment.NewLine}");
            }
        }
        catch (Exception ex)
        {
            LogError("Deployment failed with exception", ex);
            LogOutput += $"{Environment.NewLine}*** Deployment crashed. See log file: {_currentLogFile} ***{Environment.NewLine}";
        }
        finally
        {
            IsDeploying = false;
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

            if (success)
            {
                LogOutput += $"Lab removed successfully!{Environment.NewLine}";
                RecentLabs.Remove(SelectedLab);
            }
            else
            {
                LogOutput += $"Removal failed. Check log for details.{Environment.NewLine}";
            }
        }
        catch (Exception ex)
        {
            LogError("Removal failed with exception", ex);
        }
        finally
        {
            IsDeploying = false;
        }
    }
}

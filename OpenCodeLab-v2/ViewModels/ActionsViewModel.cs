using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
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
    private bool _isCancellationRequested;
    private System.Threading.CancellationTokenSource? _deployCts;
    private string _activeDeploymentId = string.Empty;

    // Default paths
    private const string DefaultLabSources = @"C:\LabSources";
    private const string DefaultLabConfigPath = @"C:\LabSources\LabConfig";
    private const string DefaultISOPath = @"C:\LabSources\ISOs";
    private const string DefaultLogDirectory = @"C:\LabSources\Logs";

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
    public bool IsCancellationRequested { get => _isCancellationRequested; set { _isCancellationRequested = value; OnPropertyChanged(); UpdateCommands(); } }

    public ActionsViewModel()
    {
        NewLabCommand = new AsyncCommand(ShowNewLabDialogAsync);
        EditLabCommand = new AsyncCommand(EditLabAsync, () => SelectedLab != null && !IsDeploying && !IsCancellationRequested);
        DeployLabCommand = new AsyncCommand(DeployLabAsync, () => SelectedLab != null && !IsDeploying && !IsCancellationRequested);
        CancelDeployCommand = new AsyncCommand(CancelDeploymentAsync, () => IsDeploying && !IsCancellationRequested);
        RemoveLabCommand = new AsyncCommand(RemoveLabAsync, () => SelectedLab != null && !IsDeploying && !IsCancellationRequested);
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

    private static string ResolvePath(string? configuredPath, string fallback)
    {
        return string.IsNullOrWhiteSpace(configuredPath) ? fallback : configuredPath;
    }

    private static string GetLabSourcesPath(AppSettings settings)
    {
        return ResolvePath(settings.DefaultLabPath, DefaultLabSources);
    }

    private static string GetLabConfigPath(AppSettings settings)
    {
        return ResolvePath(settings.LabConfigPath, DefaultLabConfigPath);
    }

    private static string GetIsoPath(AppSettings settings)
    {
        return ResolvePath(settings.ISOPath, DefaultISOPath);
    }

    private static string GetLogDirectoryPath(AppSettings settings)
    {
        var labSources = GetLabSourcesPath(settings);
        if (string.IsNullOrWhiteSpace(labSources))
            return DefaultLogDirectory;

        return Path.Combine(labSources, "Logs");
    }

    private void TrackDeploymentEvent(string eventName, string? details = null)
    {
        var deployId = string.IsNullOrWhiteSpace(_activeDeploymentId) ? "none" : _activeDeploymentId;
        var safeDetails = string.IsNullOrWhiteSpace(details)
            ? string.Empty
            : $" detail={details.Replace(Environment.NewLine, " ").Trim()}";

        var line = $"[telemetry] deploy_id={deployId} event={eventName}{safeDetails} ts={DateTimeOffset.UtcNow:O}";
        LogOutput += line + Environment.NewLine;
        WriteToLog(line + Environment.NewLine);
    }

    private Task CancelDeploymentAsync()
    {
        try
        {
            if (!IsDeploying || IsCancellationRequested)
                return Task.CompletedTask;

            IsCancellationRequested = true;
            TrackDeploymentEvent("cancel_requested", $"lab={SelectedLab?.LabName ?? "unknown"}");
            _deployCts?.Cancel();
            LogOutput += $"Deployment cancellation requested...{Environment.NewLine}";
            LogOutput += $"Waiting for current deployment process to stop...{Environment.NewLine}";
        }
        catch (Exception ex) { LogError("Failed to request deployment cancellation", ex); }

        return Task.CompletedTask;
    }

    private void EnsureDirectoriesExist()
    {
        try
        {
            var settings = AppSettingsStore.LoadOrDefault();
            Directory.CreateDirectory(GetLabSourcesPath(settings));
            Directory.CreateDirectory(GetLabConfigPath(settings));
            Directory.CreateDirectory(GetIsoPath(settings));
            Directory.CreateDirectory(GetLogDirectoryPath(settings));
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
                var settings = AppSettingsStore.LoadOrDefault();
                _currentLogFile = Path.Combine(GetLogDirectoryPath(settings), $"deployment-{DateTime.Now:yyyyMMdd-HHmmss}.log");
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
            var settings = AppSettingsStore.LoadOrDefault();
            var labConfigPath = GetLabConfigPath(settings);

            RecentLabs.Clear();
            if (Directory.Exists(labConfigPath))
            {
                foreach (var file in Directory.GetFiles(labConfigPath, "*.json"))
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
                var settings = AppSettingsStore.LoadOrDefault();
                var labConfigPath = GetLabConfigPath(settings);
                var dialog = new NewLabDialog(AppSettingsStore.LoadOrDefault());
                if (dialog.ShowDialog() == true)
                {
                    var lab = dialog.GetLabConfig();

                    // Auto-save to default config folder
                    try
                    {
                        Directory.CreateDirectory(labConfigPath);
                        lab.LabPath = Path.Combine(labConfigPath, $"{lab.LabName}.json");
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
                var settings = AppSettingsStore.LoadOrDefault();
                var labConfigPath = GetLabConfigPath(settings);
                var dialog = new NewLabDialog(SelectedLab);
                if (dialog.ShowDialog() == true)
                {
                    var lab = dialog.GetLabConfig();
                    lab.LabPath = SelectedLab.LabPath;

                    // Auto-save changes
                    try
                    {
                        if (string.IsNullOrEmpty(lab.LabPath))
                            lab.LabPath = Path.Combine(labConfigPath, $"{lab.LabName}.json");
                        Directory.CreateDirectory(labConfigPath);
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
                var settings = AppSettingsStore.LoadOrDefault();
                var labConfigPath = GetLabConfigPath(settings);

                if (string.IsNullOrEmpty(SelectedLab.LabPath) || !SelectedLab.LabPath.EndsWith(".json"))
                {
                    SelectedLab.LabPath = Path.Combine(labConfigPath, $"{SelectedLab.LabName}.json");
                }

                Directory.CreateDirectory(labConfigPath);
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

        var settings = AppSettingsStore.LoadOrDefault();
        var labConfigPath = GetLabConfigPath(settings);
        var logDirectory = GetLogDirectoryPath(settings);
        string? adminPassword = null;

        try
        {
            // Deployment script requires domain admin credentials for lab domain setup.
            // Prefer an environment-provided value for non-interactive automation.
            adminPassword = Environment.GetEnvironmentVariable("OPENCODELAB_ADMIN_PASSWORD");

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
                    return;
                }
            }

            // Set environment variable for this process
            Environment.SetEnvironmentVariable("OPENCODELAB_ADMIN_PASSWORD", adminPassword);

            // Auto-save before deploying
            if (string.IsNullOrEmpty(SelectedLab.LabPath) || !SelectedLab.LabPath.EndsWith(".json"))
            {
                SelectedLab.LabPath = Path.Combine(labConfigPath, $"{SelectedLab.LabName}.json");
                try
                {
                    Directory.CreateDirectory(labConfigPath);
                    var json = System.Text.Json.JsonSerializer.Serialize(SelectedLab, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
                    File.WriteAllText(SelectedLab.LabPath, json);
                    LogOutput += $"Lab saved to: {SelectedLab.LabPath}{Environment.NewLine}";
                }
                catch { }
            }

            IsDeploying = true;
            IsCancellationRequested = false;
            LogOutput = string.Empty;

            Directory.CreateDirectory(logDirectory);
            _activeDeploymentId = Guid.NewGuid().ToString("N")[..8];
            _currentLogFile = Path.Combine(logDirectory, $"deployment-{DateTime.Now:yyyyMMdd-HHmmss}.log");
            TrackDeploymentEvent("deploy_start", $"lab={SelectedLab.LabName}");
            WriteToLog($"Starting deployment of lab: {SelectedLab.LabName}{Environment.NewLine}");

            // Check if any VMs already exist - offer incremental deployment
            bool useIncremental = false;
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
                // Some VMs exist, some are new - ask user
                var newVMs = SelectedLab.VMs.Where(v => !existingVMs.Contains(v.Name)).Select(v => v.Name);
                await Task.Run(() => Application.Current.Dispatcher.Invoke(() =>
                {
                    var result = MessageBox.Show(
                        $"Existing VMs found: {string.Join(", ", existingVMs)}\n" +
                        $"New VMs to create: {string.Join(", ", newVMs)}\n\n" +
                        "Click YES to add new VMs (keep existing).\n" +
                        "Click NO to redeploy everything from scratch.",
                        "Incremental Deployment?",
                        MessageBoxButton.YesNoCancel,
                        MessageBoxImage.Question);
                    if (result == MessageBoxResult.Yes) useIncremental = true;
                    else if (result == MessageBoxResult.Cancel) { useIncremental = false; adminPassword = null; } // signal cancel
                }));
                if (adminPassword == null)
                {
                    TrackDeploymentEvent("deploy_completed", "status=cancelled-before-run");
                    return;
                }
            }
            else if (existingVMs.Count > 0 && existingVMs.Count == SelectedLab.VMs.Count)
            {
                // All VMs already exist
                await Task.Run(() => Application.Current.Dispatcher.Invoke(() =>
                {
                    var result = MessageBox.Show(
                        $"All VMs already exist: {string.Join(", ", existingVMs)}\n\n" +
                        "Click YES to redeploy everything from scratch.\n" +
                        "Click NO to cancel.",
                        "Lab Already Deployed",
                        MessageBoxButton.YesNo,
                        MessageBoxImage.Question);
                    if (result == MessageBoxResult.No) adminPassword = null; // signal cancel
                }));
                if (adminPassword == null)
                {
                    TrackDeploymentEvent("deploy_completed", "status=cancelled-before-run");
                    return;
                }
            }

            var deployStopwatch = System.Diagnostics.Stopwatch.StartNew();
            var deployStartTime = DateTime.Now;
            LogOutput += $"Deployment started at {deployStartTime:HH:mm:ss}{Environment.NewLine}";
            WriteToLog($"Deployment started at {deployStartTime:HH:mm:ss}{Environment.NewLine}");

            _deployCts?.Dispose();
            _deployCts = new System.Threading.CancellationTokenSource();
            var success = await _deploymentService.DeployLabAsync(SelectedLab, msg =>
            {
                Application.Current.Dispatcher.BeginInvoke(() =>
                {
                    LogOutput += msg + Environment.NewLine;
                });
                WriteToLog(msg + Environment.NewLine);
            }, adminPassword, useIncremental, _deployCts.Token);

            deployStopwatch.Stop();
            var elapsed = deployStopwatch.Elapsed;
            var timeStr = elapsed.TotalHours >= 1
                ? $"{(int)elapsed.TotalHours}h {elapsed.Minutes:D2}m {elapsed.Seconds:D2}s"
                : $"{(int)elapsed.TotalMinutes}m {elapsed.Seconds:D2}s";
            var wasCancelled = IsCancellationRequested || (_deployCts?.IsCancellationRequested == true);

            if (success)
            {
                LogOutput += $"{Environment.NewLine}*** Deployment completed successfully in {timeStr}! ***{Environment.NewLine}";
                WriteToLog($"{Environment.NewLine}*** Deployment completed successfully in {timeStr}! ***{Environment.NewLine}");
                TrackDeploymentEvent("deploy_completed", $"status=success duration={timeStr}");
            }
            else if (wasCancelled)
            {
                LogOutput += $"{Environment.NewLine}*** Deployment cancelled after {timeStr}. ***{Environment.NewLine}";
                WriteToLog($"{Environment.NewLine}*** Deployment cancelled after {timeStr}. ***{Environment.NewLine}");
                TrackDeploymentEvent("deploy_completed", $"status=cancelled duration={timeStr}");
            }
            else
            {
                LogOutput += $"{Environment.NewLine}*** Deployment failed after {timeStr}. Check log for details. ***{Environment.NewLine}";
                WriteToLog($"{Environment.NewLine}*** Deployment failed after {timeStr}. ***{Environment.NewLine}");
                TrackDeploymentEvent("deploy_completed", $"status=failed duration={timeStr}");
            }
        }
        catch (Exception ex)
        {
            var safeMessage = ex.Message.Replace(Environment.NewLine, " ").Trim();
            TrackDeploymentEvent("deploy_completed", $"status=crashed error={safeMessage}");
            LogError("Deployment failed with exception", ex);
            LogOutput += $"{Environment.NewLine}*** Deployment crashed. See log file: {_currentLogFile} ***{Environment.NewLine}";
        }
        finally
        {
            Environment.SetEnvironmentVariable("OPENCODELAB_ADMIN_PASSWORD", null);
            _deployCts?.Dispose();
            _deployCts = null;
            IsDeploying = false;
            IsCancellationRequested = false;
            _activeDeploymentId = string.Empty;
        }
    }

    private async Task RemoveLabAsync()
    {
        if (SelectedLab == null) return;

        try
        {
            var settings = AppSettingsStore.LoadOrDefault();
            var logDirectory = GetLogDirectoryPath(settings);

            IsDeploying = true;
            IsCancellationRequested = false;
            LogOutput = string.Empty;
            Directory.CreateDirectory(logDirectory);
            _currentLogFile = Path.Combine(logDirectory, $"removal-{DateTime.Now:yyyyMMdd-HHmmss}.log");
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

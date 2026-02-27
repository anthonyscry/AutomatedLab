using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using OpenCodeLab.Models;
using OpenCodeLab.Services;

namespace OpenCodeLab.ViewModels;

public class DashboardViewModel : ObservableObject
{
    private readonly HyperVService _hvService = new();
    private readonly LabDeploymentService _deploymentService = new();
    private VirtualMachine? _selectedVM;
    private bool _hasFailures;
    private bool _isInitializing;
    private bool _preflightExpanded = true;

    public ObservableCollection<VirtualMachine> VirtualMachines { get; } = new();
    public ObservableCollection<HealthCheckItem> HealthChecks { get; } = new();

    public AsyncCommand RefreshCommand { get; }
    public AsyncCommand StartCommand { get; }
    public AsyncCommand StopCommand { get; }
    public AsyncCommand RestartCommand { get; }
    public AsyncCommand PauseCommand { get; }
    public AsyncCommand RemoveSelectedVMCommand { get; }
    public AsyncCommand BlowAwayCommand { get; }
    public AsyncCommand RecheckCommand { get; }
    public AsyncCommand InitializeCommand { get; }

    public VirtualMachine? SelectedVM
    {
        get => _selectedVM;
        set
        {
            _selectedVM = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CanStart));
            OnPropertyChanged(nameof(CanStop));
            OnPropertyChanged(nameof(CanRestart));
            OnPropertyChanged(nameof(CanPause));
            StartCommand.RaiseCanExecuteChanged();
            StopCommand.RaiseCanExecuteChanged();
            RestartCommand.RaiseCanExecuteChanged();
            PauseCommand.RaiseCanExecuteChanged();
            RemoveSelectedVMCommand?.RaiseCanExecuteChanged();
            BlowAwayCommand?.RaiseCanExecuteChanged();
        }
    }

    public bool CanStart => SelectedVM?.CanStart ?? false;
    public bool CanStop => SelectedVM?.CanStop ?? false;
    public bool CanRestart => SelectedVM?.CanRestart ?? false;
    public bool CanPause => SelectedVM?.CanPause ?? false;

    public int TotalVMs => VirtualMachines.Count;
    public int RunningVMs => VirtualMachines.Count(v => v.State == "Running");
    public int StoppedVMs => VirtualMachines.Count(v => v.State == "Off");
    public string TotalMemoryGB => $"{VirtualMachines.Sum(v => v.MemoryGB):F1} GB";
    public string TotalProcessors => $"{VirtualMachines.Sum(v => v.Processors)}";

    public bool HasFailures
    {
        get => _hasFailures;
        set { _hasFailures = value; OnPropertyChanged(); }
    }

    public bool IsInitializing
    {
        get => _isInitializing;
        set { _isInitializing = value; OnPropertyChanged(); InitializeCommand.RaiseCanExecuteChanged(); }
    }

    public bool PreflightExpanded
    {
        get => _preflightExpanded;
        set { _preflightExpanded = value; OnPropertyChanged(); }
    }

    public DashboardViewModel()
    {
        RefreshCommand = new AsyncCommand(RefreshAsync);
        StartCommand = new AsyncCommand(StartSelectedAsync, () => CanStart);
        StopCommand = new AsyncCommand(StopSelectedAsync, () => CanStop);
        RestartCommand = new AsyncCommand(RestartSelectedAsync, () => CanRestart);
        PauseCommand = new AsyncCommand(PauseSelectedAsync, () => CanPause);
        RemoveSelectedVMCommand = new AsyncCommand(RemoveSelectedVMAsync, () => SelectedVM != null);
        BlowAwayCommand = new AsyncCommand(BlowAwayAllAsync, () => TotalVMs > 0);
        RecheckCommand = new AsyncCommand(RunHealthChecksAsync);
        InitializeCommand = new AsyncCommand(InitializeEnvironmentAsync, () => HasFailures && !IsInitializing);
    }

    public async Task LoadAsync()
    {
        var vms = await _hvService.GetVirtualMachinesAsync();
        VirtualMachines.Clear();
        foreach (var vm in vms) VirtualMachines.Add(vm);
        OnPropertyChanged(nameof(TotalVMs)); OnPropertyChanged(nameof(RunningVMs));
        OnPropertyChanged(nameof(StoppedVMs)); OnPropertyChanged(nameof(TotalMemoryGB));
        OnPropertyChanged(nameof(TotalProcessors));
        RemoveSelectedVMCommand.RaiseCanExecuteChanged();
        BlowAwayCommand.RaiseCanExecuteChanged();

        await RunHealthChecksAsync();
    }

    public async Task RunHealthChecksAsync()
    {
        HealthChecks.Clear();

        var hyperV = new HealthCheckItem { Name = "Hyper-V Enabled" };
        var labSources = new HealthCheckItem { Name = "LabSources Directory" };
        var isoImages = new HealthCheckItem { Name = "ISO Images" };
        var alModule = new HealthCheckItem { Name = "AutomatedLab Module" };
        var pwsh = new HealthCheckItem { Name = "PowerShell 7" };

        HealthChecks.Add(hyperV);
        HealthChecks.Add(labSources);
        HealthChecks.Add(isoImages);
        HealthChecks.Add(alModule);
        HealthChecks.Add(pwsh);

        await Task.Run(() =>
        {
            // 1. Hyper-V Enabled
            try
            {
                var hvPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "vmms.exe");
                if (File.Exists(hvPath))
                    SetCheck(hyperV, true, "Enabled", Brushes.Green);
                else
                    SetCheck(hyperV, false, "Not enabled", Brushes.Red);
            }
            catch
            {
                SetCheck(hyperV, false, "Unable to detect", Brushes.Red);
            }

            // 2. LabSources Directory
            if (Directory.Exists(@"C:\LabSources"))
                SetCheck(labSources, true, @"C:\LabSources exists", Brushes.Green);
            else
                SetCheck(labSources, false, "Not found", Brushes.Red);

            // 3. ISO Images
            var isosDir = @"C:\LabSources\ISOs";
            if (Directory.Exists(isosDir) && Directory.GetFiles(isosDir, "*.iso").Length > 0)
            {
                var count = Directory.GetFiles(isosDir, "*.iso").Length;
                SetCheck(isoImages, true, $"{count} ISO(s) found", Brushes.Green);
            }
            else
            {
                SetCheck(isoImages, true, "No ISOs found", Brushes.Orange);
            }

            // 4. AutomatedLab Module
            var modulePaths = new[]
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "WindowsPowerShell", "Modules", "AutomatedLab"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "WindowsPowerShell", "Modules", "AutomatedLab"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "PowerShell", "Modules", "AutomatedLab")
            };
            if (modulePaths.Any(Directory.Exists))
                SetCheck(alModule, true, "Installed", Brushes.Green);
            else
                SetCheck(alModule, false, "Not installed", Brushes.Red);

            // 5. PowerShell 7
            var pwshPaths = new[]
            {
                @"C:\Program Files\PowerShell\7\pwsh.exe",
                Path.Combine(AppContext.BaseDirectory, "pwsh", "pwsh.exe")
            };
            if (pwshPaths.Any(File.Exists))
                SetCheck(pwsh, true, "Available", Brushes.Green);
            else
                SetCheck(pwsh, true, "Will use Windows PowerShell", Brushes.Orange);
        });

        HasFailures = HealthChecks.Any(h => !h.Passed && h.StatusColor == Brushes.Red);
        InitializeCommand.RaiseCanExecuteChanged();
    }

    private static void SetCheck(HealthCheckItem item, bool passed, string status, Brush color)
    {
        Application.Current.Dispatcher.Invoke(() =>
        {
            item.Passed = passed;
            item.Status = status;
            item.StatusColor = color;
        });
    }

    private async Task InitializeEnvironmentAsync()
    {
        IsInitializing = true;
        try
        {
            var bundledLabSources = Path.Combine(AppContext.BaseDirectory, "LabSources");
            var targetLabSources = @"C:\LabSources";

            var script = new StringBuilder();
            script.AppendLine("$ErrorActionPreference = 'Stop'");

            // Step 1: Copy LabSources to C:\LabSources
            if (Directory.Exists(bundledLabSources))
            {
                var safeSrc = bundledLabSources.Replace("'", "''");
                var safeDst = targetLabSources.Replace("'", "''");
                script.AppendLine($"Write-Host 'Copying LabSources to {targetLabSources}...'");
                script.AppendLine($"Copy-Item -Path '{safeSrc}\\*' -Destination '{safeDst}' -Recurse -Force");
                script.AppendLine("Write-Host 'LabSources copied successfully.'");
            }
            else
            {
                // If no bundled LabSources, just create the directory structure
                script.AppendLine($"Write-Host 'Creating LabSources directory structure...'");
                script.AppendLine($"New-Item -Path '{targetLabSources}' -ItemType Directory -Force | Out-Null");
                foreach (var sub in new[] { "ISOs", "VMs", "Logs", "OSUpdates", "LabConfig", "SSHKeys", "Modules" })
                    script.AppendLine($"New-Item -Path '{targetLabSources}\\{sub}' -ItemType Directory -Force | Out-Null");
                script.AppendLine("Write-Host 'Directory structure created.'");
            }

            // Step 2: Install AutomatedLab modules from bundled Modules folder
            var bundledModules = Path.Combine(bundledLabSources, "Modules");
            if (Directory.Exists(bundledModules))
            {
                var safeModSrc = bundledModules.Replace("'", "''");
                script.AppendLine("Write-Host 'Installing AutomatedLab modules...'");
                script.AppendLine($"$moduleSrc = '{safeModSrc}'");
                script.AppendLine("$moduleDst = Join-Path $env:ProgramFiles 'WindowsPowerShell\\Modules'");
                script.AppendLine("Get-ChildItem -Path $moduleSrc -Directory | ForEach-Object {");
                script.AppendLine("    $dest = Join-Path $moduleDst $_.Name");
                script.AppendLine("    Write-Host \"  Installing module: $($_.Name)\"");
                script.AppendLine("    Copy-Item -Path $_.FullName -Destination $dest -Recurse -Force");
                script.AppendLine("}");
                script.AppendLine("Write-Host 'Modules installed successfully.'");
            }
            else
            {
                // Try running Setup-AutomatedLab.ps1 from LabSources
                var setupScript = Path.Combine(targetLabSources, "Setup-AutomatedLab.ps1");
                if (File.Exists(setupScript))
                {
                    var safeSetup = setupScript.Replace("'", "''");
                    script.AppendLine("Write-Host 'Running Setup-AutomatedLab.ps1...'");
                    script.AppendLine($"& '{safeSetup}'");
                }
            }

            script.AppendLine("Write-Host 'Initialization complete.'");

            await _deploymentService.RunPowerShellInlineAsync(script.ToString(), null, CancellationToken.None);

            await RunHealthChecksAsync();

            Application.Current.Dispatcher.Invoke(() =>
            {
                MessageBox.Show("Environment initialized successfully!\n\nLabSources copied and modules installed.",
                    "Initialize Complete", MessageBoxButton.OK, MessageBoxImage.Information);
            });
        }
        catch (Exception ex)
        {
            Application.Current.Dispatcher.Invoke(() =>
            {
                MessageBox.Show($"Initialization failed:\n{ex.Message}",
                    "Initialize Error", MessageBoxButton.OK, MessageBoxImage.Error);
            });
        }
        finally
        {
            IsInitializing = false;
        }
    }

    private async Task RefreshAsync()
    {
        await LoadAsync();
        OnPropertyChanged(nameof(CanStart)); OnPropertyChanged(nameof(CanStop));
        OnPropertyChanged(nameof(CanRestart)); OnPropertyChanged(nameof(CanPause));
    }

    private async Task StartSelectedAsync()
    {
        if (SelectedVM == null) return;
        await _hvService.StartVMAsync(SelectedVM.Name);
        await RefreshAsync();
    }

    private async Task StopSelectedAsync()
    {
        if (SelectedVM == null) return;
        await _hvService.StopVMAsync(SelectedVM.Name);
        await RefreshAsync();
    }

    private async Task RestartSelectedAsync()
    {
        if (SelectedVM == null) return;
        await _hvService.RestartVMAsync(SelectedVM.Name);
        await RefreshAsync();
    }

    private async Task PauseSelectedAsync()
    {
        if (SelectedVM == null) return;
        await _hvService.PauseVMAsync(SelectedVM.Name);
        await RefreshAsync();
    }

    private async Task BlowAwayAllAsync()
    {
        if (VirtualMachines.Count == 0) return;

        MessageBoxResult result = MessageBoxResult.No;
        System.Windows.Application.Current.Dispatcher.Invoke(() =>
        {
            result = System.Windows.MessageBox.Show(
                $"This will permanently delete ALL {VirtualMachines.Count} VM(s) and their disk files.\n\nThis action CANNOT be undone!\n\nContinue?",
                "Confirm Destruction",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning,
                MessageBoxResult.No);
        });

        if (result != MessageBoxResult.Yes)
            return;

        foreach (var vm in VirtualMachines.ToList())
        {
            try
            {
                await _hvService.StopVMAsync(vm.Name);
                await _hvService.RemoveVMAsync(vm.Name, deleteDisk: true);
            }
            catch { }
        }
        await RefreshAsync();
    }

    private async Task RemoveSelectedVMAsync()
    {
        if (SelectedVM == null) return;

        var vmName = SelectedVM.Name;

        MessageBoxResult result = MessageBoxResult.No;
        System.Windows.Application.Current.Dispatcher.Invoke(() =>
        {
            result = System.Windows.MessageBox.Show(
                $"This will permanently delete VM '{vmName}' and its disk files.\n\nThis action CANNOT be undone!\n\nContinue?",
                "Confirm VM Removal",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning,
                MessageBoxResult.No);
        });

        if (result != MessageBoxResult.Yes)
            return;

        try
        {
            await _hvService.StopVMAsync(vmName);
            var removed = await _hvService.RemoveVMAsync(vmName, deleteDisk: true);
            if (!removed)
            {
                System.Windows.Application.Current.Dispatcher.Invoke(() =>
                {
                    System.Windows.MessageBox.Show(
                        $"Failed to remove VM '{vmName}'. Check Hyper-V permissions and logs.",
                        "VM Removal Failed",
                        MessageBoxButton.OK,
                        MessageBoxImage.Error);
                });
            }
        }
        catch (Exception ex)
        {
            System.Windows.Application.Current.Dispatcher.Invoke(() =>
            {
                System.Windows.MessageBox.Show(
                    $"Error removing VM '{vmName}': {ex.Message}",
                    "VM Removal Error",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);
            });
        }

        await RefreshAsync();
    }
}

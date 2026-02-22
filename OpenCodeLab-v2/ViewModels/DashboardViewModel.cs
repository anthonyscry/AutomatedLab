using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using OpenCodeLab.Models;
using OpenCodeLab.Services;

namespace OpenCodeLab.ViewModels;

public class DashboardViewModel : ObservableObject
{
    private readonly HyperVService _hvService = new();
    private readonly LabDeploymentService _deploymentService = new();
    private VirtualMachine? _selectedVM;

    public ObservableCollection<VirtualMachine> VirtualMachines { get; } = new();
    public AsyncCommand RefreshCommand { get; }
    public AsyncCommand StartCommand { get; }
    public AsyncCommand StopCommand { get; }
    public AsyncCommand RestartCommand { get; }
    public AsyncCommand PauseCommand { get; }
    public AsyncCommand BlowAwayCommand { get; }

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
            // Notify commands to re-evaluate CanExecute
            StartCommand.RaiseCanExecuteChanged();
            StopCommand.RaiseCanExecuteChanged();
            RestartCommand.RaiseCanExecuteChanged();
            PauseCommand.RaiseCanExecuteChanged();
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

    public DashboardViewModel()
    {
        RefreshCommand = new AsyncCommand(RefreshAsync);
        StartCommand = new AsyncCommand(StartSelectedAsync, () => CanStart);
        StopCommand = new AsyncCommand(StopSelectedAsync, () => CanStop);
        RestartCommand = new AsyncCommand(RestartSelectedAsync, () => CanRestart);
        PauseCommand = new AsyncCommand(PauseSelectedAsync, () => CanPause);
        BlowAwayCommand = new AsyncCommand(BlowAwayAllAsync, () => TotalVMs > 0);
    }

    public async Task LoadAsync()
    {
        var vms = await _hvService.GetVirtualMachinesAsync();
        VirtualMachines.Clear();
        foreach (var vm in vms) VirtualMachines.Add(vm);
        OnPropertyChanged(nameof(TotalVMs)); OnPropertyChanged(nameof(RunningVMs));
        OnPropertyChanged(nameof(StoppedVMs)); OnPropertyChanged(nameof(TotalMemoryGB));
        OnPropertyChanged(nameof(TotalProcessors));
        // Update BlowAway command state
        BlowAwayCommand.RaiseCanExecuteChanged();
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

        // Show confirmation dialog on UI thread
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

        // Stop all VMs and delete them along with their disks
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
}

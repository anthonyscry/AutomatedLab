using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using OpenCodeLab.Models;
using OpenCodeLab.Services;

namespace OpenCodeLab.ViewModels;

public class CheckpointsViewModel : ObservableObject
{
    private readonly CheckpointService _checkpointService = new();
    private string _labName = string.Empty;
    private string _checkpointName = string.Empty;
    private ChangeCheckpoint? _selectedCheckpoint;

    public ObservableCollection<ChangeCheckpoint> Checkpoints { get; } = new();

    public AsyncCommand CreateCheckpointCommand { get; }
    public AsyncCommand RefreshCommand { get; }
    public AsyncCommand RollbackCommand { get; }
    public AsyncCommand CompareCommand { get; }
    public AsyncCommand DeleteCommand { get; }

    public string LabName
    {
        get => _labName;
        set { _labName = value; OnPropertyChanged(); CreateCheckpointCommand.RaiseCanExecuteChanged(); RefreshCommand.RaiseCanExecuteChanged(); }
    }

    public string CheckpointName
    {
        get => _checkpointName;
        set { _checkpointName = value; OnPropertyChanged(); CreateCheckpointCommand.RaiseCanExecuteChanged(); }
    }

    public ChangeCheckpoint? SelectedCheckpoint
    {
        get => _selectedCheckpoint;
        set { _selectedCheckpoint = value; OnPropertyChanged(); RollbackCommand.RaiseCanExecuteChanged(); DeleteCommand.RaiseCanExecuteChanged(); CompareCommand.RaiseCanExecuteChanged(); }
    }

    public CheckpointsViewModel()
    {
        CreateCheckpointCommand = new AsyncCommand(CreateCheckpointAsync, () => !string.IsNullOrWhiteSpace(LabName) && !string.IsNullOrWhiteSpace(CheckpointName));
        RefreshCommand = new AsyncCommand(RefreshAsync, () => !string.IsNullOrWhiteSpace(LabName));
        RollbackCommand = new AsyncCommand(RollbackAsync, () => SelectedCheckpoint != null);
        CompareCommand = new AsyncCommand(CompareAsync, () => SelectedCheckpoint != null);
        DeleteCommand = new AsyncCommand(DeleteAsync, () => SelectedCheckpoint != null);
    }

    public async Task LoadAsync(string? labName = null)
    {
        if (labName != null) LabName = labName;
        await RefreshAsync();
    }

    private async Task CreateCheckpointAsync()
    {
        try
        {
            var result = await _checkpointService.CreateCheckpointAsync(LabName, CheckpointName);
            if (result.Status == CheckpointStatus.Failed)
                MessageBox.Show($"Checkpoint creation had failures. Check details.", "Warning", MessageBoxButton.OK, MessageBoxImage.Warning);
            else
                MessageBox.Show($"Checkpoint '{CheckpointName}' created successfully with {result.Snapshots.Count} VM snapshot(s).", "Success", MessageBoxButton.OK, MessageBoxImage.Information);

            CheckpointName = string.Empty;
            await RefreshAsync();
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Failed to create checkpoint: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async Task RefreshAsync()
    {
        if (string.IsNullOrWhiteSpace(LabName)) return;
        try
        {
            var list = await _checkpointService.GetCheckpointsAsync(LabName);
            Checkpoints.Clear();
            foreach (var cp in list)
                Checkpoints.Add(cp);
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Failed to load checkpoints: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async Task RollbackAsync()
    {
        if (SelectedCheckpoint == null) return;
        var result = MessageBox.Show(
            $"Rollback all VMs to checkpoint '{SelectedCheckpoint.Name}'?\n\nThis will restore {SelectedCheckpoint.Snapshots.Count} VM(s) to their state at {SelectedCheckpoint.CreatedAt:g}.",
            "Confirm Rollback", MessageBoxButton.YesNo, MessageBoxImage.Warning);
        if (result != MessageBoxResult.Yes) return;

        try
        {
            var success = await _checkpointService.RollbackCheckpointAsync(LabName, SelectedCheckpoint.Id);
            MessageBox.Show(success ? "Rollback completed successfully." : "Rollback completed with some failures.", success ? "Success" : "Warning", MessageBoxButton.OK, success ? MessageBoxImage.Information : MessageBoxImage.Warning);
            await RefreshAsync();
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Rollback failed: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async Task CompareAsync()
    {
        if (SelectedCheckpoint == null) return;
        try
        {
            var checkpoints = await _checkpointService.GetCheckpointsAsync(LabName);
            if (checkpoints.Count < 2)
            {
                MessageBox.Show("Need at least 2 checkpoints to compare.", "Info", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }
            // Compare selected with the next older checkpoint
            var idx = checkpoints.FindIndex(c => c.Id == SelectedCheckpoint.Id);
            var compareWith = idx < checkpoints.Count - 1 ? checkpoints[idx + 1] : checkpoints[0];
            var diffs = await _checkpointService.CompareCheckpointsAsync(LabName, SelectedCheckpoint.Id, compareWith.Id);
            var diffText = diffs.Count > 0 ? string.Join("\n", diffs) : "No differences found.";
            MessageBox.Show($"Comparing '{SelectedCheckpoint.Name}' vs '{compareWith.Name}':\n\n{diffText}", "Checkpoint Comparison", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Compare failed: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private async Task DeleteAsync()
    {
        if (SelectedCheckpoint == null) return;
        var result = MessageBox.Show($"Delete checkpoint '{SelectedCheckpoint.Name}'?", "Confirm Delete", MessageBoxButton.YesNo, MessageBoxImage.Question);
        if (result != MessageBoxResult.Yes) return;
        try
        {
            await _checkpointService.DeleteCheckpointAsync(LabName, SelectedCheckpoint.Id);
            await RefreshAsync();
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Delete failed: {ex.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
}

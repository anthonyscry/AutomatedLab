using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using OpenCodeLab.Services;

namespace OpenCodeLab.ViewModels
{
    /// <summary>
    /// ViewModel for the Scheduled Tasks view
    /// </summary>
    public class SchedulerViewModel : ObservableObject
    {
        private readonly ScheduledTaskService _taskService = new();
        
        private string _labName = string.Empty;
        private bool _isLoading;
        private string _statusMessage = "Ready";
        private ScheduledTask? _selectedTask;
        
        // New task fields
        private string _newTaskName = string.Empty;
        private string _newTaskType = "DriftCheck";
        private string _newCronExpression = "0 * * * *";
        private bool _newTaskEnabled = true;

        public ObservableCollection<ScheduledTask> Tasks { get; } = new();
        public ObservableCollection<ScheduledTaskResult> History { get; } = new();

        public AsyncCommand LoadCommand { get; }
        public AsyncCommand AddTaskCommand { get; }
        public AsyncCommand DeleteTaskCommand { get; }
        public AsyncCommand RunNowCommand { get; }
        public AsyncCommand RefreshCommand { get; }

        public string LabName
        {
            get => _labName;
            set { _labName = value; OnPropertyChanged(); }
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

        public ScheduledTask? SelectedTask
        {
            get => _selectedTask;
            set { _selectedTask = value; OnPropertyChanged(); OnPropertyChanged(nameof(HasSelectedTask)); }
        }

        public bool HasSelectedTask => SelectedTask != null;

        public string NewTaskName
        {
            get => _newTaskName;
            set { _newTaskName = value; OnPropertyChanged(); }
        }

        public string NewTaskType
        {
            get => _newTaskType;
            set { _newTaskType = value; OnPropertyChanged(); }
        }

        public string NewCronExpression
        {
            get => _newCronExpression;
            set { _newCronExpression = value; OnPropertyChanged(); }
        }

        public bool NewTaskEnabled
        {
            get => _newTaskEnabled;
            set { _newTaskEnabled = value; OnPropertyChanged(); }
        }

        public string[] TaskTypes { get; } = new[] { "DriftCheck", "HealthCheck", "BaselineCapture", "Backup" };

        public SchedulerViewModel()
        {
            LoadCommand = new AsyncCommand(LoadAsync, () => !IsLoading);
            AddTaskCommand = new AsyncCommand(AddTaskAsync, () => !IsLoading && !string.IsNullOrWhiteSpace(NewTaskName));
            DeleteTaskCommand = new AsyncCommand(DeleteTaskAsync, () => !IsLoading && HasSelectedTask);
            RunNowCommand = new AsyncCommand(RunNowAsync, () => !IsLoading && HasSelectedTask);
            RefreshCommand = new AsyncCommand(LoadAsync, () => !IsLoading);
        }

        public async Task LoadAsync()
        {
            IsLoading = true;
            StatusMessage = "Loading scheduled tasks...";

            try
            {
                var tasks = await _taskService.LoadTasksAsync();
                Tasks.Clear();
                foreach (var task in tasks.OrderByDescending(t => t.CreatedAt))
                    Tasks.Add(task);

                var history = await _taskService.GetHistoryAsync(null, 20);
                History.Clear();
                foreach (var result in history)
                    History.Add(result);

                StatusMessage = $"Loaded {Tasks.Count} task(s)";
            }
            catch (Exception ex)
            {
                StatusMessage = $"Error loading tasks: {ex.Message}";
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task AddTaskAsync()
        {
            if (string.IsNullOrWhiteSpace(NewTaskName))
                return;

            IsLoading = true;
            StatusMessage = "Creating task...";

            try
            {
                var task = new ScheduledTask
                {
                    Name = NewTaskName,
                    TaskType = NewTaskType,
                    LabName = LabName,
                    CronExpression = NewCronExpression,
                    IsEnabled = NewTaskEnabled
                };

                await _taskService.UpsertTaskAsync(task);
                Tasks.Insert(0, task);

                NewTaskName = string.Empty;
                StatusMessage = $"Created task: {task.Name}";
            }
            catch (Exception ex)
            {
                StatusMessage = $"Error creating task: {ex.Message}";
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task DeleteTaskAsync()
        {
            if (SelectedTask == null) return;

            IsLoading = true;
            StatusMessage = "Deleting task...";

            try
            {
                await _taskService.DeleteTaskAsync(SelectedTask.Id);
                Tasks.Remove(SelectedTask);
                SelectedTask = null;
                StatusMessage = "Task deleted";
            }
            catch (Exception ex)
            {
                StatusMessage = $"Error deleting task: {ex.Message}";
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task RunNowAsync()
        {
            if (SelectedTask == null) return;

            IsLoading = true;
            StatusMessage = "Running task...";

            try
            {
                var result = await _taskService.RunTaskNowAsync(SelectedTask.Id);
                History.Insert(0, result);
                StatusMessage = $"Task completed: {result.Message}";
            }
            catch (Exception ex)
            {
                StatusMessage = $"Error running task: {ex.Message}";
            }
            finally
            {
                IsLoading = false;
            }
        }

        private void RefreshCommands()
        {
            LoadCommand.RaiseCanExecuteChanged();
            AddTaskCommand.RaiseCanExecuteChanged();
            DeleteTaskCommand.RaiseCanExecuteChanged();
            RunNowCommand.RaiseCanExecuteChanged();
            RefreshCommand.RaiseCanExecuteChanged();
        }
    }
}

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace OpenCodeLab.Services;

/// <summary>
/// Scheduled task definition for automated operations
/// </summary>
public class ScheduledTask
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Name { get; set; } = string.Empty;
    public string TaskType { get; set; } = string.Empty; // DriftCheck, HealthCheck, Backup
    public string LabName { get; set; } = string.Empty;
    public string CronExpression { get; set; } = string.Empty;
    public bool IsEnabled { get; set; } = true;
    public DateTime LastRun { get; set; } = DateTime.MinValue;
    public DateTime? NextRun { get; set; }
    public string? LastResult { get; set; }
    public bool LastRunSuccess { get; set; }
    public Dictionary<string, string> Parameters { get; set; } = new();
    public List<string> NotificationEmails { get; set; } = new();
    public string? WebhookUrl { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// Result of a scheduled task execution
/// </summary>
public class ScheduledTaskResult
{
    public string TaskId { get; set; } = string.Empty;
    public DateTime ExecutedAt { get; set; } = DateTime.UtcNow;
    public bool Success { get; set; }
    public string Message { get; set; } = string.Empty;
    public string? Details { get; set; }
    public TimeSpan Duration { get; set; }
    public bool NotificationSent { get; set; }
}

/// <summary>
/// Simple cron expression parser for scheduling
/// </summary>
public class SimpleCron
{
    public int Minute { get; set; } = -1; // -1 = every
    public int Hour { get; set; } = -1;
    public int DayOfMonth { get; set; } = -1;
    public int Month { get; set; } = -1;
    public int DayOfWeek { get; set; } = -1;
    public int IntervalMinutes { get; set; } = 0;

    public static SimpleCron Parse(string expression)
    {
        var parts = expression.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var cron = new SimpleCron();

        if (parts.Length >= 1 && parts[0] != "*")
        {
            if (parts[0].StartsWith("*/"))
                cron.IntervalMinutes = int.Parse(parts[0][2..]);
            else
                cron.Minute = int.Parse(parts[0]);
        }

        if (parts.Length >= 2 && parts[1] != "*")
            cron.Hour = int.Parse(parts[1]);

        if (parts.Length >= 3 && parts[2] != "*")
            cron.DayOfMonth = int.Parse(parts[2]);

        if (parts.Length >= 4 && parts[3] != "*")
            cron.Month = int.Parse(parts[3]);

        if (parts.Length >= 5 && parts[4] != "*")
            cron.DayOfWeek = int.Parse(parts[4]);

        return cron;
    }

    public DateTime? GetNextRun(DateTime from)
    {
        // Handle interval-based scheduling (e.g., every 30 minutes)
        if (IntervalMinutes > 0)
        {
            var next = from.AddMinutes(IntervalMinutes);
            return new DateTime(next.Year, next.Month, next.Day, next.Hour, next.Minute, 0);
        }

        // Simple daily/hourly scheduling
        var candidate = from.AddMinutes(1);
        
        // Find next matching time
        for (int i = 0; i < 10080; i++) // Check up to a week
        {
            if (Matches(candidate))
                return candidate;
            candidate = candidate.AddMinutes(1);
        }

        return null;
    }

    private bool Matches(DateTime dt)
    {
        if (Minute >= 0 && dt.Minute != Minute) return false;
        if (Hour >= 0 && dt.Hour != Hour) return false;
        if (DayOfMonth >= 0 && dt.Day != DayOfMonth) return false;
        if (Month >= 0 && dt.Month != Month) return false;
        if (DayOfWeek >= 0 && (int)dt.DayOfWeek != DayOfWeek) return false;
        return true;
    }
}

/// <summary>
/// Service for managing scheduled tasks (drift detection, health checks, etc.)
/// </summary>
public class ScheduledTaskService
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private const string TasksFilePath = @"C:\LabSources\LabConfig\_system\scheduled-tasks.json";
    private const string ResultsFilePath = @"C:\LabSources\LabConfig\_system\task-results.json";
    
    private List<ScheduledTask> _tasks = new();
    private List<ScheduledTaskResult> _results = new();
    private CancellationTokenSource? _schedulerCts;
    private bool _isRunning;

    public event EventHandler<ScheduledTaskResult>? TaskExecuted;

    /// <summary>
    /// Load all scheduled tasks
    /// </summary>
    public async Task<List<ScheduledTask>> LoadTasksAsync()
    {
        if (!File.Exists(TasksFilePath))
            return _tasks;

        var json = await File.ReadAllTextAsync(TasksFilePath);
        _tasks = JsonSerializer.Deserialize<List<ScheduledTask>>(json) ?? new();
        
        // Calculate next run times
        foreach (var task in _tasks)
        {
            if (task.IsEnabled)
                task.NextRun = SimpleCron.Parse(task.CronExpression).GetNextRun(DateTime.UtcNow);
        }

        return _tasks;
    }

    /// <summary>
    /// Save all scheduled tasks
    /// </summary>
    public async Task SaveTasksAsync()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(TasksFilePath)!);
        var json = JsonSerializer.Serialize(_tasks, JsonOptions);
        await File.WriteAllTextAsync(TasksFilePath, json);
    }

    /// <summary>
    /// Add or update a scheduled task
    /// </summary>
    public async Task<ScheduledTask> UpsertTaskAsync(ScheduledTask task)
    {
        var existing = _tasks.FirstOrDefault(t => t.Id == task.Id);
        if (existing != null)
        {
            _tasks.Remove(existing);
        }

        // Calculate next run
        task.NextRun = SimpleCron.Parse(task.CronExpression).GetNextRun(DateTime.UtcNow);
        _tasks.Add(task);
        await SaveTasksAsync();

        return task;
    }

    /// <summary>
    /// Delete a scheduled task
    /// </summary>
    public async Task<bool> DeleteTaskAsync(string taskId)
    {
        var task = _tasks.FirstOrDefault(t => t.Id == taskId);
        if (task == null) return false;

        _tasks.Remove(task);
        await SaveTasksAsync();
        return true;
    }

    /// <summary>
    /// Start the scheduler
    /// </summary>
    public void Start()
    {
        if (_isRunning) return;

        _isRunning = true;
        _schedulerCts = new CancellationTokenSource();
        _ = RunSchedulerLoop(_schedulerCts.Token);
    }

    /// <summary>
    /// Stop the scheduler
    /// </summary>
    public void Stop()
    {
        _isRunning = false;
        _schedulerCts?.Cancel();
    }

    /// <summary>
    /// Run a task immediately
    /// </summary>
    public async Task<ScheduledTaskResult> RunTaskNowAsync(string taskId)
    {
        var task = _tasks.FirstOrDefault(t => t.Id == taskId);
        if (task == null)
        {
            return new ScheduledTaskResult
            {
                TaskId = taskId,
                Success = false,
                Message = "Task not found"
            };
        }

        return await ExecuteTaskAsync(task);
    }

    /// <summary>
    /// Get task execution history
    /// </summary>
    public async Task<List<ScheduledTaskResult>> GetHistoryAsync(string? taskId = null, int count = 50)
    {
        if (_results.Count == 0 && File.Exists(ResultsFilePath))
        {
            var json = await File.ReadAllTextAsync(ResultsFilePath);
            _results = JsonSerializer.Deserialize<List<ScheduledTaskResult>>(json) ?? new();
        }

        var query = _results.AsEnumerable();
        if (!string.IsNullOrEmpty(taskId))
            query = query.Where(r => r.TaskId == taskId);

        return query
            .OrderByDescending(r => r.ExecutedAt)
            .Take(count)
            .ToList();
    }

    private async Task RunSchedulerLoop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested && _isRunning)
        {
            try
            {
                await CheckAndExecuteTasksAsync(ct);
                await Task.Delay(60000, ct); // Check every minute
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception)
            {
                // Log error and continue
                await Task.Delay(5000, ct);
            }
        }
    }

    private async Task CheckAndExecuteTasksAsync(CancellationToken ct)
    {
        var now = DateTime.UtcNow;

        foreach (var task in _tasks.Where(t => t.IsEnabled && t.NextRun <= now))
        {
            if (ct.IsCancellationRequested) break;

            var result = await ExecuteTaskAsync(task);
            TaskExecuted?.Invoke(this, result);

            // Update task with result and next run
            task.LastRun = now;
            task.LastResult = result.Message;
            task.LastRunSuccess = result.Success;
            task.NextRun = SimpleCron.Parse(task.CronExpression).GetNextRun(now);

            // Save updated task
            await SaveTasksAsync();
        }
    }

    private async Task<ScheduledTaskResult> ExecuteTaskAsync(ScheduledTask task)
    {
        var startTime = DateTime.UtcNow;
        var result = new ScheduledTaskResult { TaskId = task.Id };

        try
        {
            switch (task.TaskType.ToLowerInvariant())
            {
                case "driftcheck":
                    result = await ExecuteDriftCheckAsync(task);
                    break;
                case "healthcheck":
                    result = await ExecuteHealthCheckAsync(task);
                    break;
                case "baselinecapture":
                    result = await ExecuteBaselineCaptureAsync(task);
                    break;
                case "backup":
                    result = await ExecuteBackupAsync(task);
                    break;
                default:
                    result.Success = false;
                    result.Message = $"Unknown task type: {task.TaskType}";
                    break;
            }
        }
        catch (Exception ex)
        {
            result.Success = false;
            result.Message = $"Task execution failed: {ex.Message}";
            result.Details = ex.StackTrace;
        }

        result.Duration = DateTime.UtcNow - startTime;

        // Send notifications if configured
        if (!string.IsNullOrEmpty(task.WebhookUrl) || task.NotificationEmails.Count > 0)
        {
            result.NotificationSent = await SendNotificationAsync(task, result);
        }

        // Store result
        _results.Insert(0, result);
        if (_results.Count > 1000)
            _results = _results.Take(1000).ToList();

        await SaveResultsAsync();

        return result;
    }

    private async Task<ScheduledTaskResult> ExecuteDriftCheckAsync(ScheduledTask task)
    {
        var driftService = new ExtendedDriftDetectionService();
        var labName = task.Parameters.GetValueOrDefault("LabName", task.LabName);
        var baselineId = task.Parameters.GetValueOrDefault("BaselineId", "");

        if (string.IsNullOrEmpty(baselineId))
        {
            // Get the golden baseline or latest
            var baselines = await driftService.ListBaselinesAsync(labName);
            var golden = baselines.FirstOrDefault(b => b.IsGoldenBaseline) ?? baselines.FirstOrDefault();
            baselineId = golden?.Id ?? "";
        }

        if (string.IsNullOrEmpty(baselineId))
        {
            return new ScheduledTaskResult
            {
                TaskId = task.Id,
                Success = false,
                Message = "No baseline found for drift check"
            };
        }

        var report = await driftService.DetectExtendedDriftAsync(labName, baselineId, null, CancellationToken.None);

        return new ScheduledTaskResult
        {
            TaskId = task.Id,
            Success = report.OverallStatus != DriftStatus.Critical,
            Message = $"Drift check: {report.TotalDriftCount} item(s) found, Status: {report.OverallStatus}",
            Details = $"VmGuestDrift: {report.VmGuestDrift.Count}, HostDrift: {report.HostDrift.Count}"
        };
    }

    private async Task<ScheduledTaskResult> ExecuteHealthCheckAsync(ScheduledTask task)
    {
        var healthService = new HealthMonitoringService();
        var labName = task.Parameters.GetValueOrDefault("LabName", task.LabName);

        var report = await healthService.RunHealthCheckAsync(labName, null, CancellationToken.None);

        return new ScheduledTaskResult
        {
            TaskId = task.Id,
            Success = report.OverallStatus != HealthStatus.Critical,
            Message = $"Health check: {report.OverallStatus}, Checks: {report.Checks.Count}",
            Details = $"Healthy: {report.HealthyCount}, Warning: {report.WarningCount}, Critical: {report.CriticalCount}"
        };
    }

    private async Task<ScheduledTaskResult> ExecuteBaselineCaptureAsync(ScheduledTask task)
    {
        var driftService = new ExtendedDriftDetectionService();
        var labName = task.Parameters.GetValueOrDefault("LabName", task.LabName);
        var description = task.Parameters.GetValueOrDefault("Description", "Scheduled baseline capture");

        var baseline = await driftService.CaptureExtendedBaselineAsync(labName, description, null, CancellationToken.None);

        return new ScheduledTaskResult
        {
            TaskId = task.Id,
            Success = true,
            Message = $"Baseline captured: {baseline.Id}",
            Details = $"VMs: {baseline.VmCount}, Created: {baseline.CreatedAt}"
        };
    }

    private async Task<ScheduledTaskResult> ExecuteBackupAsync(ScheduledTask task)
    {
        var labName = task.Parameters.GetValueOrDefault("LabName", task.LabName);
        var backupPath = task.Parameters.GetValueOrDefault("BackupPath", @"C:\LabSources\Backups");

        var timestamp = DateTime.UtcNow.ToString("yyyyMMdd-HHmmss");
        var destPath = Path.Combine(backupPath, labName, timestamp);

        Directory.CreateDirectory(destPath);

        var sourcePath = Path.Combine(@"C:\LabSources\LabConfig", labName);
        if (Directory.Exists(sourcePath))
        {
            foreach (var file in Directory.GetFiles(sourcePath, "*", SearchOption.AllDirectories))
            {
                var relativePath = file[(sourcePath.Length + 1)..];
                var destFile = Path.Combine(destPath, relativePath);
                Directory.CreateDirectory(Path.GetDirectoryName(destFile)!);
                File.Copy(file, destFile, true);
            }
        }

        var filesCopied = Directory.GetFiles(destPath, "*", SearchOption.AllDirectories).Length;

        return new ScheduledTaskResult
        {
            TaskId = task.Id,
            Success = true,
            Message = $"Backup created: {filesCopied} files",
            Details = $"Path: {destPath}"
        };
    }

    private async Task<bool> SendNotificationAsync(ScheduledTask task, ScheduledTaskResult result)
    {
        try
        {
            // Webhook notification
            if (!string.IsNullOrEmpty(task.WebhookUrl))
            {
                using var client = new System.Net.Http.HttpClient();
                var payload = new
                {
                    task_name = task.Name,
                    task_type = task.TaskType,
                    lab_name = task.LabName,
                    success = result.Success,
                    message = result.Message,
                    executed_at = result.ExecutedAt,
                    duration_seconds = result.Duration.TotalSeconds
                };

                var json = JsonSerializer.Serialize(payload);
                var content = new System.Net.Http.StringContent(json, System.Text.Encoding.UTF8, "application/json");
                await client.PostAsync(task.WebhookUrl, content);
            }

            // Email notification would go here (requires SMTP configuration)
            // For now, just log it
            if (task.NotificationEmails.Count > 0)
            {
                // TODO: Implement email notification
            }

            return true;
        }
        catch
        {
            return false;
        }
    }

    private async Task SaveResultsAsync()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(ResultsFilePath)!);
        var json = JsonSerializer.Serialize(_results.Take(500).ToList(), JsonOptions);
        await File.WriteAllTextAsync(ResultsFilePath, json);
    }
}

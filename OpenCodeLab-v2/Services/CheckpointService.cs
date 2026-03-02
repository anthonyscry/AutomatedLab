using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using OpenCodeLab.Models;

namespace OpenCodeLab.Services;

public class CheckpointService
{
    private const string CheckpointsDir = "checkpoints";

    public async Task<ChangeCheckpoint> CreateCheckpointAsync(string labName, string checkpointName, string? description = null, Action<string>? log = null, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(labName))
            throw new ArgumentException("Lab name is required.", nameof(labName));
        if (string.IsNullOrWhiteSpace(checkpointName))
            throw new ArgumentException("Checkpoint name is required.", nameof(checkpointName));

        var checkpoint = new ChangeCheckpoint
        {
            Name = checkpointName,
            Description = description,
            LabName = labName,
            CreatedAt = DateTime.UtcNow,
            Status = CheckpointStatus.Active
        };

        try
        {
            ct.ThrowIfCancellationRequested();
            var safeLabName = EscapeSingleQuote(labName);
            var vmListScript = $"Get-VM | Where-Object {{ $_.Name -like '{safeLabName}*' }} | Select-Object -ExpandProperty Name";
            var vmListOutput = await RunPowerShellAsync(vmListScript, ct);
            var vmNames = vmListOutput
                .Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                .Select(v => v.Trim())
                .Where(v => !string.IsNullOrWhiteSpace(v))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();

            if (vmNames.Count == 0)
            {
                checkpoint.Status = CheckpointStatus.Failed;
                checkpoint.Metadata["Error"] = "No VMs found for lab prefix.";
                log?.Invoke($"No VMs found matching lab prefix '{labName}'.");
                await SaveCheckpointAsync(checkpoint, ct);
                return checkpoint;
            }

            var stateCaptureScriptPath = FindVmStateCaptureScript();
            foreach (var vmName in vmNames)
            {
                ct.ThrowIfCancellationRequested();
                var snapshot = new VMSnapshot
                {
                    VMName = vmName,
                    SnapshotName = checkpointName,
                    CreatedAt = DateTime.UtcNow
                };

                try
                {
                    var safeVmName = EscapeSingleQuote(vmName);
                    var safeCheckpointName = EscapeSingleQuote(checkpointName);
                    var script = $"try {{ Checkpoint-VM -Name '{safeVmName}' -SnapshotName '{safeCheckpointName}' -ErrorAction Stop | Out-Null; Write-Output 'OK' }} catch {{ Write-Output ('ERROR: ' + $_.Exception.Message) }}";
                    var output = await RunPowerShellAsync(script, ct);
                    var trimmed = (output ?? string.Empty).Trim();

                    if (trimmed.StartsWith("ERROR:", StringComparison.OrdinalIgnoreCase))
                    {
                        snapshot.Success = false;
                        snapshot.ErrorMessage = trimmed;
                        checkpoint.Status = CheckpointStatus.Failed;
                        log?.Invoke($"Checkpoint failed for VM '{vmName}': {trimmed}");
                    }
                    else
                    {
                        snapshot.Success = true;
                        log?.Invoke($"Checkpoint created for VM '{vmName}'.");
                    }

                    if (!string.IsNullOrWhiteSpace(stateCaptureScriptPath))
                    {
                        var safeScriptPath = EscapeSingleQuote(stateCaptureScriptPath);
                        var captureScript = $"if (Test-Path '{safeScriptPath}') {{ & '{safeScriptPath}' -VMName '{safeVmName}' }}";
                        var stateOutput = await RunPowerShellAsync(captureScript, ct);
                        if (!string.IsNullOrWhiteSpace(stateOutput))
                            snapshot.StateJson = stateOutput.Trim();
                    }
                }
                catch (Exception ex)
                {
                    snapshot.Success = false;
                    snapshot.ErrorMessage = ex.Message;
                    checkpoint.Status = CheckpointStatus.Failed;
                    log?.Invoke($"Checkpoint failed for VM '{vmName}': {ex.Message}");
                }

                checkpoint.Snapshots.Add(snapshot);
            }

            checkpoint.Metadata["VMCount"] = checkpoint.Snapshots.Count.ToString();
            checkpoint.Metadata["SuccessfulCount"] = checkpoint.Snapshots.Count(s => s.Success).ToString();
            checkpoint.Metadata["FailedCount"] = checkpoint.Snapshots.Count(s => !s.Success).ToString();

            await SaveCheckpointAsync(checkpoint, ct);
            return checkpoint;
        }
        catch (OperationCanceledException)
        {
            log?.Invoke("Checkpoint creation cancelled.");
            throw;
        }
        catch (Exception ex)
        {
            checkpoint.Status = CheckpointStatus.Failed;
            checkpoint.Metadata["Error"] = ex.Message;
            log?.Invoke($"Checkpoint creation failed: {ex.Message}");
            await SaveCheckpointAsync(checkpoint, ct);
            return checkpoint;
        }
    }

    public async Task<List<ChangeCheckpoint>> GetCheckpointsAsync(string labName, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(labName))
            throw new ArgumentException("Lab name is required.", nameof(labName));

        var dir = GetCheckpointDir(labName);
        if (!Directory.Exists(dir))
            return new List<ChangeCheckpoint>();

        var checkpoints = new List<ChangeCheckpoint>();
        foreach (var file in Directory.GetFiles(dir, "*.json"))
        {
            ct.ThrowIfCancellationRequested();
            var json = await File.ReadAllTextAsync(file, ct);
            var checkpoint = JsonSerializer.Deserialize<ChangeCheckpoint>(json);
            if (checkpoint != null)
                checkpoints.Add(checkpoint);
        }

        return checkpoints
            .OrderByDescending(c => c.CreatedAt)
            .ToList();
    }

    public async Task<bool> RollbackCheckpointAsync(string labName, string checkpointId, Action<string>? log = null, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(labName))
            throw new ArgumentException("Lab name is required.", nameof(labName));
        if (string.IsNullOrWhiteSpace(checkpointId))
            throw new ArgumentException("Checkpoint id is required.", nameof(checkpointId));

        try
        {
            var checkpoint = await LoadCheckpointAsync(labName, checkpointId, ct);
            if (checkpoint == null)
            {
                log?.Invoke($"Checkpoint '{checkpointId}' not found.");
                return false;
            }

            var allSucceeded = true;
            foreach (var snapshot in checkpoint.Snapshots)
            {
                ct.ThrowIfCancellationRequested();
                var safeVmName = EscapeSingleQuote(snapshot.VMName);
                var safeSnapshotName = EscapeSingleQuote(snapshot.SnapshotName);
                var script = $"try {{ Restore-VMCheckpoint -VMName '{safeVmName}' -Name '{safeSnapshotName}' -Confirm:$false -ErrorAction Stop | Out-Null; Write-Output 'OK' }} catch {{ Write-Output ('ERROR: ' + $_.Exception.Message) }}";
                var output = await RunPowerShellAsync(script, ct);
                var trimmed = (output ?? string.Empty).Trim();
                if (trimmed.StartsWith("ERROR:", StringComparison.OrdinalIgnoreCase))
                {
                    allSucceeded = false;
                    log?.Invoke($"Rollback failed for VM '{snapshot.VMName}': {trimmed}");
                }
                else
                {
                    log?.Invoke($"Rolled back VM '{snapshot.VMName}' to '{snapshot.SnapshotName}'.");
                }
            }

            if (!allSucceeded)
                return false;

            var allCheckpoints = await GetCheckpointsAsync(labName, ct);
            foreach (var cp in allCheckpoints)
            {
                if (string.Equals(cp.Id, checkpoint.Id, StringComparison.OrdinalIgnoreCase))
                {
                    cp.Status = CheckpointStatus.Active;
                }
                else if (cp.CreatedAt > checkpoint.CreatedAt)
                {
                    cp.Status = CheckpointStatus.Superseded;
                }

                await SaveCheckpointAsync(cp, ct);
            }

            return true;
        }
        catch (OperationCanceledException)
        {
            log?.Invoke("Rollback cancelled.");
            throw;
        }
        catch (Exception ex)
        {
            log?.Invoke($"Rollback failed: {ex.Message}");
            return false;
        }
    }

    public async Task<bool> DeleteCheckpointAsync(string labName, string checkpointId, Action<string>? log = null, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(labName))
            throw new ArgumentException("Lab name is required.", nameof(labName));
        if (string.IsNullOrWhiteSpace(checkpointId))
            throw new ArgumentException("Checkpoint id is required.", nameof(checkpointId));

        try
        {
            var checkpoint = await LoadCheckpointAsync(labName, checkpointId, ct);
            if (checkpoint == null)
            {
                log?.Invoke($"Checkpoint '{checkpointId}' not found.");
                return false;
            }

            var allSucceeded = true;
            foreach (var snapshot in checkpoint.Snapshots)
            {
                ct.ThrowIfCancellationRequested();
                var safeVmName = EscapeSingleQuote(snapshot.VMName);
                var safeSnapshotName = EscapeSingleQuote(snapshot.SnapshotName);
                var script = $"try {{ Remove-VMCheckpoint -VMName '{safeVmName}' -Name '{safeSnapshotName}' -ErrorAction Stop | Out-Null; Write-Output 'OK' }} catch {{ Write-Output ('ERROR: ' + $_.Exception.Message) }}";
                var output = await RunPowerShellAsync(script, ct);
                var trimmed = (output ?? string.Empty).Trim();
                if (trimmed.StartsWith("ERROR:", StringComparison.OrdinalIgnoreCase))
                {
                    allSucceeded = false;
                    log?.Invoke($"Failed to remove VM checkpoint for '{snapshot.VMName}': {trimmed}");
                }
                else
                {
                    log?.Invoke($"Removed VM checkpoint '{snapshot.SnapshotName}' for '{snapshot.VMName}'.");
                }
            }

            var path = GetCheckpointPath(labName, checkpointId);
            if (File.Exists(path))
                File.Delete(path);

            return allSucceeded;
        }
        catch (OperationCanceledException)
        {
            log?.Invoke("Checkpoint delete cancelled.");
            throw;
        }
        catch (Exception ex)
        {
            log?.Invoke($"Checkpoint delete failed: {ex.Message}");
            return false;
        }
    }

    public async Task<List<string>> CompareCheckpointsAsync(string labName, string checkpointId1, string checkpointId2, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(labName))
            throw new ArgumentException("Lab name is required.", nameof(labName));
        if (string.IsNullOrWhiteSpace(checkpointId1))
            throw new ArgumentException("Checkpoint id 1 is required.", nameof(checkpointId1));
        if (string.IsNullOrWhiteSpace(checkpointId2))
            throw new ArgumentException("Checkpoint id 2 is required.", nameof(checkpointId2));

        var checkpoint1 = await LoadCheckpointAsync(labName, checkpointId1, ct);
        var checkpoint2 = await LoadCheckpointAsync(labName, checkpointId2, ct);
        if (checkpoint1 == null || checkpoint2 == null)
            return new List<string> { "One or both checkpoints were not found." };

        var differences = new List<string>();
        var snapshotLookup1 = checkpoint1.Snapshots.ToDictionary(s => s.VMName, StringComparer.OrdinalIgnoreCase);
        var snapshotLookup2 = checkpoint2.Snapshots.ToDictionary(s => s.VMName, StringComparer.OrdinalIgnoreCase);
        var vmNames = snapshotLookup1.Keys
            .Union(snapshotLookup2.Keys, StringComparer.OrdinalIgnoreCase)
            .OrderBy(x => x, StringComparer.OrdinalIgnoreCase);

        foreach (var vmName in vmNames)
        {
            ct.ThrowIfCancellationRequested();
            var has1 = snapshotLookup1.TryGetValue(vmName, out var snapshot1);
            var has2 = snapshotLookup2.TryGetValue(vmName, out var snapshot2);

            if (!has1)
            {
                differences.Add($"VM '{vmName}' exists only in checkpoint '{checkpoint2.Name}'.");
                continue;
            }

            if (!has2)
            {
                differences.Add($"VM '{vmName}' exists only in checkpoint '{checkpoint1.Name}'.");
                continue;
            }

            if (snapshot1 == null || snapshot2 == null)
                continue;

            if (!string.Equals(snapshot1.StateJson ?? string.Empty, snapshot2.StateJson ?? string.Empty, StringComparison.Ordinal))
                differences.Add($"VM '{vmName}' state differs between checkpoints.");
            if (!string.Equals(snapshot1.SnapshotName, snapshot2.SnapshotName, StringComparison.OrdinalIgnoreCase))
                differences.Add($"VM '{vmName}' snapshot name changed: '{snapshot1.SnapshotName}' vs '{snapshot2.SnapshotName}'.");
            if (snapshot1.Success != snapshot2.Success)
                differences.Add($"VM '{vmName}' success flag changed: {snapshot1.Success} vs {snapshot2.Success}.");
        }

        if (differences.Count == 0)
            differences.Add("No differences found.");

        return differences;
    }

    private string GetCheckpointDir(string labName)
    {
        var dir = Path.Combine(@"C:\LabSources\LabConfig", labName, CheckpointsDir);
        Directory.CreateDirectory(dir);
        return dir;
    }

    private string GetCheckpointPath(string labName, string checkpointId)
    {
        return Path.Combine(GetCheckpointDir(labName), $"{checkpointId}.json");
    }

    private async Task SaveCheckpointAsync(ChangeCheckpoint checkpoint, CancellationToken ct = default)
    {
        var dir = GetCheckpointDir(checkpoint.LabName);
        var path = Path.Combine(dir, $"{checkpoint.Id}.json");
        var json = JsonSerializer.Serialize(checkpoint, new JsonSerializerOptions { WriteIndented = true });
        await File.WriteAllTextAsync(path, json, ct);
    }

    private async Task<ChangeCheckpoint?> LoadCheckpointAsync(string labName, string checkpointId, CancellationToken ct = default)
    {
        var path = GetCheckpointPath(labName, checkpointId);
        if (!File.Exists(path))
            return null;

        var json = await File.ReadAllTextAsync(path, ct);
        return JsonSerializer.Deserialize<ChangeCheckpoint>(json);
    }

    private static string? FindVmStateCaptureScript()
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "Invoke-VMStateCapture.ps1"),
            Path.Combine(AppContext.BaseDirectory, "scripts", "Invoke-VMStateCapture.ps1"),
            Path.Combine(Environment.CurrentDirectory, "Invoke-VMStateCapture.ps1"),
            Path.Combine(Environment.CurrentDirectory, "scripts", "Invoke-VMStateCapture.ps1")
        };

        foreach (var path in candidates)
        {
            if (File.Exists(path))
                return path;
        }

        return null;
    }

    private static string EscapeSingleQuote(string input)
    {
        if (string.IsNullOrEmpty(input))
            return string.Empty;

        return input.Replace("'", "''");
    }

    private async Task<string> RunPowerShellAsync(string script, CancellationToken ct = default)
    {
        var pwsh = FindPowerShell();
        var psi = new ProcessStartInfo
        {
            FileName = pwsh,
            Arguments = $"-NoProfile -NonInteractive -Command \"{script}\"",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        using var process = new Process { StartInfo = psi };
        process.Start();
        var output = await process.StandardOutput.ReadToEndAsync();
        await process.WaitForExitAsync(ct);
        return output;
    }

    private static string FindPowerShell()
    {
        var pwsh = "pwsh";
        try
        {
            var p = Process.Start(new ProcessStartInfo
            {
                FileName = pwsh,
                Arguments = "-Version",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                CreateNoWindow = true
            });
            p?.WaitForExit(3000);
            if (p?.ExitCode == 0)
                return pwsh;
        }
        catch
        {
        }

        return "powershell.exe";
    }
}

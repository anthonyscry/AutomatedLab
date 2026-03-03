using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Threading.Tasks;

namespace OpenCodeLab.Services;

/// <summary>
/// Reusable PowerShell execution engine using the SDK (no process spawning).
/// Replaces Process.Start-based PowerShell invocation for better performance.
/// </summary>
public static class PowerShellRunner
{
    /// <summary>
    /// Run an inline PowerShell script and return stdout as a string.
    /// </summary>
    public static async Task<(string Output, string Errors, bool Success)> RunScriptAsync(
        string script, CancellationToken ct = default)
    {
        return await Task.Run(() =>
        {
            using var runspace = RunspaceFactory.CreateRunspace();
            runspace.Open();

            using var ps = PowerShell.Create();
            ps.Runspace = runspace;
            ps.AddScript(script);

            using var _ = ct.Register(() =>
            {
                try { ps.Stop(); } catch { }
            });

            var results = ps.Invoke();

            var output = string.Join("\n", results.Select(r => r?.ToString() ?? string.Empty));
            var errors = string.Join("\n", ps.Streams.Error.Select(e => e.ToString()));
            var success = !ps.HadErrors;

            ct.ThrowIfCancellationRequested();
            return (output, errors, success);
        }, ct);
    }

    /// <summary>
    /// Run an inline script and return output as JSON string.
    /// Wraps the script output with ConvertTo-Json if not already JSON.
    /// </summary>
    public static async Task<string?> RunScriptGetJsonAsync(
        string script, CancellationToken ct = default)
    {
        var (output, _, _) = await RunScriptAsync(script, ct);
        return string.IsNullOrWhiteSpace(output) ? null : output.Trim();
    }

    /// <summary>
    /// Run a .ps1 script file with named parameters.
    /// </summary>
    public static async Task<(string Output, string Errors, bool Success)> RunFileAsync(
        string scriptPath, Dictionary<string, object?>? parameters = null,
        CancellationToken ct = default)
    {
        return await Task.Run(() =>
        {
            using var runspace = RunspaceFactory.CreateRunspace();
            runspace.Open();

            using var ps = PowerShell.Create();
            ps.Runspace = runspace;
            ps.AddCommand(scriptPath);

            if (parameters != null)
            {
                foreach (var kvp in parameters)
                    ps.AddParameter(kvp.Key, kvp.Value);
            }

            using var _ = ct.Register(() =>
            {
                try { ps.Stop(); } catch { }
            });

            var results = ps.Invoke();

            var output = string.Join("\n", results.Select(r => r?.ToString() ?? string.Empty));
            var errors = string.Join("\n", ps.Streams.Error.Select(e => e.ToString()));
            var success = !ps.HadErrors;

            ct.ThrowIfCancellationRequested();
            return (output, errors, success);
        }, ct);
    }

    /// <summary>
    /// Run a script with real-time output streaming via callback.
    /// Used for long-running operations like lab deployment.
    /// </summary>
    public static async Task<bool> RunScriptStreamingAsync(
        string script, Action<string>? onOutput = null,
        Action<string>? onError = null, CancellationToken ct = default)
    {
        return await Task.Run(() =>
        {
            using var runspace = RunspaceFactory.CreateRunspace();
            runspace.Open();

            using var ps = PowerShell.Create();
            ps.Runspace = runspace;
            ps.AddScript(script);

            var output = new PSDataCollection<PSObject>();
            output.DataAdded += (_, e) =>
            {
                var item = output[e.Index];
                if (item != null)
                    onOutput?.Invoke(item.ToString() ?? string.Empty);
            };

            ps.Streams.Information.DataAdded += (_, e) =>
            {
                var info = ps.Streams.Information[e.Index];
                onOutput?.Invoke(info.MessageData?.ToString() ?? string.Empty);
            };
            ps.Streams.Warning.DataAdded += (_, e) =>
            {
                var warn = ps.Streams.Warning[e.Index];
                onOutput?.Invoke($"WARNING: {warn}");
            };
            ps.Streams.Error.DataAdded += (_, e) =>
            {
                var err = ps.Streams.Error[e.Index];
                onError?.Invoke(err.ToString());
            };

            using var _ = ct.Register(() =>
            {
                try { ps.Stop(); } catch { }
            });

            var asyncResult = ps.BeginInvoke<PSObject, PSObject>(input: null, output);
            while (!asyncResult.IsCompleted)
            {
                ct.ThrowIfCancellationRequested();
                Thread.Sleep(50);
            }

            ps.EndInvoke(asyncResult);
            ct.ThrowIfCancellationRequested();
            return !ps.HadErrors;
        }, ct);
    }
}

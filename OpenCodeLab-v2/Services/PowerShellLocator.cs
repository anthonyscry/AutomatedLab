using System;
using System.IO;
using System.Linq;

namespace OpenCodeLab.Services;

/// <summary>
/// Utility class for locating PowerShell executable across different deployment scenarios.
/// </summary>
internal static class PowerShellLocator
{
    /// <summary>
    /// Locates the PowerShell executable with fallback strategy:
    /// 1. Check for bundled pwsh.exe alongside the app (for airgapped deployment)
    /// 2. Check common system install locations
    /// 3. Try PATH environment variable
    /// 4. Fall back to Windows PowerShell
    /// </summary>
    /// <returns>Path to PowerShell executable or "pwsh.exe" as last resort</returns>
    internal static string FindPowerShell()
    {
        // 1. Check for bundled pwsh.exe alongside the app (for airgapped deployment)
        var appDir = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        var bundledPwsh = Path.Combine(appDir, "pwsh", "pwsh.exe");
        if (File.Exists(bundledPwsh))
            return bundledPwsh;

        // 2. Check common system install locations
        var candidates = new[]
        {
            @"C:\Program Files\PowerShell\7\pwsh.exe",
            @"C:\Program Files\PowerShell\7-preview\pwsh.exe",
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "PowerShell", "7", "pwsh.exe")
        };

        foreach (var path in candidates)
        {
            if (File.Exists(path))
                return path;
        }

        // 3. Try PATH
        var pathDirs = Environment.GetEnvironmentVariable("PATH")?.Split(Path.PathSeparator) ?? Array.Empty<string>();
        foreach (var dir in pathDirs)
        {
            var pwshPath = Path.Combine(dir, "pwsh.exe");
            if (File.Exists(pwshPath))
                return pwshPath;
        }

        // 4. Fall back to Windows PowerShell
        var winPs = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
            "WindowsPowerShell", "v1.0", "powershell.exe");
        if (File.Exists(winPs))
            return winPs;

        return "pwsh.exe";
    }
}

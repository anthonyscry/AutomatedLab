using System;
using System.IO;
using System.Windows;
using OpenCodeLab.Services;

namespace OpenCodeLab;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Ensure log directory exists
        try { Directory.CreateDirectory(LabPaths.Logs); }
        catch { }

        // Handle unhandled exceptions on UI thread
        DispatcherUnhandledException += (s, args) =>
        {
            LogException(args.Exception);
            var message = $"An error occurred:\n\n{args.Exception.Message}\n\n" +
                         $"Details have been logged to:\n{GetLogPath()}";
            MessageBox.Show(message, "Error", MessageBoxButton.OK, MessageBoxImage.Error);
            args.Handled = true;
        };

        // Handle unhandled exceptions on any thread
        AppDomain.CurrentDomain.UnhandledException += (s, args) =>
        {
            if (args.ExceptionObject is Exception ex)
            {
                LogException(ex);
            }
        };
    }

    private void LogException(Exception ex)
    {
        try
        {
            Directory.CreateDirectory(LabPaths.Logs);
            var logPath = Path.Combine(LabPaths.Logs, $"crash-{DateTime.Now:yyyyMMdd-HHmmss}.log");
            var content = $"CRASH LOG - {DateTime.Now:yyyy-MM-dd HH:mm:ss}\n\n" +
                         $"Message: {ex.Message}\n\n" +
                         $"Stack Trace:\n{ex.StackTrace}\n\n";
            if (ex.InnerException != null)
            {
                content += $"Inner Exception: {ex.InnerException.Message}\n" +
                          $"{ex.InnerException.StackTrace}\n";
            }
            File.WriteAllText(logPath, content);
        }
        catch { }
    }

    private string GetLogPath()
    {
        return Path.Combine(LabPaths.Logs, $"crash-{DateTime.Now:yyyyMMdd-HHmmss}.log");
    }
}

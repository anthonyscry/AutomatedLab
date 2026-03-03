using System.IO;

namespace OpenCodeLab.Services;

/// <summary>
/// Centralized path provider for all lab infrastructure directories.
/// All paths derive from Root, making the entire tree relocatable.
/// </summary>
public static class LabPaths
{
    /// <summary>
    /// Root lab sources directory. Change this to relocate all lab paths.
    /// </summary>
    public static string Root { get; set; } = @"C:\LabSources";

    public static string LabConfig => Path.Combine(Root, "LabConfig");
    public static string ISOs => Path.Combine(Root, "ISOs");
    public static string VMs => Path.Combine(Root, "VMs");
    public static string Logs => Path.Combine(Root, "Logs");
    public static string Docs => Path.Combine(Root, "Docs");
    public static string Backups => Path.Combine(Root, "Backups");
    public static string IaC => Path.Combine(Root, "IaC");
    public static string Templates => Path.Combine(LabConfig, "templates");
    public static string SystemConfig => Path.Combine(LabConfig, "_system");
}

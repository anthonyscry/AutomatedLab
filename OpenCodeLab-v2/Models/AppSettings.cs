namespace OpenCodeLab.Models;

using OpenCodeLab.Services;

public class AppSettings
{
    public string DefaultLabPath { get; set; } = LabPaths.Root;
    public string LabConfigPath { get; set; } = LabPaths.LabConfig;
    public string ISOPath { get; set; } = LabPaths.ISOs;
    public string VMPath { get; set; } = LabPaths.VMs;
    public string LogPath { get; set; } = LabPaths.Logs;
    public string DocsPath { get; set; } = LabPaths.Docs;
    public string BackupsPath { get; set; } = LabPaths.Backups;
    public string IaCPath { get; set; } = LabPaths.IaC;
    public string TemplatePath { get; set; } = LabPaths.Templates;
    public string DefaultSwitchName { get; set; } = "LabSwitch";
    public string DefaultSwitchType { get; set; } = "Internal";
    public bool EnableAutoStart { get; set; }
    public int RefreshIntervalSeconds { get; set; } = 10;
    public int MaxLogLines { get; set; } = 1000;
}

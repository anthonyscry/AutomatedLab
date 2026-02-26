namespace OpenCodeLab.Models;

public class AppSettings
{
    public string DefaultLabPath { get; set; } = @"C:\LabSources";
    public string LabConfigPath { get; set; } = @"C:\LabSources\LabConfig";
    public string ISOPath { get; set; } = @"C:\LabSources\ISOs";
    public string VMPath { get; set; } = @"C:\LabSources\VMs";
    public string DefaultSwitchName { get; set; } = "LabSwitch";
    public string DefaultSwitchType { get; set; } = "Internal";
    public bool EnableAutoStart { get; set; }
    public int RefreshIntervalSeconds { get; set; } = 10;
    public int MaxLogLines { get; set; } = 1000;
}

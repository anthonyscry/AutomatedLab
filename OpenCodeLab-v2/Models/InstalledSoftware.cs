using System;
using System.Collections.Generic;

namespace OpenCodeLab.Models;

public class InstalledSoftware
{
    public string Name { get; set; } = string.Empty;
    public string Version { get; set; } = string.Empty;
    public string Publisher { get; set; } = string.Empty;
    public DateTime? InstallDate { get; set; }
}

public class ScanResult
{
    public string VMName { get; set; } = string.Empty;
    public string VMState { get; set; } = string.Empty;
    public List<InstalledSoftware> Software { get; set; } = new();
    public DateTime ScannedAt { get; set; }
    public bool Success { get; set; }
    public string? ErrorMessage { get; set; }
}

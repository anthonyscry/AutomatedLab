using System.Collections.Generic;

namespace OpenCodeLab.Models;

public class LabConfig
{
    public string LabName { get; set; } = "MyLab";
    public string? LabPath { get; set; }
    public string? Description { get; set; }
    public NetworkConfig Network { get; set; } = new();
    public List<VMDefinition> VMs { get; set; } = new();
    public List<string> CustomRoles { get; set; } = new();
    public string? DomainName { get; set; } = "contoso.com"; // Configurable domain name
}

public class NetworkConfig
{
    public string SwitchName { get; set; } = "LabSwitch";
    public string SwitchType { get; set; } = "Internal";
    public string? IPAddressPrefix { get; set; }
    public int VLANID { get; set; }
}

public class VMDefinition
{
    public string Name { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty;
    public long MemoryGB { get; set; } = 2;
    public int Processors { get; set; } = 2;
    public string? SwitchName { get; set; }
    public string? IPAddress { get; set; }
    public string? SubnetMask { get; set; }
    public string? Gateway { get; set; }
    public List<string>? DnsServers { get; set; }
    public string? TimeZone { get; set; } = "Pacific Standard Time";
    public string? ISOPath { get; set; }
    public long DiskSizeGB { get; set; } = 40;
}

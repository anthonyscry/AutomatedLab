using System.Collections.Generic;

namespace OpenCodeLab.Models;

public class SubnetDefinition
{
    public string Name { get; set; } = "Default";
    public string SwitchName { get; set; } = "LabSwitch";
    public string SwitchType { get; set; } = "Internal";
    public string AddressPrefix { get; set; } = "192.168.10.0/24";
    public string Gateway { get; set; } = "192.168.10.1";
    public string SubnetMask { get; set; } = "255.255.255.0";
    public int VLANID { get; set; }
    public bool EnableNAT { get; set; } = true;
    public string? NATName { get; set; }
    public string? DnsServer { get; set; }
    public List<string> ConnectedVMs { get; set; } = new();
}

using System;
using System.Collections.Generic;

namespace OpenCodeLab.Models;

/// <summary>
/// VM configuration at the Hyper-V host level
/// </summary>
public class HostVmConfiguration
{
    public string VmName { get; set; } = string.Empty;
    public int ProcessorCount { get; set; }
    public long MemoryStartupBytes { get; set; }
    public long MemoryMinimumBytes { get; set; }
    public long MemoryMaximumBytes { get; set; }
    public bool DynamicMemoryEnabled { get; set; }
    public List<HostDiskConfiguration> Disks { get; set; } = new();
    public List<HostNetworkAdapterConfiguration> NetworkAdapters { get; set; } = new();
    public string Generation { get; set; } = "2";
    public bool AutomaticCheckpointsEnabled { get; set; }
    public string? CheckpointFileLocation { get; set; }
    public string? SmartPagingFilePath { get; set; }
    public DateTime CapturedAt { get; set; } = DateTime.UtcNow;

    [System.Text.Json.Serialization.JsonIgnore]
    public string MemoryStartupGB => $"{MemoryStartupBytes / (1024.0 * 1024 * 1024):F1} GB";

    [System.Text.Json.Serialization.JsonIgnore]
    public string MemoryMaximumGB => $"{MemoryMaximumBytes / (1024.0 * 1024 * 1024):F1} GB";
}

/// <summary>
/// Disk configuration for a VM
/// </summary>
public class HostDiskConfiguration
{
    public string Path { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty; // VHD, VHDX, DVD, Floppy
    public long SizeBytes { get; set; }
    public long? FileSizeBytes { get; set; }
    public int ControllerNumber { get; set; }
    public int ControllerLocation { get; set; }
    public bool IsAttached { get; set; }

    [System.Text.Json.Serialization.JsonIgnore]
    public string SizeGB => $"{SizeBytes / (1024.0 * 1024 * 1024):F1} GB";

    [System.Text.Json.Serialization.JsonIgnore]
    public string FileSizeGB => FileSizeBytes.HasValue 
        ? $"{FileSizeBytes.Value / (1024.0 * 1024 * 1024):F1} GB" 
        : "N/A";
}

/// <summary>
/// Network adapter configuration for a VM
/// </summary>
public class HostNetworkAdapterConfiguration
{
    public string Name { get; set; } = string.Empty;
    public string? SwitchName { get; set; }
    public bool IsConnected { get; set; }
    public List<string> IpAddresses { get; set; } = new();
    public List<string> MacAddresses { get; set; } = new();
    public string? VlanId { get; set; }
    public bool AllowManagementOs { get; set; }
}

/// <summary>
/// Host-level network configuration
/// </summary>
public class HostNetworkConfiguration
{
    public DateTime CapturedAt { get; set; } = DateTime.UtcNow;
    public List<VirtualSwitchConfiguration> Switches { get; set; } = new();
    public List<NatConfiguration> NatConfigurations { get; set; } = new();
    public List<NetworkAdapterConfiguration> HostAdapters { get; set; } = new();
}

/// <summary>
/// Virtual switch configuration
/// </summary>
public class VirtualSwitchConfiguration
{
    public string Name { get; set; } = string.Empty;
    public string SwitchType { get; set; } = string.Empty; // Internal, External, Private
    public string? NetAdapterInterfaceDescription { get; set; }
    public bool AllowManagementOs { get; set; }
    public string? DefaultFlowMinimumBandwidthAbsolute { get; set; }
    public List<string> ConnectedVms { get; set; } = new();
}

/// <summary>
/// NAT configuration
/// </summary>
public class NatConfiguration
{
    public string Name { get; set; } = string.Empty;
    public string Subnet { get; set; } = string.Empty; // e.g., "192.168.10.0/24"
    public string InternalIpInterfaceAddress { get; set; } = string.Empty;
    public List<NatMapping> Mappings { get; set; } = new();
}

/// <summary>
/// NAT port mapping
/// </summary>
public class NatMapping
{
    public string Protocol { get; set; } = "TCP";
    public int ExternalPort { get; set; }
    public int InternalPort { get; set; }
    public string InternalAddress { get; set; } = string.Empty;
}

/// <summary>
/// Host network adapter configuration
/// </summary>
public class NetworkAdapterConfiguration
{
    public string Name { get; set; } = string.Empty;
    public string InterfaceDescription { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public string? MacAddress { get; set; }
    public List<string> IpAddresses { get; set; } = new();
    public string? DefaultGateway { get; set; }
    public List<string> DnsServers { get; set; } = new();
}

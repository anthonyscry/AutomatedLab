# Phase 4: VM Provisioning - Research

**Researched:** 2026-02-09
**Domain:** Hyper-V VM provisioning, PowerShell automation
**Confidence:** HIGH

## Summary

Phase 4 implements VM provisioning using native Hyper-V PowerShell cmdlets to create Windows domain lab VMs (Domain Controller, Server 2019, Windows 11). The implementation uses the built-in Hyper-V module (New-VM, Set-VM, Add-VMDvdDrive, Set-VMProcessor, Set-VMMemory) without external dependencies like AutomatedLab. Key patterns include idempotent VM creation with stale VM cleanup, Generation 2 VMs for modern Windows support, static memory allocation for reliability, and ISO attachment for bootable installations.

**Primary recommendation:** Use native Hyper-V cmdlets (New-VM, Set-VMProcessor, Set-VMMemory, Add-VMDvdDrive) with Generation 2 VMs, static memory configuration (2GB for DC/Server, 4GB for Win11), 60GB dynamic VHDX disks, and ISO attachment to the existing "SimpleLab" vSwitch from Phase 3.

## Standard Stack

### Core
| Library/Feature | Version | Purpose | Why Standard |
|-----------------|---------|---------|--------------|
| **Hyper-V Module** | Built-in (Windows 10/11, Server 2016+) | VM provisioning and management | Native Windows module for complete Hyper-V control. Includes New-VM, Set-VM, Start-VM, Remove-VM, Add-VMDvdDrive, Set-VMProcessor, Set-VMMemory. No third-party dependencies. |
| **New-VM** | Built-in | Create new virtual machines | Core cmdlet for VM creation with configurable memory, generation, VHD path, and switch connection |
| **Set-VMProcessor** | Built-in | Configure virtual processors | Set CPU count for VMs (recommend 2-4 vCPUs for lab VMs) |
| **Set-VMMemory** | Built-in | Configure VM memory | Set static memory allocation (avoids dynamic memory complexity) |
| **Add-VMDvdDrive** | Built-in | Attach ISO to VM | Boot from Windows Server/Client ISOs for installation |
| **Get-VM** | Built-in | Query VM state | Detect existing VMs for idempotent operations |
| **Remove-VM** | Built-in | Delete VMs | Cleanup stale VMs from failed runs |

### Supporting
| Feature | Purpose | When to Use |
|---------|---------|-------------|
| **Get-VMSwitch** | Verify vSwitch exists | Validate network setup before VM creation |
| **Test-Path** | Verify ISO files exist | Pre-flight validation before attaching ISOs |
| **PSCustomObject** | Structured results | Return VM creation status with properties |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| **Native Hyper-V cmdlets** | AutomatedLab framework | AutomatedLab is overkill for simple 3-VM labs. Adds complexity (ISO detection, disclaimers, role abstraction) and slower builds due to generic abstraction layers. Native cmdlets are faster, simpler, and have fewer dependencies. |
| **Static memory** | Dynamic memory | Dynamic memory adds complexity and can cause performance issues during DC promotion. Static memory is predictable and recommended for domain controllers. |
| **Generation 2 VMs** | Generation 1 VMs | Gen1 is legacy (BIOS boot). Gen2 is modern (UEFI boot), required for Windows 11 and Secure Boot. Use Gen2 for all Windows Server 2016+ and Windows 11+ VMs. |

**Installation:** No installation required - uses built-in Hyper-V PowerShell module included with Windows 10/11 Pro/Ent and Windows Server 2016+.

## Architecture Patterns

### Recommended Project Structure
```
SimpleLab/
├── Public/
│   ├── New-LabVM.ps1           # Single VM creation (idempotent)
│   ├── Remove-LabVM.ps1        # VM removal (cleanup)
│   └── Initialize-LabVMs.ps1   # Orchestrator: create all lab VMs
└── Private/
    ├── Get-LabVMConfig.ps1     # Retrieve VM hardware specifications
    ├── Test-LabVM.ps1          # Check if VM exists
    └── Remove-StaleVM.ps1      # Aggressive cleanup (from Phase 3)
```

### Pattern 1: Idempotent VM Creation
**What:** Check if VM exists before creating, remove stale VMs from failed runs.

**When to use:** Every VM creation operation to ensure repeatable deployments.

**Example:**
```powershell
# Source: Microsoft New-VM documentation + existing Remove-HyperVVMStale pattern
function New-LabVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VMName,

        [Parameter(Mandatory)]
        [int64]$MemoryBytes,

        [Parameter(Mandatory)]
        [string]$VHDPath,

        [Parameter(Mandatory)]
        [string]$SwitchName,

        [string]$IsoPath,

        [int]$ProcessorCount = 2,

        [int]$Generation = 2,

        [switch]$Force
    )

    # Check if VM already exists
    $existingVM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if ($existingVM -and -not $Force) {
        return [PSCustomObject]@{
            VMName = $VMName
            Created = $false
            Status = 'AlreadyExists'
            Message = "VM '$VMName' already exists. Use -Force to recreate."
        }
    }

    # Remove stale VM if -Force specified
    if ($existingVM -and $Force) {
        Remove-VM -Name $VMName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2  # Wait for removal to complete
    }

    # Create the VM
    try {
        $vmParams = @{
            Name = $VMName
            MemoryStartupBytes = $MemoryBytes
            NewVHDPath = $VHDPath
            NewVHDSizeBytes = 60GB
            Generation = $Generation
            SwitchName = $SwitchName
            ErrorAction = 'Stop'
        }

        $vm = New-VM @vmParams

        # Configure processor
        Set-VMProcessor -VMName $VMName -Count $ProcessorCount

        # Configure static memory
        Set-VMMemory -VMName $VMName -StartupBytes $MemoryBytes -DynamicMemoryEnabled $false

        # Attach ISO if provided
        if ($IsoPath -and (Test-Path $IsoPath)) {
            Add-VMDvdDrive -VMName $VMName -Path $IsoPath
        }

        return [PSCustomObject]@{
            VMName = $VMName
            Created = $true
            Status = 'OK'
            Message = "VM '$VMName' created successfully"
            VHDPath = $VHDPath
            MemoryGB = $MemoryBytes / 1GB
            ProcessorCount = $ProcessorCount
        }
    }
    catch {
        return [PSCustomObject]@{
            VMName = $VMName
            Created = $false
            Status = 'Failed'
            Message = "VM creation failed: $($_.Exception.Message)"
        }
    }
}
```

### Pattern 2: Orchestrator for Multi-VM Creation
**What:** Create all lab VMs with proper sequencing and error handling.

**When to use:** Building the complete 3-VM lab (DC, Server, Win11).

**Example:**
```powershell
# Source: Orchestrator pattern from Initialize-LabNetwork (Phase 3)
function Initialize-LabVMs {
    [CmdletBinding()]
    param(
        [string]$SwitchName = 'SimpleLab',
        [string]$VHDBasePath = 'C:\Lab\VMs',
        [switch]$Force
    )

    $ErrorActionPreference = 'Stop'
    $results = @{}
    $overallStatus = 'OK'

    # VM configuration from requirements
    $vmConfigs = @(
        @{ Name = 'SimpleDC'; MemoryGB = 2; ISO = 'Server2019' },
        @{ Name = 'SimpleServer'; MemoryGB = 2; ISO = 'Server2019' },
        @{ Name = 'SimpleWin11'; MemoryGB = 4; ISO = 'Windows11' }
    )

    # Get ISO paths from config
    $config = Get-LabConfig
    $isoPaths = $config.IsoPaths

    # Ensure VM path exists
    if (-not (Test-Path $VHDBasePath)) {
        New-Item -Path $VHDBasePath -ItemType Directory -Force | Out-Null
    }

    foreach ($vmConfig in $vmConfigs) {
        Write-Host "Creating VM: $($vmConfig.Name)" -ForegroundColor Cyan

        $vhdPath = Join-Path $VHDBasePath "$($vmConfig.Name).vhdx"
        $isoPath = $isoPaths[$vmConfig.ISO]

        $result = New-LabVM -VMName $vmConfig.Name `
            -MemoryBytes ($vmConfig.MemoryGB * 1GB) `
            -VHDPath $vhdPath `
            -SwitchName $SwitchName `
            -IsoPath $isoPath `
            -ProcessorCount 2 `
            -Generation 2 `
            -Force:$Force

        $results[$vmConfig.Name] = $result

        if ($result.Status -ne 'OK') {
            $overallStatus = 'Failed'
        }
    }

    return [PSCustomObject]@{
        Status = $overallStatus
        VMs = $results
        Message = if ($overallStatus -eq 'OK') {
            "All VMs created successfully"
        } else {
            "Some VMs failed to create"
        }
    }
}
```

### Pattern 3: VM Configuration Retrieval
**What:** Centralize VM hardware specifications for easy modification.

**When to use:** Retrieving VM configurations for creation or validation.

**Example:**
```powershell
# Source: Configuration pattern from Get-LabNetworkConfig (Phase 3)
function Get-LabVMConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$VMName
    )

    # Default VM configurations from requirements
    $vmConfigs = @{
        'SimpleDC' = @{
            MemoryGB = 2
            ProcessorCount = 2
            DiskSizeGB = 60
            Generation = 2
            ISO = 'Server2019'
        }
        'SimpleServer' = @{
            MemoryGB = 2
            ProcessorCount = 2
            DiskSizeGB = 60
            Generation = 2
            ISO = 'Server2019'
        }
        'SimpleWin11' = @{
            MemoryGB = 4
            ProcessorCount = 2
            DiskSizeGB = 60
            Generation = 2
            ISO = 'Windows11'
        }
    }

    if ($VMName) {
        return $vmConfigs[$VMName]
    }

    return $vmConfigs
}
```

### Anti-Patterns to Avoid

- **Non-idempotent VM creation:** Always check if VM exists before creating
  - Bad: Always call New-VM without checking for existing VMs
  - Good: Use Get-VM to check existence, use -Force for recreation

- **Assuming clean environment:** Failed runs leave stale VMs
  - Bad: Assume no VMs exist at script start
  - Good: Check for existing VMs, remove stale ones with aggressive cleanup

- **Silent failures:** VM creation errors must surface immediately
  - Bad: Use -ErrorAction SilentlyContinue for VM operations
  - Good: Use try/catch with structured error reporting

- **Dynamic memory for DCs:** Can cause performance issues
  - Bad: Enable dynamic memory for domain controllers
  - Good: Use static memory (2GB minimum for Server 2019 DC)

- **Generation 1 for modern Windows:** Not compatible with Windows 11
  - Bad: Use Generation 1 VMs for Windows 11
  - Good: Use Generation 2 VMs for all Server 2016+ and Windows 11+

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| VM creation | Custom VHDX formatting, registry hacks | New-VM cmdlet | Handles VHDX creation, VM configuration, state management |
| VM detection | WMI queries, XML parsing | Get-VM cmdlet | Reliable detection, proper error handling |
| Processor configuration | Direct registry modification | Set-VMProcessor | Official API, handles NUMA, hot-add scenarios |
| Memory configuration | VM settings XML manipulation | Set-VMMemory | Proper integration with Hyper-V memory manager |
| DVD drive attachment | SCSI controller manipulation | Add-VMDvdDrive | Handles controller location, IDE/SCSI differences |
| VM removal | File deletion, registry cleanup | Remove-VM | Proper cleanup of VM files, checkpoints, saved state |

**Key insight:** Hyper-V module provides complete VM lifecycle management. Custom solutions add complexity and miss edge cases (checkpoints, saved state, network adapters, integration services).

## Common Pitfalls

### Pitfall 1: Stale VM State from Previous Failed Runs
**What goes wrong:** Failed deployments leave VMs in inconsistent states. Subsequent runs fail with "VM already exists" errors.

**Why it happens:** Scripts assume clean environment, don't check for existing VMs, Hyper-V operations are asynchronous.

**How to avoid:**
- Implement aggressive pre-flight cleanup (see Remove-HyperVVMStale pattern from Phase 3)
- Use Get-VM to check for existing VMs before creation
- Use -Force parameter to recreate VMs when needed
- Wait for VM removal to complete (Start-Sleep -Seconds 2)

**Warning signs:** "VM already exists" errors, having to manually delete VMs between runs.

### Pitfall 2: Incorrect Memory Configuration
**What goes wrong:** VMs with insufficient memory fail during Windows installation or DC promotion.

**Why it happens:** Using default 512MB memory, not accounting for OS requirements, using dynamic memory with insufficient minimum.

**How to avoid:**
- Use static memory with -DynamicMemoryEnabled $false
- Allocate minimum 2GB for Server 2019, 4GB for Windows 11
- Set memory at creation time with -MemoryStartupBytes
- Validate using Set-VMMemory -StartupBytes

**Warning signs:** VMs start but fail during installation, sluggish performance.

### Pitfall 3: ISO Path Issues
**What goes wrong:** VMs created but won't boot because ISO not attached or path is wrong.

**Why it happens:** Relative paths resolve differently, ISOs moved after configuration, not validating ISO existence before attachment.

**How to avoid:**
- Use absolute paths for ISO files
- Validate ISO exists with Test-Path before attaching
- Get ISO paths from centralized config (Get-LabConfig)
- Use Add-VMDvdDrive after VM creation

**Warning signs:** VMs boot to "No operating system found", "Boot failed" messages.

### Pitfall 4: Generation Mismatch
**What goes wrong:** Generation 1 VMs can't boot Windows 11 (UEFI required), Secure Boot issues.

**Why it happens:** Using default or incorrect generation, not understanding Gen1 vs Gen2 differences.

**How to avoid:**
- Always use Generation 2 for Windows Server 2016+ and Windows 11+
- Specify -Generation 2 parameter on New-VM
- Understand Gen1 = BIOS, Gen2 = UEFI
- Disable Secure Boot only if needed for specific scenarios

**Warning signs:** "Boot failed" errors, Windows 11 won't install, Secure Boot violations.

### Pitfall 5: Missing Network Switch
**What goes wrong:** VMs created but can't communicate because vSwitch doesn't exist or name is wrong.

**Why it happens:** Assuming vSwitch from Phase 3 exists, typo in switch name, vSwitch deleted between runs.

**How to avoid:**
- Validate vSwitch exists before VM creation (Get-VMSwitch)
- Use consistent switch name ("SimpleLab")
- Create vSwitch if missing (New-LabSwitch from Phase 3)
- Include switch name in VM configuration

**Warning signs:** VMs have "Network cable unplugged", can't get IP addresses.

## Code Examples

Verified patterns from official sources:

### VM Creation with Basic Configuration
```powershell
# Source: Microsoft New-VM documentation
# URL: https://learn.microsoft.com/en-us/powershell/module/hyper-v/new-vm

# Create VM with new VHD
$vm = New-VM -Name "TestVM" `
    -MemoryStartupBytes 2GB `
    -NewVHDPath "C:\VMs\TestVM.vhdx" `
    -NewVHDSizeBytes 60GB `
    -Generation 2 `
    -SwitchName "SimpleLab"

# Configure processor count
Set-VMProcessor -VMName "TestVM" -Count 2

# Configure static memory
Set-VMMemory -VMName "TestVM" -StartupBytes 2GB -DynamicMemoryEnabled $false
```

### Attach ISO to Existing VM
```powershell
# Source: Microsoft Add-VMDvdDrive documentation
# URL: https://learn.microsoft.com/en-us/powershell/module/hyper-v/add-vmdvddrive

Add-VMDvdDrive -VMName "TestVM" -Path "C:\ISOs\Server2019.iso"
```

### Check if VM Exists
```powershell
# Source: Microsoft Get-VM documentation
# Pattern: Idempotent VM creation

$vm = Get-VM -Name "TestVM" -ErrorAction SilentlyContinue
if ($vm) {
    Write-Host "VM exists"
} else {
    Write-Host "VM does not exist"
}
```

### Remove VM with Cleanup
```powershell
# Source: Microsoft Remove-VM documentation
# Pattern: Aggressive cleanup from existing code

# Stop VM if running
if ((Get-VM -Name "TestVM").State -ne 'Off') {
    Stop-VM -Name "TestVM" -TurnOff -Force
}

# Remove VM
Remove-VM -Name "TestVM" -Force
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Generation 1 VMs (BIOS) | Generation 2 VMs (UEFI) | Windows Server 2016 / Windows 11 | Gen2 required for modern Windows, Secure Boot support |
| Dynamic memory default | Static memory recommended | Ongoing best practice | Static memory more predictable for DCs, no performance issues |
| Separate ISO attachment | Integrated with VM creation | PowerShell 5.1+ | Simplified workflow, single operation |
| Manual VM cleanup | Automated stale VM removal | Ongoing pattern | Idempotent operations, reliable rebuilds |

**Deprecated/outdated:**
- **Generation 1 VMs for modern Windows:** Use Gen2 for Server 2016+ and Windows 11+
- **Dynamic memory for domain controllers:** Can cause performance issues during promotion
- **Separate disk creation scripts:** New-VM handles VHD creation automatically

## Open Questions

1. **VHD Storage Location**
   - What we know: Hyper-V default path is typically C:\Users\Public\Documents\Hyper-V\Virtual Hard Disks
   - What's unclear: Whether to use default path or custom path (e.g., C:\Lab\VMs)
   - Recommendation: Use custom path C:\Lab\VMs for easier cleanup and separation from user data

2. **VM Removal Strategy**
   - What we know: Remove-VM can delete VMs, but VHD files may remain
   - What's unclear: Whether to delete VHD files on VM removal (preserving templates)
   - Recommendation: Keep VHD files by default, provide -DeleteVHD switch for cleanup

3. **ISO Handling After Boot**
   - What we know: ISO attached during creation enables boot
   - What's unclear: Whether to detach ISO after first boot (prevents reboot loops)
   - Recommendation: Phase 5 (Domain Configuration) should handle ISO detachment after install

## Sources

### Primary (HIGH confidence)
- **Microsoft Learn - New-VM (Hyper-V)** - Official cmdlet documentation for VM creation
- **Microsoft Learn - Set-VMProcessor (Hyper-V)** - Official cmdlet documentation for processor configuration
- **Microsoft Learn - Set-VMMemory (Hyper-V)** - Official cmdlet documentation for memory configuration
- **Microsoft Learn - Add-VMDvdDrive (Hyper-V)** - Official cmdlet documentation for ISO attachment
- **Microsoft Learn - Get-VM (Hyper-V)** - Official cmdlet documentation for VM queries
- **Existing codebase** - Deploy.ps1, Lab-Common.ps1 for VM provisioning patterns

### Secondary (MEDIUM confidence)
- **Microsoft Learn - Hyper-V PowerShell Overview** - Comprehensive Hyper-V automation guide
- **AutomatedLab GitHub Repository** - Source code review for complexity assessment (alternative not chosen)

### Tertiary (LOW confidence)
- **Community blog posts on Hyper-V automation** - Used for supplementary patterns only, verified against official docs

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All built-in Hyper-V module features, official documentation available
- Architecture: HIGH - Based on Microsoft documentation and existing codebase patterns
- Pitfalls: HIGH - All verified against official documentation, existing code, and common issues

**Research date:** 2026-02-09
**Valid until:** 2026-03-09 (30 days - Hyper-V fundamentals are stable)

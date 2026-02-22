# Coding Conventions

**Analysis Date:** 2025-02-21

## Naming Patterns

**Files:**
- PascalCase: `LabConfig.cs`, `HyperVService.cs`, `DashboardViewModel.cs`
- XAML files match code-behind: `DashboardView.xaml` with `DashboardView.xaml.cs`
- Suffix conventions: `*ViewModel.cs`, `*Service.cs`, `*Dialog.cs`, `*View.xaml` for UI files
- File path example: `/mnt/c/projects/AutomatedLab/OpenCodeLab-v2/Models/LabConfig.cs`

**Classes & Types:**
- PascalCase: `LabConfig`, `VirtualMachine`, `HyperVService`, `DashboardViewModel`
- Model classes: `LabConfig`, `NetConfig`, `VMDefinition`, `VirtualMachine`
- ViewModels inherit from `ObservableObject`: `DashboardViewModel`, `ActionsViewModel`, `SettingsViewModel`
- Service classes named descriptively: `HyperVService`, `LabDeploymentService`
- Internal classes prefixed with `internal`: `PowerShellResult` (`/mnt/c/projects/AutomatedLab/OpenCodeLab-v2/Services/LabDeploymentService.cs`, line 386)

**Properties:**
- PascalCase for public properties: `LabName`, `VirtualMachines`, `SelectedVM`, `DeploymentProgress`
- Auto-properties with backing fields: `public string LabName { get; set; } = "MyLab"` in `LabConfig.cs` (line 7)
- Computed properties as read-only: `public bool CanStart => State is "Off" or "Saved"` in `VirtualMachine.cs` (line 28)
- Nullable reference types enabled: `public string? LabPath { get; set; }` in `LabConfig.cs` (line 8)

**Variables & Fields:**
- Private fields use camelCase with underscore prefix: `_selectedVM`, `_deploymentService`, `_vms`
- Field example: `private VirtualMachine? _selectedVM;` in `DashboardViewModel.cs` (line 15)
- Local variables in camelCase: `vmName`, `startInfo`, `script`
- Constants in UPPER_SNAKE_CASE: `HyperVNamespace`, `DefaultLabSources`, `LogDirectory`
- Const field example: `private const string HyperVNamespace = @"root\virtualization\v2"` in `HyperVService.cs` (line 12)

**Methods:**
- PascalCase: `GetVirtualMachinesAsync()`, `StartVMAsync()`, `ExecuteVMStateChangeAsync()`
- Async methods end with `Async`: `GetVirtualMachinesAsync()` in `HyperVService.cs` (line 14), `RefreshAsync()` in `DashboardViewModel.cs` (line 78)
- Command methods end with suffix: `RefreshAsync()`, `StartSelectedAsync()`, `DeployLabAsync()`
- Private helper methods: `GetStateText()`, `GetVMMemoryGB()`, `ValidateConfigInputs()`
- Methods with side effects are commands: `async Task DeployLabAsync()`, `async Task RemoveLabAsync()`

## Code Style

**Formatting:**
- No explicit formatter configured (no .editorconfig, .prettierrc, or EditorConfig file detected)
- C# file-scoped namespaces used: `namespace OpenCodeLab.Models;` (file-scoped syntax) in `LabConfig.cs` (line 3)
- Default indentation: 4 spaces (standard .NET)
- Consistent brace style: Opening braces on same line (K&R style)

**Linting:**
- Nullable reference types enabled: `<Nullable>enable</Nullable>` in `.csproj`
- No explicit analyzer configuration files found
- Code follows basic C# style guidelines implicitly

**Line Length:**
- Variable, no strict limit enforced
- Longest observed lines around 140-160 characters

## Import Organization

**Order:**
1. System namespaces: `using System;`, `using System.Collections.ObjectModel;`
2. System.* extended: `using System.Management;`, `using System.Text;`
3. Project namespaces: `using OpenCodeLab.Models;`, `using OpenCodeLab.Services;`
4. Windows/UI namespaces: `using System.Windows;`, `using Microsoft.Win32;`

**Example from HyperVService.cs (lines 1-8):**
```csharp
using System;
using System.Collections.Generic;
using System.Linq;
using System.Management;
using System.Threading.Tasks;
using OpenCodeLab.Models;

namespace OpenCodeLab.Services;
```

**Path Aliases:**
- No custom path aliases configured
- Full namespace paths used throughout

## Error Handling

**Patterns:**
- Try-catch blocks with swallowed exceptions (fire-and-forget logging): `catch { }` or `catch (Exception ex) { }`
- Example from `HyperVService.cs` line 40: `catch (Exception ex) { System.Diagnostics.Debug.WriteLine($"Error: {ex.Message}"); }`
- Broad catch-all approach in UI code: `catch { }` in `ActionsViewModel.cs` lines 86, 114, 128
- Safe property access with null coalescing: `name = vm["ElementName"]?.ToString() ?? "Unknown"` in `HyperVService.cs` (line 26)
- Return false on error in async operations: `return await ExecuteVMStateChangeAsync(vmName, 3);` with error handling in `HyperVService.cs` (line 45)

**Exception Logging:**
- `System.Diagnostics.Debug.WriteLine()` for debug output in `HyperVService.cs` (line 40)
- Custom logging via `LogError()` method in `ActionsViewModel.cs` (lines 131-142)
- `App.xaml.cs` captures unhandled exceptions and writes to crash logs (lines 39-55)

**Validation:**
- Input validation before processing: `if (!ValidateConfigInputs(config, log))` in `LabDeploymentService.cs` (line 28)
- Regex validation for names: `if (!Regex.IsMatch(config.LabName, @"^[a-zA-Z0-9\-_\s]+$"))` in `LabDeploymentService.cs` (line 318)
- Null checks before operations: `if (SelectedVM == null) return;` in `DashboardViewModel.cs` (line 87)
- Collection empty checks: `if (VirtualMachines.Count == 0) return;` in `DashboardViewModel.cs` (line 115)

## Logging

**Framework:**
- `System.Diagnostics.Debug` for debug output in services
- Custom `WriteToLog()` method for deployment logs in `ActionsViewModel.cs` (lines 118-129)
- File-based logging to `C:\LabSources\Logs` directory
- Timestamped log entries: `$"[{DateTime.Now:HH:mm:ss}] {message}"` in `ActionsViewModel.cs` (line 126)

**Patterns:**
- Log deployment progress: `$"[{e.Percent}%] {e.Message}"` in `ActionsViewModel.cs` (line 54)
- Log state changes: `LogOutput += $"Created new lab: {lab.LabName} with {lab.VMs.Count} VM(s)"` in `ActionsViewModel.cs` (line 205)
- Error logging with context: `LogError("Error loading recent labs", ex)` in `ActionsViewModel.cs` (line 189)
- Exception details logged: Inner exception messages included in error output

## Comments

**When to Comment:**
- XML documentation comments for public methods: `/// <summary>` blocks in `NewLabDialog.xaml.cs` (lines 115-117)
- Inline comments for non-obvious logic
- Default values noted in configuration: `// Default, could be made configurable via UI` in `NewLabDialog.xaml.cs` (line 111)
- Hints for users: `// Tip: Leave empty to create VM without OS media.` in `NewLabDialog.xaml.cs` (line 345)
- TODO-style comments: `// Check environment variable first` in `ActionsViewModel.cs` (line 294)

**JSDoc/TSDoc:**
- C# uses `/// <summary>` XML documentation syntax
- Example from `NewLabDialog.xaml.cs` (lines 115-117):
```csharp
/// <summary>
/// Dialog for prompting the user for admin password at deployment time
/// </summary>
public class PasswordDialog : Window
```
- Not consistently applied across all classes
- Primarily used for public dialog classes

## Function Design

**Size:**
- Methods range from 1-2 lines (simple commands) to 50+ lines (complex operations like `DeployLabAsync()`)
- Average method size: 20-30 lines
- Large method example: `DeployLabAsync()` in `ActionsViewModel.cs` (lines 282-369) - 88 lines with business logic

**Parameters:**
- Minimal parameters: `public async Task<bool> StartVMAsync(string vmName)` in `HyperVService.cs` (line 44)
- Optional parameters with defaults: `public async Task<bool> RemoveVMAsync(string vmName, bool deleteDisk = true)` in `HyperVService.cs` (line 54)
- Action callbacks for logging: `DeployLabAsync(LabConfig config, Action<string>? log = null)` in `LabDeploymentService.cs` (line 21)
- Closure pattern for state sharing: Anonymous lambdas in command handlers

**Return Values:**
- Boolean for success/failure: `Task<bool> StartVMAsync()` in `HyperVService.cs` (line 44)
- Collections for lists: `Task<List<VirtualMachine>> GetVirtualMachinesAsync()` in `HyperVService.cs` (line 14)
- Objects for complex results: `VirtualMachine` model returned with state/metrics
- Void for event handlers and fire-and-forget operations: `private async void Execute(object? parameter)` in `AsyncCommand.cs` (line 21)

## Module Design

**Exports:**
- Public classes for models: `LabConfig`, `VirtualMachine`, `VMDefinition`, `NetworkConfig`
- Public services: `HyperVService`, `LabDeploymentService`
- Public ViewModels: `DashboardViewModel`, `ActionsViewModel`, `SettingsViewModel`
- Internal helpers: `PowerShellResult` marked as `internal` in `LabDeploymentService.cs` (line 386)
- File path: `/mnt/c/projects/AutomatedLab/OpenCodeLab-v2/Services/LabDeploymentService.cs`

**Barrel Files:**
- No barrel exports (index.ts/cs) used
- Direct imports from specific namespaces: `using OpenCodeLab.Models;`, `using OpenCodeLab.Services;`

**Dependency Injection:**
- Services instantiated directly in ViewModels: `private readonly HyperVService _hvService = new();` in `DashboardViewModel.cs` (line 13)
- No dependency injection container (no IServiceProvider, no constructor injection)
- Tightly coupled design: Services created in-place where needed
- Models passed by reference: `LabConfig` passed to services for deployment

**Observables & Events:**
- WPF ObservableCollection for UI binding: `public ObservableCollection<VirtualMachine> VirtualMachines { get; } = new();` in `DashboardViewModel.cs` (line 17)
- INotifyPropertyChanged for ViewModel state: Inherited from `ObservableObject` base class (implemented in `/mnt/c/projects/AutomatedLab/OpenCodeLab-v2/ViewModels/ObservableObject.cs`)
- Event-based progress reporting: `public event EventHandler<DeploymentProgressArgs>? Progress;` in `LabDeploymentService.cs` (line 16)

---

*Convention analysis: 2025-02-21*

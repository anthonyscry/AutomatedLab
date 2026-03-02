using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using OpenCodeLab.Models;
using OpenCodeLab.Services;

namespace OpenCodeLab.ViewModels
{
    /// <summary>
    /// ViewModel for Infrastructure-as-Code export functionality
    /// </summary>
    public class IaCExportViewModel : ObservableObject
    {
        private readonly ExtendedDriftDetectionService _driftService = new();
        
        private string _labName = string.Empty;
        private bool _isLoading;
        private string _statusMessage = "Ready";
        private string _selectedFormat = "Terraform";
        private string _outputPath = @"C:\LabSources\IaC";
        private string _previewContent = string.Empty;
        private ExtendedDriftBaseline? _baseline;

        public ObservableCollection<ExtendedDriftBaseline> Baselines { get; } = new();
        public ObservableCollection<IaCVariable> Variables { get; } = new();

        public AsyncCommand LoadCommand { get; }
        public AsyncCommand ExportCommand { get; }
        public AsyncCommand PreviewCommand { get; }
        public AsyncCommand CopyCommand { get; }
        public AsyncCommand SaveCommand { get; }

        public string LabName
        {
            get => _labName;
            set { _labName = value; OnPropertyChanged(); }
        }

        public bool IsLoading
        {
            get => _isLoading;
            set { _isLoading = value; OnPropertyChanged(); RefreshCommands(); }
        }

        public string StatusMessage
        {
            get => _statusMessage;
            set { _statusMessage = value; OnPropertyChanged(); }
        }

        public string SelectedFormat
        {
            get => _selectedFormat;
            set { _selectedFormat = value; OnPropertyChanged(); }
        }

        public string OutputPath
        {
            get => _outputPath;
            set { _outputPath = value; OnPropertyChanged(); }
        }

        public string PreviewContent
        {
            get => _previewContent;
            set { _previewContent = value; OnPropertyChanged(); OnPropertyChanged(nameof(HasPreview)); }
        }

        public bool HasPreview => !string.IsNullOrWhiteSpace(PreviewContent);

        public ExtendedDriftBaseline? SelectedBaseline
        {
            get => _baseline;
            set { _baseline = value; OnPropertyChanged(); }
        }

        public string[] FormatOptions { get; } = new[] { "Terraform", "Ansible", "Bicep", "ARMTemplate", "Docker" };

        public IaCExportViewModel()
        {
            LoadCommand = new AsyncCommand(LoadAsync, () => !IsLoading);
            ExportCommand = new AsyncCommand(ExportAsync, () => !IsLoading && !string.IsNullOrWhiteSpace(LabName) && HasPreview);
            PreviewCommand = new AsyncCommand(PreviewAsync, () => !IsLoading && !string.IsNullOrWhiteSpace(LabName));
            CopyCommand = new AsyncCommand(CopyToClipboardAsync, () => HasPreview);
            SaveCommand = new AsyncCommand(SaveAsync, () => !IsLoading && HasPreview);
        }

        public async Task LoadAsync()
        {
            IsLoading = true;
            StatusMessage = "Loading baselines...";

            try
            {
                var baselines = await _driftService.ListBaselinesAsync(LabName);
                Baselines.Clear();
                foreach (var baseline in baselines.OrderByDescending(b => b.CreatedAt))
                    Baselines.Add(baseline);

                StatusMessage = $"Loaded {Baselines.Count} baseline(s)";
            }
            catch (Exception ex)
            {
                StatusMessage = $"Error loading: {ex.Message}";
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task PreviewAsync()
        {
            if (string.IsNullOrWhiteSpace(LabName))
                return;

            IsLoading = true;
            StatusMessage = "Generating preview...";

            try
            {
                var baseline = SelectedBaseline ?? Baselines.FirstOrDefault();
                if (baseline == null)
                {
                    // Load latest baseline
                    var baselines = await _driftService.ListBaselinesAsync(LabName);
                    baseline = baselines.FirstOrDefault(b => b.IsGoldenBaseline) ?? baselines.FirstOrDefault();
                }

                if (baseline == null)
                {
                    StatusMessage = "No baseline found. Capture a baseline first.";
                    return;
                }

                PreviewContent = SelectedFormat switch
                {
                    "Terraform" => GenerateTerraform(baseline),
                    "Ansible" => GenerateAnsible(baseline),
                    "Bicep" => GenerateBicep(baseline),
                    "ARMTemplate" => GenerateArmTemplate(baseline),
                    "Docker" => GenerateDocker(baseline),
                    _ => GenerateTerraform(baseline)
                };

                StatusMessage = $"Generated {SelectedFormat} preview";
            }
            catch (Exception ex)
            {
                StatusMessage = $"Error generating preview: {ex.Message}";
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task ExportAsync()
        {
            if (!HasPreview)
            {
                await PreviewAsync();
                if (!HasPreview) return;
            }

            IsLoading = true;
            StatusMessage = "Exporting...";

            try
            {
                var fileName = $"{LabName.ToLowerInvariant()}-{SelectedFormat.ToLowerInvariant()}";
                var extension = SelectedFormat switch
                {
                    "Terraform" => ".tf",
                    "Ansible" => ".yml",
                    "Bicep" => ".bicep",
                    "ARMTemplate" => ".json",
                    "Docker" => ".yml",
                    _ => ".txt"
                };

                Directory.CreateDirectory(OutputPath);
                var filePath = Path.Combine(OutputPath, fileName + extension);
                await File.WriteAllTextAsync(filePath, PreviewContent);
                StatusMessage = $"Exported to: {filePath}";
            }
            catch (Exception ex)
            {
                StatusMessage = $"Export failed: {ex.Message}";
            }
            finally
            {
                IsLoading = false;
            }
        }

        private async Task CopyToClipboardAsync()
        {
            if (!HasPreview) return;

            try
            {
                System.Windows.Clipboard.SetText(PreviewContent);
                StatusMessage = "Copied to clipboard";
                await Task.CompletedTask;
            }
            catch (Exception ex)
            {
                StatusMessage = $"Copy failed: {ex.Message}";
            }
        }

        private async Task SaveAsync()
        {
            await ExportAsync();
        }

        private string GenerateTerraform(ExtendedDriftBaseline baseline)
        {
            var sb = new StringBuilder();
            sb.AppendLine("# Auto-generated Terraform configuration for OpenCodeLab");
            sb.AppendLine($"# Lab: {LabName}");
            sb.AppendLine($"# Generated: {DateTime.UtcNow:yyyy-MM-dd HH:mm}");
            sb.AppendLine($"# Baseline: {baseline.Name} ({baseline.Id})");
            sb.AppendLine();

            // Provider configuration
            sb.AppendLine("provider \"azurerm\" {");
            sb.AppendLine("  features {}");
            sb.AppendLine("}");
            sb.AppendLine();

            // Variables
            sb.AppendLine("variable \"resource_group_name\" {");
            sb.AppendLine("  type        = string");
            sb.AppendLine($"  default     = \"{LabName}-rg\"");
            sb.AppendLine("}");
            sb.AppendLine();

            // Resource group
            sb.AppendLine("resource \"azurerm_resource_group\" \"lab\" {");
            sb.AppendLine("  name     = var.resource_group_name");
            sb.AppendLine("  location = \"East US\"");
            sb.AppendLine("}");
            sb.AppendLine();

            // Virtual network
            sb.AppendLine("resource \"azurerm_virtual_network\" \"lab\" {");
            sb.AppendLine($"  name                = \"{LabName}-vnet\"");
            sb.AppendLine("  address_space       = [\"10.0.0.0/16\"]");
            sb.AppendLine("  location            = azurerm_resource_group.lab.location");
            sb.AppendLine("  resource_group_name = azurerm_resource_group.lab.name");
            sb.AppendLine("}");
            sb.AppendLine();

            sb.AppendLine("resource \"azurerm_subnet\" \"lab\" {");
            sb.AppendLine($"  name                 = \"{LabName}-subnet\"");
            sb.AppendLine("  resource_group_name  = azurerm_resource_group.lab.name");
            sb.AppendLine("  virtual_network_name = azurerm_virtual_network.lab.name");
            sb.AppendLine("  address_prefixes     = [\"10.0.1.0/24\"]");
            sb.AppendLine("}");
            sb.AppendLine();

            // VMs
            int vmCount = 0;
            foreach (var vm in baseline.VmBaselines)
            {
                vmCount++;
                sb.AppendLine($"resource \"azurerm_windows_virtual_machine\" \"{vm.VmName}\" {{");
                sb.AppendLine($"  name                = \"{vm.VmName}\"");
                sb.AppendLine("  resource_group_name = azurerm_resource_group.lab.name");
                sb.AppendLine("  location            = azurerm_resource_group.lab.location");
                sb.AppendLine($"  size                = \"Standard_D2s_v3\"");
                sb.AppendLine();
                sb.AppendLine("  network_interface_ids = [");
                sb.AppendLine($"    azurerm_network_interface.{vm.VmName}.id,");
                sb.AppendLine("  ]");
                sb.AppendLine();
                sb.AppendLine("  os_disk {");
                sb.AppendLine("    caching              = \"ReadWrite\"");
                sb.AppendLine("    storage_account_type = \"Standard_LRS\"");
                sb.AppendLine("  }");
                sb.AppendLine();
                sb.AppendLine("  source_image_reference {");
                sb.AppendLine("    publisher = \"MicrosoftWindowsServer\"");
                sb.AppendLine("    offer     = \"WindowsServer\"");
                sb.AppendLine("    sku       = \"2022-datacenter-azure-edition\"");
                sb.AppendLine("    version   = \"latest\"");
                sb.AppendLine("  }");
                sb.AppendLine("}");
                sb.AppendLine();

                sb.AppendLine($"resource \"azurerm_network_interface\" \"{vm.VmName}\" {{");
                sb.AppendLine($"  name                = \"{vm.VmName}-nic\"");
                sb.AppendLine("  resource_group_name = azurerm_resource_group.lab.name");
                sb.AppendLine("  location            = azurerm_resource_group.lab.location");
                sb.AppendLine();
                sb.AppendLine("  ip_configuration {");
                sb.AppendLine("    name                          = \"internal\"");
                sb.AppendLine($"    subnet_id                     = azurerm_subnet.lab.id");
                sb.AppendLine($"    private_ip_address_allocation = \"Dynamic\"");
                sb.AppendLine("  }");
                sb.AppendLine("}");
                sb.AppendLine();
            }

            sb.AppendLine($"# Total VMs: {vmCount}");
            return sb.ToString();
        }

        private string GenerateAnsible(ExtendedDriftBaseline baseline)
        {
            var sb = new StringBuilder();
            sb.AppendLine("---");
            sb.AppendLine("# Auto-generated Ansible playbook for OpenCodeLab");
            sb.AppendLine($"# Lab: {LabName}");
            sb.AppendLine($"# Generated: {DateTime.UtcNow:yyyy-MM-dd HH:mm}");
            sb.AppendLine($"# Baseline: {baseline.Name}");
            sb.AppendLine();

            sb.AppendLine("- name: Deploy OpenCodeLab VMs");
            sb.AppendLine($"  hosts: {LabName}");
            sb.AppendLine("  gather_facts: no");
            sb.AppendLine("  tasks:");
            sb.AppendLine();

            int taskNum = 1;
            foreach (var vm in baseline.VmBaselines)
            {
                sb.AppendLine($"    - name: Ensure VM {vm.VmName} is configured");
                sb.AppendLine("      win_shell: |");
                sb.AppendLine($"        Write-Host \"Configuring {vm.VmName}\"");
                sb.AppendLine($"        # Memory: {vm.MemoryGB}GB");
                sb.AppendLine($"        # Processors: {vm.ProcessorCount}");
                sb.AppendLine();
                taskNum++;
            }

            sb.AppendLine("  vars:");
            sb.AppendLine($"    lab_name: {LabName}");
            sb.AppendLine("    ansible_connection: winrm");
            sb.AppendLine("    ansible_winrm_server_cert_validation: ignore");
            sb.AppendLine("...");

            return sb.ToString();
        }

        private string GenerateBicep(ExtendedDriftBaseline baseline)
        {
            var sb = new StringBuilder();
            sb.AppendLine("// Auto-generated Bicep configuration for OpenCodeLab");
            sb.AppendLine($"// Lab: {LabName}");
            sb.AppendLine($"// Generated: {DateTime.UtcNow:yyyy-MM-dd HH:mm}");
            sb.AppendLine($"// Baseline: {baseline.Name}");
            sb.AppendLine();

            sb.AppendLine("param location string = resourceGroup().location");
            sb.AppendLine($"param labName string = '{LabName}'");
            sb.AppendLine();

            sb.AppendLine("resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {");
            sb.AppendLine("  name: '${labName}-vnet'");
            sb.AppendLine("  location: location");
            sb.AppendLine("  properties: {");
            sb.AppendLine("    addressSpace: {");
            sb.AppendLine("      addressPrefixes: ['10.0.0.0/16']");
            sb.AppendLine("    }");
            sb.AppendLine("    subnets: [");
            sb.AppendLine("      {");
            sb.AppendLine("        name: 'default'");
            sb.AppendLine("        properties: {");
            sb.AppendLine("          addressPrefix: '10.0.1.0/24'");
            sb.AppendLine("        }");
            sb.AppendLine("      }");
            sb.AppendLine("    ]");
            sb.AppendLine("  }");
            sb.AppendLine("}");
            sb.AppendLine();

            foreach (var vm in baseline.VmBaselines)
            {
                sb.AppendLine($"// VM: {vm.VmName}");
                sb.AppendLine($"// Memory: {vm.MemoryGB}GB, CPUs: {vm.ProcessorCount}");
                sb.AppendLine();
            }

            return sb.ToString();
        }

        private string GenerateArmTemplate(ExtendedDriftBaseline baseline)
        {
            var template = new
            {
                schema = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
                contentVersion = "1.0.0.0",
                parameters = new
                {
                    location = new { type = "string", defaultValue = "[resourceGroup().location]" },
                    labName = new { type = "string", defaultValue = LabName }
                },
                resources = new object[] { }
            };

            return JsonSerializer.Serialize(template, new JsonSerializerOptions { WriteIndented = true });
        }

        private string GenerateDocker(ExtendedDriftBaseline baseline)
        {
            var sb = new StringBuilder();
            sb.AppendLine("# Auto-generated Docker Compose for OpenCodeLab");
            sb.AppendLine($"# Lab: {LabName}");
            sb.AppendLine($"# Generated: {DateTime.UtcNow:yyyy-MM-dd HH:mm}");
            sb.AppendLine();

            sb.AppendLine("version: '3.8'");
            sb.AppendLine();
            sb.AppendLine("services:");

            foreach (var vm in baseline.VmBaselines)
            {
                sb.AppendLine($"  {vm.VmName.ToLowerInvariant()}:");
                sb.AppendLine("    image: mcr.microsoft.com/windows/servercore:ltsc2022");
                sb.AppendLine($"    hostname: {vm.VmName}");
                sb.AppendLine("    mem_limit: 2g");
                sb.AppendLine("    cpus: 2");
                sb.AppendLine();
            }

            return sb.ToString();
        }

        private void RefreshCommands()
        {
            LoadCommand.RaiseCanExecuteChanged();
            ExportCommand.RaiseCanExecuteChanged();
            PreviewCommand.RaiseCanExecuteChanged();
            CopyCommand.RaiseCanExecuteChanged();
            SaveCommand.RaiseCanExecuteChanged();
        }
    }

    /// <summary>
    /// Represents an IaC variable
    /// </summary>
    public class IaCVariable
    {
        public string Name { get; set; } = string.Empty;
        public string Type { get; set; } = "string";
        public string DefaultValue { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
    }
}

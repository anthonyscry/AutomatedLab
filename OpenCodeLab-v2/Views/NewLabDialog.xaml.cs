using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using OpenCodeLab.Models;

namespace OpenCodeLab.Views;

public partial class NewLabDialog : Window
{
    private List<VMDefinition> _vms = new();

    public NewLabDialog()
    {
        InitializeComponent();
        VMListBox.SelectionChanged += (s, e) =>
        {
            EditVMButton.IsEnabled = VMListBox.SelectedItem != null;
            DeleteVMButton.IsEnabled = VMListBox.SelectedItem != null;
        };
    }

    private void AddVMButton_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new NewVMDialog(_vms);
        if (dialog.ShowDialog() == true)
        {
            _vms.Add(dialog.GetVMDefinition());
            RefreshVMList();
        }
    }

    private void EditVMButton_Click(object sender, RoutedEventArgs e)
    {
        if (VMListBox.SelectedItem is not VMDefinition selectedVM) return;

        var dialog = new NewVMDialog(_vms, selectedVM);
        if (dialog.ShowDialog() == true)
        {
            var index = _vms.IndexOf(selectedVM);
            if (index >= 0)
            {
                _vms[index] = dialog.GetVMDefinition();
                RefreshVMList();
            }
        }
    }

    private void DeleteVMButton_Click(object sender, RoutedEventArgs e)
    {
        if (VMListBox.SelectedItem is not VMDefinition selectedVM) return;

        var result = MessageBox.Show(
            $"Delete VM '{selectedVM.Name}' from the lab configuration?",
            "Confirm Delete",
            MessageBoxButton.YesNo,
            MessageBoxImage.Question);

        if (result == MessageBoxResult.Yes)
        {
            _vms.Remove(selectedVM);
            RefreshVMList();
        }
    }

    private void RefreshVMList()
    {
        VMListBox.ItemsSource = null;
        VMListBox.ItemsSource = _vms;
    }

    private void CreateButton_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(LabNameBox.Text))
        {
            MessageBox.Show("Please enter a lab name.", "Validation Error", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (_vms.Count == 0)
        {
            var result = MessageBox.Show(
                "You haven't added any virtual machines to this lab. Continue anyway?",
                "No VMs Defined",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question);
            if (result == MessageBoxResult.No) return;
        }
        DialogResult = true;
        Close();
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }

    public LabConfig GetLabConfig() => new()
    {
        LabName = LabNameBox.Text,
        Description = DescriptionBox.Text,
        Network = new NetworkConfig
        {
            SwitchName = SwitchNameBox.Text,
            SwitchType = ((ComboBoxItem)SwitchTypeBox.SelectedItem).Content.ToString()!
        },
        VMs = new List<VMDefinition>(_vms),
        DomainName = "contoso.com" // Default, could be made configurable via UI
    };
}

/// <summary>
/// Dialog for prompting the user for admin password at deployment time
/// </summary>
public class PasswordDialog : Window
{
    public string Password { get; private set; } = string.Empty;

    public PasswordDialog(string labName)
    {
        Title = "Deployment Credentials";
        Width = 400;
        Height = 200;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ResizeMode = ResizeMode.NoResize;

        var grid = new Grid { Margin = new Thickness(20) };
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        // Message
        var message = new TextBlock
        {
            Text = $"Enter admin password for '{labName}':",
            FontWeight = FontWeights.SemiBold,
            Margin = new Thickness(0, 0, 0, 15)
        };
        grid.Children.Add(message);
        Grid.SetRow(message, 0);

        // Password input panel
        var panel = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        var label = new TextBlock
        {
            Text = "Password:",
            Margin = new Thickness(0, 0, 0, 5)
        };
        var passwordBox = new PasswordBox
        {
            Width = 250,
            Height = 32
        };

        var envHint = new TextBlock
        {
            Text = "Or set OPENCODELAB_ADMIN_PASSWORD environment variable",
            FontSize = 10,
            Foreground = System.Windows.Media.Brushes.Gray,
            Margin = new Thickness(0, 10, 0, 0)
        };

        panel.Children.Add(label);
        panel.Children.Add(passwordBox);
        panel.Children.Add(envHint);
        grid.Children.Add(panel);
        Grid.SetRow(panel, 1);

        // Buttons
        var buttonPanel = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 15, 0, 0)
        };

        var cancelBtn = new Button { Content = "Cancel", Width = 80, Height = 32, Margin = new Thickness(5) };
        cancelBtn.Click += (s, e) => { DialogResult = false; Close(); };

        var okBtn = new Button
        {
            Content = "Deploy",
            Width = 80,
            Height = 32,
            Margin = new Thickness(5),
            Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0, 120, 212)),
            Foreground = System.Windows.Media.Brushes.White
        };
        okBtn.Click += (s, e) =>
        {
            Password = passwordBox.Password;
            if (string.IsNullOrEmpty(Password))
            {
                // Allow empty - will check environment variable later
            }
            DialogResult = true;
            Close();
        };

        buttonPanel.Children.Add(cancelBtn);
        buttonPanel.Children.Add(okBtn);
        grid.Children.Add(buttonPanel);
        Grid.SetRow(buttonPanel, 2);

        Content = grid;
        passwordBox.Focus();
    }

    public static string PromptForPassword(Window owner, string labName)
    {
        var dialog = new PasswordDialog(labName);
        dialog.Owner = owner;
        if (dialog.ShowDialog() == true)
        {
            return dialog.Password;
        }
        return string.Empty;
    }
}

/// <summary>
/// Dialog for adding/editing individual VMs with dropdown roles and ISO selection
/// </summary>
public class NewVMDialog : Window
{
    private TextBox NameBox = new() { Text = "VM1" };
    private ComboBox RoleBox = new();
    private TextBox MemoryBox = new() { Text = "2" };
    private TextBox CPUBox = new() { Text = "2" };
    private TextBox DiskBox = new() { Text = "40" };
    private TextBox ISOPathBox = new() { IsReadOnly = true };
    private Button BrowseButton = new() { Content = "Browse...", Width = 80 };
    private List<VMDefinition> _existingVMs = new();

    private static readonly string[] CommonRoles = new[]
    {
        "DC", "FileServer", "WebServer", "SQLServer", "DHCP", "DNS",
        "CA", "RRAS", "WSUS", "SCCM", "Client", "MemberServer"
    };

    // Role-based VM naming patterns
    private static readonly Dictionary<string, string> RoleNamePrefixes = new(StringComparer.OrdinalIgnoreCase)
    {
        { "DC", "DC" },
        { "Client", "WS" },
        { "MemberServer", "MS" },
        { "FileServer", "FS" },
        { "WebServer", "WEB" },
        { "SQLServer", "SQL" },
        { "DHCP", "DHCP" },
        { "DNS", "DNS" },
        { "CA", "CA" },
        { "RRAS", "RRAS" },
        { "WSUS", "WSUS" },
        { "SCCM", "SCCM" }
    };

    public NewVMDialog(List<VMDefinition>? existingVMs = null, VMDefinition? existingVM = null)
    {
        if (existingVMs != null) _existingVMs = new List<VMDefinition>(existingVMs);


        Title = existingVM == null ? "Add Virtual Machine" : "Edit Virtual Machine";
        Width = 450;
        Height = existingVM == null ? 520 : 520;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ResizeMode = ResizeMode.NoResize;

        var grid = new Grid { Margin = new Thickness(20) };
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var panel = new StackPanel();

        // VM Name
        panel.Children.Add(CreateLabel("VM Name:"));
        panel.Children.Add(NameBox);
        panel.Children.Add(new SpacerControl { Height = 10 });

        // Role (ComboBox)
        panel.Children.Add(CreateLabel("Role:"));
        RoleBox.Items.Clear();
        foreach (var role in CommonRoles)
            RoleBox.Items.Add(role);
        RoleBox.SelectedIndex = 0;
        panel.Children.Add(RoleBox);
        // Auto-generate VM name when role changes
        RoleBox.SelectionChanged += (s, e) => GenerateVMName();
        panel.Children.Add(new SpacerControl { Height = 10 });

        // Hardware Settings in Grid
        var hwGrid = new Grid();
        hwGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        hwGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        hwGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var memPanel = new StackPanel();
        memPanel.Children.Add(CreateLabel("RAM (GB):"));
        MemoryBox.Width = 80;
        memPanel.Children.Add(MemoryBox);
        hwGrid.Children.Add(memPanel);
        Grid.SetColumn(memPanel, 0);

        var cpuPanel = new StackPanel();
        cpuPanel.Children.Add(CreateLabel("CPU Cores:"));
        CPUBox.Width = 80;
        cpuPanel.Children.Add(CPUBox);
        hwGrid.Children.Add(cpuPanel);
        Grid.SetColumn(cpuPanel, 1);

        var diskPanel = new StackPanel();
        diskPanel.Children.Add(CreateLabel("Disk (GB):"));
        DiskBox.Width = 80;
        diskPanel.Children.Add(DiskBox);
        hwGrid.Children.Add(diskPanel);
        Grid.SetColumn(diskPanel, 2);

        panel.Children.Add(hwGrid);
        panel.Children.Add(new SpacerControl { Height = 10 });

        // ISO Path
        panel.Children.Add(CreateLabel("ISO Path (Installation Media):"));
        var isoGrid = new Grid();
        isoGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        isoGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        ISOPathBox.Margin = new Thickness(0, 0, 5, 0);
        isoGrid.Children.Add(ISOPathBox);
        isoGrid.Children.Add(BrowseButton);
        Grid.SetColumn(BrowseButton, 1);
        panel.Children.Add(isoGrid);
        panel.Children.Add(new SpacerControl { Height = 5 });
        panel.Children.Add(CreateLabel("Tip: Leave empty to create VM without OS media.", 10));

        // Load existing values if editing
        if (existingVM != null)
        {
            NameBox.Text = existingVM.Name;
            var roleIndex = Array.IndexOf(CommonRoles, existingVM.Role);
            RoleBox.SelectedIndex = roleIndex >= 0 ? roleIndex : 0;
            MemoryBox.Text = existingVM.MemoryGB.ToString();
            CPUBox.Text = existingVM.Processors.ToString();
            DiskBox.Text = existingVM.DiskSizeGB.ToString();
            ISOPathBox.Text = existingVM.ISOPath ?? string.Empty;
        }
        else
        {
            // Auto-generate initial name based on default role
            GenerateVMName();
        }

        BrowseButton.Click += (s, e) => BrowseISO();

        // Button Panel
        var buttonPanel = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 15, 0, 0)
        };

        var cancelBtn = new Button { Content = "Cancel", Width = 90, Height = 32, Margin = new Thickness(5) };
        cancelBtn.Click += (s, e) => { DialogResult = false; Close(); };

        var saveBtn = new Button
        {
            Content = existingVM == null ? "Add VM" : "Save",
            Width = 90,
            Height = 32,
            Margin = new Thickness(5),
            Background = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0, 120, 212)),
            Foreground = System.Windows.Media.Brushes.White
        };
        saveBtn.Click += (s, e) =>
        {
            if (string.IsNullOrWhiteSpace(NameBox.Text))
            {
                MessageBox.Show("Please enter a VM name.", "Validation", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            DialogResult = true;
            Close();
        };

        buttonPanel.Children.Add(cancelBtn);
        buttonPanel.Children.Add(saveBtn);

        grid.Children.Add(panel);
        Grid.SetRow(panel, 0);
        grid.Children.Add(buttonPanel);
        Grid.SetRow(buttonPanel, 1);

        Content = grid;
    }

    private TextBlock CreateLabel(string text, int fontSize = 11)
    {
        return new TextBlock
        {
            Text = text,
            FontWeight = FontWeights.SemiBold,
            FontSize = fontSize,
            Margin = new Thickness(0, 0, 0, 5)
        };
    }

    private void BrowseISO()
    {
        var defaultIsoPath = @"C:\LabSources\ISOs";

        var dialog = new OpenFileDialog
        {
            Filter = "ISO Files (*.iso)|*.iso|All Files (*.*)|*.*",
            Title = "Select ISO File",
            CheckFileExists = true,
            Multiselect = false,
            InitialDirectory = System.IO.Directory.Exists(defaultIsoPath) ? defaultIsoPath : Environment.GetFolderPath(Environment.SpecialFolder.MyComputer)
        };

        if (dialog.ShowDialog() == true)
        {
            ISOPathBox.Text = dialog.FileName;
        }
    }

    private void GenerateVMName()
    {
        if (RoleBox.SelectedItem == null) return;

        var selectedRole = RoleBox.SelectedItem.ToString() ?? "MemberServer";

        // Get the prefix for this role
        if (RoleNamePrefixes.TryGetValue(selectedRole, out var prefix))
        {
            // Find the next available number
            var existingNumbers = _existingVMs
                .Where(vm => vm.Name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                .Select(vm =>
                {
                    var numPart = vm.Name.Substring(prefix.Length);
                    if (int.TryParse(numPart, out var num)) return num;
                    return 0;
                })
                .Where(n => n > 0)
                .ToList();

            var nextNum = existingNumbers.Count > 0 ? existingNumbers.Max() + 1 : 1;
            NameBox.Text = $"{prefix}{nextNum:D2}";
        }
        else
        {
            // Fallback for unknown roles
            var count = _existingVMs.Count(v => v.Role.Equals(selectedRole, StringComparison.OrdinalIgnoreCase));
            NameBox.Text = $"{selectedRole}{count + 1:D2}";
        }
    }

    public VMDefinition GetVMDefinition() => new()
    {
        Name = NameBox.Text,
        Role = RoleBox.SelectedItem?.ToString() ?? "MemberServer",
        MemoryGB = long.TryParse(MemoryBox.Text, out var mem) ? mem : 2,
        Processors = int.TryParse(CPUBox.Text, out var cpu) ? cpu : 2,
        DiskSizeGB = long.TryParse(DiskBox.Text, out var disk) ? disk : 40,
        ISOPath = string.IsNullOrWhiteSpace(ISOPathBox.Text) ? null : ISOPathBox.Text
    };
}

/// <summary>
/// Simple spacer control for margins
/// </summary>
public class SpacerControl : System.Windows.Controls.Control
{
    public new double Height { get; set; }
}

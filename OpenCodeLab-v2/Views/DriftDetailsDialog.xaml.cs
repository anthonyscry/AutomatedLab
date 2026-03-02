using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using OpenCodeLab.Models;

namespace OpenCodeLab.Views;

public partial class DriftDetailsDialog : Window
{
    private readonly DriftReport _report;
    private List<DriftItemRow> _allItems = new();

    public DriftDetailsDialog(DriftReport report)
    {
        InitializeComponent();
        _report = report;

        SummaryText.Text = $"{report.StatusEmoji} Drift Report — {report.LabName}";
        DetailText.Text = $"Generated: {report.GeneratedAt:g} | VMs scanned: {report.Results.Count} | Drifted: {report.DriftCount}";

        // Flatten items with VM name
        foreach (var vmResult in report.Results)
        {
            foreach (var item in vmResult.Items)
            {
                _allItems.Add(new DriftItemRow
                {
                    VMName = vmResult.VMName,
                    Category = item.Category,
                    Property = item.Property,
                    Expected = item.Expected ?? "-",
                    Actual = item.Actual ?? "-",
                    SeverityEmoji = item.SeverityEmoji,
                    Severity = item.Severity
                });
            }
            // Add VM filter option
            VMFilter.Items.Add(new ComboBoxItem { Content = vmResult.VMName });
        }

        DriftItemsList.ItemsSource = _allItems;
    }

    private void VMFilter_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (VMFilter.SelectedIndex == 0)
            DriftItemsList.ItemsSource = _allItems;
        else
        {
            var vmName = ((ComboBoxItem)VMFilter.SelectedItem).Content.ToString();
            DriftItemsList.ItemsSource = _allItems.Where(i => i.VMName == vmName).ToList();
        }
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();
}

public class DriftItemRow
{
    public string VMName { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string Property { get; set; } = string.Empty;
    public string? Expected { get; set; }
    public string? Actual { get; set; }
    public string SeverityEmoji { get; set; } = string.Empty;
    public DriftSeverity Severity { get; set; }
}
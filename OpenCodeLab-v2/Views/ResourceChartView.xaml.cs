using System;
using System.ComponentModel;
using System.Windows.Controls;
using ScottPlot;
using OpenCodeLab.ViewModels;

namespace OpenCodeLab.Views;

/// <summary>
/// Code-behind for ResourceChartView - handles ScottPlot chart rendering
/// </summary>
public partial class ResourceChartView : UserControl
{
    private ResourceChartViewModel? ViewModel => DataContext as ResourceChartViewModel;

    public ResourceChartView()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, System.Windows.RoutedEventArgs e)
    {
        InitializeChart();
    }

    private void OnDataContextChanged(object sender, System.Windows.DependencyPropertyChangedEventArgs e)
    {
        if (e.OldValue is ResourceChartViewModel oldVm)
        {
            oldVm.PropertyChanged -= OnViewModelPropertyChanged;
        }

        if (e.NewValue is ResourceChartViewModel newVm)
        {
            newVm.PropertyChanged += OnViewModelPropertyChanged;
        }
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(ResourceChartViewModel.NeedsChartRefresh) ||
            e.PropertyName == nameof(ResourceChartViewModel.CpuYs) ||
            e.PropertyName == nameof(ResourceChartViewModel.MemoryYs) ||
            e.PropertyName == nameof(ResourceChartViewModel.DiskYs))
        {
            UpdateChart();
        }
    }

    private void InitializeChart()
    {
        var plot = ResourcePlot.Plot;
        
        // Basic styling
        plot.Title("Resource Utilization");
        plot.XLabel("Time");
        plot.YLabel("Usage (%)");

        // Set Y axis limits (0-100%)
        plot.Axes.SetLimitsY(0, 100);

        // Date axis for X
        plot.Axes.DateTimeTicksBottom();

        ResourcePlot.Refresh();
    }

    private void UpdateChart()
    {
        if (ViewModel == null)
            return;

        var plot = ResourcePlot.Plot;
        plot.Clear();

        // Add CPU series if enabled and has data
        if (ViewModel.ShowCpu && ViewModel.CpuXs.Length > 0 && ViewModel.CpuYs.Length > 0)
        {
            var cpuPlot = plot.Add.Scatter(ViewModel.CpuXs, ViewModel.CpuYs);
            cpuPlot.LegendText = "CPU";
            cpuPlot.Color = new ScottPlot.Color(33, 150, 243); // Blue
            cpuPlot.LineWidth = 2;
        }

        // Add Memory series if enabled and has data
        if (ViewModel.ShowMemory && ViewModel.MemoryXs.Length > 0 && ViewModel.MemoryYs.Length > 0)
        {
            var memPlot = plot.Add.Scatter(ViewModel.MemoryXs, ViewModel.MemoryYs);
            memPlot.LegendText = "Memory";
            memPlot.Color = new ScottPlot.Color(76, 175, 80); // Green
            memPlot.LineWidth = 2;
        }

        // Add Disk series if enabled and has data
        if (ViewModel.ShowDisk && ViewModel.DiskXs.Length > 0 && ViewModel.DiskYs.Length > 0)
        {
            var diskPlot = plot.Add.Scatter(ViewModel.DiskXs, ViewModel.DiskYs);
            diskPlot.LegendText = "Disk";
            diskPlot.Color = new ScottPlot.Color(255, 152, 0); // Orange
            diskPlot.LineWidth = 2;
        }

        // Update title with selected lab
        var labName = string.IsNullOrEmpty(ViewModel.SelectedLabName) ? "Resource" : ViewModel.SelectedLabName;
        plot.Title($"{labName} - Resource Utilization");

        // Configure axes
        plot.Axes.SetLimitsY(0, 100);
        plot.Axes.DateTimeTicksBottom();

        // Show legend
        plot.ShowLegend(Alignment.UpperRight);

        // Auto-scale X axis to data
        plot.Axes.AutoScale();

        ResourcePlot.Refresh();
    }
}

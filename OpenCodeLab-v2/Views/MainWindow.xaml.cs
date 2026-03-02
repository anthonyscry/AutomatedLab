using System;
using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Input;
using OpenCodeLab;
using OpenCodeLab.ViewModels;

namespace OpenCodeLab.Views;

public partial class MainWindow : Window
{
    public DashboardViewModel DashboardVM { get; }
    public ActionsViewModel ActionsVM { get; }
    public SettingsViewModel SettingsVM { get; }
    public SoftwareInventoryViewModel SoftwareInventoryVM { get; }
    public CheckpointsViewModel CheckpointsVM { get; }
    public HealthDashboardViewModel HealthVM { get; }
    public BaselineManagerViewModel BaselinesVM { get; }
    public DocumentationHubViewModel DocumentationVM { get; }
    public SchedulerViewModel SchedulerVM { get; }
    public IaCExportViewModel IaCVM { get; }
    public ResourceChartViewModel ChartsVM { get; }

    public MainWindow()
    {
        InitializeComponent();
        SidebarVersionText.Text = $"Version {AppVersion.Display}";
        DashboardVM = new DashboardViewModel();
        ActionsVM = new ActionsViewModel();
        SettingsVM = new SettingsViewModel();
        SoftwareInventoryVM = new SoftwareInventoryViewModel();
        CheckpointsVM = new CheckpointsViewModel();
        HealthVM = new HealthDashboardViewModel();
        BaselinesVM = new BaselineManagerViewModel();
        DocumentationVM = new DocumentationHubViewModel();
        SchedulerVM = new SchedulerViewModel();
        IaCVM = new IaCExportViewModel();
        ChartsVM = new ResourceChartViewModel();

        DashboardView.DataContext = DashboardVM;
        ActionsView.DataContext = ActionsVM;
        SettingsView.DataContext = SettingsVM;
        SoftwareInventoryView.DataContext = SoftwareInventoryVM;
        CheckpointsView.DataContext = CheckpointsVM;
        HealthView.DataContext = HealthVM;
        BaselinesView.DataContext = BaselinesVM;
        DocumentationView.DataContext = DocumentationVM;
        SchedulerView.DataContext = SchedulerVM;
        IaCView.DataContext = IaCVM;
        ChartsView.DataContext = ChartsVM;

        Loaded += MainWindow_Loaded;
        NavigateTo("Dashboard");
    }

    private async void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        try { await DashboardVM.LoadAsync(); }
        catch (Exception ex) { StatusText.Text = $"Error: {ex.Message}"; }
    }

    private void NavButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string tag)
            NavigateTo(tag);
    }

    private void NavigateTo(string viewName)
    {
        DashboardView.Visibility = Visibility.Collapsed;
        ActionsView.Visibility = Visibility.Collapsed;
        SettingsView.Visibility = Visibility.Collapsed;
        SoftwareInventoryView.Visibility = Visibility.Collapsed;
        CheckpointsView.Visibility = Visibility.Collapsed;
        HealthView.Visibility = Visibility.Collapsed;
        BaselinesView.Visibility = Visibility.Collapsed;
        DocumentationView.Visibility = Visibility.Collapsed;
        SchedulerView.Visibility = Visibility.Collapsed;
        IaCView.Visibility = Visibility.Collapsed;
        ChartsView.Visibility = Visibility.Collapsed;

        ResetButtonStyles();

        switch (viewName)
        {
            case "Dashboard":
                DashboardView.Visibility = Visibility.Visible;
                TitleText.Text = "Dashboard";
                HighlightButton(DashboardButton);
                break;
            case "Actions":
                ActionsView.Visibility = Visibility.Visible;
                TitleText.Text = "Lab Actions";
                HighlightButton(ActionsButton);
                break;
            case "Settings":
                SettingsView.Visibility = Visibility.Visible;
                TitleText.Text = "Settings";
                HighlightButton(SettingsButton);
                break;
            case "SoftwareInventory":
                SoftwareInventoryView.Visibility = Visibility.Visible;
                TitleText.Text = "Software Inventory";
                HighlightButton(SoftwareInventoryButton);
                _ = SoftwareInventoryVM.LoadAsync();
                break;
            case "Checkpoints":
                CheckpointsView.Visibility = Visibility.Visible;
                TitleText.Text = "Checkpoints";
                HighlightButton(CheckpointsButton);
                _ = CheckpointsVM.LoadAsync();
                break;
            case "Health":
                HealthView.Visibility = Visibility.Visible;
                TitleText.Text = "Health Dashboard";
                HighlightButton(HealthButton);
                _ = HealthVM.LoadAsync();
                break;
            case "Baselines":
                BaselinesView.Visibility = Visibility.Visible;
                TitleText.Text = "Baseline Manager";
                HighlightButton(BaselinesButton);
                _ = BaselinesVM.LoadAsync();
                break;
            case "Charts":
                ChartsView.Visibility = Visibility.Visible;
                TitleText.Text = "Resource Charts";
                HighlightButton(ChartsButton);
                _ = ChartsVM.LoadAsync();
                break;
            case "Documentation":
                DocumentationView.Visibility = Visibility.Visible;
                TitleText.Text = "Documentation Hub";
                HighlightButton(DocumentationButton);
                _ = DocumentationVM.LoadAsync();
                break;
            case "Scheduler":
                SchedulerView.Visibility = Visibility.Visible;
                TitleText.Text = "Scheduled Tasks";
                HighlightButton(SchedulerButton);
                _ = SchedulerVM.LoadAsync();
                break;
            case "IaC":
                IaCView.Visibility = Visibility.Visible;
                TitleText.Text = "IaC Export";
                HighlightButton(IaCButton);
                _ = IaCVM.LoadAsync();
                break;
        }

        StatusText.Text = $"Viewing {viewName}";
        FocusManager.SetFocusedElement(this, viewName switch
        {
            "Dashboard" => DashboardButton,
            "Actions" => ActionsButton,
            "Settings" => SettingsButton,
            "SoftwareInventory" => SoftwareInventoryButton,
            "Checkpoints" => CheckpointsButton,
            "Health" => HealthButton,
            "Baselines" => BaselinesButton,
            "Charts" => ChartsButton,
            "Documentation" => DocumentationButton,
            "Scheduler" => SchedulerButton,
            "IaC" => IaCButton,
            _ => DashboardButton
        });
    }

    private void HighlightButton(Button btn)
    {
        btn.Background = new SolidColorBrush(Color.FromRgb(240, 240, 240));
    }

    private void ResetButtonStyles()
    {
        DashboardButton.Background = Brushes.Transparent;
        ActionsButton.Background = Brushes.Transparent;
        SettingsButton.Background = Brushes.Transparent;
        SoftwareInventoryButton.Background = Brushes.Transparent;
        CheckpointsButton.Background = Brushes.Transparent;
        HealthButton.Background = Brushes.Transparent;
        BaselinesButton.Background = Brushes.Transparent;
        ChartsButton.Background = Brushes.Transparent;
        DocumentationButton.Background = Brushes.Transparent;
        SchedulerButton.Background = Brushes.Transparent;
        IaCButton.Background = Brushes.Transparent;
    }

    private void HelpButton_Click(object sender, RoutedEventArgs e)
    {
        var help = new HelpWindow { Owner = this };
        help.ShowDialog();
    }

    private void AboutButton_Click(object sender, RoutedEventArgs e)
    {
        var about = new AboutWindow { Owner = this };
        about.ShowDialog();
    }

    private void Window_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        var isTypingTarget = IsTypingTarget(Keyboard.FocusedElement);

        if (Keyboard.Modifiers == ModifierKeys.Control)
        {
            switch (e.Key)
            {
                case Key.D1:
                    NavigateTo("Dashboard");
                    e.Handled = true;
                    break;
                case Key.D2:
                    NavigateTo("Actions");
                    e.Handled = true;
                    break;
                case Key.D3:
                    NavigateTo("Settings");
                    e.Handled = true;
                    break;
                case Key.D4:
                    NavigateTo("SoftwareInventory");
                    e.Handled = true;
                    break;
                case Key.D5:
                    NavigateTo("Checkpoints");
                    e.Handled = true;
                    break;
                case Key.D6:
                    NavigateTo("Health");
                    e.Handled = true;
                    break;
                case Key.D7:
                    NavigateTo("Baselines");
                    e.Handled = true;
                    break;
                case Key.D8:
                    NavigateTo("Charts");
                    e.Handled = true;
                    break;
                case Key.D9:
                    NavigateTo("Scheduler");
                    e.Handled = true;
                    break;
                case Key.D0:
                    NavigateTo("IaC");
                    e.Handled = true;
                    break;
                case Key.R:
                    if (!isTypingTarget
                        && DashboardView.Visibility == Visibility.Visible
                        && DashboardVM.RefreshCommand.CanExecute(null))
                    {
                        DashboardVM.RefreshCommand.Execute(null);
                        e.Handled = true;
                    }
                    break;
                case Key.L:
                    if (!isTypingTarget && ActionsView.Visibility == Visibility.Visible)
                    {
                        ActionsView.FocusLogText();
                        e.Handled = true;
                    }
                    break;
            }

            return;
        }

        if (isTypingTarget)
            return;

        if (e.Key == Key.F5)
        {
            if (DashboardView.Visibility == Visibility.Visible && DashboardVM.RefreshCommand.CanExecute(null))
            {
                DashboardVM.RefreshCommand.Execute(null);
                e.Handled = true;
            }
        }
        else if (e.Key == Key.Escape)
        {
            StatusText.Text = "Ready";
            e.Handled = true;
        }
    }

    private static bool IsTypingTarget(IInputElement? element)
    {
        return element is TextBox
            || element is Primitives.TextBoxBase
            || element is ComboBox
            || element is PasswordBox
            || element is RichTextBox;
    }
}

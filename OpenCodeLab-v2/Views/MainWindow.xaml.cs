using System;
using System.Windows;
using System.Windows.Media;
using OpenCodeLab.ViewModels;

namespace OpenCodeLab.Views;

public partial class MainWindow : Window
{
    public DashboardViewModel DashboardVM { get; }
    public ActionsViewModel ActionsVM { get; }
    public SettingsViewModel SettingsVM { get; }

    public MainWindow()
    {
        InitializeComponent();
        DashboardVM = new DashboardViewModel();
        ActionsVM = new ActionsViewModel();
        SettingsVM = new SettingsViewModel();

        DashboardView.DataContext = DashboardVM;
        ActionsView.DataContext = ActionsVM;
        SettingsView.DataContext = SettingsVM;

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
        if (sender is System.Windows.Controls.Button btn && btn.Tag is string tag)
            NavigateTo(tag);
    }

    private void NavigateTo(string viewName)
    {
        DashboardView.Visibility = Visibility.Collapsed;
        ActionsView.Visibility = Visibility.Collapsed;
        SettingsView.Visibility = Visibility.Collapsed;

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
        }

        StatusText.Text = $"Viewing {viewName}";
    }

    private void HighlightButton(System.Windows.Controls.Button btn)
    {
        btn.Background = new SolidColorBrush(Color.FromRgb(240, 240, 240));
    }

    private void ResetButtonStyles()
    {
        DashboardButton.Background = Brushes.Transparent;
        ActionsButton.Background = Brushes.Transparent;
        SettingsButton.Background = Brushes.Transparent;
    }
}

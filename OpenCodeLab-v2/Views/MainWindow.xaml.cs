using System;
using System.Windows;
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

    public MainWindow()
    {
        InitializeComponent();
        SidebarVersionText.Text = $"Version {AppVersion.Display}";
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
        FocusManager.SetFocusedElement(this, viewName switch
        {
            "Dashboard" => DashboardButton,
            "Actions" => ActionsButton,
            "Settings" => SettingsButton,
            _ => DashboardButton
        });
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
            if (DashboardView.Visibility == Visibility.Visible || ActionsView.Visibility == Visibility.Visible || SettingsView.Visibility == Visibility.Visible)
            {
                StatusText.Text = "Ready";
                e.Handled = true;
            }
        }
    }

    private static bool IsTypingTarget(IInputElement? element)
    {
        return element is System.Windows.Controls.TextBox
            || element is System.Windows.Controls.Primitives.TextBoxBase
            || element is System.Windows.Controls.ComboBox
            || element is System.Windows.Controls.PasswordBox
            || element is System.Windows.Controls.RichTextBox;
    }
}

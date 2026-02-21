using System.Windows;

namespace OpenCodeLab.Views;

public partial class DeploymentProgressWindow : Window
{
    public DeploymentProgressWindow() => InitializeComponent();

    public void UpdateProgress(int percent, string message)
    {
        ProgressBar.Value = percent;
        StatusText.Text = message;
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();
}

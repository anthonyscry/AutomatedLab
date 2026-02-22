using System.Windows.Controls;

namespace OpenCodeLab.Views;

public partial class ActionsView : UserControl
{
    public ActionsView() => InitializeComponent();

    private void LogTextBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (sender is TextBox textBox)
        {
            textBox.ScrollToEnd();
        }
    }
}

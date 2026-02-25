using System.Windows.Controls;
using System.Windows.Input;

namespace OpenCodeLab.Views;

public partial class ActionsView : UserControl
{
    public ActionsView() => InitializeComponent();

    public void FocusLogText()
    {
        Keyboard.Focus(LogTextBox);
    }

    private void LogTextBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (sender is TextBox textBox)
        {
            textBox.ScrollToEnd();
        }
    }
}

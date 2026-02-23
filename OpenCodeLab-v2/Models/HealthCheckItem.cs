using System.Windows.Media;
using OpenCodeLab.ViewModels;

namespace OpenCodeLab.Models;

public class HealthCheckItem : ObservableObject
{
    private string _name = string.Empty;
    private string _status = "Checking...";
    private Brush _statusColor = Brushes.Gray;
    private bool _passed;

    public string Name
    {
        get => _name;
        set { _name = value; OnPropertyChanged(); }
    }

    public string Status
    {
        get => _status;
        set { _status = value; OnPropertyChanged(); }
    }

    public Brush StatusColor
    {
        get => _statusColor;
        set { _statusColor = value; OnPropertyChanged(); }
    }

    public bool Passed
    {
        get => _passed;
        set { _passed = value; OnPropertyChanged(); }
    }
}

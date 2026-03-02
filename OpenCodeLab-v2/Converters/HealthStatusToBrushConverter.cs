using System;
using System.Globalization;
using System.Windows.Data;
using System.Windows.Media;
using OpenCodeLab.Models;

namespace OpenCodeLab.Converters;

/// <summary>
/// Converts HealthStatus enum to a Brush for UI display
/// </summary>
public class HealthStatusToBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is HealthStatus status)
        {
            return status switch
            {
                HealthStatus.Healthy => Brushes.Green,
                HealthStatus.Warning => Brushes.Orange,
                HealthStatus.Critical => Brushes.Red,
                _ => Brushes.Gray
            };
        }
        return Brushes.Gray;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is Brush brush)
        {
            if (brush == Brushes.Green) return HealthStatus.Healthy;
            if (brush == Brushes.Orange) return HealthStatus.Warning;
            if (brush == Brushes.Red) return HealthStatus.Critical;
            return HealthStatus.Unknown;
        }
        return HealthStatus.Unknown;
    }
}

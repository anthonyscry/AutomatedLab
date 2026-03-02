using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using OpenCodeLab.Models;
using OpenCodeLab.Services;

namespace OpenCodeLab.Views;

public partial class TemplateGalleryDialog : Window
{
    private readonly TemplateService _templateService = new();
    private List<LabTemplate> _templates = new();

    public LabTemplate? SelectedTemplate { get; private set; }

    public TemplateGalleryDialog()
    {
        InitializeComponent();
        Loaded += async (s, e) =>
        {
            _templates = await _templateService.GetTemplatesAsync();
            TemplateList.ItemsSource = _templates;
        };
    }

    private void TemplateList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        var selected = TemplateList.SelectedItem as LabTemplate;
        UseButton.IsEnabled = selected != null;
        DeleteButton.IsEnabled = selected != null && !selected.IsBuiltIn;
    }

    private void UseButton_Click(object sender, RoutedEventArgs e)
    {
        SelectedTemplate = TemplateList.SelectedItem as LabTemplate;
        if (SelectedTemplate != null)
        {
            DialogResult = true;
            Close();
        }
    }

    private async void DeleteButton_Click(object sender, RoutedEventArgs e)
    {
        if (TemplateList.SelectedItem is not LabTemplate template || template.IsBuiltIn) return;
        var result = MessageBox.Show($"Delete template '{template.Name}'?", "Confirm Delete", MessageBoxButton.YesNo, MessageBoxImage.Question);
        if (result != MessageBoxResult.Yes) return;
        await _templateService.DeleteTemplateAsync(template.Id);
        _templates = await _templateService.GetTemplatesAsync();
        TemplateList.ItemsSource = null;
        TemplateList.ItemsSource = _templates;
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
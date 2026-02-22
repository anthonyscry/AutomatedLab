using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.Win32;
using OpenCodeLab.Models;

namespace OpenCodeLab.ViewModels;

public class SettingsViewModel : ObservableObject
{
    private AppSettings _settings = new();
    private string _settingsPath;

    public AsyncCommand SaveSettingsCommand { get; }
    public AsyncCommand LoadSettingsCommand { get; }
    public AsyncCommand ResetSettingsCommand { get; }

    public string DefaultLabPath
    {
        get => _settings.DefaultLabPath;
        set { _settings.DefaultLabPath = value; OnPropertyChanged(); }
    }

    public string LabConfigPath
    {
        get => _settings.LabConfigPath;
        set { _settings.LabConfigPath = value; OnPropertyChanged(); }
    }

    public string ISOPath
    {
        get => _settings.ISOPath;
        set { _settings.ISOPath = value; OnPropertyChanged(); }
    }

    public string VMPath
    {
        get => _settings.VMPath;
        set { _settings.VMPath = value; OnPropertyChanged(); }
    }

    public string DefaultSwitchName
    {
        get => _settings.DefaultSwitchName;
        set { _settings.DefaultSwitchName = value; OnPropertyChanged(); }
    }

    public string DefaultSwitchType
    {
        get => _settings.DefaultSwitchType;
        set { _settings.DefaultSwitchType = value; OnPropertyChanged(); }
    }

    public bool EnableAutoStart
    {
        get => _settings.EnableAutoStart;
        set { _settings.EnableAutoStart = value; OnPropertyChanged(); }
    }

    public int RefreshIntervalSeconds
    {
        get => _settings.RefreshIntervalSeconds;
        set { _settings.RefreshIntervalSeconds = value; OnPropertyChanged(); }
    }

    public int MaxLogLines
    {
        get => _settings.MaxLogLines;
        set { _settings.MaxLogLines = value; OnPropertyChanged(); }
    }

    public SettingsViewModel()
    {
        _settingsPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OpenCodeLab", "settings.json");
        LoadSettingsFromFile();
        SaveSettingsCommand = new AsyncCommand(SaveSettingsAsync);
        LoadSettingsCommand = new AsyncCommand(LoadSettingsAsync);
        ResetSettingsCommand = new AsyncCommand(ResetSettingsAsync);
    }

    private void LoadSettingsFromFile()
    {
        try
        {
            if (File.Exists(_settingsPath))
            {
                var json = File.ReadAllText(_settingsPath);
                var loaded = System.Text.Json.JsonSerializer.Deserialize<AppSettings>(json);
                if (loaded != null) _settings = loaded;
            }
        }
        catch { }
        OnPropertyChanged(nameof(DefaultLabPath));
        OnPropertyChanged(nameof(LabConfigPath));
        OnPropertyChanged(nameof(ISOPath));
        OnPropertyChanged(nameof(VMPath));
        OnPropertyChanged(nameof(DefaultSwitchName));
        OnPropertyChanged(nameof(DefaultSwitchType));
        OnPropertyChanged(nameof(EnableAutoStart));
        OnPropertyChanged(nameof(RefreshIntervalSeconds));
        OnPropertyChanged(nameof(MaxLogLines));
    }

    private async Task SaveSettingsAsync()
    {
        await Task.Run(() =>
        {
            try
            {
                // Ensure all directories exist
                Directory.CreateDirectory(_settings.DefaultLabPath);
                Directory.CreateDirectory(_settings.LabConfigPath);
                Directory.CreateDirectory(_settings.ISOPath);
                Directory.CreateDirectory(Path.GetDirectoryName(_settingsPath)!);

                var json = System.Text.Json.JsonSerializer.Serialize(_settings, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
                File.WriteAllText(_settingsPath, json);
            }
            catch { }
        });
    }

    private async Task LoadSettingsAsync()
    {
        await Task.Run(() =>
        {
            var dialog = new OpenFileDialog { Filter = "Settings Files|*.json|All Files|*.*", Title = "Load Settings" };
            if (dialog.ShowDialog() == true)
            {
                try
                {
                    var json = File.ReadAllText(dialog.FileName);
                    var loaded = System.Text.Json.JsonSerializer.Deserialize<AppSettings>(json);
                    if (loaded != null) _settings = loaded;
                    OnPropertyChanged(nameof(DefaultLabPath));
                    OnPropertyChanged(nameof(LabConfigPath));
                    OnPropertyChanged(nameof(ISOPath));
                    OnPropertyChanged(nameof(DefaultSwitchName));
                    OnPropertyChanged(nameof(DefaultSwitchType));
                    OnPropertyChanged(nameof(EnableAutoStart));
                    OnPropertyChanged(nameof(RefreshIntervalSeconds));
                    OnPropertyChanged(nameof(MaxLogLines));
                }
                catch { }
            }
        });
    }

    private async Task ResetSettingsAsync()
    {
        await Task.Run(() => { _settings = new AppSettings(); });
        OnPropertyChanged(nameof(DefaultLabPath));
        OnPropertyChanged(nameof(LabConfigPath));
        OnPropertyChanged(nameof(ISOPath));
        OnPropertyChanged(nameof(VMPath));
        OnPropertyChanged(nameof(DefaultSwitchName));
        OnPropertyChanged(nameof(DefaultSwitchType));
        OnPropertyChanged(nameof(EnableAutoStart));
        OnPropertyChanged(nameof(RefreshIntervalSeconds));
        OnPropertyChanged(nameof(MaxLogLines));
    }
}

public class AppSettings
{
    public string DefaultLabPath { get; set; } = @"C:\LabSources";
    public string LabConfigPath { get; set; } = @"C:\LabSources\LabConfig";
    public string ISOPath { get; set; } = @"C:\LabSources\ISOs";
    public string VMPath { get; set; } = @"C:\LabSources\VMs";
    public string DefaultSwitchName { get; set; } = "LabSwitch";
    public string DefaultSwitchType { get; set; } = "Internal";
    public bool EnableAutoStart { get; set; }
    public int RefreshIntervalSeconds { get; set; } = 10;
    public int MaxLogLines { get; set; } = 1000;
}

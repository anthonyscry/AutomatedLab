using System;
using System.IO;
using System.Text.Json;
using OpenCodeLab.Models;

namespace OpenCodeLab.Services;

public static class AppSettingsStore
{
    public static string GetSettingsPath()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OpenCodeLab",
            "settings.json");
    }

    public static AppSettings LoadOrDefault()
    {
        try
        {
            var path = GetSettingsPath();
            if (!File.Exists(path))
                return new AppSettings();

            var json = File.ReadAllText(path);
            var loaded = JsonSerializer.Deserialize<AppSettings>(json);
            return loaded ?? new AppSettings();
        }
        catch
        {
            return new AppSettings();
        }
    }

    public static AppSettings? LoadFromPath(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
            return null;

        try
        {
            var json = File.ReadAllText(path);
            return JsonSerializer.Deserialize<AppSettings>(json);
        }
        catch
        {
            return null;
        }
    }

    public static bool Save(string path, AppSettings settings)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var json = JsonSerializer.Serialize(settings, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(path, json);
            return true;
        }
        catch
        {
            return false;
        }
    }
}

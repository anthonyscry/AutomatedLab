using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using OpenCodeLab.Models;

namespace OpenCodeLab.Services;

public class TemplateService
{
    private const string BuiltInDir = "config/templates";
    private const string UserDir = @"C:\LabSources\LabConfig\templates";
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public async Task<List<LabTemplate>> GetTemplatesAsync()
    {
        var builtInTemplates = await LoadTemplatesFromDirectoryAsync(GetBuiltInPath(), true);
        var userTemplates = await LoadTemplatesFromDirectoryAsync(UserDir, false);

        return builtInTemplates
            .Concat(userTemplates)
            .OrderByDescending(t => t.IsBuiltIn)
            .ThenBy(t => t.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    public async Task<LabTemplate?> GetTemplateByIdAsync(string templateId)
    {
        if (string.IsNullOrWhiteSpace(templateId))
        {
            return null;
        }

        var templates = await GetTemplatesAsync();
        return templates.FirstOrDefault(t =>
            string.Equals(t.Id, templateId, StringComparison.OrdinalIgnoreCase));
    }

    public async Task SaveTemplateAsync(LabTemplate template)
    {
        ArgumentNullException.ThrowIfNull(template);

        if (template.IsBuiltIn)
        {
            throw new InvalidOperationException("Built-in templates cannot be saved as user templates.");
        }

        if (string.IsNullOrWhiteSpace(template.Id))
        {
            template.Id = $"template-{Guid.NewGuid():N}";
        }

        if (await IsBuiltInTemplateIdAsync(template.Id))
        {
            throw new InvalidOperationException("Built-in templates cannot be overwritten.");
        }

        template.IsBuiltIn = false;
        Directory.CreateDirectory(UserDir);

        var fileName = $"{SanitizeFileName(template.Id)}.json";
        var path = Path.Combine(UserDir, fileName);
        var json = JsonSerializer.Serialize(template, JsonOptions);
        await File.WriteAllTextAsync(path, json);
    }

    public async Task<bool> DeleteTemplateAsync(string templateId)
    {
        if (string.IsNullOrWhiteSpace(templateId))
        {
            return false;
        }

        if (await IsBuiltInTemplateIdAsync(templateId))
        {
            return false;
        }

        if (!Directory.Exists(UserDir))
        {
            return false;
        }

        foreach (var filePath in Directory.EnumerateFiles(UserDir, "*.json", SearchOption.TopDirectoryOnly))
        {
            try
            {
                var json = await File.ReadAllTextAsync(filePath);
                var template = JsonSerializer.Deserialize<LabTemplate>(json);
                if (template is null)
                {
                    continue;
                }

                if (!string.Equals(template.Id, templateId, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                File.Delete(filePath);
                return true;
            }
            catch
            {
            }
        }

        return false;
    }

    public async Task<LabTemplate> CreateTemplateFromLabAsync(LabConfig config, string name, string description)
    {
        ArgumentNullException.ThrowIfNull(config);

        var configJson = JsonSerializer.Serialize(config, JsonOptions);
        var deepCopy = JsonSerializer.Deserialize<LabConfig>(configJson) ?? new LabConfig();

        var template = new LabTemplate
        {
            Id = $"template-{Guid.NewGuid():N}",
            Name = name,
            Description = description,
            Category = "Custom",
            Author = "User",
            Version = "1.0",
            CreatedAt = DateTime.UtcNow,
            IsBuiltIn = false,
            Config = deepCopy
        };

        await SaveTemplateAsync(template);
        return template;
    }

    private static string GetBuiltInPath()
    {
        return Path.Combine(AppDomain.CurrentDomain.BaseDirectory, BuiltInDir);
    }

    private static async Task<List<LabTemplate>> LoadTemplatesFromDirectoryAsync(string directoryPath, bool isBuiltIn)
    {
        var templates = new List<LabTemplate>();
        if (!Directory.Exists(directoryPath))
        {
            return templates;
        }

        foreach (var filePath in Directory.EnumerateFiles(directoryPath, "*.json", SearchOption.TopDirectoryOnly))
        {
            try
            {
                var json = await File.ReadAllTextAsync(filePath);
                var template = JsonSerializer.Deserialize<LabTemplate>(json);
                if (template is null)
                {
                    continue;
                }

                template.IsBuiltIn = isBuiltIn;
                if (string.IsNullOrWhiteSpace(template.Id))
                {
                    template.Id = Path.GetFileNameWithoutExtension(filePath);
                }

                templates.Add(template);
            }
            catch
            {
            }
        }

        return templates;
    }

    private async Task<bool> IsBuiltInTemplateIdAsync(string templateId)
    {
        if (string.IsNullOrWhiteSpace(templateId))
        {
            return false;
        }

        var builtIns = await LoadTemplatesFromDirectoryAsync(GetBuiltInPath(), true);
        return builtIns.Any(t => string.Equals(t.Id, templateId, StringComparison.OrdinalIgnoreCase));
    }

    private static string SanitizeFileName(string value)
    {
        var invalidChars = Path.GetInvalidFileNameChars();
        var cleaned = new string(value
            .Trim()
            .Select(ch => invalidChars.Contains(ch) ? '_' : ch)
            .ToArray());

        return string.IsNullOrWhiteSpace(cleaned) ? $"template-{Guid.NewGuid():N}" : cleaned;
    }
}

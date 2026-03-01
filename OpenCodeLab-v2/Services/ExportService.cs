using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using OpenCodeLab.Models;

namespace OpenCodeLab.Services;

public static class ExportService
{
    public static async Task ExportToCsvAsync(IEnumerable<ScanResult> results, string filePath)
    {
        var sb = new StringBuilder();
        sb.AppendLine("VMName,Name,Version,Publisher,InstallDate");

        foreach (var result in results)
        {
            foreach (var sw in result.Software)
            {
                sb.Append(EscapeCsvField(result.VMName));
                sb.Append(',');
                sb.Append(EscapeCsvField(sw.Name));
                sb.Append(',');
                sb.Append(EscapeCsvField(sw.Version));
                sb.Append(',');
                sb.Append(EscapeCsvField(sw.Publisher));
                sb.Append(',');
                sb.Append(EscapeCsvField(sw.InstallDate?.ToString("yyyyMMdd") ?? string.Empty));
                sb.Append("\r\n");
            }
        }

        Directory.CreateDirectory(Path.GetDirectoryName(filePath)!);
        await File.WriteAllTextAsync(filePath, sb.ToString());
    }

    public static async Task ExportToJsonAsync(IEnumerable<ScanResult> results, string filePath)
    {
        var options = new JsonSerializerOptions { WriteIndented = true };
        var json = JsonSerializer.Serialize(results, options);
        Directory.CreateDirectory(Path.GetDirectoryName(filePath)!);
        await File.WriteAllTextAsync(filePath, json);
    }

    private static string EscapeCsvField(string field)
    {
        if (string.IsNullOrEmpty(field))
            return string.Empty;

        if (field.Contains(',') || field.Contains('"') || field.Contains('\n') || field.Contains('\r'))
        {
            return "\"" + field.Replace("\"", "\"\"") + "\"";
        }

        return field;
    }
}

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using OpenCodeLab.Models;

namespace OpenCodeLab.Services;

/// <summary>
/// Service for exporting drift reports in various formats
/// </summary>
public class DriftReportExportService
{
    /// <summary>
    /// Export drift report as Markdown
    /// </summary>
    public async Task<string> ExportAsMarkdownAsync(ExtendedDriftReport report, CancellationToken ct = default)
    {
        var sb = new StringBuilder();

        sb.AppendLine($"# Drift Report: {report.LabName}");
        sb.AppendLine();
        sb.AppendLine($"**Generated:** {report.GeneratedAt:yyyy-MM-dd HH:mm:ss} UTC");
        sb.AppendLine($"**Baseline:** {report.BaselineDescription ?? report.BaselineId}");
        sb.AppendLine($"**Overall Status:** {report.StatusEmoji} {report.OverallStatus}");
        sb.AppendLine($"**Total Drift Items:** {report.TotalDriftCount}");
        sb.AppendLine();

        // Summary
        sb.AppendLine("## Summary");
        sb.AppendLine();
        sb.AppendLine($"| Category | Count |");
        sb.AppendLine($"|----------|-------|");
        sb.AppendLine($"| In-Guest Drift | {report.VmGuestDrift.Sum(v => v.Items.Count)} |");
        sb.AppendLine($"| Host VM Drift | {report.HostVmDrift.Sum(v => v.Items.Count)} |");
        sb.AppendLine($"| Network Drift | {report.NetworkDrift.Count} |");
        sb.AppendLine();

        // In-Guest Drift
        if (report.VmGuestDrift.Any(v => v.Items.Count > 0))
        {
            sb.AppendLine("## In-Guest VM Drift");
            sb.AppendLine();

            foreach (var vm in report.VmGuestDrift.Where(v => v.Items.Count > 0))
            {
                sb.AppendLine($"### {vm.VMName}");
                if (!vm.Reachable)
                {
                    sb.AppendLine("*VM is not reachable*");
                    sb.AppendLine();
                    continue;
                }

                sb.AppendLine($"| Category | Property | Expected | Actual | Severity |");
                sb.AppendLine($"|----------|----------|----------|--------|----------|");

                foreach (var item in vm.Items)
                {
                    sb.AppendLine($"| {item.Category} | {item.Property} | {item.Expected ?? "-"} | {item.Actual ?? "-"} | {item.SeverityEmoji} {item.Severity} |");
                }
                sb.AppendLine();
            }
        }

        // Host VM Drift
        if (report.HostVmDrift.Any(v => v.Items.Count > 0))
        {
            sb.AppendLine("## Host-Level VM Drift");
            sb.AppendLine();

            foreach (var vm in report.HostVmDrift.Where(v => v.Items.Count > 0))
            {
                if (!vm.VmExists)
                {
                    sb.AppendLine($"### {vm.VmName} (Missing)");
                    sb.AppendLine("*VM no longer exists on host*");
                    sb.AppendLine();
                    continue;
                }

                sb.AppendLine($"### {vm.VmName}");
                sb.AppendLine($"| Category | Property | Expected | Actual | Severity |");
                sb.AppendLine($"|----------|----------|----------|--------|----------|");

                foreach (var item in vm.Items)
                {
                    sb.AppendLine($"| {item.Category} | {item.Property} | {item.Expected ?? "-"} | {item.Actual ?? "-"} | {item.SeverityEmoji} {item.Severity} |");
                }
                sb.AppendLine();
            }
        }

        // Network Drift
        if (report.NetworkDrift.Count > 0)
        {
            sb.AppendLine("## Network Drift");
            sb.AppendLine();
            sb.AppendLine($"| Category | Component | Property | Expected | Actual | Severity |");
            sb.AppendLine($"|----------|-----------|----------|----------|--------|----------|");

            foreach (var item in report.NetworkDrift)
            {
                sb.AppendLine($"| {item.Category} | {item.ComponentName} | {item.Property} | {item.Expected ?? "-"} | {item.Actual ?? "-"} | {item.SeverityEmoji} {item.Severity} |");
            }
            sb.AppendLine();
        }

        // Recommendations
        sb.AppendLine("## Recommendations");
        sb.AppendLine();

        var criticalItems = report.VmGuestDrift.SelectMany(v => v.Items)
            .Concat(report.HostVmDrift.SelectMany(v => v.Items))
            .Concat(report.NetworkDrift)
            .Where(i => i.Severity == DriftSeverity.Critical)
            .ToList();

        if (criticalItems.Count > 0)
        {
            sb.AppendLine("### Critical Issues (Immediate Action Required)");
            foreach (var item in criticalItems)
            {
                sb.AppendLine($"- Review and address: {item.Category} - {item.Property}");
            }
            sb.AppendLine();
        }

        sb.AppendLine("### General Recommendations");
        sb.AppendLine("- Review all drift items and determine if changes are intentional");
        sb.AppendLine("- Update the baseline if changes are expected");
        sb.AppendLine("- Remediate unexpected changes to restore baseline state");
        sb.AppendLine();

        // Footer
        sb.AppendLine("---");
        sb.AppendLine($"*Report generated by OpenCodeLab*");

        return sb.ToString();
    }

    /// <summary>
    /// Export drift report as JSON
    /// </summary>
    public async Task<string> ExportAsJsonAsync(ExtendedDriftReport report, CancellationToken ct = default)
    {
        return JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true });
    }

    /// <summary>
    /// Export drift report as HTML
    /// </summary>
    public async Task<string> ExportAsHtmlAsync(ExtendedDriftReport report, CancellationToken ct = default)
    {
        var md = await ExportAsMarkdownAsync(report, ct);
        return MarkdownToHtml(md);
    }

    /// <summary>
    /// Save drift report to file
    /// </summary>
    public async Task<string> SaveReportAsync(ExtendedDriftReport report, string format = "md", string? outputPath = null, CancellationToken ct = default)
    {
        outputPath ??= GetDefaultReportPath(report.LabName, report.Id, format);

        var content = format.ToLowerInvariant() switch
        {
            "json" => await ExportAsJsonAsync(report, ct),
            "html" => await ExportAsHtmlAsync(report, ct),
            _ => await ExportAsMarkdownAsync(report, ct)
        };

        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        await File.WriteAllTextAsync(outputPath, content, ct);

        return outputPath;
    }

    /// <summary>
    /// Get default path for a drift report
    /// </summary>
    public static string GetDefaultReportPath(string labName, string reportId, string format)
    {
        var ext = format.ToLowerInvariant() switch
        {
            "json" => "json",
            "html" => "html",
            _ => "md"
        };

        return Path.Combine(LabPaths.LabConfig, labName, "drift-reports", $"{reportId}.{ext}");
    }

    private static string MarkdownToHtml(string markdown)
    {
        // Simple markdown to HTML conversion
        var lines = markdown.Split('\n');
        var html = new StringBuilder();

        html.AppendLine("<!DOCTYPE html>");
        html.AppendLine("<html lang='en'>");
        html.AppendLine("<head>");
        html.AppendLine("<meta charset='UTF-8'>");
        html.AppendLine("<meta name='viewport' content='width=device-width, initial-scale=1.0'>");
        html.AppendLine("<title>Drift Report</title>");
        html.AppendLine("<style>");
        html.AppendLine("body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 1200px; margin: 0 auto; padding: 20px; }");
        html.AppendLine("h1 { border-bottom: 2px solid #333; padding-bottom: 10px; }");
        html.AppendLine("h2 { color: #333; margin-top: 30px; }");
        html.AppendLine("h3 { color: #555; }");
        html.AppendLine("table { border-collapse: collapse; width: 100%; margin: 15px 0; }");
        html.AppendLine("th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }");
        html.AppendLine("th { background-color: #f5f5f5; }");
        html.AppendLine("tr:nth-child(even) { background-color: #fafafa; }");
        html.AppendLine("hr { border: none; border-top: 1px solid #ddd; margin: 30px 0; }");
        html.AppendLine("</style>");
        html.AppendLine("</head>");
        html.AppendLine("<body>");

        bool inTable = false;
        bool inCodeBlock = false;

        foreach (var line in lines)
        {
            var trimmed = line.TrimEnd();

            if (trimmed.StartsWith("```"))
            {
                inCodeBlock = !inCodeBlock;
                if (inCodeBlock)
                    html.AppendLine("<pre><code>");
                else
                    html.AppendLine("</code></pre>");
                continue;
            }

            if (inCodeBlock)
            {
                html.AppendLine(System.Net.WebUtility.HtmlEncode(trimmed));
                continue;
            }

            // Headers
            if (trimmed.StartsWith("# "))
            {
                html.AppendLine($"<h1>{EscapeHtml(trimmed[2..])}</h1>");
                continue;
            }
            if (trimmed.StartsWith("## "))
            {
                html.AppendLine($"<h2>{EscapeHtml(trimmed[3..])}</h2>");
                continue;
            }
            if (trimmed.StartsWith("### "))
            {
                html.AppendLine($"<h3>{EscapeHtml(trimmed[4..])}</h3>");
                continue;
            }

            // Horizontal rule
            if (trimmed == "---")
            {
                html.AppendLine("<hr>");
                continue;
            }

            // Table
            if (trimmed.StartsWith("|"))
            {
                if (!inTable)
                {
                    html.AppendLine("<table>");
                    inTable = true;
                }

                var cells = trimmed.Split('|').Skip(1).SkipLast(1).Select(c => c.Trim()).ToArray();

                // Skip separator row
                if (cells.All(c => c.All(ch => ch == '-' || ch == ':')))
                    continue;

                var isHeader = !inTable || !lines[Array.IndexOf(lines, line) - 1].TrimStart().StartsWith("|");
                var tag = isHeader ? "th" : "td";

                html.AppendLine("<tr>");
                foreach (var cell in cells)
                {
                    html.AppendLine($"<{tag}>{EscapeHtml(cell)}</{tag}>");
                }
                html.AppendLine("</tr>");
                continue;
            }

            if (inTable)
            {
                html.AppendLine("</table>");
                inTable = false;
            }

            // Bold
            trimmed = System.Text.RegularExpressions.Regex.Replace(trimmed, @"\*\*(.+?)\*\*", "<strong>$1</strong>");

            // Italic
            trimmed = System.Text.RegularExpressions.Regex.Replace(trimmed, @"\*(.+?)\*", "<em>$1</em>");

            // Paragraph
            if (!string.IsNullOrWhiteSpace(trimmed))
            {
                html.AppendLine($"<p>{trimmed}</p>");
            }
        }

        if (inTable)
            html.AppendLine("</table>");

        html.AppendLine("</body>");
        html.AppendLine("</html>");

        return html.ToString();
    }

    private static string EscapeHtml(string text)
    {
        return System.Net.WebUtility.HtmlEncode(text);
    }
}

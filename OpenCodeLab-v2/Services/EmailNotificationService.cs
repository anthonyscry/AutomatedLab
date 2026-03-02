using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Mail;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using OpenCodeLab.Models;

namespace OpenCodeLab.Services;

/// <summary>
/// Service for sending email notifications for health alerts and system events
/// </summary>
public class EmailNotificationService
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private const string ConfigFile = "email-config.json";
    
    private EmailConfig? _config;

    /// <summary>
    /// Load email configuration
    /// </summary>
    public async Task<EmailConfig?> LoadConfigAsync(CancellationToken ct = default)
    {
        var path = GetConfigPath();
        if (!File.Exists(path))
            return null;

        var json = await File.ReadAllTextAsync(path, ct);
        _config = JsonSerializer.Deserialize<EmailConfig>(json);
        return _config;
    }

    /// <summary>
    /// Save email configuration
    /// </summary>
    public async Task SaveConfigAsync(EmailConfig config, CancellationToken ct = default)
    {
        var path = GetConfigPath();
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);

        var json = JsonSerializer.Serialize(config, JsonOptions);
        await File.WriteAllTextAsync(path, json, ct);
        _config = config;
    }

    /// <summary>
    /// Test SMTP connection
    /// </summary>
    public async Task<(bool Success, string Message)> TestConnectionAsync(EmailConfig config, CancellationToken ct = default)
    {
        try
        {
            using var client = CreateSmtpClient(config);
            
            // Send a test email
            var message = new MailMessage
            {
                From = new MailAddress(config.FromAddress, config.FromName ?? "OpenCodeLab"),
                Subject = "OpenCodeLab - Test Connection",
                Body = $"This is a test email from OpenCodeLab sent at {DateTime.UtcNow:yyyy-MM-dd HH:mm:ss} UTC.\n\nIf you received this email, your SMTP configuration is working correctly.",
                IsBodyHtml = false
            };
            message.To.Add(config.FromAddress); // Send to self for testing

            await client.SendMailAsync(message, ct);
            return (true, "Connection successful. Test email sent.");
        }
        catch (Exception ex)
        {
            return (false, $"Connection failed: {ex.Message}");
        }
    }

    /// <summary>
    /// Send health alert notification
    /// </summary>
    public async Task<bool> SendHealthAlertAsync(HealthAlert alert, CancellationToken ct = default)
    {
        if (_config == null)
            await LoadConfigAsync(ct);

        if (_config == null || !_config.Enabled || _config.Recipients.Count == 0)
            return false;

        try
        {
            using var client = CreateSmtpClient(_config);

            var subject = $"[OpenCodeLab] {GetSeverityPrefix(alert.Severity)} {alert.Title}";
            var body = BuildAlertEmailBody(alert);

            var message = new MailMessage
            {
                From = new MailAddress(_config.FromAddress, _config.FromName ?? "OpenCodeLab"),
                Subject = subject,
                Body = body,
                IsBodyHtml = true
            };

            foreach (var recipient in _config.Recipients)
            {
                message.To.Add(recipient);
            }

            await client.SendMailAsync(message, ct);
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Send daily health report
    /// </summary>
    public async Task<bool> SendDailyReportAsync(LabHealthReport report, CancellationToken ct = default)
    {
        if (_config == null)
            await LoadConfigAsync(ct);

        if (_config == null || !_config.Enabled || !_config.DailyReports || _config.Recipients.Count == 0)
            return false;

        try
        {
            using var client = CreateSmtpClient(_config);

            var subject = $"[OpenCodeLab] Daily Health Report - {report.LabName} ({report.OverallStatus})";
            var body = BuildReportEmailBody(report);

            var message = new MailMessage
            {
                From = new MailAddress(_config.FromAddress, _config.FromName ?? "OpenCodeLab"),
                Subject = subject,
                Body = body,
                IsBodyHtml = true
            };

            foreach (var recipient in _config.Recipients)
            {
                message.To.Add(recipient);
            }

            await client.SendMailAsync(message, ct);
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Send custom notification
    /// </summary>
    public async Task<bool> SendNotificationAsync(string subject, string body, bool isHtml = false, CancellationToken ct = default)
    {
        if (_config == null)
            await LoadConfigAsync(ct);

        if (_config == null || !_config.Enabled || _config.Recipients.Count == 0)
            return false;

        try
        {
            using var client = CreateSmtpClient(_config);

            var message = new MailMessage
            {
                From = new MailAddress(_config.FromAddress, _config.FromName ?? "OpenCodeLab"),
                Subject = $"[OpenCodeLab] {subject}",
                Body = body,
                IsBodyHtml = isHtml
            };

            foreach (var recipient in _config.Recipients)
            {
                message.To.Add(recipient);
            }

            await client.SendMailAsync(message, ct);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private SmtpClient CreateSmtpClient(EmailConfig config)
    {
        var client = new SmtpClient(config.SmtpHost, config.SmtpPort)
        {
            EnableSsl = config.UseSsl,
            DeliveryMethod = SmtpDeliveryMethod.Network,
            Timeout = 30000
        };

        if (!string.IsNullOrEmpty(config.Username))
        {
            client.Credentials = new NetworkCredential(config.Username, config.Password);
        }

        return client;
    }

    private static string GetSeverityPrefix(AlertSeverity severity)
    {
        return severity switch
        {
            AlertSeverity.Critical => "🔴 CRITICAL:",
            AlertSeverity.Warning => "⚠️ WARNING:",
            AlertSeverity.Info => "ℹ️ INFO:",
            _ => ""
        };
    }

    private static string BuildAlertEmailBody(HealthAlert alert)
    {
        var sb = new StringBuilder();
        sb.AppendLine("<!DOCTYPE html><html><body style='font-family: Arial, sans-serif;'>");
        
        var severityColor = alert.Severity switch
        {
            AlertSeverity.Critical => "#D32F2F",
            AlertSeverity.Warning => "#F57C00",
            _ => "#1976D2"
        };

        sb.AppendLine($"<div style='border-left: 4px solid {severityColor}; padding: 10px 20px; margin: 20px 0;'>");
        sb.AppendLine($"<h2 style='color: {severityColor}; margin: 0 0 10px 0;'>{alert.Title}</h2>");
        sb.AppendLine($"<p style='margin: 5px 0;'><strong>Lab:</strong> {alert.LabName}</p>");
        sb.AppendLine($"<p style='margin: 5px 0;'><strong>Severity:</strong> {alert.Severity}</p>");
        sb.AppendLine($"<p style='margin: 5px 0;'><strong>Time:</strong> {alert.CreatedAt:yyyy-MM-dd HH:mm:ss} UTC</p>");
        sb.AppendLine($"<p style='margin: 15px 0 0 0;'>{alert.Message}</p>");
        sb.AppendLine("</div>");

        if (!string.IsNullOrEmpty(alert.RecommendedAction))
        {
            sb.AppendLine("<div style='background: #E3F2FD; padding: 10px 20px; margin: 10px 0; border-radius: 4px;'>");
            sb.AppendLine($"<strong>Recommended Action:</strong><br/>{alert.RecommendedAction}");
            sb.AppendLine("</div>");
        }

        sb.AppendLine("<hr style='border: none; border-top: 1px solid #E0E0E0; margin: 20px 0;'/>");
        sb.AppendLine("<p style='color: #757575; font-size: 12px;'>This is an automated notification from OpenCodeLab.</p>");
        sb.AppendLine("</body></html>");

        return sb.ToString();
    }

    private static string BuildReportEmailBody(LabHealthReport report)
    {
        var sb = new StringBuilder();
        sb.AppendLine("<!DOCTYPE html><html><body style='font-family: Arial, sans-serif;'>");

        var statusColor = report.OverallStatus switch
        {
            HealthStatus.Healthy => "#4CAF50",
            HealthStatus.Warning => "#F57C00",
            HealthStatus.Critical => "#D32F2F",
            _ => "#757575"
        };

        sb.AppendLine($"<h1 style='color: #1976D2;'>Daily Health Report: {report.LabName}</h1>");
        sb.AppendLine($"<p><strong>Generated:</strong> {report.GeneratedAt:yyyy-MM-dd HH:mm:ss} UTC</p>");
        sb.AppendLine($"<p><strong>Overall Status:</strong> <span style='color: {statusColor}; font-weight: bold;'>{report.OverallStatus}</span></p>");

        // Summary cards
        sb.AppendLine("<div style='display: flex; gap: 20px; margin: 20px 0;'>");
        sb.AppendLine($"<div style='background: #E8F5E9; padding: 15px; border-radius: 4px; text-align: center; min-width: 100px;'><div style='font-size: 24px; font-weight: bold; color: #4CAF50;'>{report.HealthyCount}</div><div>Healthy</div></div>");
        sb.AppendLine($"<div style='background: #FFF3E0; padding: 15px; border-radius: 4px; text-align: center; min-width: 100px;'><div style='font-size: 24px; font-weight: bold; color: #F57C00;'>{report.WarningCount}</div><div>Warnings</div></div>");
        sb.AppendLine($"<div style='background: #FFEBEE; padding: 15px; border-radius: 4px; text-align: center; min-width: 100px;'><div style='font-size: 24px; font-weight: bold; color: #D32F2F;'>{report.CriticalCount}</div><div>Critical</div></div>");
        sb.AppendLine("</div>");

        // Checks table
        if (report.Checks.Count > 0)
        {
            sb.AppendLine("<h2>Health Checks</h2>");
            sb.AppendLine("<table style='border-collapse: collapse; width: 100%;'>");
            sb.AppendLine("<tr style='background: #F5F5F5;'><th style='padding: 10px; text-align: left; border: 1px solid #E0E0E0;'>Check</th><th style='padding: 10px; text-align: left; border: 1px solid #E0E0E0;'>Status</th><th style='padding: 10px; text-align: left; border: 1px solid #E0E0E0;'>Message</th></tr>");
            
            foreach (var check in report.Checks)
            {
                var checkColor = check.Status switch
                {
                    HealthStatus.Healthy => "#4CAF50",
                    HealthStatus.Warning => "#F57C00",
                    HealthStatus.Critical => "#D32F2F",
                    _ => "#757575"
                };
                sb.AppendLine($"<tr><td style='padding: 10px; border: 1px solid #E0E0E0;'>{check.CheckName}</td><td style='padding: 10px; border: 1px solid #E0E0E0; color: {checkColor};'>{check.StatusEmoji} {check.StatusText}</td><td style='padding: 10px; border: 1px solid #E0E0E0;'>{check.Message}</td></tr>");
            }
            sb.AppendLine("</table>");
        }

        // VM Health
        if (report.VmHealthStatuses.Count > 0)
        {
            sb.AppendLine("<h2>VM Health</h2>");
            sb.AppendLine("<table style='border-collapse: collapse; width: 100%;'>");
            sb.AppendLine("<tr style='background: #F5F5F5;'><th style='padding: 10px; text-align: left; border: 1px solid #E0E0E0;'>VM</th><th style='padding: 10px; text-align: left; border: 1px solid #E0E0E0;'>State</th><th style='padding: 10px; text-align: left; border: 1px solid #E0E0E0;'>Health</th></tr>");
            
            foreach (var vm in report.VmHealthStatuses)
            {
                sb.AppendLine($"<tr><td style='padding: 10px; border: 1px solid #E0E0E0;'>{vm.VmName}</td><td style='padding: 10px; border: 1px solid #E0E0E0;'>{vm.State}</td><td style='padding: 10px; border: 1px solid #E0E0E0;'>{vm.HealthEmoji}</td></tr>");
            }
            sb.AppendLine("</table>");
        }

        sb.AppendLine("<hr style='border: none; border-top: 1px solid #E0E0E0; margin: 20px 0;'/>");
        sb.AppendLine("<p style='color: #757575; font-size: 12px;'>This is an automated daily report from OpenCodeLab.</p>");
        sb.AppendLine("</body></html>");

        return sb.ToString();
    }

    private static string GetConfigPath()
    {
        return Path.Combine(@"C:\LabSources\LabConfig", "_system", ConfigFile);
    }
}

/// <summary>
/// Email configuration settings
/// </summary>
public class EmailConfig
{
    public bool Enabled { get; set; }
    public string SmtpHost { get; set; } = "smtp.gmail.com";
    public int SmtpPort { get; set; } = 587;
    public bool UseSsl { get; set; } = true;
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string FromAddress { get; set; } = string.Empty;
    public string? FromName { get; set; } = "OpenCodeLab";
    public List<string> Recipients { get; set; } = new();
    public bool DailyReports { get; set; } = true;
    public bool AlertOnCritical { get; set; } = true;
    public bool AlertOnWarning { get; set; } = false;
}

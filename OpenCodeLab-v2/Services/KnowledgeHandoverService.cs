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
/// Service for generating and managing knowledge handover documentation
/// </summary>
public class KnowledgeHandoverService
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private static readonly string DecisionLogPath = Path.Combine(LabPaths.SystemConfig, "decisions.json");

    #region Decision Records

    /// <summary>
    /// Get all decision records
    /// </summary>
    public async Task<List<DecisionRecord>> GetDecisionRecordsAsync(CancellationToken ct = default)
    {
        if (!File.Exists(DecisionLogPath))
            return new List<DecisionRecord>();

        var json = await File.ReadAllTextAsync(DecisionLogPath, ct);
        return JsonSerializer.Deserialize<List<DecisionRecord>>(json) ?? new List<DecisionRecord>();
    }

    /// <summary>
    /// Create a new decision record
    /// </summary>
    public async Task<DecisionRecord> CreateDecisionRecordAsync(
        string title,
        string context,
        string decision,
        string consequences,
        string? relatedLab = null,
        CancellationToken ct = default)
    {
        var records = await GetDecisionRecordsAsync(ct);
        var nextNumber = records.Count == 0 ? 1 : records.Max(r => r.SequenceNumber) + 1;

        var record = new DecisionRecord
        {
            Id = Guid.NewGuid().ToString("N"),
            Title = title,
            SequenceNumber = nextNumber,
            Context = context,
            Decision = decision,
            Consequences = consequences,
            RelatedLab = relatedLab,
            Status = DecisionStatus.Proposed,
            CreatedAt = DateTime.UtcNow,
            Author = Environment.UserName
        };

        records.Add(record);
        await SaveDecisionRecordsAsync(records, ct);
        return record;
    }

    /// <summary>
    /// Update decision record status
    /// </summary>
    public async Task<bool> UpdateDecisionStatusAsync(string recordId, DecisionStatus status, CancellationToken ct = default)
    {
        var records = await GetDecisionRecordsAsync(ct);
        var record = records.FirstOrDefault(r => r.Id == recordId);
        if (record == null) return false;

        record.Status = status;
        if (status == DecisionStatus.Accepted)
            record.DecidedAt = DateTime.UtcNow;

        await SaveDecisionRecordsAsync(records, ct);
        return true;
    }

    private async Task SaveDecisionRecordsAsync(List<DecisionRecord> records, CancellationToken ct)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(DecisionLogPath)!);
        var json = JsonSerializer.Serialize(records, JsonOptions);
        await File.WriteAllTextAsync(DecisionLogPath, json, ct);
    }

    #endregion

    #region Runbook Generation

    /// <summary>
    /// Generate a runbook for a lab
    /// </summary>
    public async Task<RunbookDocument> GenerateRunbookAsync(
        string labName,
        string title,
        string category,
        List<RunbookStep> steps,
        List<string>? prerequisites = null,
        CancellationToken ct = default)
    {
        var runbook = new RunbookDocument
        {
            Id = Guid.NewGuid().ToString("N"),
            Title = title,
            LabName = labName,
            Category = category,
            Steps = steps,
            Prerequisites = prerequisites ?? new List<string>(),
            GeneratedAt = DateTime.UtcNow
        };

        // Generate markdown content
        var sb = new StringBuilder();
        sb.AppendLine($"# {title}");
        sb.AppendLine();
        sb.AppendLine($"**Lab:** {labName}");
        sb.AppendLine($"**Category:** {category}");
        sb.AppendLine($"**Generated:** {runbook.GeneratedAt:yyyy-MM-dd HH:mm}");
        sb.AppendLine();

        if (runbook.Prerequisites.Count > 0)
        {
            sb.AppendLine("## Prerequisites");
            sb.AppendLine();
            foreach (var prereq in runbook.Prerequisites)
                sb.AppendLine($"- {prereq}");
            sb.AppendLine();
        }

        sb.AppendLine("## Steps");
        sb.AppendLine();
        foreach (var step in steps.OrderBy(s => s.Order))
        {
            sb.AppendLine($"### Step {step.Order}: {step.Title}");
            sb.AppendLine();
            sb.AppendLine(step.Description);
            if (!string.IsNullOrWhiteSpace(step.Command))
            {
                sb.AppendLine();
                sb.AppendLine("```powershell");
                sb.AppendLine(step.Command);
                sb.AppendLine("```");
            }
            if (!string.IsNullOrWhiteSpace(step.ExpectedResult))
            {
                sb.AppendLine();
                sb.AppendLine($"**Expected Result:** {step.ExpectedResult}");
            }
            if (step.Notes.Count > 0)
            {
                sb.AppendLine();
                sb.AppendLine("**Notes:**");
                foreach (var note in step.Notes)
                    sb.AppendLine($"- {note}");
            }
            sb.AppendLine();
        }

        runbook.Content = sb.ToString();

        // Save to file
        var runbookPath = GetRunbookPath(labName, runbook.Id);
        Directory.CreateDirectory(Path.GetDirectoryName(runbookPath)!);
        await File.WriteAllTextAsync(runbookPath, runbook.Content, ct);

        return runbook;
    }

    /// <summary>
    /// Get all runbooks for a lab
    /// </summary>
    public async Task<List<RunbookDocument>> GetRunbooksAsync(string labName, CancellationToken ct = default)
    {
        var runbookDir = GetRunbookDirectory(labName);
        if (!Directory.Exists(runbookDir))
            return new List<RunbookDocument>();

        var runbooks = new List<RunbookDocument>();
        foreach (var file in Directory.GetFiles(runbookDir, "*.md"))
        {
            var content = await File.ReadAllTextAsync(file, ct);
            var runbook = ParseRunbook(content, file);
            if (runbook != null)
                runbooks.Add(runbook);
        }

        return runbooks;
    }

    private static RunbookDocument? ParseRunbook(string content, string filePath)
    {
        var lines = content.Split('\n');
        if (lines.Length == 0) return null;

        var title = lines[0].TrimStart('#').Trim();
        return new RunbookDocument
        {
            Id = Path.GetFileNameWithoutExtension(filePath),
            Title = title,
            Content = content
        };
    }

    #endregion

    #region System Overview

    /// <summary>
    /// Generate system overview document
    /// </summary>
    public async Task<string> GenerateSystemOverviewAsync(string? labName = null, CancellationToken ct = default)
    {
        var sb = new StringBuilder();

        sb.AppendLine("# OpenCodeLab System Overview");
        sb.AppendLine();
        sb.AppendLine($"**Generated:** {DateTime.UtcNow:yyyy-MM-dd HH:mm} UTC");
        sb.AppendLine($"**Generated By:** {Environment.UserName}");
        sb.AppendLine();

        sb.AppendLine("## Executive Summary");
        sb.AppendLine();
        sb.AppendLine("OpenCodeLab is a WPF .NET 8 desktop application for managing Hyper-V lab environments.");
        sb.AppendLine("It provides GUI-based lab deployment, drift detection, health monitoring, and documentation capabilities.");
        sb.AppendLine();

        sb.AppendLine("## Architecture");
        sb.AppendLine();
        sb.AppendLine("### Technology Stack");
        sb.AppendLine("- .NET 8 (WPF Desktop Application)");
        sb.AppendLine("- PowerShell Integration (AutomatedLab)");
        sb.AppendLine("- Hyper-V Management");
        sb.AppendLine("- JSON Configuration Storage");
        sb.AppendLine();

        sb.AppendLine("### Directory Structure");
        sb.AppendLine("```");
        sb.AppendLine($"{LabPaths.Root}\\");
        sb.AppendLine("├── ISOs/              # Windows/Linux ISO files");
        sb.AppendLine("├── VMs/               # VM disk storage");
        sb.AppendLine("├── LabConfig/         # Saved lab configurations");
        sb.AppendLine("├── Docs/              # User documentation");
        sb.AppendLine("└── Logs/              # Application logs");
        sb.AppendLine("```");
        sb.AppendLine();

        if (!string.IsNullOrWhiteSpace(labName))
        {
            sb.AppendLine($"## Lab: {labName}");
            sb.AppendLine();
            sb.AppendLine($"For detailed lab configuration, see LabConfig/{labName}/");
            sb.AppendLine();
        }

        sb.AppendLine("## Key Features");
        sb.AppendLine();
        sb.AppendLine("1. **Health Monitoring** - Real-time VM and host health checks");
        sb.AppendLine("2. **Drift Detection** - Baseline comparison for configuration changes");
        sb.AppendLine("3. **Documentation Hub** - Centralized documentation management");
        sb.AppendLine("4. **Runbook Generation** - Automated operational procedures");
        sb.AppendLine("5. **Decision Logging** - Architecture decision records");
        sb.AppendLine();

        sb.AppendLine("## Support");
        sb.AppendLine();
        sb.AppendLine("- GitHub: https://github.com/anthonyscry/OpenCodeLab");
        sb.AppendLine("- Documentation: See docs/ folder");
        sb.AppendLine();

        return sb.ToString();
    }

    #endregion

    #region Onboarding Guide

    /// <summary>
    /// Generate onboarding guide for a lab
    /// </summary>
    public async Task<OnboardingGuide> GenerateOnboardingGuideAsync(
        string labName,
        string targetRole = "Developer",
        CancellationToken ct = default)
    {
        var guide = new OnboardingGuide
        {
            Id = Guid.NewGuid().ToString("N"),
            Title = $"Onboarding Guide - {labName}",
            LabName = labName,
            TargetRole = targetRole,
            GeneratedAt = DateTime.UtcNow,
            Steps = GenerateDefaultOnboardingSteps(),
            Prerequisites = new List<string>
            {
                "Windows 10/11 Pro or Enterprise",
                ".NET 8 Desktop Runtime",
                "Hyper-V enabled",
                "Access to OpenCodeLab application"
            },
            Resources = new List<string>
            {
                "README.md - Project overview",
                "docs/ARCHITECTURE.md - Technical architecture",
                "docs/GETTING-STARTED.md - Quick start guide"
            },
            Contacts = new List<string>
            {
                "Lab Administrator",
                "IT Support"
            }
        };

        // Generate content
        var sb = new StringBuilder();
        sb.AppendLine($"# {guide.Title}");
        sb.AppendLine();
        sb.AppendLine($"**Target Role:** {targetRole}");
        sb.AppendLine($"**Generated:** {guide.GeneratedAt:yyyy-MM-dd HH:mm}");
        sb.AppendLine();

        sb.AppendLine("## Prerequisites");
        foreach (var prereq in guide.Prerequisites)
            sb.AppendLine($"- {prereq}");
        sb.AppendLine();

        sb.AppendLine("## Onboarding Steps");
        int totalMinutes = 0;
        foreach (var step in guide.Steps)
        {
            sb.AppendLine($"### {step.Order}. {step.Title}");
            sb.AppendLine($"*Estimated time: {step.EstimatedMinutes} minutes*");
            sb.AppendLine();
            sb.AppendLine(step.Description);
            if (!string.IsNullOrWhiteSpace(step.VerificationCriteria))
            {
                sb.AppendLine();
                sb.AppendLine($"**Verification:** {step.VerificationCriteria}");
            }
            sb.AppendLine();
            totalMinutes += step.EstimatedMinutes;
        }

        sb.AppendLine($"**Total Estimated Time:** {totalMinutes} minutes");
        sb.AppendLine();

        sb.AppendLine("## Resources");
        foreach (var resource in guide.Resources)
            sb.AppendLine($"- {resource}");
        sb.AppendLine();

        guide.Content = sb.ToString();

        // Save
        var guidePath = GetOnboardingPath(labName);
        Directory.CreateDirectory(Path.GetDirectoryName(guidePath)!);
        await File.WriteAllTextAsync(guidePath, guide.Content, ct);

        return guide;
    }

    private static List<OnboardingStep> GenerateDefaultOnboardingSteps()
    {
        return new List<OnboardingStep>
        {
            new() { Order = 1, Title = "Environment Setup", Description = "Install .NET 8 Desktop Runtime and verify Hyper-V is enabled.", EstimatedMinutes = 15, VerificationCriteria = "OpenCodeLab starts without errors" },
            new() { Order = 2, Title = "Access Configuration", Description = "Obtain access to LabSources directory and ISO files.", EstimatedMinutes = 10, VerificationCriteria = $"{LabPaths.ISOs} contains required ISOs" },
            new() { Order = 3, Title = "Application Launch", Description = "Launch OpenCodeLab as Administrator and review Dashboard.", EstimatedMinutes = 5, VerificationCriteria = "Dashboard shows preflight checks passing" },
            new() { Order = 4, Title = "Review Documentation", Description = "Read README.md and ARCHITECTURE.md for system overview.", EstimatedMinutes = 20, VerificationCriteria = "Understand basic system architecture" },
            new() { Order = 5, Title = "First Lab Deployment", Description = "Create and deploy a test lab with guidance.", EstimatedMinutes = 30, VerificationCriteria = "Test lab VMs are running" }
        };
    }

    #endregion

    private static string GetRunbookPath(string labName, string runbookId)
    {
        return Path.Combine(LabPaths.LabConfig, labName, "runbooks", $"{runbookId}.md");
    }

    private static string GetRunbookDirectory(string labName)
    {
        return Path.Combine(LabPaths.LabConfig, labName, "runbooks");
    }

    private static string GetOnboardingPath(string labName)
    {
        return Path.Combine(LabPaths.LabConfig, labName, "docs", "onboarding.md");
    }
}

using System;
using System.Collections.Generic;

namespace OpenCodeLab.Models;

/// <summary>
/// Runbook template for operational procedures
/// </summary>
public class RunbookTemplate
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string Category { get; set; } = string.Empty;
    public string TemplateContent { get; set; } = string.Empty;
    public List<string> RequiredVariables { get; set; } = new();
    public List<string> OptionalVariables { get; set; } = new();
    public bool IsBuiltIn { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// Generated runbook document
/// </summary>
public class RunbookDocument
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Title { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string LabName { get; set; } = string.Empty;
    public string Content { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public List<RunbookStep> Steps { get; set; } = new();
    public List<string> Prerequisites { get; set; } = new();
    public List<string> VerificationSteps { get; set; } = new();
    public List<string> RollbackSteps { get; set; } = new();
    public List<string> EscalationContacts { get; set; } = new();
    public DateTime GeneratedAt { get; set; } = DateTime.UtcNow;
    public string? TemplateId { get; set; }
}

/// <summary>
/// Single step in a runbook
/// </summary>
public class RunbookStep
{
    public int Order { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string? Command { get; set; }
    public string? ExpectedResult { get; set; }
    public List<string> Notes { get; set; } = new();
}

/// <summary>
/// Decision record (ADR - Architecture Decision Record)
/// </summary>
public class DecisionRecord
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Title { get; set; } = string.Empty;
    public int SequenceNumber { get; set; }
    public DecisionStatus Status { get; set; } = DecisionStatus.Proposed;
    public string Context { get; set; } = string.Empty;
    public string Decision { get; set; } = string.Empty;
    public string Consequences { get; set; } = string.Empty;
    public List<string> Alternatives { get; set; } = new();
    public string? RelatedLab { get; set; }
    public List<string> Tags { get; set; } = new();
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? DecidedAt { get; set; }
    public DateTime? SupersededAt { get; set; }
    public string? SupersededBy { get; set; }
    public string Author { get; set; } = Environment.UserName;

    [System.Text.Json.Serialization.JsonIgnore]
    public string StatusEmoji => Status switch
    {
        DecisionStatus.Proposed => "💡",
        DecisionStatus.Accepted => "✅",
        DecisionStatus.Deprecated => "⚠️",
        DecisionStatus.Superseded => "🔄",
        DecisionStatus.Rejected => "❌",
        _ => "❓"
    };

    [System.Text.Json.Serialization.JsonIgnore]
    public string ShortId => $"ADR-{SequenceNumber:D4}";
}

/// <summary>
/// Status of a decision record
/// </summary>
public enum DecisionStatus
{
    Proposed = 0,
    Accepted = 1,
    Deprecated = 2,
    Superseded = 3,
    Rejected = 4
}

/// <summary>
/// Onboarding guide for new team members
/// </summary>
public class OnboardingGuide
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Title { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string LabName { get; set; } = string.Empty;
    public string Content { get; set; } = string.Empty;
    public List<OnboardingStep> Steps { get; set; } = new();
    public List<string> Prerequisites { get; set; } = new();
    public List<string> Resources { get; set; } = new();
    public List<string> Contacts { get; set; } = new();
    public DateTime GeneratedAt { get; set; } = DateTime.UtcNow;
    public string TargetRole { get; set; } = "Developer";
}

/// <summary>
/// Single step in onboarding
/// </summary>
public class OnboardingStep
{
    public int Order { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string? VerificationCriteria { get; set; }
    public int EstimatedMinutes { get; set; }
    public List<string> Resources { get; set; } = new();
}

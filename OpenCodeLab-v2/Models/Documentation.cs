using System;
using System.Collections.Generic;

namespace OpenCodeLab.Models;

/// <summary>
/// Represents a documentation document in the system
/// </summary>
public class DocumentationDocument
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Title { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string Content { get; set; } = string.Empty;
    public string ContentPath { get; set; } = string.Empty;
    public DocumentationCategory Category { get; set; } = DocumentationCategory.UserGuide;
    public DocumentationSourceType SourceType { get; set; } = DocumentationSourceType.BuiltIn;
    public List<string> Tags { get; set; } = new();
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
    public string? Author { get; set; }
    public string? LabName { get; set; }
    public int SortOrder { get; set; }

    [System.Text.Json.Serialization.JsonIgnore]
    public string CategoryEmoji => Category switch
    {
        DocumentationCategory.UserGuide => "📖",
        DocumentationCategory.Architecture => "🏗️",
        DocumentationCategory.Operations => "⚙️",
        DocumentationCategory.Troubleshooting => "🔧",
        DocumentationCategory.ApiReference => "📚",
        DocumentationCategory.Runbook => "📋",
        DocumentationCategory.DecisionLog => "📝",
        DocumentationCategory.ReleaseNotes => "🚀",
        DocumentationCategory.LabSpecific => "🔬",
        _ => "📄"
    };

    [System.Text.Json.Serialization.JsonIgnore]
    public string SourceTypeText => SourceType switch
    {
        DocumentationSourceType.BuiltIn => "Built-in",
        DocumentationSourceType.UserCreated => "User",
        DocumentationSourceType.Generated => "Generated",
        _ => "Unknown"
    };
}

/// <summary>
/// Categories for documentation
/// </summary>
public enum DocumentationCategory
{
    UserGuide = 0,
    Architecture = 1,
    Operations = 2,
    Troubleshooting = 3,
    ApiReference = 4,
    Runbook = 5,
    DecisionLog = 6,
    ReleaseNotes = 7,
    LabSpecific = 8
}

/// <summary>
/// Source type for documentation
/// </summary>
public enum DocumentationSourceType
{
    BuiltIn = 0,
    UserCreated = 1,
    Generated = 2
}

/// <summary>
/// Search result for documentation queries
/// </summary>
public class DocumentationSearchResult
{
    public string DocumentId { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string Category { get; set; } = string.Empty;
    public string CategoryEmoji { get; set; } = string.Empty;
    public string? MatchedContent { get; set; }
    public int RelevanceScore { get; set; }
    public string SourceType { get; set; } = string.Empty;
    public DateTime UpdatedAt { get; set; }
}

/// <summary>
/// Documentation index entry for fast searching
/// </summary>
public class DocumentationIndexEntry
{
    public string DocumentId { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string? Description { get; set; }
    public List<string> Keywords { get; set; } = new();
    public string Category { get; set; } = string.Empty;
    public string SourceType { get; set; } = string.Empty;
    public DateTime UpdatedAt { get; set; }
}
